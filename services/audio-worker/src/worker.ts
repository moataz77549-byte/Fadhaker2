import { join } from 'node:path';
import { stat } from 'node:fs/promises';
import { ProcessingDatabase } from './database.js';
import { TrustedStorage } from './storage.js';
import { Logger } from './logger.js';
import { asProcessingError, ProcessingError, safeErrorMessage } from './errors.js';
import { probeFile, validateSource } from './probe.js';
import { sha256File } from './checksum.js';
import { transcode } from './transcode.js';
import { withWorkspace } from './workspace.js';
import type { WorkerConfig } from './config.js';
import type { ProcessingClaim } from './types.js';

export class AudioWorker {
  private readonly database: ProcessingDatabase;
  private readonly storage: TrustedStorage;
  private readonly logger = new Logger();
  private stopping = false;

  constructor(private readonly config: WorkerConfig) {
    this.database = new ProcessingDatabase(config.supabaseUrl, config.supabaseSecretKey);
    this.storage = new TrustedStorage(config.supabaseUrl, config.supabaseSecretKey);
  }

  stop(): void { this.stopping = true; }

  async run(): Promise<void> {
    const recovered = await this.database.recoverStale();
    let nextRecoveryAt = Date.now() + this.config.recoveryIntervalMs;
    this.logger.info('WORKER_STARTED', { worker_id: this.config.workerId, version: this.config.workerVersion, recovered_stale_jobs: recovered });
    while (!this.stopping) {
      if (Date.now() >= nextRecoveryAt) {
        const count = await this.database.recoverStale();
        if (count > 0) this.logger.warn('STALE_JOBS_RECOVERED', { count });
        nextRecoveryAt = Date.now() + this.config.recoveryIntervalMs;
      }
      const results = await Promise.all(Array.from({ length: this.config.concurrency }, () => this.runOnce()));
      if (!results.some(Boolean)) await new Promise((resolve) => setTimeout(resolve, this.config.idlePollMs));
    }
  }

  async runOnce(): Promise<boolean> {
    const claim = await this.database.claim(this.config.workerId, this.config.workerVersion, this.config.profileCode, this.config.leaseSeconds, this.config.maxAttempts);
    if (!claim) return false;
    const started = performance.now();
    this.logger.info('PROCESSING_CLAIMED', this.context(claim));
    let heartbeatError: unknown;
    let heartbeatInFlight = false;
    const heartbeat = setInterval(() => {
      if (heartbeatInFlight || heartbeatError) return;
      heartbeatInFlight = true;
      void this.database.heartbeat(claim, this.config.workerId, this.config.leaseSeconds)
        .catch((error) => { heartbeatError = error; this.logger.error('PROCESSING_HEARTBEAT_FAILED', error, this.context(claim)); })
        .finally(() => { heartbeatInFlight = false; });
    }, this.config.heartbeatSeconds * 1000);
    heartbeat.unref();
    try {
      await withWorkspace(this.config.tempRoot, claim.job_id, async (directory) => {
        const input = join(directory, `input.${claim.source_extension}`);
        const output = join(directory, `output.${claim.profile.extension}`);
        await this.storage.download(claim.original_bucket, claim.original_path, input, this.config.processingTimeoutMs);
        const inputStat = await stat(input);
        const checksum = await sha256File(input);
        const source = await probeFile(this.config.ffprobePath, input, this.config.probeTimeoutMs);
        await validateSource(input, claim, source.probe);
        if (heartbeatError) throw new ProcessingError('DATABASE_FAILED', 'Processing lease heartbeat failed', heartbeatError);
        await this.database.recordProbe(claim, this.config.workerId, source.probe, checksum, inputStat.size, source.durationMs);
        this.logger.info('FFPROBE_VALIDATED', { ...this.context(claim), format: source.probe.detectedFormat, codec: source.probe.codec, duration_ms: source.probe.durationMs });
        const processed = await transcode(this.config.ffmpegPath, this.config.ffprobePath, input, output, source.probe, claim.profile, this.config.processingTimeoutMs, this.config.probeTimeoutMs);
        if (heartbeatError) throw new ProcessingError('DATABASE_FAILED', 'Processing lease heartbeat failed', heartbeatError);
        const objectKey = this.processedKey(claim);
        await this.storage.uploadProcessed(objectKey, output, claim.profile.mime_type, processed.sha256);
        if (heartbeatError) throw new ProcessingError('DATABASE_FAILED', 'Processing lease heartbeat failed after upload', heartbeatError);
        const variantId = await this.database.complete(claim, this.config.workerId, objectKey, processed);
        this.logger.info('MEDIA_READY', { ...this.context(claim), variant_id: variantId, output_size_bytes: processed.sizeBytes, processing_duration_ms: Math.round(performance.now() - started) });
      });
    } catch (error) {
      const processingError = asProcessingError(error);
      this.logger.error('PROCESSING_FAILED', processingError, { ...this.context(claim), error_code: processingError.code, processing_duration_ms: Math.round(performance.now() - started) });
      try {
        const delay = Math.min(3600, 30 * (2 ** Math.max(0, claim.claim_token - 1)));
        await this.database.fail(claim, this.config.workerId, processingError.code, safeErrorMessage(processingError), delay);
      } catch (failureUpdateError) {
        this.logger.error('PROCESSING_FAILURE_STATE_UNCONFIRMED', failureUpdateError, this.context(claim));
      }
    } finally { clearInterval(heartbeat); }
    return true;
  }

  processedKey(claim: ProcessingClaim): string {
    const segment = claim.profile.code.toLowerCase().replaceAll('_', '-');
    return `media/${claim.media_id}/processed/${segment}/v${claim.profile.version}/${claim.attempt_id}.${claim.profile.extension}`;
  }

  private context(claim: ProcessingClaim): Record<string, unknown> {
    return { worker_id: this.config.workerId, job_id: claim.job_id, attempt_id: claim.attempt_id, media_id: claim.media_id, claim_token: claim.claim_token };
  }
}

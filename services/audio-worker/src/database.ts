import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { ProcessingError, safeErrorMessage } from './errors.js';
import type { ProcessingClaim, ProbeResult, ProcessedOutput } from './types.js';

type LooseClient = SupabaseClient<any, any, any>;

export class ProcessingDatabase {
  private readonly client: LooseClient;

  constructor(url: string, secretKey: string) {
    this.client = createClient<any>(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { headers: { 'X-Client-Info': '@tarteel/audio-worker/0.1.0' } },
    });
  }

  async recoverStale(limit = 50): Promise<number> {
    const { data, error } = await this.client.schema('app').rpc('recover_stale_media_processing_jobs', { p_limit: limit });
    if (error) throw this.dbError(error);
    return Array.isArray(data) ? data.length : 0;
  }

  async claim(workerId: string, workerVersion: string, profileCode: string, leaseSeconds: number, maxAttempts: number): Promise<ProcessingClaim | null> {
    const { data, error } = await this.client.schema('app').rpc('claim_media_processing_job', {
      p_worker_id: workerId, p_worker_version: workerVersion, p_profile_code: profileCode,
      p_lease_seconds: leaseSeconds, p_max_attempts: maxAttempts,
    });
    if (error) throw this.dbError(error);
    const row = Array.isArray(data) ? data[0] : null;
    return row ? row as ProcessingClaim : null;
  }

  async heartbeat(claim: ProcessingClaim, workerId: string, leaseSeconds: number): Promise<void> {
    const { error } = await this.client.schema('app').rpc('heartbeat_media_processing_job', {
      p_job_id: claim.job_id, p_attempt_id: claim.attempt_id, p_worker_id: workerId,
      p_claim_token: claim.claim_token, p_lease_seconds: leaseSeconds,
    });
    if (error) throw this.dbError(error);
  }

  async recordProbe(claim: ProcessingClaim, workerId: string, probe: ProbeResult, sha256: string, sourceSize: number, probeDurationMs: number): Promise<void> {
    const { error } = await this.client.schema('app').rpc('record_media_probe', {
      p_job_id: claim.job_id, p_attempt_id: claim.attempt_id, p_worker_id: workerId,
      p_claim_token: claim.claim_token, p_sha256: sha256,
      p_detected_format: probe.detectedFormat, p_detected_codec: probe.codec,
      p_duration_ms: probe.durationMs, p_sample_rate_hz: probe.sampleRateHz,
      p_channels: probe.channels, p_source_bitrate_kbps: probe.bitrateKbps,
      p_source_size_bytes: sourceSize, p_ffprobe_duration_ms: probeDurationMs,
      p_diagnostics: probe.diagnostics,
    });
    if (error) throw this.dbError(error);
  }

  async fail(claim: ProcessingClaim, workerId: string, code: string, message: string, retryDelaySeconds: number): Promise<string> {
    const { data, error } = await this.client.schema('app').rpc('fail_media_processing_job', {
      p_job_id: claim.job_id, p_attempt_id: claim.attempt_id, p_worker_id: workerId,
      p_claim_token: claim.claim_token, p_error_code: code,
      p_error_message: message, p_retry_delay_seconds: retryDelaySeconds,
    });
    if (error) throw this.dbError(error);
    return String(data);
  }

  async complete(claim: ProcessingClaim, workerId: string, objectKey: string, output: ProcessedOutput): Promise<string> {
    const { data, error } = await this.client.schema('app').rpc('complete_media_processing_job', {
      p_job_id: claim.job_id, p_attempt_id: claim.attempt_id, p_worker_id: workerId,
      p_claim_token: claim.claim_token, p_bucket_id: 'tarteel-media-processed',
      p_object_key: objectKey, p_output_sha256: output.sha256,
      p_output_format: output.detectedFormat, p_output_mime_type: claim.profile.mime_type,
      p_output_codec: output.codec, p_output_bitrate_kbps: claim.profile.bitrate_kbps,
      p_output_sample_rate_hz: output.sampleRateHz, p_output_channels: output.channels,
      p_output_duration_ms: output.durationMs, p_output_size_bytes: output.sizeBytes,
      p_ffmpeg_duration_ms: output.ffmpegDurationMs,
      p_metadata: { loudness: output.loudness, output_probe: output.diagnostics },
    });
    if (error) {
      const state = await this.getJobStatus(claim.job_id);
      if (state?.status === 'COMPLETED') return state.variantId ?? 'already-completed';
      throw this.dbError(error);
    }
    return String(data);
  }

  private async getJobStatus(jobId: string): Promise<{status: string; variantId: string | null} | null> {
    const { data, error } = await this.client.schema('app').from('media_processing_jobs')
      .select('status,processed_media_variants(id)').eq('id', jobId).maybeSingle();
    if (error) return null;
    const variants = (data as any)?.processed_media_variants as Array<{id:string}> | undefined;
    return data ? { status: String((data as any).status), variantId: variants?.[0]?.id ?? null } : null;
  }

  private dbError(error: unknown): ProcessingError {
    return new ProcessingError('DATABASE_FAILED', safeErrorMessage(error), error);
  }
}

import { ProcessingError } from './errors.js';

export interface WorkerConfig {
  supabaseUrl: string;
  supabaseSecretKey: string;
  workerId: string;
  workerVersion: string;
  concurrency: number;
  leaseSeconds: number;
  heartbeatSeconds: number;
  probeTimeoutMs: number;
  processingTimeoutMs: number;
  maxAttempts: number;
  idlePollMs: number;
  recoveryIntervalMs: number;
  tempRoot: string;
  ffmpegPath: string;
  ffprobePath: string;
  profileCode: string;
}

const intEnv = (name: string, fallback: number, min: number, max: number): number => {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ProcessingError('WORKER_INTERNAL_ERROR', `${name} must be an integer from ${min} to ${max}`);
  }
  return value;
};

export function loadConfig(requireRemote = true): WorkerConfig {
  const supabaseUrl = process.env.TARTEEL_SUPABASE_URL ?? '';
  const supabaseSecretKey = process.env.TARTEEL_SUPABASE_SECRET_KEY ?? '';
  if (requireRemote && (!supabaseUrl || !supabaseSecretKey)) {
    throw new ProcessingError('WORKER_INTERNAL_ERROR', 'Trusted Supabase environment variables are required');
  }
  const leaseSeconds = intEnv('TARTEEL_AUDIO_WORKER_LEASE_SECONDS', 300, 60, 3600);
  const heartbeatSeconds = intEnv('TARTEEL_AUDIO_WORKER_HEARTBEAT_SECONDS', 30, 5, 600);
  if (heartbeatSeconds * 3 >= leaseSeconds) {
    throw new ProcessingError('WORKER_INTERNAL_ERROR', 'Heartbeat interval must be less than one third of lease duration');
  }
  return {
    supabaseUrl,
    supabaseSecretKey,
    workerId: process.env.TARTEEL_AUDIO_WORKER_ID ?? 'audio-worker-dev-01',
    workerVersion: process.env.TARTEEL_AUDIO_WORKER_VERSION ?? '0.1.0',
    concurrency: intEnv('TARTEEL_AUDIO_WORKER_CONCURRENCY', 1, 1, 8),
    leaseSeconds,
    heartbeatSeconds,
    probeTimeoutMs: intEnv('TARTEEL_AUDIO_WORKER_PROBE_TIMEOUT_SECONDS', 30, 5, 300) * 1000,
    processingTimeoutMs: intEnv('TARTEEL_AUDIO_WORKER_PROCESSING_TIMEOUT_SECONDS', 900, 30, 7200) * 1000,
    maxAttempts: intEnv('TARTEEL_AUDIO_WORKER_MAX_ATTEMPTS', 3, 1, 10),
    idlePollMs: intEnv('TARTEEL_AUDIO_WORKER_IDLE_POLL_MS', 5000, 250, 60000),
    recoveryIntervalMs: intEnv('TARTEEL_AUDIO_WORKER_RECOVERY_INTERVAL_SECONDS', 60, 10, 3600) * 1000,
    tempRoot: process.env.TARTEEL_AUDIO_WORKER_TEMP_ROOT ?? '/tmp/tarteel/audio-worker',
    ffmpegPath: process.env.TARTEEL_FFMPEG_PATH ?? 'ffmpeg',
    ffprobePath: process.env.TARTEEL_FFPROBE_PATH ?? 'ffprobe',
    profileCode: process.env.TARTEEL_PROCESSING_PROFILE ?? 'AUDIO_STANDARD_V1',
  };
}

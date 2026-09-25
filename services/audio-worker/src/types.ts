export type ErrorCode =
  | 'INVALID_MEDIA' | 'UNSUPPORTED_FORMAT' | 'NO_AUDIO_STREAM'
  | 'VIDEO_STREAM_REJECTED' | 'CORRUPT_INPUT' | 'DURATION_LIMIT_EXCEEDED'
  | 'INPUT_SIZE_MISMATCH' | 'OBJECT_KEY_MISMATCH' | 'DOWNLOAD_FAILED'
  | 'STORAGE_FAILED' | 'FFPROBE_FAILED' | 'FFPROBE_TIMEOUT'
  | 'PROCESSING_TIMEOUT' | 'FFMPEG_FAILED' | 'OUTPUT_INVALID'
  | 'DATABASE_FAILED' | 'WORKER_INTERNAL_ERROR';

export interface ProcessingProfile {
  id: string;
  code: string;
  version: number;
  container: string;
  extension: string;
  mime_type: string;
  codec: string;
  bitrate_kbps: number;
  sample_rate_hz: number;
  channels: number;
  loudness_i_lufs: number;
  loudness_tp_dbtp: number;
  loudness_lra_lu: number;
  max_duration_ms: number;
  max_output_size_bytes: number;
}

export interface ProcessingClaim {
  job_id: string;
  attempt_id: string;
  media_id: string;
  claim_token: number;
  original_bucket: string;
  original_path: string;
  original_object_version: string | null;
  original_filename: string | null;
  declared_mime_type: string;
  expected_size_bytes: number;
  source_extension: string;
  allowed_formats: string[];
  allowed_codecs: string[];
  profile: ProcessingProfile;
}

export interface ProbeResult {
  detectedFormat: string;
  codec: string;
  durationMs: number;
  sampleRateHz: number;
  channels: number;
  bitrateKbps: number;
  audioStreamCount: number;
  videoStreamCount: number;
  encrypted: boolean;
  diagnostics: Record<string, unknown>;
}

export interface ProcessedOutput extends ProbeResult {
  path: string;
  sizeBytes: number;
  sha256: string;
  ffmpegDurationMs: number;
  loudness: LoudnessMeasurement;
}

export interface LoudnessMeasurement {
  input_i: string;
  input_tp: string;
  input_lra: string;
  input_thresh: string;
  target_offset: string;
}

export type MediaProcessingJobStatus =
  | 'PENDING' | 'PROCESSING' | 'RETRY_WAIT' | 'COMPLETED' | 'FAILED' | 'CANCELLED';

export type MediaProcessingErrorCode =
  | 'INVALID_MEDIA' | 'UNSUPPORTED_FORMAT' | 'NO_AUDIO_STREAM'
  | 'VIDEO_STREAM_REJECTED' | 'CORRUPT_INPUT' | 'DURATION_LIMIT_EXCEEDED'
  | 'INPUT_SIZE_MISMATCH' | 'OBJECT_KEY_MISMATCH' | 'DOWNLOAD_FAILED'
  | 'STORAGE_FAILED' | 'FFPROBE_FAILED' | 'FFPROBE_TIMEOUT'
  | 'PROCESSING_TIMEOUT' | 'FFMPEG_FAILED' | 'OUTPUT_INVALID'
  | 'DATABASE_FAILED' | 'WORKER_INTERNAL_ERROR';

export interface ProcessingProfileSummary {
  code: 'AUDIO_STANDARD_V1' | string;
  version: number;
  codec: string;
  container: string;
  bitrateKbps: number;
  sampleRateHz: number;
  channels: number;
}

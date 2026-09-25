export const TARTEEL_STORAGE_BUCKETS = {
  originals: 'tarteel-media-originals',
  processed: 'tarteel-media-processed',
  artwork: 'tarteel-artwork',
} as const;

export type UploadSourceExtension = 'mp3' | 'm4a' | 'aac' | 'wav' | 'flac';

export interface CreateMediaUploadIntentRequest {
  mediaId: string;
  stationId: string | null;
  originalFilename: string;
  extension: UploadSourceExtension;
  declaredMimeType: string;
  expectedSizeBytes: number;
  idempotencyKey: string;
}

export interface MediaUploadIntentResponse {
  intentId: string;
  mediaId: string;
  bucket: typeof TARTEEL_STORAGE_BUCKETS.originals;
  objectKey: string;
  expectedSizeBytes: number;
  declaredMimeType: string;
  intentExpiresAt: string;
  /** Returned only by the Backend API; never persisted or logged. */
  signedUploadToken: string;
}

export interface CompleteMediaUploadRequest {
  intentId: string;
}

export type MediaUploadState =
  | 'UPLOADING'
  | 'UPLOADED'
  | 'PROCESSING'
  | 'READY'
  | 'FAILED'
  | 'ARCHIVED';

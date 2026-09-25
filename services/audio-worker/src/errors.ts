import type { ErrorCode } from './types.js';

export class ProcessingError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message: string,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'ProcessingError';
  }
}

export function safeErrorMessage(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  return raw
    .replace(/sb_secret_[A-Za-z0-9_-]+/g, '[REDACTED]')
    .replace(/Bearer\s+\S+/gi, 'Bearer [REDACTED]')
    .replace(/token=[^\s&]+/gi, 'token=[REDACTED]')
    .slice(0, 2_000);
}

export function asProcessingError(error: unknown): ProcessingError {
  if (error instanceof ProcessingError) return error;
  return new ProcessingError('WORKER_INTERNAL_ERROR', safeErrorMessage(error), error);
}

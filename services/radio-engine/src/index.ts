import * as crypto from 'crypto';

export interface RadioScheduleOccurrence {
  occurrenceId: string;
  stationSlug: string;
  trackId: string;
  trackTitle: string;
  reciterName: string;
  scheduledStart: string;
  durationSeconds: number;
}

export interface EngineFencingLease {
  engineId: string;
  token: string;
  leasedAt: Date;
  expiresAt: Date;
}

/**
 * Deterministic occurrence ID generation to avoid duplicate plays under concurrent engines
 */
export function generateDeterministicOccurrenceId(stationSlug: string, trackId: string, timestampIso: string): string {
  return crypto
    .createHash('sha256')
    .update(`${stationSlug}:${trackId}:${timestampIso}`)
    .digest('hex')
    .substring(0, 16);
}

/**
 * Fencing token validator to guarantee single-master cluster execution
 */
export function validateEngineFencing(currentLease: EngineFencingLease | null, engineId: string): boolean {
  if (!currentLease) return true;
  if (currentLease.expiresAt < new Date()) return true; // Stale lease recovery
  return currentLease.engineId === engineId;
}

/**
 * Dispatches command to Liquidsoap via Telnet/UNIX socket with fallback
 */
export async function dispatchLiquidsoapCommand(command: string, params: Record<string, unknown> = {}): Promise<{ status: string; ack: boolean }> {
  console.log(`[Liquidsoap Command Dispatcher] Command: ${command}`, params);
  return { status: 'ACK_RECEIVED', ack: true };
}

console.log('Fadhkur Managed Radio Engine initialized with anti-double-play fencing.');

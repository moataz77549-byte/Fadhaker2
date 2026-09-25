export type EngineMode = 'STARTING'|'AUTO'|'SCHEDULED'|'MANUAL'|'LIVE'|'RECOVERING'|'ERROR'|'STOPPED';

export interface Track {
  mediaId: string | null;
  queueEntryId?: string | null;
  title: string;
  path: string;
  durationSeconds: number;
}

export interface Lease {
  stationId: string;
  ownerId: string;
  fencingToken: number;
  expiresAt: string;
}

export interface EngineSnapshot {
  mode: EngineMode;
  sourceConnected: boolean;
  liquidsoapAlive: boolean;
  icecastReachable: boolean;
  mountAvailable: boolean;
  broadcasting: boolean;
  streamMount: string;
  current: Track | null;
  next: Track | null;
  currentStartedAt: string | null;
  expectedEndAt: string | null;
  sourceStartedAt: string | null;
  lastError: string | null;
  lastRecoveryAt: string | null;
  reconnectCount: number;
  trackFailures: number;
  playoutAckCount: number;
}

export interface LeaseStore {
  acquire(stationId: string, ownerId: string, ttlSeconds: number): Promise<Lease|null>;
  renew(lease: Lease, ttlSeconds: number): Promise<Lease>;
  checkpoint(lease: Lease, snapshot: EngineSnapshot, version: string): Promise<number>;
  release(lease: Lease): Promise<void>;
}

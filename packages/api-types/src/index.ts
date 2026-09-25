/**
 * Shared API and Data Contracts for Fadhkur (فذكر)
 */

export type UUID = string;

export interface Surah {
  id: number;
  number: number;
  nameArabic: string;
  nameEnglish: string;
  nameTransliteration: string;
  ayahCount: number;
  revelationType: 'meccan' | 'medinan';
  pageNumber: number;
}

export interface Ayah {
  id: number;
  surahNumber: number;
  ayahNumber: number;
  textArabicUthmani: string;
  textArabicSimple: string;
  pageNumber: number;
  juzNumber: number;
  hizbQuarter: number;
}

export interface Reciter {
  id: UUID;
  nameArabic: string;
  nameEnglish: string;
  slug: string;
  bioArabic?: string;
  rewaya: string; // e.g., 'Hafs A\'n Assem'
  avatarUrl?: string;
  isFeatured: boolean;
  surahsAvailableCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface AudioTrack {
  id: UUID;
  reciterId: UUID;
  surahNumber: number;
  audioUrl: string;
  durationSeconds: number;
  fileSizeBytes: number;
  bitrateKbps: number;
  format: 'mp3' | 'aac' | 'm4a' | 'flac';
  loudnessLufs: number; // Normalized target e.g. -16.0 LUFS
  waveform?: number[]; // Normalized 100-point waveform
  checksumSha256: string;
  createdAt: string;
}

export interface RadioStation {
  id: UUID;
  titleArabic: string;
  titleEnglish: string;
  slug: string;
  streamUrl: string;
  fallbackStreamUrl?: string;
  status: 'active' | 'scheduled' | 'offline';
  currentReciterName?: string;
  currentSurahName?: string;
  currentTrackId?: UUID;
  listenersCount: number;
  coverUrl?: string;
}

export interface PlaylistItem {
  id: UUID;
  radioId: UUID;
  audioTrackId: UUID;
  position: number;
  scheduledTime?: string;
  durationSeconds: number;
}

export interface MaintenanceConfig {
  isInMaintenance: boolean;
  messageArabic: string;
  messageEnglish: string;
  minAppVersionRequired: string;
  forceUpdateUrl?: string;
}

export interface RemoteConfigData {
  maintenance: MaintenanceConfig;
  features: {
    enableElysiaBff: boolean;
    enableLiveRadio: boolean;
    enableWaveforms: boolean;
    enableAudioDownloads: boolean;
  };
  announcements: {
    id: string;
    title: string;
    body: string;
    dismissible: boolean;
  }[];
  routesAllowList: string[];
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
    details?: unknown;
  };
  timestamp: string;
}

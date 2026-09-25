import { fetchProviderJson } from './provider_http.ts';

type JsonRecord = Record<string, unknown>;

export interface QuranEncEdition {
  key: string;
  language: string;
  title: string;
  version: string;
  updatedAt: string | null;
}

export function normalizeEdition(payload: unknown, key: string): QuranEncEdition {
  // QuranEnc currently returns the translation catalog as a top-level JSON
  // array. Older mirrors/proxies have also wrapped it in { translations: [] }.
  // Accept both documented shapes, but fail closed on everything else.
  const catalog = Array.isArray(payload)
    ? payload
    : payload && typeof payload === 'object' &&
        Array.isArray((payload as JsonRecord).translations)
      ? (payload as JsonRecord).translations as unknown[]
      : null;
  if (catalog == null) throw new Error('invalid_edition_catalog');
  const edition = catalog
    .find(v => v && typeof v === 'object' && (v as JsonRecord).key === key) as JsonRecord | undefined;
  if (!edition || typeof edition.language_iso_code !== 'string' ||
      typeof edition.version !== 'string' || !edition.version.trim() ||
      typeof edition.title !== 'string') throw new Error('unknown_or_unversioned_translation');
  const seconds = Number(edition.last_update);
  return {
    key,
    language: edition.language_iso_code,
    title: edition.title,
    version: edition.version,
    updatedAt: Number.isFinite(seconds) && seconds > 0
      ? new Date(seconds * 1000).toISOString() : null,
  };
}

export function normalizeSurah(payload: unknown, surah: number, expectedCount: number):
    Array<{ surah: number; ayah: number; translation: string; footnotes: string }> {
  const result = payload && typeof payload === 'object' && (payload as JsonRecord).result;
  if (!Array.isArray(result) || result.length !== expectedCount) {
    throw new Error('surah_translation_count_mismatch');
  }
  const seen = new Set<number>();
  return result.map((value: unknown) => {
    if (!value || typeof value !== 'object') throw new Error('invalid_translation_row');
    const row = value as JsonRecord;
    const aya = Number(row.aya);
    if (Number(row.sura) !== surah || !Number.isInteger(aya) ||
        aya < 1 || aya > expectedCount || seen.has(aya) ||
        typeof row.translation !== 'string' || !row.translation.trim()) {
      throw new Error('invalid_translation_row');
    }
    seen.add(aya);
    return {
      surah,
      ayah: aya,
      translation: row.translation,
      footnotes: typeof row.footnotes === 'string' ? row.footnotes : '',
    };
  }).sort((a, b) => a.ayah - b.ayah);
}

export async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)))
    .map(v => v.toString(16).padStart(2, '0')).join('');
}

// No canonical Quran text is read or written. The caller persists validated
// translation rows only after the entire surah has passed count/id checks.
export async function fetchQuranEncBatch(
  key: string, surah: number, expectedCount: number,
  options: Parameters<typeof fetchProviderJson>[1] = {},
) {
  if (!/^[a-z0-9_]{3,80}$/.test(key) || surah < 1 || surah > 114) {
    throw new Error('invalid_translation_request');
  }
  const sourceUrl = `https://quranenc.com/api/v1/translation/sura/${key}/${surah}`;
  const payload = await fetchProviderJson(sourceUrl, options);
  return { sourceUrl, rows: normalizeSurah(payload, surah, expectedCount) };
}

export function resolvePageFromLookupPayload(
  payload: { pages?: Record<string, unknown> },
): number | null {
  const page = Object.keys(payload.pages ?? {})
    .map(Number)
    .find((value) => Number.isInteger(value) && value >= 1 && value <= 604);
  return page ?? null;
}

export function parseVerseKey(value: string): { chapter: number; verse: number } | null {
  const match = /^(\d{1,3}):(\d{1,3})$/.exec(value.trim());
  if (!match) return null;
  const chapter = Number(match[1]);
  const verse = Number(match[2]);
  if (!Number.isInteger(chapter) || chapter < 1 || chapter > 114 ||
      !Number.isInteger(verse) || verse < 1) {
    return null;
  }
  return { chapter, verse };
}

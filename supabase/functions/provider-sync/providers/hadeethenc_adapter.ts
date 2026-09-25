import { fetchProviderJson } from './provider_http.ts';
type Entry = Record<string, unknown>;

export function normalizeHadithPage(payload: unknown, requestedPage: number, maxItems: number) {
  if (!payload || typeof payload !== 'object') throw new Error('invalid_hadith_page');
  const { data, meta } = payload as Entry;
  if (!Array.isArray(data) || !meta || typeof meta !== 'object' ||
      Number((meta as Entry).current_page) !== requestedPage ||
      !Number.isInteger(Number((meta as Entry).last_page)) ||
      data.length > maxItems) throw new Error('invalid_hadith_page');
  const seen = new Set<string>();
  const ids = data.map(item => {
    if (!item || typeof item !== 'object' ||
        !/^\d{1,12}$/.test(String((item as Entry).id))) {
      throw new Error('invalid_hadith_identity');
    }
    const id = String((item as Entry).id);
    if (seen.has(id)) throw new Error('duplicate_hadith_identity');
    seen.add(id);
    return id;
  });
  return { ids, lastPage: Number((meta as Entry).last_page) };
}

export function normalizeHadithDetail(payload: unknown, requestedId: string) {
  if (!payload || typeof payload !== 'object') throw new Error('invalid_hadith_detail');
  const data = payload as Entry;
  if (String(data.id) !== requestedId || typeof data.hadeeth !== 'string' ||
      !data.hadeeth.trim() || typeof data.reference !== 'string' ||
      !data.reference.trim()) throw new Error('unreferenced_hadith');
  const optionalText = (key: string) => typeof data[key] === 'string' ? data[key] as string : null;
  const hints = Array.isArray(data.hints) && data.hints.every(v => typeof v === 'string')
    ? data.hints as string[] : [];
  const categories = Array.isArray(data.categories)
    ? data.categories.map(v => String(v)).filter(v => /^\d{1,12}$/.test(v)) : [];
  return { id: requestedId, title: optionalText('title'), text: data.hadeeth,
    attribution: optionalText('attribution'), grade: optionalText('grade'),
    explanation: optionalText('explanation'), benefits: hints.join('\n'),
    reference: data.reference, categories };
}

export async function fetchHadithPage(
  language: string, categoryId: string, page: number, perPage: number,
  options: Parameters<typeof fetchProviderJson>[1] = {},
) {
  if (!/^[a-z]{2,3}$/.test(language) || !/^\d{1,12}$/.test(categoryId) ||
      !Number.isInteger(page) || page < 1 || !Number.isInteger(perPage) ||
      perPage < 1 || perPage > 10) throw new Error('invalid_hadith_request');
  const url = new URL('https://hadeethenc.com/api/v1/hadeeths/list/');
  url.search = new URLSearchParams({ language, category_id: categoryId,
    page: String(page), per_page: String(perPage) }).toString();
  return normalizeHadithPage(await fetchProviderJson(url.toString(), options), page, perPage);
}

export async function fetchHadithDetail(
  language: string, id: string, options: Parameters<typeof fetchProviderJson>[1] = {},
) {
  if (!/^[a-z]{2,3}$/.test(language) || !/^\d{1,12}$/.test(id))
    throw new Error('invalid_hadith_request');
  const url = new URL('https://hadeethenc.com/api/v1/hadeeths/one/');
  url.search = new URLSearchParams({ id, language }).toString();
  return { sourceUrl: `https://hadeethenc.com/${language}/browse/hadith/${id}`,
    detail: normalizeHadithDetail(await fetchProviderJson(url.toString(), options), id) };
}

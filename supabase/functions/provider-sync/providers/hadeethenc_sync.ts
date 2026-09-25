import { fetchProviderJson } from './provider_http.ts';
import { fetchHadithPage, fetchHadithDetail } from './hadeethenc_adapter.ts';
import { sha256 } from './quranenc_adapter.ts';

// The source supplies no version for this endpoint. Keep source_version NULL
// rather than inventing one. The exact source URL and content hash remain.
export async function syncHadithCategory(db: any, provider: { id: string }, input: Record<string, unknown>) {
  const categoryId = String(input.categoryId ?? '');
  const language = String(input.language ?? 'ar');
  const dryRun = input.dryRun === true;
  const full = input.full === true;
  const perPage = Number(input.perPage ?? 5);
  if (!/^\d{1,12}$/.test(categoryId) || !/^[a-z]{2,3}$/.test(language) ||
      !Number.isInteger(perPage) || perPage < 1 || perPage > 10) {
    throw new Error('invalid_hadith_request');
  }
  const dataset = `hadith:${language}:${categoryId}`;
  const { data: previousState } = await db.schema('app').from('provider_sync_state')
    .select('cursor_data').eq('provider_id', provider.id).eq('dataset', dataset).maybeSingle();
  const cursor = previousState?.cursor_data;
  const page = full ? 1 : Number(cursor?.next_page) || 1;
  if (!Number.isInteger(page) || page < 1 || page > 100000) throw new Error('invalid_hadith_cursor');
  let requestCount = 0, rateLimitEvents = 0;
  const opts = { onRequest: (limited: boolean) => {
    if (limited) rateLimitEvents++; else requestCount++;
  } };
  const started = Date.now();
  const { data: run, error: runError } = await db.schema('app').from('provider_sync_runs')
    .insert({ provider_id: provider.id, dataset,
      idempotency_key: `${dataset}:${crypto.randomUUID()}`,
      status: 'RUNNING', started_at: new Date().toISOString(),
      metadata: { dry_run: dryRun, full } }).select('id').single();
  if (runError || !run) throw new Error('sync_run_unavailable');
  let fetched = 0, inserted = 0, updated = 0, unchanged = 0;
  try {
    const categoryUrl = `https://hadeethenc.com/api/v1/categories/list/?language=${language}`;
    const categories = await fetchProviderJson(categoryUrl, opts);
    if (!Array.isArray(categories)) throw new Error('invalid_hadith_categories');
    const category = categories.find(c => c && typeof c === 'object' && String(c.id) === categoryId);
    if (!category || typeof category.title !== 'string' || !category.title.trim())
      throw new Error('hadith_category_missing');
    let dbCategoryId: string | null = null;
    if (!dryRun) {
      const { data, error } = await db.schema('app').from('hadith_categories').upsert({
        provider_id: provider.id, external_id: categoryId, language_code: language,
        name: category.title, parent_external_id: category.parent_id
          ? String(category.parent_id) : null,
        source_url: categoryUrl, content_hash: await sha256(category.title),
        synced_at: new Date().toISOString(), is_active: false,
      }, { onConflict: 'provider_id,external_id,language_code' }).select('id').single();
      if (error || !data) throw new Error('hadith_category_upsert_failed');
      dbCategoryId = data.id;
    }
    const list = await fetchHadithPage(language, categoryId, page, perPage, opts);
    if (!list.ids.length && page <= list.lastPage) throw new Error('empty_hadith_page');
    for (const id of list.ids) {
      const { sourceUrl, detail } = await fetchHadithDetail(language, id, opts);
      const hash = await sha256(JSON.stringify([detail.text, detail.title,
        detail.attribution, detail.grade, detail.explanation, detail.benefits,
        detail.reference]));
      const { data: existing, error: lookupError } = await db.schema('app').from('hadiths')
        .select('id,content_hash').eq('provider_id', provider.id)
        .eq('external_id', id).eq('language_code', language).maybeSingle();
      if (lookupError) throw new Error('hadith_lookup_failed');
      fetched++;
      if (existing?.content_hash === hash) unchanged++;
      else if (existing) updated++; else inserted++;
      if (!dryRun) {
        const { data: saved, error } = await db.schema('app').from('hadiths').upsert({
          provider_id: provider.id, external_id: id, language_code: language,
          title: detail.title, hadith_text: detail.text, attribution: detail.attribution,
          grade: detail.grade, explanation: detail.explanation,
          benefits: detail.benefits, reference: detail.reference,
          source_url: sourceUrl, content_hash: hash, synced_at: new Date().toISOString(),
          verified_at: null, is_active: false,
        }, { onConflict: 'provider_id,external_id,language_code' }).select('id').single();
        if (error || !saved) throw new Error('hadith_upsert_failed');
        const link = await db.schema('app').from('hadith_category_links').upsert({
          hadith_id: saved.id, category_id: dbCategoryId,
        }, { onConflict: 'hadith_id,category_id' });
        if (link.error) throw new Error('hadith_category_link_failed');
      }
    }
    const nextPage = page + 1;
    if (!dryRun) {
      const { error } = await db.schema('app').from('provider_sync_state').upsert({
        provider_id: provider.id, dataset,
        cursor_data: { next_page: nextPage, last_page: list.lastPage },
        last_success_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      }, { onConflict: 'provider_id,dataset' });
      if (error) throw new Error('hadith_cursor_failed');
    }
    const status = nextPage > list.lastPage ? 'COMPLETED' : 'PARTIAL';
    await db.schema('app').from('provider_sync_runs').update({ status,
      fetched_count: fetched, inserted_count: inserted, updated_count: updated,
      unchanged_count: unchanged, cursor_data: { next_page: nextPage },
      finished_at: new Date().toISOString(), metadata: { dry_run: dryRun,
        request_count: requestCount, rate_limit_events: rateLimitEvents,
        duration_ms: Date.now() - started } }).eq('id', run.id);
    console.info(JSON.stringify({ event: 'provider_sync', provider: 'hadeethenc', dataset,
      status, fetched, inserted, updated, unchanged, request_count: requestCount,
      rate_limit_events: rateLimitEvents, duration_ms: Date.now() - started }));
    return { run_id: run.id, status, dry_run: dryRun, next_page: nextPage,
      fetched, inserted, updated, unchanged };
  } catch (error) {
    const code = error instanceof Error ? error.message : 'hadith_sync_error';
    await db.schema('app').from('provider_sync_runs').update({ status: 'FAILED',
      error_code: code.slice(0, 80), fetched_count: fetched,
      finished_at: new Date().toISOString(), metadata: { dry_run: dryRun,
        request_count: requestCount, rate_limit_events: rateLimitEvents,
        duration_ms: Date.now() - started } }).eq('id', run.id);
    throw error;
  }
}

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { fetchProviderJson } from './providers/provider_http.ts';
import { fetchQuranEncBatch, normalizeEdition, sha256 } from './providers/quranenc_adapter.ts';
import { syncHadithCategory } from './providers/hadeethenc_sync.ts';

const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { 'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-provider-sync-secret',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS' },
});

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return json({}, 200);
  if (req.method !== 'POST' && req.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !serviceKey) return json({ error: 'Backend unavailable' }, 503);
  const db = createClient(url, serviceKey);
  const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const cronSecret = req.headers.get('x-provider-sync-secret') ?? '';
  let authorized = bearer.length > 0 && bearer === serviceKey;
  if (!authorized && cronSecret) {
    const { data: expected, error } = await db.rpc('get_cron_secret', { p_name: 'provider-sync' });
    authorized = !error && typeof expected === 'string' && expected.length >= 32 &&
      cronSecret === expected;
  }
  if (!authorized && bearer) {
    const { data, error } = await db.auth.getUser(bearer);
    if (!error && data.user) {
      const userDb = createClient(url, serviceKey, {
        global: { headers: { Authorization: `Bearer ${bearer}` } },
      });
      const permission = await userDb.schema('app').rpc('has_permission', {
        p_perm: req.method === 'GET' ? 'providers.read' : 'providers.sync',
      });
      authorized = !permission.error && permission.data === true;
    }
  }
  if (!authorized) return json({ error: 'Unauthorized' }, 401);

  if (req.method === 'GET') {
    const requestUrl = new URL(req.url);
    const review = requestUrl.searchParams.get('review');
    const limit = Math.min(30, Math.max(1, Number(requestUrl.searchParams.get('limit') ?? 20)));
    const offset = Math.min(3000, Math.max(0, Number(requestUrl.searchParams.get('offset') ?? 0)));
    if (!Number.isInteger(limit) || !Number.isInteger(offset)) {
      return json({ error: 'Invalid pagination' }, 400);
    }

    if (review === 'translations') {
      const { data, error, count } = await db.schema('app').from('quran_translations')
        .select(
          'id,provider_id,translation_key,language_code,title,surah_number,ayah_number,' +
          'translation_text,footnotes,source_url,source_version,last_synced_at,is_active',
          { count: 'exact' },
        )
        .order('last_synced_at', { ascending: false })
        .range(offset, offset + limit - 1);
      if (error) return json({ error: 'Translation review unavailable' }, 503);
      return json({ dataset: review, items: data ?? [], count: count ?? 0, limit, offset });
    }

    if (review === 'hadiths') {
      const { data, error, count } = await db.schema('app').from('hadiths')
        .select(
          'id,provider_id,language_code,title,hadith_text,narrator,grade,attribution,' +
          'reference,source_url,verified_at,synced_at,is_active',
          { count: 'exact' },
        )
        .order('synced_at', { ascending: false })
        .range(offset, offset + limit - 1);
      if (error) return json({ error: 'Hadith review unavailable' }, 503);
      return json({ dataset: review, items: data ?? [], count: count ?? 0, limit, offset });
    }

    if (review != null && review.isNotEmpty) {
      return json({ error: 'Unsupported review dataset' }, 422);
    }

    const [providers, runs, translations, hadiths] = await Promise.all([
      db.schema('app').from('content_providers').select('id,name,slug,production_enabled,rights_status,commercial_use_status,health_status,verified_at,last_success_at').is('deleted_at', null).order('priority', { ascending: false }),
      db.schema('app').from('provider_sync_runs').select('id,provider_id,dataset,status,started_at,finished_at,fetched_count,inserted_count,updated_count,unchanged_count,error_code,metadata').order('created_at', { ascending: false }).limit(30),
      db.schema('app').from('quran_translations').select('id', { count: 'exact', head: true }),
      db.schema('app').from('hadiths').select('id', { count: 'exact', head: true }),
    ]);
    if (providers.error || runs.error || translations.error || hadiths.error)
      return json({ error: 'Provider status unavailable' }, 503);
    return json({ providers: providers.data, runs: runs.data,
      counts: { translations: translations.count ?? 0, hadiths: hadiths.count ?? 0 } });
  }

  let input: Record<string, unknown>;
  try {
    if (Number(req.headers.get('content-length') ?? 0) > 4096) return json({ error: 'Request too large' }, 413);
    const body = await req.text();
    if (body.length > 4096) return json({ error: 'Request too large' }, 413);
    // Preserve the existing scheduler's empty POST health contract.
    if (!body.trim()) {
      const { count, error } = await db.schema('app').from('stations')
        .select('id', { count: 'exact', head: true }).eq('is_active', true);
      return error ? json({ error: 'Provider sync query failed' }, 503)
        : json({ success: true, checkedStationsCount: count ?? 0,
          syncedAt: new Date().toISOString() });
    }
    input = JSON.parse(body);
    if (!input || Array.isArray(input) || typeof input !== 'object') throw Error('bad input');
  } catch (_) {
    return json({ error: 'Invalid request' }, 400);
  }
  const providerSlug = input.provider;
  const dataset = input.dataset;
  const editionKey = input.translationKey;
  const full = input.full === true;
  const dryRun = input.dryRun === true;
  const limitSurahs = input.limitSurahs === undefined ? 1 : Number(input.limitSurahs);
  if (!((providerSlug === 'quranenc' && dataset === 'translations' &&
      typeof editionKey === 'string' && /^[a-z0-9_]{3,80}$/.test(editionKey) &&
      Number.isInteger(limitSurahs) && limitSurahs >= 1 && limitSurahs <= 3) ||
      (providerSlug === 'hadeethenc' && dataset === 'hadith'))) {
    return json({ error: 'Unsupported provider or invalid dataset arguments' }, 422);
  }
  const { data: provider, error: providerError } = await db.schema('app').from('content_providers')
    .select('id,rights_status,production_enabled,is_active')
    .eq('slug', providerSlug).is('deleted_at', null).single();
  if (providerError || !provider || !provider.is_active) return json({ error: 'Provider unavailable' }, 422);

  if (providerSlug === 'hadeethenc') {
    try {
      return json(await syncHadithCategory(db, provider, input));
    } catch (error) {
      const code = error instanceof Error ? error.message : 'hadith_sync_error';
      return json({ error: 'Sync failed', code: code.slice(0, 80) }, 502);
    }
  }

  const stateKey = `translations:${editionKey}`;
  const { data: syncState } = await db.schema('app').from('provider_sync_state')
    .select('cursor_data').eq('provider_id', provider.id).eq('dataset', stateKey).maybeSingle();
  const saved = syncState?.cursor_data && typeof syncState.cursor_data === 'object'
    ? syncState.cursor_data as Record<string, unknown> : {};
  let requestCount = 0;
  let rateLimitEvents = 0;
  const opts = { onRequest: (limited: boolean) => {
    if (limited) rateLimitEvents++;
    else requestCount++;
  } };
  const started = Date.now();
  const runKey = `${providerSlug}:${stateKey}:${crypto.randomUUID()}`;
  const { data: run, error: runError } = await db.schema('app').from('provider_sync_runs')
    .insert({ provider_id: provider.id, dataset: stateKey, idempotency_key: runKey,
      status: 'RUNNING', started_at: new Date().toISOString(),
      metadata: { dry_run: dryRun, full } })
    .select('id').single();
  if (runError || !run) return json({ error: 'Sync run unavailable' }, 503);
  let fetched = 0, inserted = 0, updated = 0, unchanged = 0;
  let cursor = 1;
  let editionVersion = '';
  try {
    const edition = normalizeEdition(
      await fetchProviderJson('https://quranenc.com/api/v1/translations/list', opts), editionKey);
    editionVersion = edition.version;
    cursor = full || saved.version !== edition.version ? 1 : Number(saved.next_surah) || 1;
    if (cursor < 1 || cursor > 115 || !Number.isInteger(cursor)) cursor = 1;
    const end = Math.min(114, cursor + limitSurahs - 1);
    for (let surah = cursor; surah <= end; surah++) {
      const { data: chapter, error: chapterError } = await db.schema('app').from('surahs')
        .select('ayah_count').eq('number', surah).single();
      if (chapterError || !chapter?.ayah_count) throw new Error('missing_surah_baseline');
      const batch = await fetchQuranEncBatch(editionKey, surah, chapter.ayah_count, opts);
      const { data: previous, error: previousError } = await db.schema('app').from('quran_translations')
        .select('ayah_number,content_hash').eq('provider_id', provider.id)
        .eq('translation_key', editionKey).eq('surah_number', surah);
      if (previousError) throw new Error('translation_lookup_failed');
      const known = new Map((previous ?? []).map(row => [row.ayah_number, row.content_hash]));
      const changed = [];
      for (const row of batch.rows) {
        const hash = await sha256(`${edition.version}\u0000${row.translation}\u0000${row.footnotes}`);
        fetched++;
        if (known.get(row.ayah) === hash) {
          unchanged++;
          continue;
        }
        if (known.has(row.ayah)) updated++; else inserted++;
        changed.push({ provider_id: provider.id, translation_key: editionKey,
          source_external_id: `${editionKey}:${surah}:${row.ayah}`,
          language_code: edition.language, title: edition.title,
          surah_number: surah, ayah_number: row.ayah,
          translation_text: row.translation, footnotes: row.footnotes,
          source_url: batch.sourceUrl, source_version: edition.version,
          content_hash: hash, source_updated_at: edition.updatedAt,
          last_synced_at: new Date().toISOString(),
          is_active: provider.production_enabled && provider.rights_status === 'APPROVED' });
      }
      if (!dryRun && changed.length) {
        const { error } = await db.schema('app').from('quran_translations').upsert(changed,
          { onConflict: 'provider_id,translation_key,surah_number,ayah_number' });
        if (error) throw new Error('translation_upsert_failed');
      }
      if (!dryRun) {
        const { error } = await db.schema('app').from('provider_sync_state').upsert({
          provider_id: provider.id, dataset: stateKey,
          cursor_data: { version: edition.version, next_surah: surah + 1 },
          last_success_at: new Date().toISOString(), updated_at: new Date().toISOString(),
        }, { onConflict: 'provider_id,dataset' });
        if (error) throw new Error('sync_cursor_failed');
      }
      cursor = surah + 1;
    }
    const finished = new Date().toISOString();
    const status = cursor > 114 ? 'COMPLETED' : 'PARTIAL';
    const { error } = await db.schema('app').from('provider_sync_runs').update({
      status, fetched_count: fetched, inserted_count: inserted, updated_count: updated,
      unchanged_count: unchanged, cursor_data: { version: editionVersion, next_surah: cursor },
      finished_at: finished, metadata: { dry_run: dryRun, full, request_count: requestCount,
        rate_limit_events: rateLimitEvents, duration_ms: Date.now() - started },
    }).eq('id', run.id);
    if (error) throw new Error('sync_run_update_failed');
    console.info(JSON.stringify({ event: 'provider_sync', provider: providerSlug, dataset: stateKey,
      status, fetched, inserted, updated, unchanged, request_count: requestCount,
      rate_limit_events: rateLimitEvents, duration_ms: Date.now() - started }));
    return json({ run_id: run.id, status, dry_run: dryRun, next_surah: cursor,
      fetched, inserted, updated, unchanged });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'unexpected_provider_error';
    await db.schema('app').from('provider_sync_runs').update({ status: 'FAILED',
      error_code: code.slice(0, 80), fetched_count: fetched, inserted_count: inserted,
      updated_count: updated, unchanged_count: unchanged, finished_at: new Date().toISOString(),
      metadata: { request_count: requestCount, rate_limit_events: rateLimitEvents,
        duration_ms: Date.now() - started } }).eq('id', run.id);
    console.warn(JSON.stringify({ event: 'provider_sync', provider: providerSlug,
      dataset: stateKey, status: 'FAILED', error_code: code.slice(0, 80) }));
    return json({ run_id: run.id, error: 'Sync failed', code: code.slice(0, 80) }, 502);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchProviderJson, ProviderHttpError } from './provider_http.ts';
import { normalizeEdition, normalizeSurah, fetchQuranEncBatch, sha256 } from './quranenc_adapter.ts';

const catalog = [{ key: 'english_saheeh', language_iso_code: 'en',
  title: 'Translation', version: '1.0.9', last_update: 1700000000 }];
test('edition version and source metadata', () => {
  assert.equal(normalizeEdition(catalog, 'english_saheeh').version, '1.0.9');
  // Keep compatibility with a legacy/proxy wrapper while preferring the
  // documented top-level array returned by QuranEnc.
  assert.equal(normalizeEdition({ translations: catalog }, 'english_saheeh').version, '1.0.9');
  assert.throws(() => normalizeEdition([], 'english_saheeh'));
  assert.throws(() => normalizeEdition({ translations: [] }, 'english_saheeh'));
});
test('surah validation fails closed on mismatches and duplicates', () => {
  const good = { result: [{ sura: '1', aya: '2', translation: 'second' },
    { sura: '1', aya: '1', translation: 'first', footnotes: 'note' }] };
  assert.deepEqual(normalizeSurah(good, 1, 2).map(v => v.ayah), [1, 2]);
  assert.throws(() => normalizeSurah(good, 1, 3));
  assert.throws(() => normalizeSurah({ result: [good.result[0], good.result[0]] }, 1, 2));
  assert.throws(() => normalizeSurah({ result: [{ ...good.result[0], sura: 2 }] }, 1, 1));
});
test('no arbitrary host or empty/malformed response', async () => {
  await assert.rejects(fetchProviderJson('https://untrusted.example/api'),
    e => e instanceof ProviderHttpError && e.code === 'unapproved_provider_host');
  const fetcher = async () => new Response('{', { status: 200 });
  await assert.rejects(fetchProviderJson('https://quranenc.com/api/v1/translations/list', { fetcher }),
    e => e.code === 'provider_malformed_json');
});
test('HTTP 429 retries and timeout is bounded', async () => {
  let calls = 0, rateLimits = 0;
  const json = await fetchProviderJson('https://quranenc.com/api/v1/translations/list', {
    fetcher: async () => ++calls === 1
      ? new Response('', { status: 429 }) : Response.json(catalog),
    onRequest: limited => { if (limited) rateLimits++; }, sleep: async () => {},
  });
  assert.equal(calls, 2);
  assert.equal(rateLimits, 1);
  assert.deepEqual(json, catalog);
  await assert.rejects(fetchProviderJson('https://quranenc.com/api/v1/translations/list', {
    fetcher: async () => { throw new Error('timeout'); }, sleep: async () => {},
  }), e => e.code === 'provider_timeout');
});
test('fetches a single documented surah and hashes its exact content', async () => {
  const result = await fetchQuranEncBatch('english_saheeh', 1, 1, {
    fetcher: async url => {
      assert.match(url, /translation\/sura\/english_saheeh\/1$/);
      return Response.json({ result: [{ sura: '1', aya: '1', translation: 'original' }] });
    },
  });
  assert.equal(result.rows[0].translation, 'original');
  assert.match(await sha256('original'), /^[a-f0-9]{64}$/);
});

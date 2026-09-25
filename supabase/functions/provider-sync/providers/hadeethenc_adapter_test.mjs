import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeHadithPage, normalizeHadithDetail, fetchHadithPage } from './hadeethenc_adapter.ts';

test('category page validates pagination and unique provider identities', () => {
  const valid = { data: [{ id: '12' }, { id: '13' }],
    meta: { current_page: '1', last_page: 2 } };
  assert.deepEqual(normalizeHadithPage(valid, 1, 3), { ids: ['12', '13'], lastPage: 2 });
  assert.throws(() => normalizeHadithPage(valid, 2, 3));
  assert.throws(() => normalizeHadithPage({ ...valid, data: [{ id: '12' }, { id: '12' }] }, 1, 3));
  assert.throws(() => normalizeHadithPage({ ...valid, data: [{ id: '../../x' }] }, 1, 3));
});
test('detail preserves original text, references and source grade', () => {
  const row = { id: '12', title: 'a', hadeeth: 'original text', reference: 'reference',
    grade: 'grade', hints: ['one', 'two'], categories: ['1', '2'] };
  assert.equal(normalizeHadithDetail(row, '12').text, 'original text');
  assert.equal(normalizeHadithDetail(row, '12').benefits, 'one\ntwo');
  assert.throws(() => normalizeHadithDetail({ ...row, reference: '' }, '12'));
  assert.throws(() => normalizeHadithDetail(row, '13'));
});
test('bounded API query rejects untrusted category and pages', async () => {
  await assert.rejects(fetchHadithPage('ar', '../../etc', 1, 5));
  await assert.rejects(fetchHadithPage('ar', '1', 1, 100));
  const result = await fetchHadithPage('ar', '1', 1, 1, {
    fetcher: async url => {
      assert.equal(new URL(url).searchParams.get('category_id'), '1');
      return Response.json({ data: [{ id: '2962' }], meta: { current_page: 1, last_page: 1 } });
    },
  });
  assert.deepEqual(result.ids, ['2962']);
});

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseVerseKey,
  resolvePageFromLookupPayload,
} from './quran_mapping.ts';

test('QCF V2 lookup payload maps documented verse keys to page keys', () => {
  const fixtures = [
    ['1:1', '1'],
    ['2:255', '42'],
    ['18:1', '293'],
    ['114:6', '604'],
  ];

  for (const [verseKey, pageKey] of fixtures) {
    const resolved = resolvePageFromLookupPayload({
      pages: {
        [pageKey]: {
          from: verseKey,
          to: verseKey,
          first_verse_key: verseKey,
          last_verse_key: verseKey,
        },
      },
    });
    assert.equal(resolved, Number(pageKey), verseKey);
  }
});

test('rejects invalid/empty page lookup payloads', () => {
  assert.equal(resolvePageFromLookupPayload({ pages: {} }), null);
  assert.equal(resolvePageFromLookupPayload({ pages: { '0': {} } }), null);
  assert.equal(resolvePageFromLookupPayload({ pages: { '605': {} } }), null);
});

test('verse key parser validates basic bounds', () => {
  assert.deepEqual(parseVerseKey('2:255'), { chapter: 2, verse: 255 });
  assert.equal(parseVerseKey('0:1'), null);
  assert.equal(parseVerseKey('115:1'), null);
  assert.equal(parseVerseKey('bad'), null);
});

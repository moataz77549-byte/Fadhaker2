import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseLocalDateTime, normalizePrayerTimes, matchesRule, matchingRules,
  lastThirdWindow, selectWeighted, refreshAfterSeconds,
} from './resolver.ts';

const prayers = normalizePrayerTimes({
  fajr: '05:00', dhuhr: '12:00', asr: '15:20', maghrib: '18:00', isha: '19:15',
});

const rule = (overrides = {}) => ({
  id: 'r', rule_key: 'r', title_ar: 'قاعدة', trigger_type: 'CLOCK',
  prayer_name: null, start_offset_minutes: null, end_offset_minutes: null,
  starts_at: '06:00:00', ends_at: '18:00:00', days_of_week: [],
  priority: 10, source_pool_key: 'daytime', transition_policy: 'SOFT_DEADLINE',
  refresh_minutes: 15, valid_from: null, valid_until: null, is_active: true,
  ...overrides,
});

test('prayer-relative windows match before and after Fajr', () => {
  const pre = rule({ trigger_type: 'PRAYER_RELATIVE', prayer_name: 'fajr',
    start_offset_minutes: -45, end_offset_minutes: 0 });
  const post = rule({ id: 'post', trigger_type: 'PRAYER_RELATIVE', prayer_name: 'fajr',
    start_offset_minutes: 0, end_offset_minutes: 45 });
  assert.equal(matchesRule(pre, parseLocalDateTime('2026-09-25T04:30:00'), prayers), true);
  assert.equal(matchesRule(post, parseLocalDateTime('2026-09-25T05:10:00'), prayers), true);
  assert.equal(matchesRule(pre, parseLocalDateTime('2026-09-25T05:10:00'), prayers), false);
});

test('last third of night crosses midnight correctly', () => {
  const atTwo = lastThirdWindow(120, prayers.maghrib, prayers.fajr);
  assert.equal(atTwo.active, true);
  const noon = lastThirdWindow(720, prayers.maghrib, prayers.fajr);
  assert.equal(noon.active, false);
});

test('overnight clock rule matches both sides of midnight', () => {
  const night = rule({ starts_at: '19:00:00', ends_at: '05:30:00' });
  assert.equal(matchesRule(night, parseLocalDateTime('2026-09-25T23:20:00'), prayers), true);
  assert.equal(matchesRule(night, parseLocalDateTime('2026-09-25T02:20:00'), prayers), true);
  assert.equal(matchesRule(night, parseLocalDateTime('2026-09-25T12:00:00'), prayers), false);
});

test('Friday and priority resolution are deterministic', () => {
  // 2026-09-25 is Friday.
  const friday = rule({ id: 'fri', rule_key: 'friday', trigger_type: 'FRIDAY',
    priority: 55, source_pool_key: 'friday' });
  const daytime = rule({ id: 'day', priority: 10 });
  const active = matchingRules(
    [daytime, friday],
    parseLocalDateTime('2026-09-25T10:00:00'),
    prayers,
  );
  assert.deepEqual(active.map(v => v.id), ['fri', 'day']);
});

test('weighted source selection is stable and respects weights statistically', () => {
  const items = [{ id: 'a', weight: 1, priority: 0 }, { id: 'b', weight: 9, priority: 0 }];
  assert.equal(selectWeighted(items, 'same-seed')?.id, selectWeighted(items, 'same-seed')?.id);
  let b = 0;
  for (let i = 0; i < 1000; i++) if (selectWeighted(items, `seed-${i}`)?.id === 'b') b++;
  assert.ok(b > 750, `expected weighted item to dominate, got ${b}/1000`);
});

test('refresh interval is bounded by prayer window end', () => {
  const pre = rule({ trigger_type: 'PRAYER_RELATIVE', prayer_name: 'dhuhr',
    start_offset_minutes: -15, end_offset_minutes: 0, refresh_minutes: 15 });
  const seconds = refreshAfterSeconds(
    pre,
    parseLocalDateTime('2026-09-25T11:55:00'),
    prayers,
  );
  assert.equal(seconds, 5 * 60);
});

test('invalid wall clock or prayer input fails closed', () => {
  assert.throws(() => parseLocalDateTime('not-a-date'));
  assert.throws(() => normalizePrayerTimes({
    fajr: '25:00', dhuhr: '12:00', asr: '15:20', maghrib: '18:00', isha: '19:15',
  }));
});

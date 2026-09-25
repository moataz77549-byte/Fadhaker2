export type PrayerName = 'fajr' | 'dhuhr' | 'asr' | 'maghrib' | 'isha';

export type PrayerTimes = Record<PrayerName, number>;

export interface WallClock {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  minuteOfDay: number;
  isoDay: number;
  dateKey: string;
}

export interface SmartRule {
  id: string;
  rule_key: string;
  title_ar: string;
  trigger_type: string;
  prayer_name: PrayerName | null;
  start_offset_minutes: number | null;
  end_offset_minutes: number | null;
  starts_at: string | null;
  ends_at: string | null;
  days_of_week: number[];
  priority: number;
  source_pool_key: string;
  transition_policy: string;
  refresh_minutes: number;
  valid_from: string | null;
  valid_until: string | null;
  is_active: boolean;
}

export function parseLocalDateTime(value: string): WallClock {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?$/.exec(value);
  if (!match) throw new Error('invalid_local_datetime');
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6] ?? 0);
  const date = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day ||
    hour > 23 || minute > 59 || second > 59
  ) throw new Error('invalid_local_datetime');
  const jsDay = date.getUTCDay();
  return {
    year, month, day, hour, minute, second,
    minuteOfDay: hour * 60 + minute,
    isoDay: jsDay === 0 ? 7 : jsDay,
    dateKey: `${match[1]}-${match[2]}-${match[3]}`,
  };
}

export function parseTime(value: string): number {
  const match = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(value);
  if (!match) throw new Error('invalid_time');
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) throw new Error('invalid_time');
  return hour * 60 + minute;
}

export function normalizePrayerTimes(input: Record<string, unknown>): PrayerTimes {
  const output = {} as PrayerTimes;
  for (const key of ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'] as PrayerName[]) {
    if (typeof input[key] !== 'string') throw new Error('invalid_prayer_times');
    output[key] = parseTime(input[key] as string);
  }
  return output;
}

export function isWithinClock(now: number, start: number, end: number): boolean {
  if (start === end) return true;
  if (start < end) return now >= start && now < end;
  return now >= start || now < end;
}

export function isWithinPrayerWindow(
  now: number,
  prayer: number,
  startOffset: number,
  endOffset: number,
): boolean {
  for (const shift of [-1440, 0, 1440]) {
    const start = prayer + startOffset + shift;
    const end = prayer + endOffset + shift;
    if (now >= start && now < end) return true;
  }
  return false;
}

export function lastThirdWindow(
  nowMinute: number,
  maghribMinute: number,
  fajrMinute: number,
): { active: boolean; start: number; end: number; current: number } {
  let start: number;
  let end: number;
  let current = nowMinute;
  if (nowMinute >= maghribMinute) {
    start = maghribMinute;
    end = 1440 + fajrMinute;
  } else if (nowMinute < fajrMinute) {
    start = maghribMinute - 1440;
    end = fajrMinute;
  } else {
    const duration = (1440 - maghribMinute) + fajrMinute;
    const thirdStart = maghribMinute - Math.floor(duration / 3);
    return { active: false, start: thirdStart, end: fajrMinute, current };
  }
  const nightDuration = end - start;
  const lastThirdStart = end - nightDuration / 3;
  return {
    active: current >= lastThirdStart && current < end,
    start: lastThirdStart,
    end,
    current,
  };
}

function dateAllowed(rule: SmartRule, dateKey: string): boolean {
  if (rule.valid_from && dateKey < rule.valid_from) return false;
  if (rule.valid_until && dateKey > rule.valid_until) return false;
  return true;
}

export function matchesRule(
  rule: SmartRule,
  wall: WallClock,
  prayers: PrayerTimes,
): boolean {
  if (!rule.is_active || !dateAllowed(rule, wall.dateKey)) return false;
  const now = wall.minuteOfDay;
  switch (rule.trigger_type) {
    case 'CLOCK':
      return rule.starts_at != null && rule.ends_at != null &&
        isWithinClock(now, parseTime(rule.starts_at), parseTime(rule.ends_at));
    case 'PRAYER_RELATIVE': {
      if (!rule.prayer_name || rule.start_offset_minutes == null ||
          rule.end_offset_minutes == null) return false;
      return isWithinPrayerWindow(
        now,
        prayers[rule.prayer_name],
        rule.start_offset_minutes,
        rule.end_offset_minutes,
      );
    }
    case 'DAY_OF_WEEK':
      return rule.days_of_week.includes(wall.isoDay);
    case 'FRIDAY':
      return wall.isoDay === 5;
    case 'NIGHT_THIRD':
      return lastThirdWindow(now, prayers.maghrib, prayers.fajr).active;
    case 'SEASONAL':
      return true;
    case 'MANUAL_OVERRIDE':
      return false; // overrides live in their own table with absolute expiry.
    default:
      return false;
  }
}

export function matchingRules(
  rules: SmartRule[],
  wall: WallClock,
  prayers: PrayerTimes,
): SmartRule[] {
  return rules
    .filter(rule => matchesRule(rule, wall, prayers))
    .sort((a, b) => b.priority - a.priority || a.rule_key.localeCompare(b.rule_key));
}

function fnv1a(value: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

export function selectWeighted<T extends { weight: number }>(
  items: T[],
  seed: string,
): T | null {
  const valid = items.filter(item => Number.isFinite(item.weight) && item.weight > 0);
  if (valid.length === 0) return null;
  const maxPriority = Math.max(...valid.map(item =>
    typeof (item as T & { priority?: number }).priority === 'number'
      ? (item as T & { priority: number }).priority : 0));
  const prioritized = valid.filter(item =>
    (typeof (item as T & { priority?: number }).priority === 'number'
      ? (item as T & { priority: number }).priority : 0) === maxPriority);
  const total = prioritized.reduce((sum, item) => sum + item.weight, 0);
  let ticket = fnv1a(seed) % total;
  for (const item of prioritized) {
    if (ticket < item.weight) return item;
    ticket -= item.weight;
  }
  return prioritized[prioritized.length - 1];
}

function nearestPrayerWindowEnd(
  now: number,
  prayer: number,
  endOffset: number,
): number | null {
  const ends = [-1440, 0, 1440, 2880]
    .map(shift => prayer + endOffset + shift)
    .filter(end => end > now)
    .sort((a, b) => a - b);
  return ends[0] ?? null;
}

export function refreshAfterSeconds(
  rule: SmartRule,
  wall: WallClock,
  prayers: PrayerTimes,
): number {
  const defaultMinutes = Math.max(5, Math.min(120, rule.refresh_minutes || 15));
  let boundaryMinutes: number | null = null;
  if (rule.trigger_type === 'PRAYER_RELATIVE' && rule.prayer_name &&
      rule.end_offset_minutes != null) {
    const end = nearestPrayerWindowEnd(
      wall.minuteOfDay,
      prayers[rule.prayer_name],
      rule.end_offset_minutes,
    );
    if (end != null) boundaryMinutes = end - wall.minuteOfDay;
  } else if (rule.trigger_type === 'CLOCK' && rule.ends_at) {
    let end = parseTime(rule.ends_at);
    if (end <= wall.minuteOfDay) end += 1440;
    boundaryMinutes = end - wall.minuteOfDay;
  } else if (rule.trigger_type === 'NIGHT_THIRD') {
    const window = lastThirdWindow(wall.minuteOfDay, prayers.maghrib, prayers.fajr);
    let end = window.end;
    let current = window.current;
    if (end <= current) end += 1440;
    boundaryMinutes = end - current;
  } else if (rule.trigger_type === 'FRIDAY') {
    boundaryMinutes = 1440 - wall.minuteOfDay;
  }
  const minutes = boundaryMinutes == null
    ? defaultMinutes
    : Math.max(1, Math.min(defaultMinutes, boundaryMinutes));
  return Math.max(60, Math.round(minutes * 60));
}

export function formatLocalAfter(wall: WallClock, seconds: number): string {
  const date = new Date(Date.UTC(
    wall.year, wall.month - 1, wall.day, wall.hour, wall.minute, wall.second + seconds,
  ));
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}` +
    `T${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`;
}

export function nextRuleBoundary(
  rules: SmartRule[],
  activeRule: SmartRule,
  wall: WallClock,
  prayers: PrayerTimes,
): { rule: SmartRule; minutes: number } | null {
  const now = wall.minuteOfDay;
  const candidates: Array<{ rule: SmartRule; minutes: number }> = [];
  for (const rule of rules) {
    if (!rule.is_active || rule.id === activeRule.id || !dateAllowed(rule, wall.dateKey)) continue;
    let start: number | null = null;
    if (rule.trigger_type === 'PRAYER_RELATIVE' && rule.prayer_name &&
        rule.start_offset_minutes != null) {
      start = prayers[rule.prayer_name] + rule.start_offset_minutes;
      while (start <= now) start += 1440;
    } else if (rule.trigger_type === 'CLOCK' && rule.starts_at) {
      start = parseTime(rule.starts_at);
      if (start <= now) start += 1440;
    } else if (rule.trigger_type === 'NIGHT_THIRD') {
      const duration = (1440 - prayers.maghrib) + prayers.fajr;
      start = prayers.fajr - duration / 3;
      while (start <= now) start += 1440;
    } else if (rule.trigger_type === 'FRIDAY') {
      const days = (5 - wall.isoDay + 7) % 7 || 7;
      // Absolute minute relative to today's local midnight.
      start = days * 1440;
    } else {
      continue;
    }
    const minutes = start - now;
    if (minutes > 0 && minutes <= 7 * 1440) candidates.push({ rule, minutes });
  }
  candidates.sort((a, b) => a.minutes - b.minutes ||
    b.rule.priority - a.rule.priority);
  return candidates[0] ?? null;
}

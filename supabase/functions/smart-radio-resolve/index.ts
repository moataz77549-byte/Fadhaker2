import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import {
  formatLocalAfter,
  matchingRules,
  nextRuleBoundary,
  normalizePrayerTimes,
  parseLocalDateTime,
  refreshAfterSeconds,
  selectWeighted,
  type SmartRule,
} from './resolver.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS, GET',
};

type JsonRecord = Record<string, unknown>;

type SourceRow = {
  id: string;
  program_key: string;
  source_type: string;
  station_id: string | null;
  reciter_track_id: string | null;
  playlist_id: string | null;
  media_id: string | null;
  title_override: string | null;
  priority: number;
  weight: number;
  metadata: JsonRecord;
};

type StationRow = {
  id: string;
  name_ar: string;
  stream_url: string;
  fallback_stream_url: string | null;
  status: string;
  health_status: string;
  is_active: boolean;
  is_playable: boolean;
  production_enabled: boolean;
  rights_status: string;
  commercial_use_status: string;
  external_key: string | null;
  source_url: string | null;
  provider_id: string | null;
  metadata: JsonRecord;
};

type ProviderRow = {
  id: string;
  slug: string;
  is_active: boolean;
  production_enabled: boolean;
  rights_status: string;
  commercial_use_status: string;
  api_stream_links_enabled: boolean;
};

type ResolvedSource = SourceRow & {
  nameAr: string;
  streamUrl: string;
  fallbackUrl: string | null;
  bitrateKbps: number;
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function errorEnvelope(code: string, message: string, status: number): Response {
  return json({ error: { code, message } }, status);
}

function isValidTimezone(value: string): boolean {
  if (value === 'UTC') return true;
  if (!/^[A-Za-z_]+(?:\/[A-Za-z0-9_+\-]+)+$/.test(value)) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value }).format(new Date());
    return true;
  } catch {
    return false;
  }
}

function hasPreciseLocationKeys(input: JsonRecord): boolean {
  const blocked = new Set([
    'lat', 'latitude', 'lng', 'lon', 'long', 'longitude',
    'coordinates', 'exact_location', 'location_history',
  ]);
  return Object.keys(input).some(key => blocked.has(key.toLowerCase()));
}

function bitrateFrom(metadata: JsonRecord): number {
  const value = metadata.bitrate_kbps ?? metadata.bitrate;
  if (typeof value === 'number' && Number.isFinite(value)) return Math.round(value);
  if (typeof value === 'string') return Number.parseInt(value, 10) || 0;
  return 0;
}

function stationEligible(
  station: StationRow,
  provider: ProviderRow | undefined,
): boolean {
  if (!station.is_active || !station.is_playable) return false;
  if (!['HEALTHY', 'DEGRADED'].includes(station.health_status)) return false;
  if (['OFFLINE', 'MAINTENANCE'].includes(station.status)) return false;
  if (!station.stream_url.startsWith('https://')) return false;

  const generallyApproved =
    station.production_enabled &&
    station.rights_status === 'APPROVED' &&
    station.commercial_use_status === 'ALLOWED' &&
    provider?.is_active === true &&
    provider.production_enabled === true &&
    provider.rights_status === 'APPROVED' &&
    provider.commercial_use_status === 'ALLOWED';

  // Mirrors the narrow public RLS exception already used by the application:
  // only official MP3Quran API-linked, healthy station rows are eligible.
  const mp3QuranApiLink =
    station.external_key != null &&
    station.source_url === 'https://www.mp3quran.net/api/v3/radios?language=ar' &&
    station.health_status === 'HEALTHY' &&
    provider?.slug === 'mp3quran' &&
    provider.is_active === true &&
    provider.api_stream_links_enabled === true;

  return generallyApproved || mp3QuranApiLink;
}

function wallSeed(dateKey: string, minute: number, rule: SmartRule): string {
  const bucket = Math.floor(minute / Math.max(5, rule.refresh_minutes || 15));
  return `${dateKey}|${bucket}|${rule.id}|${rule.source_pool_key}`;
}

function fallbackUrlFor(
  candidates: ResolvedSource[],
  selected: ResolvedSource,
  seed: string,
): string | null {
  if (selected.fallbackUrl) return selected.fallbackUrl;
  const alternate = selectWeighted(
    candidates.filter(candidate => candidate.id !== selected.id),
    `${seed}|fallback`,
  );
  return alternate?.streamUrl ?? null;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method === 'GET') {
    return json({
      ok: true,
      service: 'smart-radio-resolve',
      privacy: 'prayer-times-only-no-precise-location',
      serverTimestamp: new Date().toISOString(),
    });
  }
  if (req.method !== 'POST') {
    return errorEnvelope('METHOD_NOT_ALLOWED', 'Only POST is supported for resolution.', 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey) {
    return errorEnvelope('NOT_CONFIGURED', 'Smart radio backend is not configured.', 500);
  }

  let raw = '';
  try {
    raw = await req.text();
    if (raw.length > 16_384) {
      return errorEnvelope('PAYLOAD_TOO_LARGE', 'Request payload is too large.', 413);
    }
  } catch {
    return errorEnvelope('INVALID_BODY', 'Could not read request body.', 400);
  }

  let input: JsonRecord;
  try {
    input = JSON.parse(raw) as JsonRecord;
  } catch {
    return errorEnvelope('INVALID_JSON', 'Request must be valid JSON.', 400);
  }

  if (hasPreciseLocationKeys(input)) {
    return errorEnvelope(
      'PRECISE_LOCATION_NOT_ACCEPTED',
      'Send local prayer times and timezone, not precise coordinates.',
      422,
    );
  }

  const channelSlug = typeof input.channel === 'string' && input.channel.trim()
    ? input.channel.trim() : 'fadhkur-smart';
  if (!/^[a-z0-9-]{2,80}$/.test(channelSlug)) {
    return errorEnvelope('INVALID_CHANNEL', 'Invalid smart radio channel.', 422);
  }
  const timezone = typeof input.timezone === 'string' ? input.timezone.trim() : '';
  if (!isValidTimezone(timezone)) {
    return errorEnvelope('INVALID_TIMEZONE', 'A valid IANA timezone is required.', 422);
  }
  if (typeof input.localDateTime !== 'string') {
    return errorEnvelope('INVALID_LOCAL_TIME', 'localDateTime is required.', 422);
  }

  let wall;
  let prayers;
  try {
    wall = parseLocalDateTime(input.localDateTime);
    if (!input.prayerTimes || typeof input.prayerTimes !== 'object') throw new Error();
    prayers = normalizePrayerTimes(input.prayerTimes as JsonRecord);
  } catch {
    return errorEnvelope('INVALID_SCHEDULE_CONTEXT', 'Local time or prayer times are invalid.', 422);
  }

  // Manual overrides use trusted server time. The client controls only the
  // local wall clock/prayer context used for schedule resolution; it cannot
  // extend or reactivate an expired admin override by spoofing UTC.
  const instant = new Date();

  const db = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: channel, error: channelError } = await db
    .schema('app')
    .from('virtual_radio_channels')
    .select('id,slug,name,is_active,metadata')
    .eq('slug', channelSlug)
    .eq('is_active', true)
    .maybeSingle();
  if (channelError) {
    return errorEnvelope('CHANNEL_QUERY_FAILED', 'Could not resolve smart radio channel.', 503);
  }
  if (!channel) {
    return errorEnvelope('CHANNEL_UNAVAILABLE', 'Smart radio channel is unavailable.', 404);
  }

  const [{ data: ruleRows, error: rulesError }, { data: sourceRows, error: sourcesError }] =
    await Promise.all([
      db.schema('app').from('virtual_radio_rules')
        .select('id,rule_key,title_ar,trigger_type,prayer_name,start_offset_minutes,end_offset_minutes,starts_at,ends_at,days_of_week,priority,source_pool_key,transition_policy,refresh_minutes,valid_from,valid_until,is_active')
        .eq('channel_id', channel.id).eq('is_active', true)
        .order('priority', { ascending: false }),
      db.schema('app').from('virtual_radio_sources')
        .select('id,program_key,source_type,station_id,reciter_track_id,playlist_id,media_id,title_override,priority,weight,metadata')
        .eq('channel_id', channel.id).eq('is_active', true),
    ]);
  if (rulesError || sourcesError) {
    return errorEnvelope('CONFIG_QUERY_FAILED', 'Smart radio configuration is temporarily unavailable.', 503);
  }

  const rules = (ruleRows ?? []) as SmartRule[];
  const sources = (sourceRows ?? []) as SourceRow[];
  const stationIds = [...new Set(sources
    .filter(source => source.source_type === 'LIVE_STATION' && source.station_id)
    .map(source => source.station_id as string))];

  const stationMap = new Map<string, StationRow>();
  const providerMap = new Map<string, ProviderRow>();
  if (stationIds.length > 0) {
    const { data: stations, error } = await db.schema('app').from('stations')
      .select('id,name_ar,stream_url,fallback_stream_url,status,health_status,is_active,is_playable,production_enabled,rights_status,commercial_use_status,external_key,source_url,provider_id,metadata')
      .in('id', stationIds);
    if (error) {
      return errorEnvelope('SOURCE_QUERY_FAILED', 'Could not validate radio sources.', 503);
    }
    for (const station of (stations ?? []) as StationRow[]) stationMap.set(station.id, station);
    const providerIds = [...new Set((stations ?? [])
      .map((station: { provider_id?: string | null }) => station.provider_id)
      .filter((id): id is string => typeof id === 'string'))];
    if (providerIds.length > 0) {
      const { data: providers, error: providerError } = await db.schema('app')
        .from('content_providers')
        .select('id,slug,is_active,production_enabled,rights_status,commercial_use_status,api_stream_links_enabled')
        .in('id', providerIds);
      if (providerError) {
        return errorEnvelope('PROVIDER_QUERY_FAILED', 'Could not validate source rights.', 503);
      }
      for (const provider of (providers ?? []) as ProviderRow[]) providerMap.set(provider.id, provider);
    }
  }

  const eligibleByPool = new Map<string, ResolvedSource[]>();
  for (const source of sources) {
    if (source.source_type !== 'LIVE_STATION' || !source.station_id) continue;
    const station = stationMap.get(source.station_id);
    if (!station) continue;
    const provider = station.provider_id ? providerMap.get(station.provider_id) : undefined;
    if (!stationEligible(station, provider)) continue;
    const resolved: ResolvedSource = {
      ...source,
      nameAr: source.title_override?.trim() || station.name_ar,
      streamUrl: station.stream_url,
      fallbackUrl:
        station.fallback_stream_url?.startsWith('https://') === true &&
          station.fallback_stream_url !== station.stream_url
          ? station.fallback_stream_url
          : null,
      bitrateKbps: bitrateFrom(station.metadata ?? {}),
    };
    const list = eligibleByPool.get(source.program_key) ?? [];
    list.push(resolved);
    eligibleByPool.set(source.program_key, list);
  }

  // Absolute, expiring override wins only when its source is still eligible.
  const instantIso = instant.toISOString();
  const { data: overrides } = await db.schema('app').from('virtual_radio_overrides')
    .select('id,source_id,source_pool_key,title_ar,starts_at,expires_at,transition_policy')
    .eq('channel_id', channel.id).eq('is_active', true)
    .lte('starts_at', instantIso).gt('expires_at', instantIso)
    .order('starts_at', { ascending: false }).limit(5);

  for (const override of overrides ?? []) {
    let candidates: ResolvedSource[] = [];
    if (override.source_id) {
      for (const list of eligibleByPool.values()) {
        const found = list.find(source => source.id === override.source_id);
        if (found) { candidates = [found]; break; }
      }
    } else if (override.source_pool_key) {
      candidates = eligibleByPool.get(override.source_pool_key) ?? [];
    }
    const seed = `override|${override.id}`;
    const selected = selectWeighted(candidates, seed);
    if (!selected) continue;
    const fallbackUrl = override.source_id
      ? selected.fallbackUrl
      : fallbackUrlFor(candidates, selected, seed);
    const seconds = Math.max(
      60,
      Math.min(7200, Math.floor((new Date(override.expires_at).getTime() - instant.getTime()) / 1000)),
    );
    return json({
      channel: { slug: channel.slug, name: channel.name },
      program: {
        key: 'manual_override',
        title: override.title_ar,
        sourceType: selected.source_type,
        sourceId: selected.id,
        sourceName: selected.nameAr,
        streamUrl: selected.streamUrl,
        fallbackUrl,
        bitrateKbps: selected.bitrateKbps,
        validUntil: formatLocalAfter(wall, seconds),
        refreshAfterSeconds: seconds,
        transitionPolicy: override.transition_policy,
        override: true,
      },
      next: null,
      timezone,
      generatedAt: new Date().toISOString(),
      privacy: { preciseLocationReceived: false },
    });
  }

  const activeRules = matchingRules(rules, wall, prayers);
  let chosenRule: SmartRule | null = null;
  let selected: ResolvedSource | null = null;
  let selectedCandidates: ResolvedSource[] = [];
  let selectedSeed = '';
  for (const rule of activeRules) {
    const candidates = eligibleByPool.get(rule.source_pool_key) ?? [];
    const seed = wallSeed(wall.dateKey, wall.minuteOfDay, rule);
    selected = selectWeighted(candidates, seed);
    if (selected) {
      chosenRule = rule;
      selectedCandidates = candidates;
      selectedSeed = seed;
      break;
    }
  }

  let fallbackMode = false;
  if (!chosenRule || !selected) {
    const allEligible = [...eligibleByPool.values()].flat();
    selectedSeed = `fallback|${wall.dateKey}|${wall.hour}`;
    selected = selectWeighted(allEligible, selectedSeed);
    if (!selected) {
      return errorEnvelope('NO_ELIGIBLE_SOURCE', 'No eligible smart-radio source is available.', 503);
    }
    fallbackMode = true;
    selectedCandidates = allEligible;
    chosenRule = {
      id: 'fallback', rule_key: 'fallback', title_ar: 'تلاوات قرآنية',
      trigger_type: 'CLOCK', prayer_name: null, start_offset_minutes: null,
      end_offset_minutes: null, starts_at: null, ends_at: null, days_of_week: [],
      priority: 0, source_pool_key: selected.program_key,
      transition_policy: 'SOFT_DEADLINE', refresh_minutes: 15,
      valid_from: null, valid_until: null, is_active: true,
    };
  }

  const seconds = refreshAfterSeconds(chosenRule, wall, prayers);
  const fallbackUrl = fallbackUrlFor(
    selectedCandidates,
    selected,
    selectedSeed || `${chosenRule.id}|${wall.dateKey}`,
  );
  const resolvableRules = rules.filter(rule =>
    (eligibleByPool.get(rule.source_pool_key)?.length ?? 0) > 0);
  const nextBoundary = nextRuleBoundary(resolvableRules, chosenRule, wall, prayers);

  return json({
    channel: {
      slug: channel.slug,
      name: channel.name,
      description: (channel.metadata as JsonRecord | null)?.description_ar ?? null,
    },
    program: {
      key: chosenRule.rule_key,
      title: chosenRule.title_ar,
      sourceType: selected.source_type,
      sourceId: selected.id,
      sourceName: selected.nameAr,
      streamUrl: selected.streamUrl,
      fallbackUrl,
      bitrateKbps: selected.bitrateKbps,
      validUntil: formatLocalAfter(wall, seconds),
      refreshAfterSeconds: seconds,
      transitionPolicy: chosenRule.transition_policy,
      override: false,
      fallbackMode,
    },
    next: nextBoundary ? {
      title: nextBoundary.rule.title_ar,
      startsAt: formatLocalAfter(wall, Math.round(nextBoundary.minutes * 60)),
    } : null,
    timezone,
    generatedAt: new Date().toISOString(),
    privacy: { preciseLocationReceived: false },
  });
});

// ============================================================================
// supabase/functions/radio-schedule/index.ts
//
// Real radio schedule endpoint for Fadhkur — no mock data.
//
// Reads (server-side, service_role):
//   * the active station from app.stations
//       (is_active = true, deleted_at IS NULL, ordered by sort_order /
//        is_featured — first match wins; optional ?slug= / ?station_id=)
//   * the broadcast schedule from app.schedules when the table exists
//       (enabled entries for the station, ordered by next_run_at)
//   * the live track from radio.now_playing when available
//
// Failover:
//   * if the chosen station reports status OFFLINE/MAINTENANCE, the response
//     names a failover station (next active ONLINE station in catalog order)
//     and always exposes the station's own fallback_stream_url.
//   * when no station can be resolved, an honest error state is returned
//     (HTTP 503) — never fabricated station/schedule payloads.
//
// Errors are explicit: 500 on misconfiguration, 503 when no active station
// exists, 200 with partial-but-honest data when schedules are unavailable.
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

type StationRow = {
  id: string;
  slug: string;
  name_ar: string;
  name_en: string | null;
  stream_url: string;
  fallback_stream_url: string | null;
  logo_url: string | null;
  status: string | null;
  is_active: boolean;
  is_featured: boolean;
  sort_order: number;
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function errorEnvelope(code: string, message: string, status: number, details?: unknown) {
  return json({ error: { code, message, details: details ?? null } }, status);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return errorEnvelope("METHOD_NOT_ALLOWED", "Only GET is supported", 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    // Honest failure: the function cannot reach the database.
    return errorEnvelope(
      "NOT_CONFIGURED",
      "Radio schedule backend is not configured (missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY).",
      500,
    );
  }
  const db = createClient(supabaseUrl, serviceKey);

  const url = new URL(req.url);
  const wantedSlug = url.searchParams.get("slug");
  const wantedId = url.searchParams.get("station_id");

  // ---- 1. Active stations -------------------------------------------------
  let stations: StationRow[] | null = null;
  try {
    const { data, error } = await db
      .schema("app")
      .from("stations")
      .select(
        "id, slug, name_ar, name_en, stream_url, fallback_stream_url, logo_url, status, is_active, is_featured, sort_order",
      )
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("sort_order", { ascending: true })
      .order("is_featured", { ascending: false });
    if (error) throw new Error(error.message);
    stations = (data ?? []) as StationRow[];
  } catch (e) {
    return errorEnvelope(
      "STATIONS_QUERY_FAILED",
      "Could not load the station catalog from the database.",
      503,
      String(e),
    );
  }

  if (!stations || stations.length === 0) {
    return errorEnvelope(
      "NO_ACTIVE_STATION",
      "No active radio station is configured. Add one in the admin dashboard.",
      503,
    );
  }

  let station: StationRow | undefined;
  if (wantedId) station = stations.find((s) => s.id === wantedId);
  if (!station && wantedSlug) station = stations.find((s) => s.slug === wantedSlug);
  if (!station) station = stations[0];

  // ---- 2. Failover --------------------------------------------------------
  const stationDown =
    station.status === "OFFLINE" || station.status === "MAINTENANCE";
  let failover: StationRow | null = null;
  if (stationDown) {
    failover =
      stations.find((s) => s.id !== station!.id && s.status === "ONLINE") ??
      stations.find((s) => s.id !== station!.id) ??
      null;
  }

  const stationPayload = {
    id: station.id,
    slug: station.slug,
    nameAr: station.name_ar,
    nameEn: station.name_en,
    streamUrl: station.stream_url,
    fallbackStreamUrl: station.fallback_stream_url,
    logoUrl: station.logo_url,
    status: station.status,
    isFeatured: station.is_featured,
  };

  // ---- 3. Schedule (current + next) ---------------------------------------
  let current: Record<string, unknown> | null = null;
  let next: Record<string, unknown> | null = null;
  let scheduleAvailable = true;
  try {
    const { data: rows, error } = await db
      .schema("app")
      .from("schedules")
      .select("id, name, content_type, schedule_type, start_date, start_time, timezone, priority, next_run_at")
      .eq("station_id", station.id)
      .eq("enabled", true)
      .is("deleted_at", null)
      .order("next_run_at", { ascending: true, nullsFirst: false })
      .limit(25);
    if (error) throw new Error(error.message);
    const now = Date.now();
    const list = (rows ?? []) as Array<Record<string, unknown>>;
    const past = list.filter(
      (r) => r.next_run_at && new Date(r.next_run_at as string).getTime() <= now,
    );
    const future = list.filter(
      (r) => r.next_run_at && new Date(r.next_run_at as string).getTime() > now,
    );
    current = past.length > 0 ? past[past.length - 1] : null;
    next = future.length > 0 ? future[0] : null;
  } catch {
    // Table missing or unreadable: report honestly, keep station data.
    scheduleAvailable = false;
  }

  // ---- 4. Now playing ------------------------------------------------------
  let nowPlaying: Record<string, unknown> | null = null;
  try {
    const { data, error } = await db
      .schema("radio")
      .from("now_playing")
      .select("title, artist, started_at, expected_end_at, duration_ms, updated_at")
      .eq("station_id", station.id)
      .maybeSingle();
    if (error) throw new Error(error.message);
    nowPlaying = (data as Record<string, unknown> | null) ?? null;
  } catch {
    nowPlaying = null; // honest null — the client shows an empty state
  }

  return json({
    station: stationPayload,
    nowPlaying,
    schedule: {
      available: scheduleAvailable,
      current,
      next,
    },
    failover: stationDown
      ? failover
        ? {
            id: failover.id,
            slug: failover.slug,
            nameAr: failover.name_ar,
            streamUrl: failover.stream_url,
            fallbackStreamUrl: failover.fallback_stream_url,
            reason: `Primary station is ${station.status}`,
          }
        : { reason: `Primary station is ${station.status}; no failover station configured` }
      : null,
    generatedAt: new Date().toISOString(),
  });
});

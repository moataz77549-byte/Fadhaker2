import { resolvePageFromLookupPayload } from './quran_mapping.ts';
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

// CORS headers allow-list (Read & Public Operations)
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-request-id',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

interface ErrorEnvelope {
  error: {
    code: string;
    message: string;
    requestId: string;
    details?: unknown;
  };
}

function jsonResponse(data: unknown, status = 200, requestId?: string): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      'X-Request-Id': requestId || crypto.randomUUID(),
    },
  });
}

function errorResponse(code: string, message: string, status = 400, requestId?: string): Response {
  const reqId = requestId || crypto.randomUUID();
  const body: ErrorEnvelope = {
    error: {
      code,
      message,
      requestId: reqId,
    },
  };
  return jsonResponse(body, status, reqId);
}

// In-memory rate-limiter bucket for sensitive POST endpoints (Token bucket per IP)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
function checkRateLimit(ip: string, limit = 60, windowMs = 60000): boolean {
  const now = Date.now();
  const bucket = rateLimitMap.get(ip);
  if (!bucket || bucket.resetAt < now) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + windowMs });
    return true;
  }
  if (bucket.count >= limit) {
    return false;
  }
  bucket.count++;
  return true;
}

const INSTALLATION_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_HEX_RE = /^[0-9a-f]{64}$/i;

function isValidInstallationId(value: unknown): value is string {
  return typeof value === 'string' && INSTALLATION_ID_RE.test(value);
}

function isValidInstallationSecretHash(value: unknown): value is string {
  return typeof value === 'string' && SHA256_HEX_RE.test(value);
}

function isValidFcmToken(value: unknown): value is string {
  return typeof value === 'string' && value.length >= 32 && value.length <= 4096 && !/\s/.test(value);
}

serve(async (req: Request) => {
  const requestId = req.headers.get('x-request-id') || crypto.randomUUID();
  const clientIp = req.headers.get('x-forwarded-for') || '127.0.0.1';

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/(?:quran-yutla-api|fadhkur-api)/, '') || '/';

  // Supabase client initialization (Safe anon key for reading public data)
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:54321';
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  const publicClient = createClient(supabaseUrl, supabaseAnonKey);
  const adminClient = supabaseServiceKey ? createClient(supabaseUrl, supabaseServiceKey) : publicClient;

  try {
    // 1. GET /health
    if (req.method === 'GET' && (path === '' || path === '/' || path === '/health')) {
      return jsonResponse({
        status: 'healthy',
        service: 'fadhkur-api',
        version: '1.0.64',
        edition: 'quran-uthmani-hafs-v1.0',
        timestamp: new Date().toISOString(),
      }, 200, requestId);
    }

    // 2. GET /runtime-config
    if (req.method === 'GET' && path === '/runtime-config') {
      const { data, error } = await publicClient
        .schema('app')
        .from('app_config')
        .select('key, value')
        .eq('is_public', true);

      if (error) {
        // Safe fallback configuration if DB table is initializing
        return jsonResponse({
          feature_flags: {
            radio_enabled: true,
            offline_downloads: true,
            prayer_times: true,
            adhkar: true,
            learning_center: true,
          },
          home_sections: ['featured_radio', 'prayer_times', 'daily_reading', 'stations_grid', 'reciters_carousel'],
          min_supported_version: { android: '1.0.64', ios: '1.0.64' },
          maintenance: { is_active: false },
        }, 200, requestId);
      }

      const configMap: Record<string, unknown> = {};
      data.forEach((item: { key: string; value: unknown }) => {
        configMap[item.key] = item.value;
      });
      return jsonResponse(configMap, 200, requestId);
    }

    // 3. GET /home — بيانات حقيقية فقط، بلا مدن/محطات/أرقام وهمية.
    if (req.method === 'GET' && path === '/home') {
      const { data: stationRows } = await publicClient
        .schema('app')
        .from('stations')
        .select('id,name_ar,slug,stream_url,fallback_stream_url,logo_url,stream_type,is_featured,is_active,is_playable,health_status,sort_order')
        .eq('is_active', true)
        .is('deleted_at', null)
        .order('sort_order', { ascending: true })
        .order('name_ar', { ascending: true })
        .limit(5);

      return jsonResponse({
        dailyReading: null,
        featuredRadio: (stationRows ?? []).find((row: any) => row.is_featured === true) ?? (stationRows ?? [])[0] ?? null,
        prayerTimes: null,
      }, 200, requestId);
    }

    // 4. GET /stations — نفس المصدر الذي تستخدمه واجهة التطبيق.
    if (req.method === 'GET' && path === '/stations') {
      const { data, error } = await publicClient
        .schema('app')
        .from('stations')
        .select('id,name_ar,name_en,slug,description,logo_url,stream_type,stream_url,fallback_stream_url,is_active,is_featured,is_playable,health_status,sort_order,provider_name,country')
        .eq('is_active', true)
        .is('deleted_at', null)
        .order('sort_order', { ascending: true })
        .order('name_ar', { ascending: true });

      if (error) {
        return errorResponse('DB_ERROR', 'تعذر قراءة محطات الإذاعة من قاعدة البيانات', 503, requestId);
      }
      return jsonResponse(data ?? [], 200, requestId);
    }

    // 5. GET /reciters — كتالوج قاعدة البيانات فقط، بلا fallback وهمي.
    if (req.method === 'GET' && path === '/reciters') {
      const { data, error } = await publicClient
        .schema('app')
        .from('reciters')
        .select('id,slug,canonical_slug,name_ar,name_en,name_arabic,name_english,default_riwayah,bio_arabic,is_featured,metadata')
        .eq('is_active', true)
        .is('deleted_at', null)
        .order('is_featured', { ascending: false })
        .order('name_ar', { ascending: true });

      if (error) {
        return errorResponse('DB_ERROR', 'تعذر قراءة القراء من قاعدة البيانات', 503, requestId);
      }
      return jsonResponse(data ?? [], 200, requestId);
    }

    // 6. GET /quran/surahs — المصدر الفعلي app.surahs.
    if (req.method === 'GET' && path === '/quran/surahs') {
      const { data, error } = await publicClient
        .schema('app')
        .from('surahs')
        .select('number,name_ar,name_en,ayah_count')
        .order('number', { ascending: true });
      if (error) {
        return errorResponse('DB_ERROR', 'تعذر قراءة فهرس السور من قاعدة البيانات', 503, requestId);
      }
      return jsonResponse(data ?? [], 200, requestId);
    }

    // 7. GET /quran/page/:page
    const pageMatch = path.match(/^\/quran\/page\/(\d+)$/);
    if (req.method === 'GET' && pageMatch) {
      const pageNum = parseInt(pageMatch[1], 10);
      if (pageNum < 1 || pageNum > 604) {
        return errorResponse('INVALID_PAGE', 'Page number must be between 1 and 604', 400, requestId);
      }
      const edition = BUILTIN_EDITIONS[0];
      return jsonResponse({
        pageNumber: pageNum,
        totalPages: edition.totalPages,
        edition: edition.id,
        imageUrl: String(edition.pageImageTemplate).replace('{page}', String(pageNum)),
        textEndpoint: `/quran/page?riwaya=hafs&page=${pageNum}`,
      }, 200, requestId);
    }

    // 8. POST /notifications/register (Privacy Consent-first)
    if (req.method === 'POST' && path === '/notifications/register') {
      if (!checkRateLimit(clientIp, 10)) {
        return errorResponse('RATE_LIMITED', 'Too many registration requests. Please try later.', 429, requestId);
      }

      const body = await req.json();
      const { installationId, hashedSecret, fcmToken, platform, appVersion, consentVersion, preferences } = body;

      if (!installationId || !hashedSecret || !fcmToken || !consentVersion) {
        return errorResponse('MISSING_REQUIRED_FIELDS', 'installationId, hashedSecret, fcmToken and consentVersion are required', 400, requestId);
      }
      if (!supabaseServiceKey) {
        return errorResponse('SERVER_MISCONFIGURED', 'Notification registration is temporarily unavailable', 503, requestId);
      }
      if (!isValidInstallationId(installationId)) {
        return errorResponse('INVALID_INSTALLATION_ID', 'installationId must be a UUID', 400, requestId);
      }
      if (!isValidInstallationSecretHash(hashedSecret)) {
        return errorResponse('INVALID_INSTALLATION_SECRET', 'hashedSecret must be a SHA-256 hex digest', 400, requestId);
      }
      if (!isValidFcmToken(fcmToken)) {
        return errorResponse('INVALID_FCM_TOKEN', 'fcmToken is malformed', 400, requestId);
      }
      if (platform && !['android', 'ios', 'web'].includes(platform)) {
        return errorResponse('INVALID_PLATFORM', 'platform must be android, ios or web', 400, requestId);
      }

      // Prevent installation takeover: an existing installation ID may only be
      // refreshed by a client proving possession of the original local secret.
      const { data: existingInstallation, error: lookupError } = await adminClient
        .schema('app')
        .from('installations')
        .select('installation_secret_hash')
        .eq('id', installationId)
        .maybeSingle();

      if (lookupError) {
        return errorResponse('DB_ERROR', 'Unable to verify installation ownership', 503, requestId);
      }
      if (
        existingInstallation &&
        existingInstallation.installation_secret_hash !== hashedSecret
      ) {
        return errorResponse('INSTALLATION_CONFLICT', 'Installation ownership verification failed', 409, requestId);
      }

      const { error } = await adminClient
        .schema('app')
        .from('installations')
        .upsert({
          id: installationId,
          installation_secret_hash: hashedSecret,
          platform: platform || 'android',
          app_version: appVersion || '1.0.64',
          notifications_enabled: true,
          firebase_token_encrypted: fcmToken,
          consent_version: consentVersion,
          consented_at: new Date().toISOString(),
          last_seen_at: new Date().toISOString(),
          revoked_at: null,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'id' });

      if (error) {
        return errorResponse('DB_ERROR', 'Unable to register notification installation', 500, requestId);
      }

      const pref = preferences && typeof preferences === 'object' ? preferences as Record<string, unknown> : {};
      const prayerEnabled =
        pref.prayer_alerts === true ||
        pref.prayer_fajr === true ||
        pref.prayer_dhuhr === true ||
        pref.prayer_asr === true ||
        pref.prayer_maghrib === true ||
        pref.prayer_isha === true;
      const adhkarEnabled =
        pref.morning_athkar === true ||
        pref.evening_athkar === true ||
        pref.sleep_athkar === true;
      const announcementsEnabled =
        pref.general === true ||
        pref.live_radio === true ||
        pref.live_radio_alerts === true;
      const { error: prefError } = await adminClient
        .schema('app')
        .from('notification_preferences')
        .upsert({
          installation_id: installationId,
          prayer_enabled: prayerEnabled,
          adhkar_enabled: adhkarEnabled,
          learning_enabled: true,
          announcements_enabled: announcementsEnabled,
          product_updates_enabled: false,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'installation_id' });
      if (prefError) {
        return errorResponse('DB_ERROR', 'Unable to save notification preferences', 500, requestId);
      }

      return jsonResponse({ success: true, registeredAt: new Date().toISOString() }, 201, requestId);
    }

    // 9. POST /notifications/revoke
    if (req.method === 'POST' && path === '/notifications/revoke') {
      const body = await req.json();
      const { installationId, hashedSecret } = body;

      if (!installationId || !hashedSecret) {
        return errorResponse('MISSING_CREDENTIALS', 'installationId and hashedSecret are required', 400, requestId);
      }
      if (!supabaseServiceKey) {
        return errorResponse('SERVER_MISCONFIGURED', 'Notification revocation is temporarily unavailable', 503, requestId);
      }
      if (!isValidInstallationId(installationId) || !isValidInstallationSecretHash(hashedSecret)) {
        return errorResponse('INVALID_CREDENTIALS', 'Installation credentials are malformed', 400, requestId);
      }

      const { error } = await adminClient
        .schema('app')
        .from('installations')
        .update({
          notifications_enabled: false,
          revoked_at: new Date().toISOString(),
          firebase_token_encrypted: 'REVOKED',
          updated_at: new Date().toISOString(),
        })
        .eq('id', installationId)
        .eq('installation_secret_hash', hashedSecret);

      if (error) {
        return errorResponse('DB_ERROR', 'Unable to revoke notification installation', 500, requestId);
      }

      return jsonResponse({ success: true, message: 'Notification subscription revoked completely' }, 200, requestId);
    }

    // ===== Quran Foundation proxy (server-side OAuth2) =====
    // كل أسرار Quran Foundation تبقى في Edge Function Secrets فقط.
    // Flutter ينادي هذه المسارات ولا يرى أي credentials إطلاقًا.
    if (path.startsWith('/quran/')) {
      return await handleQuranProxy(req, path, url, requestId, publicClient);
    }

    // Default 404 Route
    return errorResponse('NOT_FOUND', `The requested route '${path}' was not found`, 404, requestId);

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return errorResponse('INTERNAL_SERVER_ERROR', message, 500, requestId);
  }
});

// ============================================================================
// Quran Foundation proxy
// ----------------------------------------------------------------------------
// المصادقة: OAuth2 Client Credentials (موثّق في
// https://api-docs.quran.foundation/docs/quickstart/)
//   Token: POST {auth_base}/oauth2/token
//     Authorization: Basic base64(client_id:client_secret)
//     Body: grant_type=client_credentials&scope=content
//   الاستدعاءات: x-auth-token: <access_token> + x-client-id: <client_id>
// البيئات:
//   production: auth https://oauth2.quran.foundation | api https://apis.quran.foundation
//   prelive:    auth https://prelive-oauth2.quran.foundation | api https://apis-prelive.quran.foundation
// المسارات هنا:
//   GET /quran/config                       — إعدادات وقت التشغيل (روايات/خطوط/تفاسير)
//   GET /quran/page?riwaya=hafs&page=293    — نص صفحة عبر QF
//   GET /quran/lookup?chapter=18&verse=1    — رقم صفحة آية
//   GET /quran/tafsirs                      — فهرس التفاسير
//   GET /quran/tafsir/{id}/ayah/{c}/{v}     — تفسير آية
// ============================================================================

const QF_ENV = Deno.env.get('QF_ENV') ?? 'production';
const QF_CLIENT_ID = Deno.env.get('QF_CLIENT_ID') ?? '';
const QF_CLIENT_SECRET = Deno.env.get('QF_CLIENT_SECRET') ?? '';

const QF_HOSTS = QF_ENV === 'prelive'
  ? { auth: 'https://prelive-oauth2.quran.foundation', api: 'https://apis-prelive.quran.foundation' }
  : { auth: 'https://oauth2.quran.foundation', api: 'https://apis.quran.foundation' };
const QF_CONTENT_BASE = `${QF_HOSTS.api}/content/api/v4`;
const QF_SEARCH_BASE = `${QF_HOSTS.api}/search/api/v1`;
const QURANPEDIA_BASE = 'https://api.quranpedia.net/v1';
const QF_USER_AGENT = 'Fadhkur/1.0 (Supabase Edge Function; +https://fadhkur.app)';

const qfTokenCache = new Map<string, { accessToken: string; expiresAt: number }>();

async function getQfAccessToken(scope = 'content'): Promise<string> {
  if (!QF_CLIENT_ID || !QF_CLIENT_SECRET) {
    throw Object.assign(new Error('Quran Foundation credentials are not configured'), { code: 'QF_NOT_CONFIGURED' });
  }
  const now = Date.now();
  const cached = qfTokenCache.get(scope);
  if (cached && cached.expiresAt > now + 60_000) {
    return cached.accessToken;
  }
  const basic = btoa(`${QF_CLIENT_ID}:${QF_CLIENT_SECRET}`);
  const res = await fetch(`${QF_HOSTS.auth}/oauth2/token`, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${basic}`,
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': QF_USER_AGENT,
    },
    body: `grant_type=client_credentials&scope=${encodeURIComponent(scope)}`,
  });
  if (!res.ok) {
    throw Object.assign(new Error(`Quran Foundation token request failed (${res.status})`), { code: 'QF_TOKEN_FAILED' });
  }
  const data = await res.json() as { access_token?: string; expires_in?: number };
  if (!data.access_token) {
    throw Object.assign(new Error('Quran Foundation returned no access token'), { code: 'QF_TOKEN_FAILED' });
  }
  const cachedToken = {
    accessToken: data.access_token,
    expiresAt: now + (data.expires_in ?? 3600) * 1000,
  };
  qfTokenCache.set(scope, cachedToken);
  return cachedToken.accessToken;
}

async function qfGet(pathname: string, params: Record<string, string>): Promise<Response> {
  const token = await getQfAccessToken('content');
  const target = new URL(QF_CONTENT_BASE + pathname);
  for (const [k, v] of Object.entries(params)) target.searchParams.set(k, v);
  return await fetch(target.toString(), {
    headers: {
      'x-auth-token': token,
      'x-client-id': QF_CLIENT_ID,
      'Accept': 'application/json',
      'User-Agent': QF_USER_AGENT,
    },
  });
}

async function qfSearch(params: Record<string, string>): Promise<Response> {
  const token = await getQfAccessToken('search');
  const target = new URL(`${QF_SEARCH_BASE}/search`);
  for (const [k, v] of Object.entries(params)) target.searchParams.set(k, v);
  return await fetch(target.toString(), {
    headers: {
      'x-auth-token': token,
      'x-client-id': QF_CLIENT_ID,
      'Accept': 'application/json',
      'User-Agent': QF_USER_AGENT,
    },
  });
}

async function quranpediaGet(pathname: string, params: Record<string, string> = {}): Promise<Response> {
  const target = new URL(QURANPEDIA_BASE + pathname);
  for (const [k, v] of Object.entries(params)) target.searchParams.set(k, v);
  return await fetch(target.toString(), {
    headers: {
      'Accept': 'application/json',
      'User-Agent': QF_USER_AGENT,
    },
  });
}

// ذاكرة مؤقتة داخل الـ Function (تُصفَّر مع كل نشر/تجميد).
const qfMemoryCache = new Map<string, { at: number; value: unknown }>();
function cacheGet<T>(key: string, ttlMs: number): T | null {
  const hit = qfMemoryCache.get(key);
  if (hit && Date.now() - hit.at < ttlMs) return hit.value as T;
  return null;
}
function cacheSet(key: string, value: unknown): void {
  qfMemoryCache.set(key, { at: Date.now(), value });
}

// السجل المضمّن كاحتياطي — الأولوية دائمًا لقيم app.app_config.
// لا نفترض 604 صفحة لغير حفص: totalPages = null = غير موثّق.
const BUILTIN_RIWAYAT = [
  { id: 'hafs', nameAr: 'حفص عن عاصم', narratorAr: 'عاصم بن أبي النجود الكوفي', totalPages: 604, pageImageTemplate: null, qfMushafId: 1, textAvailable: true, notesAr: 'المصحف المدني — 15 سطرًا في الصفحة' },
  { id: 'warsh', nameAr: 'ورش عن نافع', narratorAr: 'نافع بن عبد الرحمن المدني', totalPages: null, pageImageTemplate: null, qfMushafId: null, textAvailable: false, notesAr: 'تخطيط الصفحات يختلف باختلاف الطبعة — يُوثّق من app_config' },
  { id: 'qalun', nameAr: 'قالون عن نافع', narratorAr: 'نافع بن عبد الرحمن المدني', totalPages: null, pageImageTemplate: null, qfMushafId: null, textAvailable: false, notesAr: 'تخطيط الصفحات يختلف باختلاف الطبعة — يُوثّق من app_config' },
  { id: 'duri', nameAr: 'الدوري عن أبي عمرو', narratorAr: 'أبو عمرو بن العلاء البصري', totalPages: null, pageImageTemplate: null, qfMushafId: null, textAvailable: false, notesAr: 'تخطيط الصفحات يختلف باختلاف الطبعة — يُوثّق من app_config' },
];
const BUILTIN_FONTS = [
  { id: 'uthmanic-hafs', nameAr: 'العثماني — حفص', fontFamily: 'UthmanicHafs', lineHeight: 2.1, licenseNoteAr: 'QPC Hafs font (KFGQPC) عبر QUL/Tarteel — تحقّق حي 2026-09-23', downloadUrl: 'https://static-cdn.tarteel.ai/qul/fonts/UthmanicHafs_V22.ttf' },
  { id: 'kfgqpc-hafs', nameAr: 'مجمع الملك فهد — حفص', fontFamily: 'KFGQPCUthmanicScriptHAFS', lineHeight: 2.0, licenseNoteAr: 'KFGQPC Uthmanic Hafs (إصدار 1.8) عبر مرآة jsDelivr — تحقّق حي 2026-09-23', downloadUrl: 'https://cdn.jsdelivr.net/gh/mohammed-2-5/islamic-library-data@master/fonts/UthmanicHafs_v18.ttf' },
  { id: 'qcf', nameAr: 'QCF', fontFamily: 'QCF', lineHeight: 2.0, licenseNoteAr: 'خطوط QCF من Quran Foundation — لا يوجد ملف نصي واحد موثّق (QCF ملفٌ لكل صفحة)؛ يُستخدم خط النظام', downloadUrl: null },
  { id: 'uthmanic-vector', nameAr: 'العثماني المتجه (Vector)', fontFamily: 'UthmanicVector', lineHeight: 2.0, licenseNoteAr: 'لم يُعثر على مصدر تحميل موثّق لهذا الخط؛ يُستخدم خط النظام', downloadUrl: null },
];
// إصدارات المصحف المصوّر المضمّنة — نسختا المصحف المدني (604 صفحات) الموثّقتان.
// تحقّق حي 2026-09-23: الصفحات 1/100/300/500/604 لكل نسخة (HTTP 200، image/jpeg).
// الأولوية دائمًا لقيم app.app_config (quran.mushaf_editions).
const BUILTIN_EDITIONS = [
  { id: 'hafs-madani', riwayaId: 'hafs', nameAr: 'المصحف المدني (عادي)', pageImageTemplate: 'https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/kfgqpc/hafs-wasat/{page}.jpg', totalPages: 604, pagePadWidth: 0, notesAr: 'نسخة KFGQPC (المصحف المدني) عبر مستودع QuranHub — تحقّق حي 2026-09-23' },
  { id: 'hafs-madani-tajweed', riwayaId: 'hafs', nameAr: 'المصحف الملوّن بالتجويد', pageImageTemplate: 'https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/easyquran.com/hafs-tajweed/{page}.jpg', totalPages: 604, pagePadWidth: 0, notesAr: 'نسخة التجويد الملوّن (easyquran.com) عبر مستودع QuranHub — تحقّق حي 2026-09-23' },
];
// معرّفات حقيقية من فهرس GET /resources/tafsirs (تحقّق حي 2026-09-23).
const BUILTIN_TAFSIRS = [
  { resourceId: 16, nameAr: 'التفسير الميسر', slug: 'ar-tafsir-muyassar' },
  { resourceId: 14, nameAr: 'تفسير ابن كثير', slug: 'ar-tafsir-ibn-kathir' },
  { resourceId: 91, nameAr: 'تفسير السعدي', slug: 'ar-tafseer-al-saddi' },
  { resourceId: 90, nameAr: 'تفسير القرطبي', slug: 'ar-tafseer-al-qurtubi' },
];

async function readPublicConfig(publicClient: ReturnType<typeof createClient>, key: string): Promise<unknown | null> {
  try {
    const { data, error } = await publicClient
      .schema('app')
      .from('app_config')
      .select('value')
      .eq('key', key)
      .eq('is_public', true)
      .limit(1)
      .maybeSingle();
    if (error || !data) return null;
    return (data as { value: unknown }).value ?? null;
  } catch {
    return null;
  }
}

async function fetchHafsPageFallback(page: number, requestId: string): Promise<Response> {
  const res = await fetch(`https://api.alquran.cloud/v1/page/${page}/quran-uthmani`);
  if (!res.ok) {
    return errorResponse('UPSTREAM_FALLBACK_ERROR', `Al Quran Cloud error (${res.status})`, 502, requestId);
  }
  const payload = await res.json() as { data?: { ayahs?: Array<Record<string, unknown>> } };
  const ayahs = payload.data?.ayahs ?? [];
  if (ayahs.length === 0) {
    return errorResponse('EMPTY_PAGE', 'لا توجد آيات لهذه الصفحة في المصدر الاحتياطي', 502, requestId);
  }
  const verses = ayahs.map((ayah) => ({
    verse_key: `${(ayah.surah as Record<string, unknown> | undefined)?.number ?? 0}:${ayah.numberInSurah ?? 0}`,
    text_uthmani: String(ayah.text ?? ''),
    text_uthmani_tajweed: String(ayah.text ?? ''),
    juz_number: Number(ayah.juz ?? 0),
    hizb_number: Number(ayah.hizbQuarter ?? 0),
  }));
  const surahName = String(
    ((ayahs[0].surah as Record<string, unknown> | undefined)?.name) ?? 'المصحف الشريف',
  );
  return jsonResponse(
    { page, riwaya: 'hafs', source: 'alquran-cloud', surahName, verses },
    200,
    requestId,
  );
}

async function fetchHafsLookupFallback(
  chapter: number,
  verse: number,
  requestId: string,
): Promise<Response> {
  const res = await fetch(`https://api.alquran.cloud/v1/ayah/${chapter}:${verse}/quran-uthmani`);
  if (!res.ok) {
    return errorResponse('UPSTREAM_FALLBACK_ERROR', `Al Quran Cloud error (${res.status})`, 502, requestId);
  }
  const payload = await res.json() as { data?: { page?: number } };
  const page = Number(payload.data?.page ?? NaN);
  if (!Number.isInteger(page) || page < 1 || page > 604) {
    return errorResponse('LOOKUP_FAILED', 'تعذر تحديد صفحة الآية', 502, requestId);
  }
  return jsonResponse({ chapter, verse, page, source: 'alquran-cloud' }, 200, requestId);
}

async function handleQuranProxy(
  req: Request,
  path: string,
  url: URL,
  requestId: string,
  publicClient: ReturnType<typeof createClient>,
): Promise<Response> {
  const clientIp = req.headers.get('x-forwarded-for') || '127.0.0.1';
  if (req.method !== 'GET') {
    return errorResponse('METHOD_NOT_ALLOWED', 'Only GET is supported on /quran/*', 405, requestId);
  }
  if (!checkRateLimit(`quran:${clientIp}`, 120)) {
    return errorResponse('RATE_LIMITED', 'Too many Quran requests. Please try later.', 429, requestId);
  }
  const sub = path.replace(/^\/quran\/?/, '');

  try {
    // 1) GET /quran/config — إعدادات وقت التشغيل (بلا أسرار)
    if (sub === '' || sub === 'config') {
      const cached = cacheGet<Record<string, unknown>>('quran:config', 5 * 60_000);
      if (cached) return jsonResponse(cached, 200, requestId);
      const [riwayat, editions, fonts, tafsirs] = await Promise.all([
        readPublicConfig(publicClient, 'quran.riwayat_registry'),
        readPublicConfig(publicClient, 'quran.mushaf_editions'),
        readPublicConfig(publicClient, 'quran.font_options'),
        readPublicConfig(publicClient, 'quran.tafsir_sources'),
      ]);
      const payload = {
        riwayat: Array.isArray(riwayat) && riwayat.length > 0 ? riwayat : BUILTIN_RIWAYAT,
        editions: Array.isArray(editions) && editions.length > 0 ? editions : BUILTIN_EDITIONS,
        fonts: Array.isArray(fonts) && fonts.length > 0 ? fonts : BUILTIN_FONTS,
        tafsirs: Array.isArray(tafsirs) && tafsirs.length > 0 ? tafsirs : BUILTIN_TAFSIRS,
        fetchedAt: new Date().toISOString(),
        qfEnv: QF_ENV,
      };
      cacheSet('quran:config', payload);
      return jsonResponse(payload, 200, requestId);
    }

    // 2) GET /quran/page?riwaya=hafs&page=293 — نص الصفحة
    if (sub === 'page') {
      const riwayaId = url.searchParams.get('riwaya') ?? 'hafs';
      const page = parseInt(url.searchParams.get('page') ?? '', 10);
      const riwaya = BUILTIN_RIWAYAT.find((r) => r.id === riwayaId);
      if (!riwaya) return errorResponse('UNKNOWN_RIWAYA', `Unknown riwaya: ${riwayaId}`, 400, requestId);
      if (!riwaya.textAvailable) {
        return errorResponse('TEXT_UNAVAILABLE', `نص الرواية «${riwaya.nameAr}» غير متوفّر بعد`, 404, requestId);
      }
      if (!Number.isInteger(page) || page < 1 || page > 604) {
        return errorResponse('INVALID_PAGE', 'Page number must be between 1 and 604', 400, requestId);
      }
      const params: Record<string, string> = {
        fields: 'text_uthmani,text_uthmani_tajweed',
        words: 'true',
        word_fields: 'verse_key,location,line_number,text_qpc_hafs,code_v2',
        language: 'ar',
      };
      if (riwaya.qfMushafId) params['mushaf'] = String(riwaya.qfMushafId);
      let upstream: Response;
      try {
        upstream = await qfGet(`/verses/by_page/${page}`, params);
      } catch (error) {
        if ((error as { code?: string })?.code === 'QF_NOT_CONFIGURED' && riwayaId === 'hafs') {
          return await fetchHafsPageFallback(page, requestId);
        }
        throw error;
      }
      if (!upstream.ok) {
        return errorResponse('UPSTREAM_ERROR', `Quran Foundation error (${upstream.status})`, 502, requestId);
      }
      const body = await upstream.json() as { verses?: Array<Record<string, unknown>> };
      const verses = body.verses ?? [];
      if (verses.length === 0) return errorResponse('EMPTY_PAGE', 'No verses returned for this page', 502, requestId);
      // اسم السورة من أول آية في الصفحة (مخزّن مؤقتًا لتفادي N+1).
      const firstKey = String(verses[0]['verse_key'] ?? '1:1');
      const chapterId = parseInt(firstKey.split(':')[0] || '1', 10);
      let surahName = `سورة ${chapterId}`;
      const nameCacheKey = `quran:chapter:${chapterId}`;
      const cachedName = cacheGet<string>(nameCacheKey, 24 * 3600_000);
      if (cachedName) {
        surahName = cachedName;
      } else {
        try {
          const chRes = await qfGet(`/chapters/${chapterId}`, { language: 'ar' });
          if (chRes.ok) {
            const chBody = await chRes.json() as { chapter?: { name_arabic?: string } };
            if (chBody.chapter?.name_arabic) {
              surahName = chBody.chapter.name_arabic;
              cacheSet(nameCacheKey, surahName);
            }
          }
        } catch {
          // Fallback page responses from Al Quran Cloud already contain the surah name.
        }
      }
      return jsonResponse({ page, riwaya: riwayaId, surahName, verses }, 200, requestId);
    }

    // 3) GET /quran/lookup?chapter=18&verse=1 — صفحة آية
    if (sub === 'lookup') {
      const chapter = parseInt(url.searchParams.get('chapter') ?? '', 10);
      const verse = parseInt(url.searchParams.get('verse') ?? '', 10);
      if (!Number.isInteger(chapter) || chapter < 1 || chapter > 114 || !Number.isInteger(verse) || verse < 1) {
        return errorResponse('INVALID_AYAH', 'chapter (1-114) and verse (>=1) are required', 400, requestId);
      }
      let upstream: Response;
      try {
        const verseKey = `${chapter}:${verse}`;
        upstream = await qfGet('/pages/lookup', { from: verseKey, to: verseKey, mushaf: '1' });
      } catch (error) {
        if ((error as { code?: string })?.code === 'QF_NOT_CONFIGURED') {
          return await fetchHafsLookupFallback(chapter, verse, requestId);
        }
        throw error;
      }
      if (!upstream.ok) {
        return errorResponse('UPSTREAM_ERROR', `Quran Foundation error (${upstream.status})`, 502, requestId);
      }
      const body = await upstream.json() as { pages?: Record<string, unknown> };
      const pageKey = resolvePageFromLookupPayload(body);
      if (!pageKey) {
        return errorResponse('LOOKUP_FAILED', 'Could not resolve the page for this ayah', 502, requestId);
      }
      return jsonResponse({ chapter, verse, page: pageKey }, 200, requestId);
    }

    // 4) GET /quran/search?q=... — بحث نص القرآن/السور/الصفحات عبر Search API.
    if (sub === 'search') {
      const query = (url.searchParams.get('q') ?? '').trim();
      if (query.length < 2 || query.length > 160) {
        return errorResponse('INVALID_QUERY', 'Search query must be between 2 and 160 characters', 400, requestId);
      }
      const upstream = await qfSearch({
        mode: 'quick',
        query,
        get_text: '1',
        navigationalResultsNumber: '10',
        versesResultsNumber: '30',
      });
      if (!upstream.ok) {
        return errorResponse('UPSTREAM_SEARCH_ERROR', `Quran Foundation search error (${upstream.status})`, 502, requestId);
      }
      return jsonResponse(await upstream.json(), 200, requestId);
    }

    // 5) GET /quran/topics — فهرس موضوعات Quranpedia مع الآيات المرتبطة.
    if (sub === 'topics') {
      const cached = cacheGet<unknown>('quranpedia:topics', 6 * 3600_000);
      if (cached) return jsonResponse({ topics: cached, source: 'quranpedia' }, 200, requestId);
      const upstream = await quranpediaGet('/topics');
      if (!upstream.ok) {
        return errorResponse('TOPICS_UPSTREAM_ERROR', `Quranpedia error (${upstream.status})`, 502, requestId);
      }
      const topics = await upstream.json();
      cacheSet('quranpedia:topics', topics);
      return jsonResponse({
        topics,
        source: 'quranpedia',
        sourceName: 'Quranpedia — الموسوعة القرآنية',
        sourceVersion: 'live-api-v1',
        license: 'https://quranpedia.net/api-docs#usage-policy',
        attribution: 'Quranpedia.net',
      }, 200, requestId);
    }

    // 6) GET /quran/topics/changes?since=YYYY-MM-DD — delta check فقط.
    if (sub === 'topics/changes') {
      const since = (url.searchParams.get('since') ?? '').trim();
      if (!/^\d{4}-\d{2}-\d{2}$/.test(since)) {
        return errorResponse('INVALID_SINCE', 'since must be YYYY-MM-DD', 400, requestId);
      }
      const upstream = await quranpediaGet('/changes', { since });
      if (!upstream.ok) {
        return errorResponse('TOPICS_UPSTREAM_ERROR', `Quranpedia changes error (${upstream.status})`, 502, requestId);
      }
      const payload = await upstream.json() as Record<string, unknown>;
      const topics = payload['topics'] as Record<string, unknown> | undefined;
      const count = Number(topics?.['count'] ?? 0);
      return jsonResponse({ changed: Number.isFinite(count) && count > 0, count }, 200, requestId);
    }

    // 7) GET /quran/topics/search?q=... — بحث مباشر في الموضوعات عند الحاجة.
    if (sub === 'topics/search') {
      const query = (url.searchParams.get('q') ?? '').trim();
      if (query.length < 2 || query.length > 120) {
        return errorResponse('INVALID_QUERY', 'Topic search query must be between 2 and 120 characters', 400, requestId);
      }
      const upstream = await quranpediaGet(`/search/${encodeURIComponent(query)}/topics`);
      if (!upstream.ok) {
        return errorResponse('TOPICS_UPSTREAM_ERROR', `Quranpedia search error (${upstream.status})`, 502, requestId);
      }
      const payload = await upstream.json() as unknown;
      if (Array.isArray(payload)) {
        return jsonResponse({ topics: payload }, 200, requestId);
      }
      const object = payload as Record<string, unknown>;
      const items = (object['items'] as unknown[]) ?? [];
      const normalized = items.map((item) => {
        if (!item || typeof item !== 'object') return item;
        const row = item as Record<string, unknown>;
        return (row['topic_info'] as Record<string, unknown> | undefined) ?? row;
      });
      return jsonResponse({ topics: normalized }, 200, requestId);
    }

    // 4) GET /quran/tafsirs — فهرس التفاسير
    if (sub === 'tafsirs') {
      const cached = cacheGet<unknown>('quran:tafsirs', 3600_000);
      if (cached) return jsonResponse({ tafsirs: cached }, 200, requestId);
      const upstream = await qfGet('/resources/tafsirs', { language: 'ar' });
      if (!upstream.ok) {
        return errorResponse('UPSTREAM_ERROR', `Quran Foundation error (${upstream.status})`, 502, requestId);
      }
      const body = await upstream.json() as { tafsirs?: Array<{ id: number; name: string; slug: string; language_name: string }> };
      const list = (body.tafsirs ?? [])
        .filter((t) => t.language_name === 'arabic')
        .map((t) => ({ resourceId: t.id, nameAr: t.name, slug: t.slug }));
      const result = list.length > 0 ? list : BUILTIN_TAFSIRS;
      cacheSet('quran:tafsirs', result);
      return jsonResponse({ tafsirs: result }, 200, requestId);
    }

    // 5) GET /quran/tafsir/{id}/ayah/{chapter}/{verse} — تفسير آية
    const tafsirMatch = sub.match(/^tafsir\/(\d+)\/ayah\/(\d{1,3})\/(\d{1,3})$/);
    if (tafsirMatch) {
      const [, resourceId, chapter, verse] = tafsirMatch;
      const upstream = await qfGet(`/tafsirs/${resourceId}/by_ayah/${chapter}:${verse}`, {});
      if (upstream.status === 404) {
        return errorResponse('TAFSIR_NOT_FOUND', 'لا يوجد تفسير لهذه الآية في المصدر المحدد', 404, requestId);
      }
      if (!upstream.ok) {
        return errorResponse('UPSTREAM_ERROR', `Quran Foundation error (${upstream.status})`, 502, requestId);
      }
      const body = await upstream.json();
      return jsonResponse(body, 200, requestId);
    }

    return errorResponse('NOT_FOUND', `Unknown quran route '${sub}'`, 404, requestId);
  } catch (err: unknown) {
    const code = (err as { code?: string })?.code;
    if (code === 'QF_NOT_CONFIGURED') {
      return errorResponse(
        'QF_NOT_CONFIGURED',
        'Quran Foundation credentials are not configured. Set QF_CLIENT_ID and QF_CLIENT_SECRET as Edge Function secrets.',
        503,
        requestId,
      );
    }
    const message = err instanceof Error ? err.message : String(err);
    return errorResponse('INTERNAL_SERVER_ERROR', message, 500, requestId);
  }
}

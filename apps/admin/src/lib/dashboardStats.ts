import { supabase } from './supabase';

/**
 * طبقة خدمة إحصائيات لوحة التحكم.
 *
 * كل الأرقام هنا تأتي من Supabase مباشرة. أي مقياس غير متوفر
 * (لا صلاحية، لا بيانات، الخادم غير مُهيأ) يُرجع null لتُظهر
 * الواجهة حالة فارغة صادقة بدل أرقام وهمية.
 */

export interface NowPlayingInfo {
  title: string | null;
  artist: string | null;
  nextTitle: string | null;
  updatedAt: string | null;
}

export interface WorkerInfo {
  service: string;
  status: string;
  lastSeenAt: string | null;
}

export interface DashboardStats {
  /** false عندما لا توجد إعدادات Supabase في البيئة */
  configured: boolean;
  stations: number | null;
  reciters: number | null;
  mediaReady: number | null;
  listeners: number | null;
  /** الأجهزة/التثبيتات غير الملغاة — بديل المستخدمين (لا حسابات في التطبيق) */
  users: number | null;
  /** مهام معالجة الصوت النشطة (UPLOADING/PROCESSING) */
  processingJobs: number | null;
  /** حملات الإشعارات المسجلة */
  campaigns: number | null;
  /** قنوات الفيديو المفعّلة */
  videoChannels: number | null;
  nowPlaying: NowPlayingInfo | null;
  worker: WorkerInfo | null;
}

const emptyStats = (configured: boolean): DashboardStats => ({
  configured,
  stations: null,
  reciters: null,
  mediaReady: null,
  listeners: null,
  users: null,
  processingJobs: null,
  campaigns: null,
  videoChannels: null,
  nowPlaying: null,
  worker: null,
});

async function countRows(
  schema: string,
  table: string,
  applyFilter?: (query: any) => any,
): Promise<number | null> {
  if (!supabase) return null;
  try {
    let query = supabase.schema(schema).from(table).select('id', { count: 'exact', head: true });
    if (applyFilter) query = applyFilter(query);
    const { count, error } = await query;
    if (error) return null;
    return count ?? 0;
  } catch {
    return null;
  }
}

async function fetchListeners(): Promise<number | null> {
  if (!supabase) return null;
  try {
    const { data: latest, error: latestError } = await supabase
      .schema('app')
      .from('station_metrics_minute')
      .select('bucket_at')
      .order('bucket_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (latestError || !latest?.bucket_at) return null;

    const { data, error } = await supabase
      .schema('app')
      .from('station_metrics_minute')
      .select('current_listeners')
      .eq('bucket_at', latest.bucket_at);
    if (error || !data) return null;
    return data.reduce((sum, row) => sum + (row.current_listeners ?? 0), 0);
  } catch {
    return null;
  }
}

async function fetchNowPlaying(): Promise<NowPlayingInfo | null> {
  if (!supabase) return null;
  try {
    const { data, error } = await supabase
      .schema('radio')
      .from('now_playing')
      .select('title, artist, next_title, updated_at')
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error || !data) return null;
    return {
      title: data.title ?? null,
      artist: data.artist ?? null,
      nextTitle: data.next_title ?? null,
      updatedAt: data.updated_at ?? null,
    };
  } catch {
    return null;
  }
}

async function fetchWorkerHeartbeat(): Promise<WorkerInfo | null> {
  if (!supabase) return null;
  try {
    const { data, error } = await supabase
      .schema('app')
      .from('service_heartbeats')
      .select('service, status, last_seen_at')
      .order('last_seen_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error || !data) return null;
    return {
      service: data.service,
      status: data.status,
      lastSeenAt: data.last_seen_at ?? null,
    };
  } catch {
    return null;
  }
}

export async function fetchDashboardStats(): Promise<DashboardStats> {
  if (!supabase) return emptyStats(false);

  const [
    stations,
    reciters,
    mediaReady,
    listeners,
    users,
    processingJobs,
    campaigns,
    videoChannels,
    nowPlaying,
    worker,
  ] = await Promise.all([
    countRows('app', 'stations', (q) => q.eq('is_active', true)),
    countRows('app', 'reciters', (q) => q.is('deleted_at', null)),
    countRows('app', 'media', (q) => q.eq('status', 'READY').is('deleted_at', null)),
    fetchListeners(),
    // الأجهزة المسجلة غير الملغاة — أقرب مقياس للمستخدمين (لا حسابات في التطبيق).
    countRows('app', 'installations', (q) => q.is('revoked_at', null)),
    countRows('app', 'media_processing_jobs', (q) =>
      q.in('status', ['UPLOADING', 'PROCESSING']),
    ),
    countRows('app', 'notification_campaigns'),
    countRows('app', 'video_channels', (q) => q.eq('is_active', true)),
    fetchNowPlaying(),
    fetchWorkerHeartbeat(),
  ]);

  return {
    configured: true,
    stations,
    reciters,
    mediaReady,
    listeners,
    users,
    processingJobs,
    campaigns,
    videoChannels,
    nowPlaying,
    worker,
  };
}

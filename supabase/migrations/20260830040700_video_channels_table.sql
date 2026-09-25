-- ============================================================================
-- 20260830040700_video_channels_table.sql
--
-- ⚠️  تطبيق يدوي إلزامي: طبّقه مالك قاعدة البيانات يدوياً عبر Supabase
-- Dashboard → SQL Editor بعد المراجعة (لا credentials للإنتاج في بيئة العمل).
--
-- الغرض: إنشاء جدول app.video_channels الموثّق في docs/VIDEO_CHANNELS.md
-- والمتوقَّع من supabase/seed/07_video_channels.sql (الذي يتجاوز بأمان حالياً
-- لأن الجدول غير موجود) ومن VideoChannelRepository في التطبيق.
--
-- قرارات تصميمية (من قراءة الكود الحالي):
--  * عمود stream_url واحد — نوع المصدر يُشتق في التطبيق من الرابط
--    (.m3u8 → HLS، روابط يوتيوب → YouTube، .mp4 → MP4). لا عمودين منفصلين.
--  * القراءة العامة للقنوات المفعّلة فقط تُدار عبر RLS (السياسة في الملف
--    20260830040800). الكتابة/الإدارة service_role فقط (fail-closed كبقية
--    الـ baseline) — أي عبر لوحة الإدارة/Backend API وليس من التطبيق.
--  * تغيير/تفعيل/ترتيب قناة من الإدارة ينعكس في التطبيق فوراً دون تحديث.
-- ============================================================================

create table app.video_channels (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  name_ar text not null,
  name_en text,
  stream_url text not null,
  logo_url text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index video_channels_active_order_idx
  on app.video_channels (is_active, sort_order, id)
  where is_active = true;

create trigger video_channels_updated_at
before update on app.video_channels
for each row execute function app.set_updated_at();

alter table app.video_channels enable row level security;

-- Baseline fail-closed: الكتابة والإدارة عبر service_role فقط.
grant select, insert, update, delete on app.video_channels to service_role;

comment on table app.video_channels is
  'Video channels catalog. Public read of active channels via RLS policy; writes are service_role only (admin-managed, no app update needed).';

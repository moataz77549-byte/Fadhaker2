-- ============================================================================
-- 20260830041200_video_channels_consolidation.sql
--
-- توحيد جدول app.video_channels — يجمع نية الملف
-- 20260830040700_video_channels_table.sql بصيغة idempotent بالكامل.
--
--   * آمن حتى لو طُبّق 40700 سابقاً: CREATE TABLE IF NOT EXISTS +
--     ADD COLUMN IF NOT EXISTS + فهرس ومشغّل (trigger) محميّان.
--   * قرارات التصميم (من قراءة الكود):
--     - عمود stream_url واحد؛ نوع المصدر يُشتق في التطبيق من الرابط
--       (.m3u8 → HLS، روابط يوتيوب → YouTube، .mp4 → MP4).
--     - القراءة العامة للقنوات المفعّلة فقط عبر RLS (السياسة في 41300).
--       الكتابة/الإدارة service_role فقط (fail-closed).
--     - أي تغيير من الإدارة ينعكس في التطبيق فوراً دون تحديث إجباري.
--   * لا أسرار هنا إطلاقاً.
-- ============================================================================

create table if not exists app.video_channels (
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

-- Convergence: أي عمود ناقص يُضاف دون المساس بالبيانات.
alter table app.video_channels add column if not exists slug text;
alter table app.video_channels add column if not exists name_ar text;
alter table app.video_channels add column if not exists name_en text;
alter table app.video_channels add column if not exists stream_url text;
alter table app.video_channels add column if not exists logo_url text;
alter table app.video_channels add column if not exists is_active boolean not null default true;
alter table app.video_channels add column if not exists sort_order integer not null default 0;
alter table app.video_channels add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table app.video_channels add column if not exists created_at timestamptz not null default now();
alter table app.video_channels add column if not exists updated_at timestamptz not null default now();

create index if not exists video_channels_active_order_idx
  on app.video_channels (is_active, sort_order, id)
  where is_active = true;

-- updated_at trigger (idempotent عبر الفحص ثم الإنشاء)
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'video_channels_updated_at') then
    create trigger video_channels_updated_at
    before update on app.video_channels
    for each row execute function app.set_updated_at();
  end if;
end $$;

alter table app.video_channels enable row level security;

-- Baseline fail-closed: الكتابة والإدارة عبر service_role فقط.
grant select, insert, update, delete on app.video_channels to service_role;

comment on table app.video_channels is
  'Video channels catalog. Public read of active channels via RLS policy; writes are service_role only (admin-managed, no app update needed).';

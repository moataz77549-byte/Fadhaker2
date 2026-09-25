-- ============================================================================
-- 20260830041500_admin_content_tables.sql
--
-- جداول الإدارة الناقصة فعلاً — بعد التدقيق في الـ schema الموحّد:
--
--   موجود فعلاً (يُتخطَّى إنشاؤه — موثّق في docs/MIGRATION_CONSOLIDATION.md):
--     * app.categories        ← يغني عن app.media_categories المقترح
--     * app.playlists         ← موجود (نموذج مرتبط بالمحطة للأتمتة الإذاعية)
--     * app.playlist_items    ← موجود
--     * app.schedules         ← موجود (جداول البث الزمني)
--     * app.audit_logs        ← موجود (سجل التدقيق)
--     * app.installations     ← المسمى المكافئ لـ app.devices (سجل الأجهزة/
--                               التثبيتات مع توكنز FCM؛ service_role فقط)
--
--   ناقص فعلاً ويُنشأ هنا:
--     * app.identity_settings — صف واحد لهوية المنصة (site_name, logo_url, …)
--       تحتاجه صفحة الإدارة «الهوية» لتصبح مربوطة بقاعدة البيانات.
--
-- Idempotent بالكامل: CREATE TABLE IF NOT EXISTS + ADD COLUMN IF NOT EXISTS
-- + INSERT ... ON CONFLICT DO NOTHING للصف الافتراضي.
-- ============================================================================

-- --------------------------------------------------------------------------
-- app.identity_settings — صف واحد (id=1) لهوية العلامة
-- --------------------------------------------------------------------------
create table if not exists app.identity_settings (
  id smallint primary key default 1 check (id = 1),
  site_name text not null default 'فذكر',
  tagline_ar text not null default 'منصة القرآن الكريم والبث الإذاعي',
  tagline_en text not null default 'Quran Platform & Radio Broadcast',
  logo_url text,
  logo_dark_url text,
  favicon_url text,
  primary_color text not null default '#243B6B',
  accent_color text not null default '#2E9E9E',
  support_url text,
  privacy_url text,
  terms_url text,
  contact_email text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table app.identity_settings add column if not exists site_name text;
alter table app.identity_settings add column if not exists tagline_ar text;
alter table app.identity_settings add column if not exists tagline_en text;
alter table app.identity_settings add column if not exists logo_url text;
alter table app.identity_settings add column if not exists logo_dark_url text;
alter table app.identity_settings add column if not exists favicon_url text;
alter table app.identity_settings add column if not exists primary_color text;
alter table app.identity_settings add column if not exists accent_color text;
alter table app.identity_settings add column if not exists support_url text;
alter table app.identity_settings add column if not exists privacy_url text;
alter table app.identity_settings add column if not exists terms_url text;
alter table app.identity_settings add column if not exists contact_email text;
alter table app.identity_settings add column if not exists metadata jsonb;
alter table app.identity_settings add column if not exists updated_at timestamptz not null default now();

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'identity_settings_updated_at') then
    create trigger identity_settings_updated_at
    before update on app.identity_settings
    for each row execute function app.set_updated_at();
  end if;
end $$;

alter table app.identity_settings enable row level security;

-- Fail-closed: القراءة/الكتابة للإدارة والـ backend فقط (service_role).
-- القراءة العامة للهوية (الشعار/الاسم) تُدار لاحقاً بسياسة مخصصة عند الحاجة.
revoke all on table app.identity_settings from public, anon, authenticated;
grant select, insert, update, delete on app.identity_settings to service_role;

-- الصف الافتراضي الوحيد (لا يُكتب فوق تخصيص المالك عند إعادة التطبيق)
insert into app.identity_settings (id) values (1)
on conflict (id) do nothing;

comment on table app.identity_settings is
  'Single-row platform identity (branding). Admin-managed via service_role; public read policy can be added later if the client needs it.';

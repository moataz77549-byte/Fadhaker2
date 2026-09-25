-- ============================================================================
-- 20260830040800_public_read_policies.sql
--
-- ⚠️  تطبيق يدوي إلزامي: طبّقه مالك قاعدة البيانات يدوياً عبر Supabase
-- Dashboard → SQL Editor بعد المراجعة (لا credentials للإنتاج في بيئة العمل).
--
-- الغرض: سياسات RLS الدنيا للقراءة العامة على الـ baseline الجديد
-- (20260830000100) الذي أبقى كل شيء fail-closed وrevoke من anon.
-- التطبيق (Flutter) يقرأ بالمفتاح العام (publishable/anon):
--   * app.stations (+ تضمين categories) عبر RadioCatalogService
--     (is_active=true, deleted_at is null, مرتبة بـ sort_order)
--   * app.video_channels عبر VideoChannelRepository (is_active=true)
-- بدون هذه السياسات + الـ GRANTs أدناه يفشل الكتالوج العام.
--
-- مبادئ مُطبَّقة (لا يُفتح schema كامل للعميل):
--  * SELECT فقط، وعلى أعمدة/صفوف عامة صراحةً (لا PII، لا أسرار، لا توكنز).
--  * كل ما عداها (installations, campaigns, deliveries, media, playlists,
--    schedules, radio.* ما عدا now_playing, audit/system logs, administrators,
--    roles/permissions) يبقى service_role فقط — أي عبر Edge Functions.
--  * سياسة quran_yutla القديمة "Public read playable stations" على app.stations
--    تشير للعمود is_playable غير الموجود في السكيما الجديدة (خطأ وقت التشغيل
--    إن وُجدت على نفس قاعدة البيانات) — تُحذف هنا بحذر (if exists) وتُستبدل.
-- ============================================================================

-- 1) منح الحد الأدنى اللازم لـ PostgREST (anon): استخدام السكيمات + SELECT على
--    الجداول العامة فقط. لا INSERT/UPDATE/DELETE للعميل إطلاقاً.
grant usage on schema app, radio to anon;
grant select on app.stations to anon;
grant select on app.reciters to anon;
grant select on app.surahs to anon;
grant select on app.categories to anon;
grant select on app.video_channels to anon;
grant select on app.app_config to anon;
grant select on radio.now_playing to anon;

-- 2) إزالة السياسة القديمة المكسورة (تشير لعمود غير موجود) إن وُجدت
drop policy if exists "Public read playable stations" on app.stations;

-- 3) سياسات القراءة العامة (idempotent عبر فحص pg_policies)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'app' and tablename = 'stations'
      and policyname = 'Public read active stations'
  ) then
    create policy "Public read active stations" on app.stations
      for select to anon
      using (is_active = true and deleted_at is null);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'app' and tablename = 'reciters'
      and policyname = 'Public read active reciters'
  ) then
    create policy "Public read active reciters" on app.reciters
      for select to anon
      using (is_active = true and deleted_at is null);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'app' and tablename = 'surahs'
      and policyname = 'Public read surahs'
  ) then
    create policy "Public read surahs" on app.surahs
      for select to anon
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'app' and tablename = 'categories'
      and policyname = 'Public read active categories'
  ) then
    create policy "Public read active categories" on app.categories
      for select to anon
      using (is_active = true and deleted_at is null);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'app' and tablename = 'video_channels'
      and policyname = 'Public read active video channels'
  ) then
    create policy "Public read active video channels" on app.video_channels
      for select to anon
      using (is_active = true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'app' and tablename = 'app_config'
      and policyname = 'Public read public app_config'
  ) then
    create policy "Public read public app_config" on app.app_config
      for select to anon
      using (is_public = true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'radio' and tablename = 'now_playing'
      and policyname = 'Public read now playing'
  ) then
    create policy "Public read now playing" on radio.now_playing
      for select to anon
      using (true);
  end if;
end $$;

-- 4) تذكير توثيقي داخل قاعدة البيانات
comment on policy "Public read active stations" on app.stations is
  'Minimal public catalog read for Flutter (anon key). Everything else stays service_role-only.';

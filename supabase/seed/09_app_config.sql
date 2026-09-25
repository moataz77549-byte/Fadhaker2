-- ============================================================================
-- 09_app_config.sql — مفاتيح النسخة الأدنى المدعومة (min supported version)
--
-- المفاتيح (حرفية — يقرأها تطبيق الجوال عبر /app_config العام):
--   * min_supported_version : نسخة التطبيق الدنيا المدعومة (نص JSON)
--   * min_supported_build   : رقم البناء الأدنى المدعوم (رقم JSON)
--
-- عمود value هو jsonb في السكيما الموحدة:
--   - النسخة: '"1.0.64"' كنص JSON مع value_type='STRING'
--   - البناء: '64' كرقم JSON مع value_type='INTEGER'
-- ============================================================================

insert into app.app_config (key, value, value_type, is_public, description) values
  ('min_supported_version', '"1.0.64"', 'STRING', true,
   'Minimum supported app version (semantic version string)'),
  ('min_supported_build', '64', 'INTEGER', true,
   'Minimum supported app build number')
on conflict (key) do update set
  value = excluded.value,
  value_type = excluded.value_type,
  is_public = excluded.is_public,
  description = excluded.description;

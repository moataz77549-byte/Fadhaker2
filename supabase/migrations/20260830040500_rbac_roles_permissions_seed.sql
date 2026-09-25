-- ============================================================================
-- 20260830040500_rbac_roles_permissions_seed.sql
--
-- ⚠️  تطبيق يدوي إلزامي: هذا الـ migration لم يُطبَّق تلقائياً (لا توجد
-- credentials للإنتاج في بيئة العمل). يجب على مالك قاعدة البيانات مراجعته
-- وتطبيقه يدوياً عبر Supabase Dashboard → SQL Editor بعد مراجعة الأمان.
--
-- الغرض: زرع الأدوار الإدارية المطلوبة فعلياً وصلاحيات notifications المفقودة.
--
-- ملاحظات تصميمية (مقروءة من الكود الحالي):
--  * جدول app.roles يفرض check (code ~ '^[A-Z_]+$') — لذلك تُستخدم أسماء
--    UPPER_SNAKE_CASE حصراً (وليس super_admin الصغيرة).
--  * الأدوار SUPER_ADMIN / RADIO_MANAGER / CONTENT_EDITOR / VIEWER موجودة
--    مسبقاً في supabase/seed/01_rbac.sql — هذا الملف لا يعيد تعريفها، بل يضيف
--    الأدوار الناقصة فقط ويُبقي القديمة للتوافق.
--  * الصلاحية notifications.write مُشار إليها في سياسة RLS موجودة
--    ("Admins manage campaigns" ON app.notification_campaigns) لكنها لم تُزرع
--    أبداً في supabase/seed/01_rbac.sql — هذا الملف يسدّ هذه الفجوة، وإلا بقيت
--    السياسة ميتة (لا أحد يملك الصلاحية).
--  * إنفاذ الأدوار يتم server-side فقط (Edge Functions / Backend API بمفتاح
--    service_role). تطبيق Flutter لا يملك أي service-role key ولا يتحقق من
--    الأدوار — أي عملية حساسة من العميل مباشرة مرفوضة تصميمياً.
-- ============================================================================

-- 1) صلاحيات notifications المفقودة (يُشار إليها في RLS دون أن تُزرع)
insert into app.permissions (code, description) values
  ('notifications.read',  'Read notification campaigns and delivery reports'),
  ('notifications.write', 'Create, schedule and dispatch notification campaigns')
on conflict (code) do update set description = excluded.description;

-- 2) الأدوار الإدارية الجديدة (SUPER_ADMIN موجود مسبقاً)
insert into app.roles (code, name) values
  ('CONTENT_ADMIN',      'Content Administrator'),
  ('RADIO_ADMIN',        'Radio Administrator'),
  ('NOTIFICATION_ADMIN', 'Notification Administrator'),
  ('MEDIA_ADMIN',        'Media Administrator')
on conflict (code) do update set name = excluded.name;

-- 3) SUPER_ADMIN يحصل على الصلاحيات الجديدة أيضاً
insert into app.role_permissions (role_id, permission_id)
select r.id, p.id
from app.roles r
cross join app.permissions p
where r.code = 'SUPER_ADMIN'
  and p.code in ('notifications.read', 'notifications.write')
on conflict do nothing;

-- 4) مصفوفة الصلاحيات لكل دور جديد
with matrix(role_code, permission_code) as (values
  -- NOTIFICATION_ADMIN: إدارة الحملات فقط
  ('NOTIFICATION_ADMIN','dashboard.read'),
  ('NOTIFICATION_ADMIN','notifications.read'),
  ('NOTIFICATION_ADMIN','notifications.write'),

  -- MEDIA_ADMIN: مكتبة الوسائط والأرشفة
  ('MEDIA_ADMIN','dashboard.read'),
  ('MEDIA_ADMIN','media.read'),
  ('MEDIA_ADMIN','media.write'),
  ('MEDIA_ADMIN','media.archive'),
  ('MEDIA_ADMIN','reciters.read'),

  -- CONTENT_ADMIN: المحتوى (وسائط/قرّاء/تصنيفات/قراءة المحطات والمزودين والحقوق)
  ('CONTENT_ADMIN','dashboard.read'),
  ('CONTENT_ADMIN','media.read'),
  ('CONTENT_ADMIN','media.write'),
  ('CONTENT_ADMIN','reciters.read'),
  ('CONTENT_ADMIN','reciters.write'),
  ('CONTENT_ADMIN','categories.read'),
  ('CONTENT_ADMIN','categories.write'),
  ('CONTENT_ADMIN','stations.read'),
  ('CONTENT_ADMIN','providers.read'),
  ('CONTENT_ADMIN','rights.read'),

  -- RADIO_ADMIN: إدارة الراديو الكاملة (مكافئ وظيفي لـ RADIO_MANAGER القديم)
  ('RADIO_ADMIN','dashboard.read'),
  ('RADIO_ADMIN','analytics.read'),
  ('RADIO_ADMIN','health.read'),
  ('RADIO_ADMIN','stations.read'),
  ('RADIO_ADMIN','stations.write'),
  ('RADIO_ADMIN','playlists.read'),
  ('RADIO_ADMIN','playlists.write'),
  ('RADIO_ADMIN','schedules.read'),
  ('RADIO_ADMIN','schedules.write'),
  ('RADIO_ADMIN','radio.read'),
  ('RADIO_ADMIN','radio.command'),
  ('RADIO_ADMIN','radio.interrupt'),
  ('RADIO_ADMIN','radio.live')
)
insert into app.role_permissions (role_id, permission_id)
select r.id, p.id
from matrix m
join app.roles r on r.code = m.role_code
join app.permissions p on p.code = m.permission_code
on conflict do nothing;

-- 5) توثيق داخل قاعدة البيانات: العمليات الحساسة server-side فقط
comment on table app.administrator_roles is
  'Enforced server-side only. Flutter clients never hold service_role keys and must not branch on roles.';

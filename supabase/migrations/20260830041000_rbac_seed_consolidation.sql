-- ============================================================================
-- 20260830041000_rbac_seed_consolidation.sql
--
-- توحيد زرع RBAC — يجمع نية الملف 20260830040500_rbac_roles_permissions_seed.sql
-- وsupabase/seed/01_rbac.sql في ملف idempotent واحد.
--
--   * آمن حتى لو طُبّق 40500 (أو جزء منه) سابقاً: كل الإدراجات
--     ON CONFLICT، والمصفوفة تُدرج ما ينقص فقط.
--   * الأدوار: SUPER_ADMIN / CONTENT_ADMIN / RADIO_ADMIN / NOTIFICATION_ADMIN /
--     MEDIA_ADMIN (الأكواد الكبيرة UPPER_SNAKE_CASE مطلوبة بقيد الجدول).
--     الأكواد القديمة (RADIO_MANAGER / CONTENT_EDITOR / VIEWER) تُحفظ إن وُجدت
--     ولا تُحذف — للتوافق مع أي تعيينات قائمة.
--   * إنفاذ الأدوار server-side فقط (Edge Functions / Backend بمفتاح
--     service_role). تطبيق Flutter لا يحمل service-role key ولا يفرّع على الأدوار.
--   * لا أسرار حقيقية هنا إطلاقاً.
-- ============================================================================

-- 1) الصلاحيات: الأساسية + notifications (كانت مُشاراً إليها في RLS دون زرع)
insert into app.permissions (code, description) values
  ('dashboard.read',        'Read central dashboard'),
  ('analytics.read',        'Read analytics'),
  ('health.read',           'Read detailed service health'),
  ('media.read',            'Read media library'),
  ('media.write',           'Create and edit media'),
  ('media.archive',         'Archive media'),
  ('reciters.read',         'Read reciters and tracks'),
  ('reciters.write',        'Manage reciters and tracks'),
  ('categories.read',       'Read categories'),
  ('categories.write',      'Manage categories'),
  ('stations.read',         'Read station configuration'),
  ('stations.write',        'Manage station configuration'),
  ('external_stations.write','Manage external stations'),
  ('external_stations.health','Request external stream health checks'),
  ('providers.read',        'Read provider configuration'),
  ('providers.write',       'Manage provider configuration'),
  ('providers.sync',        'Request provider synchronization'),
  ('rights.read',           'Read rights metadata'),
  ('rights.approve',        'Approve rights and commercial-use status'),
  ('playlists.read',        'Read playlists'),
  ('playlists.write',       'Manage playlists'),
  ('schedules.read',        'Read schedules and templates'),
  ('schedules.write',       'Manage schedules and templates'),
  ('radio.read',            'Read radio state and history'),
  ('radio.command',         'Create non-interrupting radio commands'),
  ('radio.interrupt',       'Create interrupting radio commands'),
  ('radio.live',            'Start and stop live mode'),
  ('notifications.read',    'Read notification campaigns and delivery reports'),
  ('notifications.write',   'Create, schedule and dispatch notification campaigns'),
  ('administrators.read',   'Read administrator profiles and assignments'),
  ('administrators.write',  'Manage administrators and assignments'),
  ('roles.read',            'Read roles and permissions'),
  ('roles.write',           'Manage role permission mappings'),
  ('settings.read',         'Read application settings'),
  ('settings.write',        'Manage application settings'),
  ('audit.read',            'Read audit trail')
on conflict (code) do update set description = excluded.description;

-- 2) الأدوار الإدارية (UPPER_SNAKE_CASE حصراً — قيد code ~ '^[A-Z_]+$')
insert into app.roles (code, name) values
  ('SUPER_ADMIN',       'Super Administrator'),
  ('CONTENT_ADMIN',     'Content Administrator'),
  ('RADIO_ADMIN',       'Radio Administrator'),
  ('NOTIFICATION_ADMIN','Notification Administrator'),
  ('MEDIA_ADMIN',       'Media Administrator')
on conflict (code) do update set name = excluded.name;

-- 3) SUPER_ADMIN يملك كل الصلاحيات الحالية (تشمل أي صلاحية تُضاف لاحقاً
--    عند إعادة تطبيق هذا الملف بعد مراجعته)
insert into app.role_permissions (role_id, permission_id)
select r.id, p.id
from app.roles r cross join app.permissions p
where r.code = 'SUPER_ADMIN'
on conflict do nothing;

-- 4) مصفوفة الصلاحيات للأدوار الجديدة (تُدرج الناقص فقط)
with matrix(role_code, permission_code) as (values
  ('NOTIFICATION_ADMIN','dashboard.read'),
  ('NOTIFICATION_ADMIN','notifications.read'),
  ('NOTIFICATION_ADMIN','notifications.write'),

  ('MEDIA_ADMIN','dashboard.read'),
  ('MEDIA_ADMIN','media.read'),
  ('MEDIA_ADMIN','media.write'),
  ('MEDIA_ADMIN','media.archive'),
  ('MEDIA_ADMIN','reciters.read'),

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

comment on table app.administrator_roles is
  'Enforced server-side only. Flutter clients never hold service_role keys and must not branch on roles.';

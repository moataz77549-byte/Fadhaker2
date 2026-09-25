insert into app.roles (code, name) values
  ('SUPER_ADMIN', 'Super Administrator'),
  ('RADIO_MANAGER', 'Radio Manager'),
  ('CONTENT_EDITOR', 'Content Editor'),
  ('VIEWER', 'Read-only Viewer')
on conflict (code) do update set name = excluded.name;

insert into app.permissions (code, description) values
  ('dashboard.read', 'Read dashboard'),
  ('analytics.read', 'Read analytics'),
  ('health.read', 'Read detailed service health'),
  ('media.read', 'Read media library'),
  ('media.write', 'Create and edit media'),
  ('media.archive', 'Archive media'),
  ('reciters.read', 'Read reciters and tracks'),
  ('reciters.write', 'Manage reciters and tracks'),
  ('categories.read', 'Read categories'),
  ('categories.write', 'Manage categories'),
  ('stations.read', 'Read station configuration'),
  ('stations.write', 'Manage station configuration'),
  ('external_stations.write', 'Manage external stations'),
  ('external_stations.health', 'Request external stream health checks'),
  ('providers.read', 'Read provider configuration'),
  ('providers.write', 'Manage provider configuration'),
  ('providers.sync', 'Request provider synchronization'),
  ('rights.read', 'Read rights metadata'),
  ('rights.approve', 'Approve rights and commercial-use status'),
  ('playlists.read', 'Read playlists'),
  ('playlists.write', 'Manage playlists'),
  ('schedules.read', 'Read schedules and templates'),
  ('schedules.write', 'Manage schedules and templates'),
  ('radio.read', 'Read radio state and history'),
  ('radio.command', 'Create non-interrupting radio commands'),
  ('radio.interrupt', 'Create interrupting radio commands'),
  ('radio.live', 'Start and stop live mode'),
  ('administrators.read', 'Read administrator profiles and assignments'),
  ('administrators.write', 'Manage administrators and assignments'),
  ('roles.read', 'Read roles and permissions'),
  ('roles.write', 'Manage role permission mappings'),
  ('settings.read', 'Read application settings'),
  ('settings.write', 'Manage application settings'),
  ('audit.read', 'Read audit trail')
on conflict (code) do update set description = excluded.description;

-- SUPER_ADMIN receives every current permission. Adding a permission later still requires a reviewed seed update.
insert into app.role_permissions (role_id, permission_id)
select r.id, p.id from app.roles r cross join app.permissions p where r.code = 'SUPER_ADMIN'
on conflict do nothing;

with matrix(role_code, permission_code) as (values
  ('RADIO_MANAGER','dashboard.read'),('RADIO_MANAGER','analytics.read'),('RADIO_MANAGER','health.read'),
  ('RADIO_MANAGER','stations.read'),('RADIO_MANAGER','playlists.read'),('RADIO_MANAGER','playlists.write'),
  ('RADIO_MANAGER','schedules.read'),('RADIO_MANAGER','schedules.write'),('RADIO_MANAGER','radio.read'),
  ('RADIO_MANAGER','radio.command'),('RADIO_MANAGER','radio.interrupt'),('RADIO_MANAGER','radio.live'),
  ('CONTENT_EDITOR','dashboard.read'),('CONTENT_EDITOR','media.read'),('CONTENT_EDITOR','media.write'),
  ('CONTENT_EDITOR','media.archive'),('CONTENT_EDITOR','reciters.read'),('CONTENT_EDITOR','reciters.write'),
  ('CONTENT_EDITOR','categories.read'),('CONTENT_EDITOR','categories.write'),('CONTENT_EDITOR','stations.read'),
  ('CONTENT_EDITOR','providers.read'),('CONTENT_EDITOR','rights.read'),
  ('VIEWER','dashboard.read'),('VIEWER','analytics.read'),('VIEWER','health.read'),
  ('VIEWER','media.read'),('VIEWER','reciters.read'),('VIEWER','categories.read'),
  ('VIEWER','stations.read'),('VIEWER','providers.read'),('VIEWER','rights.read'),
  ('VIEWER','playlists.read'),('VIEWER','schedules.read'),('VIEWER','radio.read'),('VIEWER','settings.read')
)
insert into app.role_permissions (role_id, permission_id)
select r.id, p.id from matrix m
join app.roles r on r.code = m.role_code
join app.permissions p on p.code = m.permission_code
on conflict do nothing;

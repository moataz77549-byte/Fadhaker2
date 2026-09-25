insert into app.app_config (key, value, value_type, is_public, description) values
  ('maintenance_mode', 'false', 'BOOLEAN', true, 'Global listener application maintenance flag'),
  ('minimum_android_version', '"0.0.0"', 'STRING', true, 'Minimum supported Android version'),
  ('minimum_ios_version', '"0.0.0"', 'STRING', true, 'Minimum supported iOS version'),
  ('latest_android_version', '"0.0.0"', 'STRING', true, 'Latest Android release'),
  ('latest_ios_version', '"0.0.0"', 'STRING', true, 'Latest iOS release'),
  ('radio_enabled', 'true', 'BOOLEAN', true, 'Global radio feature switch'),
  ('featured_station', 'null', 'JSON', true, 'Internal station UUID or null'),
  ('support_url', '"https://example.com/support"', 'URL', true, 'Placeholder until owner configures support URL'),
  ('privacy_url', '"https://example.com/privacy"', 'URL', true, 'Placeholder until owner configures privacy URL'),
  ('terms_url', '"https://example.com/terms"', 'URL', true, 'Placeholder until owner configures terms URL'),
  ('external_direct_playback', 'true', 'BOOLEAN', false, 'External streams play directly without platform proxy'),
  ('external_auto_hide_unreachable', 'false', 'BOOLEAN', false, 'Prepared but disabled for this phase'),
  ('external_health_policy', '{"degraded_after_failures":2,"unreachable_after_failures":5,"recovery_successes":2}', 'JSON', false, 'Configurable defaults; workers may override per environment')
on conflict (key) do update set
  value = excluded.value,
  value_type = excluded.value_type,
  is_public = excluded.is_public,
  description = excluded.description;

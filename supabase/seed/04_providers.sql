-- Repeatable provider seed. External providers are not production-approved.
insert into app.content_provider_types (code, description) values
  ('INTERNAL', 'Owned and operated by this platform'),
  ('QURANGO', 'Qurango static/stream inventory'),
  ('MP3QURAN', 'MP3Quran API catalog provider'),
  ('CUSTOM', 'Manually managed external provider'),
  ('OTHER', 'Other provider type')
on conflict (code) do nothing;

insert into app.stream_types (code, description) values
  ('INTERNAL', 'Platform-managed Icecast output'),
  ('HLS', 'HTTP Live Streaming playlist'),
  ('ICECAST', 'Icecast-compatible continuous stream'),
  ('SHOUTCAST', 'Shoutcast/ICY continuous stream'),
  ('MP3_STREAM', 'Progressive or continuous MP3 stream'),
  ('AAC_STREAM', 'Progressive or continuous AAC stream'),
  ('UNKNOWN_STREAM', 'Unclassified stream requiring validation')
on conflict (code) do nothing;

insert into app.content_providers
  (name, slug, provider_type, website_url, api_base_url, priority, production_enabled,
   rights_status, commercial_use_status, attribution_required, source_url, metadata)
values
  ('Internal Platform', 'internal', 'INTERNAL', null, null, 1000, true,
   'APPROVED', 'ALLOWED', false, null, '{"managed":true}'::jsonb),
  ('Qurango', 'qurango', 'QURANGO', 'https://qurango.net', null, 500, false,
   'REVIEW_REQUIRED', 'UNKNOWN', true, 'https://backup.qurango.net', '{"seed_inventory":true}'::jsonb),
  ('MP3Quran', 'mp3quran', 'MP3QURAN', 'https://www.mp3quran.net/ar/radios',
   'https://www.mp3quran.net/api/v3', 600, false,
   'REVIEW_REQUIRED', 'UNKNOWN', true, 'https://www.mp3quran.net/api/v3/radios?language=ar',
   '{"adapter":"Mp3QuranProviderAdapter","legacy_source":"https://www.mp3quran.net/api/radio/radio_ar.json"}'::jsonb),
  ('Holol Live', 'holol', 'OTHER', 'https://win.holol.com', null, 300, false,
   'REVIEW_REQUIRED', 'UNKNOWN', true, 'https://win.holol.com', '{"seed_inventory":true}'::jsonb),
  ('Radiojar', 'radiojar', 'OTHER', 'https://www.radiojar.com', null, 300, false,
   'REVIEW_REQUIRED', 'UNKNOWN', true, 'https://stream.radiojar.com', '{"seed_inventory":true}'::jsonb),
  ('Custom', 'custom', 'CUSTOM', null, null, 100, false,
   'REVIEW_REQUIRED', 'UNKNOWN', false, null, '{}'::jsonb)
on conflict (slug) do nothing;

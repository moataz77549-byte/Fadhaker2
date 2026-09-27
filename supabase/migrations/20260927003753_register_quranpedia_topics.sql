-- Register the official Quranpedia topics source without enabling an unreviewed
-- production sync. The official dumps are versioned and checksum-protected;
-- use only the topics file, not unrelated third-party content.
insert into app.content_sources (
  slug, name, type, website, api_url, license, license_url,
  attribution_required, attribution, offline_allowed,
  redistribution_allowed, commercial_allowed, active,
  last_checked, notes, metadata
) values (
  'quranpedia',
  'الموسوعة القرآنية — Quranpedia',
  'Quran topics / topical verse index',
  'https://quranpedia.net',
  'https://api.quranpedia.net/v1',
  'QURANPEDIA_DATA_LICENSE',
  'https://quranpedia.net/dumps/LICENSE.md',
  false,
  'الموسوعة القرآنية — https://quranpedia.net',
  true,
  false,
  false,
  false,
  now(),
  'Official topics dump may be cached in an app. Keep attribution and dump version with any exported database. Review topic payload provenance and delta sync before production activation.',
  '{"content_scope":"topics_only","dump_url":"https://quranpedia.net/dumps","changes_url":"https://quranpedia.net/api/v1/changes","terms_url":"https://quranpedia.net/api-docs#usage-policy","review_stage":"REGISTERED"}'::jsonb
)
on conflict (slug) do nothing;

insert into app.content_providers (
  name, slug, provider_type, website_url, api_base_url,
  is_active, production_enabled, rights_status,
  attribution_required, attribution_text, terms_url, source_url,
  verified_at, internal_notes, metadata
) values (
  'Quranpedia Topics',
  'quranpedia',
  'EXTERNAL',
  'https://quranpedia.net',
  'https://api.quranpedia.net/v1',
  false,
  false,
  'REVIEW_REQUIRED',
  false,
  'الموسوعة القرآنية — https://quranpedia.net',
  'https://quranpedia.net/dumps/LICENSE.md',
  'https://quranpedia.net/dumps',
  now(),
  'Topic-only offline sync; do not enable until payload, version, checksum, delta sync and app attribution are reviewed.',
  '{"content_scope":"topics_only","review_stage":"REGISTERED"}'::jsonb
)
on conflict (slug) do nothing;
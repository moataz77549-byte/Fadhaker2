-- Make intentional provider blockers explicit to the admin UI and sync layer.
-- No credentials or fabricated content are stored here.
update app.content_providers
set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'integration_state', 'blocked_missing_credentials',
      'required_secret', 'ISLAMHOUSE_API_KEY',
      'documentation_url', 'https://api2.islamhouse.com/ar/docs/quran/'
    ),
    internal_notes = concat_ws(E'\n', nullif(internal_notes, ''),
      'Integration intentionally remains disabled until an IslamHouse developer API key is provisioned as a server-side secret.'),
    production_enabled = false,
    updated_at = now()
where slug = 'islamhouse';

update app.content_providers
set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'integration_state', 'blocked_missing_curated_source',
      'required_before_sync', jsonb_build_array(
        'canonical_source_url',
        'redistribution_terms',
        'source_version_or_revision',
        'content_integrity_strategy'
      )
    ),
    internal_notes = concat_ws(E'\n', nullif(internal_notes, ''),
      'No external adhkar dataset is activated until a canonical, traceable source with redistribution terms and revision metadata is selected.'),
    production_enabled = false,
    updated_at = now()
where slug = 'hisn-al-muslim';

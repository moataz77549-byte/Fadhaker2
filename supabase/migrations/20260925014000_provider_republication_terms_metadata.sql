-- Record source-published redistribution conditions without changing
-- approval/production gates. Legal/owner approval remains a separate action.
update app.content_providers
set terms_url = 'https://quranenc.com/ar/home/api',
    attribution_required = true,
    internal_notes = concat_ws(E'\n', nullif(internal_notes, ''),
      'Source terms allow download/republication subject to preserving content, source/publisher attribution, version attribution, updates to new versions, and appropriate presentation. Provider remains gated pending owner rights review.'),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'published_terms_reviewed_at', '2026-09-25',
      'requires_source_attribution', true,
      'requires_version_attribution', true,
      'requires_content_integrity', true,
      'requires_latest_version_updates', true,
      'publication_gate_note', 'owner_review_required'
    ),
    updated_at = now()
where slug = 'quranenc';

update app.content_providers
set terms_url = 'https://hadeethenc.com/ar',
    attribution_required = true,
    internal_notes = concat_ws(E'\n', nullif(internal_notes, ''),
      'Source terms allow download/republication subject to preserving content, source/publisher attribution, version attribution, updates to new versions, and appropriate presentation. Current API ingest does not expose a reliable source version, so production publication remains blocked.'),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'published_terms_reviewed_at', '2026-09-25',
      'requires_source_attribution', true,
      'requires_version_attribution', true,
      'requires_content_integrity', true,
      'requires_latest_version_updates', true,
      'publication_gate_note', 'source_version_required_before_publication'
    ),
    updated_at = now()
where slug = 'hadeethenc';

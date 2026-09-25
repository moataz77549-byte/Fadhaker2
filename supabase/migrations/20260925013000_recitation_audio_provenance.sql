-- Attach provenance to the existing AlQuran.cloud / Islamic Network
-- recitation URLs without changing their current public-read policy.
--
-- The provider remains REVIEW_REQUIRED/UNKNOWN at the provider-rights layer:
-- audio copyright is retained by the reciters/rightsholders and may require
-- removal on request. This migration records provenance; it does not broaden
-- redistribution rights or mark the provider production-approved.
insert into app.content_providers (
  name,
  slug,
  provider_type,
  website_url,
  api_base_url,
  rights_status,
  commercial_use_status,
  production_enabled,
  attribution_required,
  attribution_text,
  terms_url,
  source_url,
  internal_notes,
  metadata
)
values (
  'AlQuran.cloud / Islamic Network',
  'alquran-cloud',
  'EXTERNAL',
  'https://alquran.cloud',
  'https://api.alquran.cloud/v1',
  'REVIEW_REQUIRED',
  'UNKNOWN',
  false,
  true,
  'Recitation source: AlQuran.cloud / Islamic Network. Recording rights remain with the reciter/rightsholder.',
  'https://alquran.cloud/terms-and-conditions',
  'https://alquran.cloud/api',
  'Provenance registration only. Do not infer provider-wide commercial approval from this row.',
  '{"role":"quran_recitation_audio","cdn_host":"cdn.islamic.network","rights_note":"reciter_rights_retained"}'::jsonb
)
on conflict (slug) do update
set website_url = excluded.website_url,
    api_base_url = excluded.api_base_url,
    attribution_required = excluded.attribution_required,
    attribution_text = excluded.attribution_text,
    terms_url = excluded.terms_url,
    source_url = excluded.source_url,
    internal_notes = excluded.internal_notes,
    metadata = coalesce(app.content_providers.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = now();

update app.reciter_tracks rt
set provider_id = cp.id,
    metadata = coalesce(rt.metadata, '{}'::jsonb) || jsonb_build_object(
      'source_provider', 'alquran-cloud',
      'source_host', 'cdn.islamic.network',
      'source_terms_url', 'https://alquran.cloud/terms-and-conditions'
    ),
    updated_at = now()
from app.content_providers cp
where cp.slug = 'alquran-cloud'
  and rt.provider_id is null
  and rt.audio_url like 'https://cdn.islamic.network/%';

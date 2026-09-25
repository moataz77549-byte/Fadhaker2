-- Add only gaps in the live app schema. Canonical Quran tables are untouched.
-- All imported content is private until the source and record pass review.
create table if not exists app.quran_translations (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  translation_key text not null,
  source_external_id text not null,
  language_code text not null,
  language_name text,
  title text not null,
  surah_number smallint not null check (surah_number between 1 and 114),
  ayah_number smallint not null check (ayah_number between 1 and 286),
  verse_key text generated always as (surah_number::text || ':' || ayah_number::text) stored,
  translation_text text not null check (length(btrim(translation_text)) > 0),
  footnotes text,
  source_url text not null,
  source_version text not null,
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  source_updated_at timestamptz,
  last_synced_at timestamptz not null default now(),
  is_active boolean not null default false,
  unique (provider_id, translation_key, surah_number, ayah_number)
);
create index if not exists quran_translations_lookup_idx
  on app.quran_translations (language_code, translation_key, surah_number, ayah_number)
  where is_active;

create table if not exists app.hadith_categories (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  external_id text not null,
  language_code text not null,
  name text not null,
  parent_external_id text,
  source_url text not null,
  source_version text,
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  synced_at timestamptz not null default now(),
  is_active boolean not null default false,
  unique (provider_id, external_id, language_code)
);
create table if not exists app.hadiths (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  external_id text not null,
  language_code text not null,
  title text,
  hadith_text text not null check (length(btrim(hadith_text)) > 0),
  narrator text,
  grade text,
  attribution text,
  explanation text,
  benefits text,
  reference text,
  source_url text not null,
  source_version text,
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  source_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  verified_at timestamptz,
  is_active boolean not null default false,
  unique (provider_id, external_id, language_code)
);
create index if not exists hadiths_language_active_idx
  on app.hadiths (language_code, id) where is_active;
create table if not exists app.hadith_category_links (
  hadith_id uuid not null references app.hadiths(id) on delete cascade,
  category_id uuid not null references app.hadith_categories(id) on delete cascade,
  primary key (hadith_id, category_id)
);
create index if not exists hadith_category_links_category_idx
  on app.hadith_category_links (category_id, hadith_id);

-- The existing adhkar table is the canonical home for reviewed adhkar.
alter table app.adhkar add column if not exists provider_id uuid references app.content_providers(id) on delete restrict;
alter table app.adhkar add column if not exists source_external_id text;
alter table app.adhkar add column if not exists source_version text;
alter table app.adhkar add column if not exists content_hash text;
alter table app.adhkar add column if not exists verified boolean not null default false;
alter table app.adhkar add column if not exists reviewed_at timestamptz;
alter table app.adhkar add column if not exists last_synced_at timestamptz;
alter table app.adhkar add column if not exists is_active boolean not null default false;
create unique index if not exists adhkar_provider_identity_idx
  on app.adhkar (provider_id, source_external_id, category, source_reference)
  where provider_id is not null and source_external_id is not null;

-- Existing sync runs hold metrics and individual cursors; state holds the
-- last successfully committed cursor. Failed runs never advance it.
alter table app.provider_sync_runs add column if not exists dataset text;
create table if not exists app.provider_sync_state (
  provider_id uuid not null references app.content_providers(id) on delete cascade,
  dataset text not null,
  cursor_data jsonb not null default '{}'::jsonb,
  last_checksum text,
  last_success_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (provider_id, dataset)
);

insert into app.content_provider_types (code, description) values
  ('QURANENC', 'QuranEnc official translations'),
  ('HADEETHENC', 'HadeethEnc official hadith catalog'),
  ('ISLAMHOUSE', 'IslamHouse curated library'),
  ('TANZIL', 'Quran text verification only'),
  ('DORAR', 'Hadith reference and verification'),
  ('HISN_AL_MUSLIM', 'Reviewed Hisn al Muslim adhkar')
on conflict (code) do nothing;
insert into app.content_providers
  (name, slug, provider_type, website_url, api_base_url, rights_status,
   commercial_use_status, production_enabled, attribution_required, terms_url,
   source_url, metadata)
values
  ('QuranEnc', 'quranenc', 'QURANENC', 'https://quranenc.com',
   'https://quranenc.com/api/v1', 'REVIEW_REQUIRED', 'UNKNOWN', false, true,
   'https://quranenc.com/ar/home', 'https://quranenc.com/ar/home/api',
   '{"role":"translations","requires_version_attribution":true}'::jsonb),
  ('HadeethEnc', 'hadeethenc', 'HADEETHENC', 'https://hadeethenc.com',
   'https://hadeethenc.com/api/v1', 'REVIEW_REQUIRED', 'UNKNOWN', false, true,
   'https://hadeethenc.com/ar', 'https://hadeethenc.com/ar',
   '{"role":"hadith"}'::jsonb),
  ('IslamHouse', 'islamhouse', 'ISLAMHOUSE', 'https://islamhouse.com',
   'https://api2.islamhouse.com', 'REVIEW_REQUIRED', 'UNKNOWN', false, true,
   'https://api2.islamhouse.com/ar/docs/', 'https://api2.islamhouse.com/ar/docs/',
   '{"role":"curated_library","requires_api_credentials":true}'::jsonb),
  ('Tanzil', 'tanzil', 'TANZIL', 'https://tanzil.net', null,
   'REVIEW_REQUIRED', 'UNKNOWN', false, true, 'https://tanzil.net/docs/',
   'https://tanzil.net/download/', '{"role":"verify_only"}'::jsonb),
  ('Dorar', 'dorar', 'DORAR', 'https://dorar.net', null,
   'REVIEW_REQUIRED', 'UNKNOWN', false, true, 'https://dorar.net',
   'https://dorar.net/article/389', '{"role":"search_reference_only"}'::jsonb),
  ('Hisn Al-Muslim', 'hisn-al-muslim', 'HISN_AL_MUSLIM', null, null,
   'REVIEW_REQUIRED', 'UNKNOWN', false, true, null, null,
   '{"role":"reviewed_adhkar_only"}'::jsonb)
on conflict (slug) do nothing;

alter table app.quran_translations enable row level security;
alter table app.hadith_categories enable row level security;
alter table app.hadiths enable row level security;
alter table app.hadith_category_links enable row level security;
alter table app.provider_sync_state enable row level security;
revoke all on app.quran_translations, app.hadith_categories, app.hadiths,
  app.hadith_category_links, app.provider_sync_state from public, anon, authenticated;
grant select, insert, update, delete on app.quran_translations, app.hadith_categories,
  app.hadiths, app.hadith_category_links, app.provider_sync_state to service_role;
grant select on app.quran_translations, app.hadith_categories, app.hadiths,
  app.hadith_category_links to anon, authenticated;
create policy "approved_quran_translations" on app.quran_translations for select to anon, authenticated
  using (is_active and exists (select 1 from app.content_providers p
    where p.id = provider_id and p.production_enabled and p.rights_status = 'APPROVED'));
create policy "approved_hadith_categories" on app.hadith_categories for select to anon, authenticated
  using (is_active and exists (select 1 from app.content_providers p
    where p.id = provider_id and p.production_enabled and p.rights_status = 'APPROVED'));
create policy "approved_hadiths" on app.hadiths for select to anon, authenticated
  using (is_active and verified_at is not null and exists
    (select 1 from app.content_providers p where p.id = provider_id
     and p.production_enabled and p.rights_status = 'APPROVED'));
create policy "approved_hadith_category_links" on app.hadith_category_links for select to anon, authenticated
  using (exists (select 1 from app.hadiths h where h.id = hadith_id));

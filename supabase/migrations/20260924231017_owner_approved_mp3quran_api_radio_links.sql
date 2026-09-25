-- Owner-approved, narrowly scoped API radio linking; no audio rehosting rights asserted.
-- Formal provider rights review remains open for all other datasets.
alter table app.content_providers
  add column if not exists api_stream_links_enabled boolean not null default false;
alter table app.content_providers
  add column if not exists api_stream_links_authorized_at timestamptz;

comment on column app.content_providers.api_stream_links_enabled is
  'Owner-authorized linking of official API radio streams only. Does not authorize copying audio or other provider datasets.';

update app.content_providers
set api_stream_links_enabled = true,
    api_stream_links_authorized_at = coalesce(api_stream_links_authorized_at, now()),
    updated_at = now()
where slug = 'mp3quran';

grant select (slug, api_stream_links_enabled) on app.content_providers to anon, authenticated;

drop policy if exists "Public read approved content providers"
  on app.content_providers;
create policy "Public read approved content providers"
  on app.content_providers for select to anon, authenticated
  using (
    is_active = true
    and deleted_at is null
    and (
      (production_enabled = true and rights_status = 'APPROVED'
       and commercial_use_status = 'ALLOWED')
      or (slug = 'mp3quran' and api_stream_links_enabled = true)
    )
  );

drop policy if exists "Public read approved stations" on app.stations;
create policy "Public read approved stations"
  on app.stations for select to anon, authenticated
  using (
    is_active = true and is_playable = true and deleted_at is null
    and exists (
      select 1 from app.content_providers cp
      where cp.id = provider_id and cp.is_active = true and cp.deleted_at is null
        and (
          (rights_status = 'APPROVED' and commercial_use_status = 'ALLOWED'
           and cp.production_enabled = true and cp.rights_status = 'APPROVED'
           and cp.commercial_use_status = 'ALLOWED')
          or (
            cp.slug = 'mp3quran' and cp.api_stream_links_enabled = true
            and external_key is not null
            and source_url = 'https://www.mp3quran.net/api/v3/radios?language=ar'
            and health_status = 'HEALTHY'
          )
        )
    )
  );

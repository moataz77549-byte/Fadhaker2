-- Column-level SELECT on content_providers requires an explicit selected column
-- in the station RLS EXISTS subquery under Postgres 17.
drop policy if exists "Public read approved stations" on app.stations;
create policy "Public read approved stations"
  on app.stations for select to anon, authenticated
  using (
    is_active = true and is_playable = true and deleted_at is null
    and exists (
      select cp.id from app.content_providers cp
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

-- Consolidate app.stations SELECT policies so authenticated requests evaluate
-- one permissive policy instead of both public + admin policies.
drop policy if exists "Public read approved stations" on app.stations;
drop policy if exists "admin_read_stations" on app.stations;

create policy "Public read approved stations"
  on app.stations
  for select
  to anon
  using (
    is_active = true
    and is_playable = true
    and deleted_at is null
    and (
      (
        rights_status = 'APPROVED'
        and commercial_use_status = 'ALLOWED'
        and private.radio_provider_allowed(provider_id, false)
      )
      or
      (
        external_key is not null
        and source_url = 'https://www.mp3quran.net/api/v3/radios?language=ar'
        and health_status = 'HEALTHY'
        and private.radio_provider_allowed(provider_id, true)
      )
    )
  );

create policy "Authenticated read stations"
  on app.stations
  for select
  to authenticated
  using (
    (
      is_active = true
      and is_playable = true
      and deleted_at is null
      and (
        (
          rights_status = 'APPROVED'
          and commercial_use_status = 'ALLOWED'
          and private.radio_provider_allowed(provider_id, false)
        )
        or
        (
          external_key is not null
          and source_url = 'https://www.mp3quran.net/api/v3/radios?language=ar'
          and health_status = 'HEALTHY'
          and private.radio_provider_allowed(provider_id, true)
        )
      )
    )
    or app.has_permission('stations.read')
    or app.has_permission('stations.write')
  );

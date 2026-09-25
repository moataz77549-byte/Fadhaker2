-- Check only provider eligibility without granting public table-wide SELECT.
create schema if not exists private;
create or replace function private.radio_provider_allowed(
  p_provider_id uuid, p_api_radio_only boolean
)
returns boolean language sql stable security definer
set search_path = ''
as $function$
  select exists (
    select cp.id from app.content_providers cp
    where cp.id = p_provider_id
      and cp.is_active = true and cp.deleted_at is null
      and (
        (p_api_radio_only = true and cp.slug = 'mp3quran'
         and cp.api_stream_links_enabled = true)
        or
        (p_api_radio_only = false and cp.production_enabled = true
         and cp.rights_status = 'APPROVED'
         and cp.commercial_use_status = 'ALLOWED')
      )
  );
$function$;
revoke all on function private.radio_provider_allowed(uuid, boolean) from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.radio_provider_allowed(uuid, boolean)
  to anon, authenticated;

drop policy if exists "Public read approved stations" on app.stations;
create policy "Public read approved stations"
  on app.stations for select to anon, authenticated
  using (
    is_active = true and is_playable = true and deleted_at is null
    and (
      (
        rights_status = 'APPROVED' and commercial_use_status = 'ALLOWED'
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

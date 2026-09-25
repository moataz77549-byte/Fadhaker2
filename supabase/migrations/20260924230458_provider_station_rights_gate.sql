-- Public radio availability follows provider and station rights.
-- Existing MP3Quran rows remain intact for review and future approval.
-- Only these provider columns are exposed for RLS evaluation.
grant select (id, is_active, production_enabled, rights_status,
              commercial_use_status, deleted_at)
  on app.content_providers to anon, authenticated;

drop policy if exists "Public read approved content providers"
  on app.content_providers;
create policy "Public read approved content providers"
  on app.content_providers for select to anon, authenticated
  using (
    is_active = true
    and production_enabled = true
    and rights_status = 'APPROVED'
    and commercial_use_status = 'ALLOWED'
    and deleted_at is null
  );

drop policy if exists "Public read active stations" on app.stations;
drop policy if exists "Public read approved stations" on app.stations;
create policy "Public read approved stations"
  on app.stations for select to anon, authenticated
  using (
    is_active = true
    and is_playable = true
    and deleted_at is null
    and rights_status = 'APPROVED'
    and commercial_use_status = 'ALLOWED'
    and exists (
      select 1 from app.content_providers cp
      where cp.id = provider_id
        and cp.is_active = true
        and cp.production_enabled = true
        and cp.rights_status = 'APPROVED'
        and cp.commercial_use_status = 'ALLOWED'
        and cp.deleted_at is null
    )
  );

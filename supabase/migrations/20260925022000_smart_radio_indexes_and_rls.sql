-- Performance + RLS cleanup for Smart Fadhkur Radio.
-- Cover every new foreign key and avoid overlapping permissive SELECT policies.

create index if not exists virtual_radio_sources_reciter_track_idx
  on app.virtual_radio_sources(reciter_track_id)
  where reciter_track_id is not null;

create index if not exists virtual_radio_sources_playlist_idx
  on app.virtual_radio_sources(playlist_id)
  where playlist_id is not null;

create index if not exists virtual_radio_sources_media_idx
  on app.virtual_radio_sources(media_id)
  where media_id is not null;

create index if not exists virtual_radio_overrides_source_idx
  on app.virtual_radio_overrides(source_id)
  where source_id is not null;

create index if not exists virtual_radio_overrides_created_by_idx
  on app.virtual_radio_overrides(created_by)
  where created_by is not null;

drop policy if exists smart_radio_sources_admin_write on app.virtual_radio_sources;

create policy smart_radio_sources_admin_insert
  on app.virtual_radio_sources
  for insert
  to authenticated
  with check (app.has_permission('smart_radio.write'));

create policy smart_radio_sources_admin_update
  on app.virtual_radio_sources
  for update
  to authenticated
  using (app.has_permission('smart_radio.write'))
  with check (app.has_permission('smart_radio.write'));

create policy smart_radio_sources_admin_delete
  on app.virtual_radio_sources
  for delete
  to authenticated
  using (app.has_permission('smart_radio.write'));

drop policy if exists smart_radio_rules_admin_write on app.virtual_radio_rules;

create policy smart_radio_rules_admin_insert
  on app.virtual_radio_rules
  for insert
  to authenticated
  with check (app.has_permission('smart_radio.write'));

create policy smart_radio_rules_admin_update
  on app.virtual_radio_rules
  for update
  to authenticated
  using (app.has_permission('smart_radio.write'))
  with check (app.has_permission('smart_radio.write'));

create policy smart_radio_rules_admin_delete
  on app.virtual_radio_rules
  for delete
  to authenticated
  using (app.has_permission('smart_radio.write'));

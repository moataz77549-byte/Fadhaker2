-- Phase 1 security hardening
-- Consolidate overlapping permissive admin SELECT policies while preserving access semantics.
-- Read access remains: read_permission OR write_permission.
-- Write access is split into explicit INSERT / UPDATE / DELETE policies.

do $$
declare
  item record;
begin
  for item in
    select * from (values
      ('app_config','settings.read','settings.write'),
      ('categories','categories.read','categories.write'),
      ('identity_settings','settings.read','settings.write'),
      ('media','media.read','media.write'),
      ('media_processing_jobs','media.read','media.write'),
      ('notification_campaigns','notifications.read','notifications.write'),
      ('reciter_tracks','reciters.read','reciters.write'),
      ('reciters','reciters.read','reciters.write'),
      ('stations','stations.read','stations.write'),
      ('video_channels','media.read','media.write')
    ) as v(table_name, read_perm, write_perm)
  loop
    execute format('drop policy if exists %I on app.%I', 'admin_read_' || item.table_name, item.table_name);
    execute format('drop policy if exists %I on app.%I', 'admin_write_' || item.table_name, item.table_name);

    execute format(
      'create policy %I on app.%I for select to authenticated using (app.has_permission(%L) or app.has_permission(%L))',
      'admin_read_' || item.table_name, item.table_name, item.read_perm, item.write_perm
    );
    execute format(
      'create policy %I on app.%I for insert to authenticated with check (app.has_permission(%L))',
      'admin_insert_' || item.table_name, item.table_name, item.write_perm
    );
    execute format(
      'create policy %I on app.%I for update to authenticated using (app.has_permission(%L)) with check (app.has_permission(%L))',
      'admin_update_' || item.table_name, item.table_name, item.write_perm, item.write_perm
    );
    execute format(
      'create policy %I on app.%I for delete to authenticated using (app.has_permission(%L))',
      'admin_delete_' || item.table_name, item.table_name, item.write_perm
    );
  end loop;
end $$;

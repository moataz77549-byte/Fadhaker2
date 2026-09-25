-- Keep optional extension objects outside public.
create schema if not exists extensions;
alter extension pg_trgm set schema extensions;

-- Purposeful FK/query-path indexes for growing or frequently queried relations.
create index administrator_roles_role_idx on app.administrator_roles (role_id, administrator_id);
create index role_permissions_permission_idx on app.role_permissions (permission_id, role_id);
create index categories_parent_idx on app.categories (parent_id) where parent_id is not null;
create index media_category_time_idx on app.media (category_id, created_at desc) where deleted_at is null;
create index media_reciter_time_idx on app.media (reciter_id, created_at desc) where reciter_id is not null and deleted_at is null;
create index media_processing_jobs_media_idx on app.media_processing_jobs (media_id, created_at desc);
create index playlist_items_media_idx on app.playlist_items (media_id, playlist_id);
create index program_items_media_idx on app.program_items (media_id, program_id);
create index reciter_tracks_media_idx on app.reciter_tracks (media_id) where media_id is not null;
create index reciter_tracks_surah_active_idx on app.reciter_tracks (surah_id, reciter_id) where is_active;
create index schedules_station_next_idx on app.schedules (station_id, next_run_at, priority) where enabled and deleted_at is null;
create index schedules_media_idx on app.schedules (media_id) where media_id is not null and deleted_at is null;
create index schedules_playlist_idx on app.schedules (station_id, playlist_id) where playlist_id is not null and deleted_at is null;
create index schedules_program_idx on app.schedules (station_id, program_id) where program_id is not null and deleted_at is null;
create index stream_health_jobs_station_time_idx on app.stream_health_jobs (station_id, scheduled_at desc);
create index system_logs_station_time_idx on app.system_logs (station_id, timestamp desc) where station_id is not null;
create index radio_events_command_idx on radio.radio_events (command_id) where command_id is not null;
create index radio_events_occurrence_idx on radio.radio_events (occurrence_id) where occurrence_id is not null;
create index play_history_command_idx on radio.play_history (command_id) where command_id is not null;
create index play_history_occurrence_idx on radio.play_history (occurrence_id) where occurrence_id is not null;

-- Initial approved database baseline for Tarteel.
-- Generated without the Supabase CLI because the CLI is unavailable in this workspace.
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

create schema if not exists app;
create schema if not exists radio;
create schema if not exists api;

create type app.media_status as enum ('UPLOADING','PROCESSING','READY','FAILED','ARCHIVED');
create type app.station_status as enum ('ONLINE','DEGRADED','OFFLINE','MAINTENANCE');
create type app.schedule_type as enum ('ONE_TIME','DAILY','WEEKLY');
create type app.content_type as enum ('MEDIA','PLAYLIST','PROGRAM');
create type app.interrupt_policy as enum ('FINISH_CURRENT','INTERRUPT','PLAY_NEXT');
create type app.priority_level as enum ('LOW','NORMAL','HIGH','EMERGENCY','LIVE');
create type app.station_source as enum ('INTERNAL','EXTERNAL');
create type app.stream_health_status as enum ('HEALTHY','DEGRADED','UNREACHABLE','INVALID','UNKNOWN');
create type app.rights_status as enum ('UNKNOWN','REVIEW_REQUIRED','APPROVED','RESTRICTED','DISABLED');
create type app.commercial_use_status as enum ('UNKNOWN','REVIEW_REQUIRED','ALLOWED','NOT_ALLOWED');
create type radio.command_type as enum ('PLAY_NOW','PLAY_NEXT','SKIP','STOP_AFTER_CURRENT','RESUME_AUTO','START_LIVE','STOP_LIVE');
create type radio.command_status as enum ('PENDING','PROCESSING','COMPLETED','FAILED','CANCELLED');
create type radio.engine_mode as enum ('STARTING','AUTO','SCHEDULED','MANUAL','LIVE','RECOVERING','ERROR','STOPPED');
create type radio.occurrence_status as enum ('PENDING','CLAIMED','PLAYING','COMPLETED','SKIPPED','FAILED','CANCELLED');

create function app.set_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;
revoke all on function app.set_updated_at() from public, anon, authenticated;

create table app.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z_]+$'),
  name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table app.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z]+([.:_-][a-z]+)*$'),
  description text not null,
  created_at timestamptz not null default now()
);
create table app.role_permissions (
  role_id uuid not null references app.roles(id) on delete cascade,
  permission_id uuid not null references app.permissions(id) on delete cascade,
  created_at timestamptz not null default now(), primary key (role_id, permission_id)
);
create table app.administrators (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null, is_active boolean not null default true,
  last_login_at timestamptz, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table app.administrator_roles (
  administrator_id uuid not null references app.administrators(id) on delete cascade,
  role_id uuid not null references app.roles(id) on delete restrict,
  granted_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), primary key (administrator_id, role_id)
);

create table app.categories (
  id uuid primary key default gen_random_uuid(), parent_id uuid references app.categories(id) on delete restrict,
  slug text not null unique, name_ar text not null, name_en text, description text, icon_key text,
  is_active boolean not null default true, sort_order integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table app.reciters (
  id uuid primary key default gen_random_uuid(), name_ar text not null, name_en text,
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  image_url text, country text, rewaya text, description text,
  search_name_ar text, search_name_en text, is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table app.surahs (
  id smallint primary key, number smallint not null unique check (number between 1 and 114),
  name_ar text not null, name_en text not null, ayah_count smallint not null check (ayah_count > 0),
  created_at timestamptz not null default now(), check (id = number)
);
create table app.media (
  id uuid primary key default gen_random_uuid(), title text not null, description text,
  category_id uuid references app.categories(id) on delete restrict,
  reciter_id uuid references app.reciters(id) on delete set null,
  original_path text not null unique, processed_path text unique,
  duration_ms bigint check (duration_ms > 0), format text, bitrate_kbps integer check (bitrate_kbps > 0),
  sample_rate_hz integer check (sample_rate_hz > 0), channels smallint check (channels between 1 and 8),
  file_size_bytes bigint not null check (file_size_bytes > 0), sha256 text check (sha256 ~ '^[0-9a-f]{64}$'),
  status app.media_status not null default 'UPLOADING', processing_profile_version text,
  metadata jsonb not null default '{}'::jsonb, failure_code text, failure_message text,
  created_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  check ((status <> 'READY') or (processed_path is not null and duration_ms is not null and sha256 is not null))
);
create table app.media_processing_jobs (
  id uuid primary key default gen_random_uuid(), media_id uuid not null references app.media(id) on delete cascade,
  idempotency_key text not null unique, status app.media_status not null,
  attempts smallint not null default 0 check (attempts >= 0), profile_version text not null,
  claimed_by text, claimed_at timestamptz, heartbeat_at timestamptz,
  error_code text, error_message text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table app.reciter_tracks (
  id uuid primary key default gen_random_uuid(), reciter_id uuid not null references app.reciters(id) on delete restrict,
  surah_id smallint not null references app.surahs(id) on delete restrict,
  provider_id uuid,
  media_id uuid references app.media(id) on delete restrict, audio_url text,
  duration_ms bigint check (duration_ms > 0), quality text not null, rewaya text not null default 'UNKNOWN',
  format text, bitrate_kbps integer check (bitrate_kbps is null or bitrate_kbps > 0),
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((media_id is not null) <> (audio_url is not null))
);

create table app.content_provider_types (
  code text primary key check (code ~ '^[A-Z][A-Z0-9_]*$'),
  description text not null, created_at timestamptz not null default now()
);
create table app.stream_types (
  code text primary key check (code ~ '^[A-Z][A-Z0-9_]*$'),
  description text not null, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table app.content_providers (
  id uuid primary key default gen_random_uuid(),
  name text not null, slug text not null unique,
  provider_type text not null references app.content_provider_types(code) on delete restrict,
  website_url text, api_base_url text, is_active boolean not null default true,
  production_enabled boolean not null default false,
  priority integer not null default 100 check (priority >= 0),
  health_status app.stream_health_status not null default 'UNKNOWN',
  last_checked_at timestamptz, last_success_at timestamptz,
  rights_status app.rights_status not null default 'REVIEW_REQUIRED',
  commercial_use_status app.commercial_use_status not null default 'UNKNOWN',
  attribution_required boolean not null default false, attribution_text text,
  terms_url text, source_url text, verified_at timestamptz, internal_notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  check (not production_enabled or (rights_status = 'APPROVED' and commercial_use_status = 'ALLOWED'))
);

alter table app.reciter_tracks add constraint reciter_tracks_provider_fk
  foreign key (provider_id) references app.content_providers(id) on delete restrict;
create unique index reciter_tracks_internal_identity_idx
  on app.reciter_tracks (reciter_id, surah_id, rewaya, quality)
  where provider_id is null;
create unique index reciter_tracks_provider_identity_idx
  on app.reciter_tracks (provider_id, reciter_id, surah_id, rewaya, quality)
  where provider_id is not null;

create table app.stations (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  name_ar text not null, name_en text, search_name_ar text, search_name_en text,
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'), description text, logo_url text,
  category_id uuid references app.categories(id) on delete restrict,
  station_source app.station_source not null,
  stream_type text not null references app.stream_types(code) on delete restrict,
  stream_url text not null, fallback_stream_url text, timezone text,
  status app.station_status not null default 'OFFLINE', default_playlist_id uuid,
  is_active boolean not null default true, is_featured boolean not null default false,
  production_enabled boolean not null default false,
  health_status app.stream_health_status not null default 'UNKNOWN',
  last_health_check timestamptz, last_success_at timestamptz,
  consecutive_failures integer not null default 0 check (consecutive_failures >= 0),
  sort_order integer not null default 0,
  external_key text, last_seen_at timestamptz, source_url text,
  rights_status app.rights_status not null default 'REVIEW_REQUIRED',
  commercial_use_status app.commercial_use_status not null default 'UNKNOWN',
  attribution_required boolean not null default false, attribution_text text,
  terms_url text, rights_verified_at timestamptz, internal_notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (provider_id, external_key),
  check (station_source = 'EXTERNAL' or timezone is not null),
  check (station_source = 'INTERNAL' or default_playlist_id is null),
  check (not production_enabled or (rights_status = 'APPROVED' and commercial_use_status = 'ALLOWED'))
);
create table app.playlists (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  name text not null, description text, shuffle boolean not null default false, repeat boolean not null default true,
  is_active boolean not null default true, version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (station_id, name), unique (station_id, id)
);
alter table app.stations add constraint stations_default_playlist_fk
  foreign key (id, default_playlist_id) references app.playlists(station_id, id);
create table app.stream_health_checks (
  id bigint generated always as identity primary key,
  station_id uuid not null references app.stations(id) on delete cascade,
  checked_at timestamptz not null default now(),
  status app.stream_health_status not null,
  http_status integer check (http_status is null or http_status between 100 and 599),
  response_time_ms integer check (response_time_ms is null or response_time_ms >= 0),
  content_type text, detected_stream_type text references app.stream_types(code) on delete restrict,
  audio_detected boolean, bytes_sampled bigint check (bytes_sampled is null or bytes_sampled >= 0),
  error_code text, error_message text, metadata jsonb not null default '{}'::jsonb
);
create table app.stream_health_jobs (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references app.stations(id) on delete cascade,
  idempotency_key text not null unique,
  status text not null check (status in ('PENDING','PROCESSING','COMPLETED','FAILED','CANCELLED')),
  priority integer not null default 100 check (priority >= 0),
  scheduled_at timestamptz not null default now(), attempts smallint not null default 0 check (attempts >= 0),
  claimed_by text, claimed_at timestamptz, heartbeat_at timestamptz,
  requested_by uuid references app.administrators(id) on delete set null,
  error_code text, error_message text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table app.provider_sync_runs (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  idempotency_key text not null unique,
  status text not null check (status in ('PENDING','RUNNING','COMPLETED','PARTIAL','FAILED','CANCELLED')),
  claimed_by text, claimed_at timestamptz, heartbeat_at timestamptz,
  started_at timestamptz, finished_at timestamptz,
  fetched_count integer not null default 0, inserted_count integer not null default 0,
  updated_count integer not null default 0, unchanged_count integer not null default 0,
  missing_count integer not null default 0, invalid_count integer not null default 0,
  cursor_data jsonb not null default '{}'::jsonb,
  error_code text, error_message text, metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table app.provider_station_records (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  station_id uuid not null references app.stations(id) on delete restrict,
  external_key text not null, discovered_name text, discovered_stream_url text,
  normalized_hash text, last_seen_at timestamptz not null,
  missing_since timestamptz, raw_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (provider_id, external_key)
);
create table app.playlist_items (
  id uuid primary key default gen_random_uuid(), playlist_id uuid not null references app.playlists(id) on delete cascade,
  media_id uuid not null references app.media(id) on delete restrict,
  position integer not null check (position >= 0), weight integer not null default 1 check (weight > 0),
  created_at timestamptz not null default now(), unique (playlist_id, position)
);
create table app.programs (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  name text not null, description text, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (station_id, id)
);
create table app.program_items (
  id uuid primary key default gen_random_uuid(), program_id uuid not null references app.programs(id) on delete cascade,
  media_id uuid not null references app.media(id) on delete restrict, position integer not null check (position >= 0),
  created_at timestamptz not null default now(), unique (program_id, position)
);

create table app.schedules (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  name text not null, content_type app.content_type not null,
  media_id uuid references app.media(id) on delete restrict, playlist_id uuid,
  program_id uuid, schedule_type app.schedule_type not null,
  start_date date not null, end_date date, start_time time not null, days_of_week smallint[], timezone text not null,
  priority app.priority_level not null default 'NORMAL', interrupt_policy app.interrupt_policy not null default 'FINISH_CURRENT',
  enabled boolean not null default true, next_run_at timestamptz, version integer not null default 1 check (version > 0),
  created_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  check (end_date is null or end_date >= start_date),
  check (days_of_week is null or days_of_week <@ array[0,1,2,3,4,5,6]::smallint[]),
  check ((content_type='MEDIA' and media_id is not null and playlist_id is null and program_id is null)
      or (content_type='PLAYLIST' and playlist_id is not null and media_id is null and program_id is null)
      or (content_type='PROGRAM' and program_id is not null and media_id is null and playlist_id is null)),
  check ((schedule_type='ONE_TIME' and end_date is null and days_of_week is null)
      or (schedule_type='DAILY' and days_of_week is null)
      or (schedule_type='WEEKLY' and days_of_week is not null and cardinality(days_of_week) > 0)),
  foreign key (station_id, playlist_id) references app.playlists(station_id, id) on delete restrict,
  foreign key (station_id, program_id) references app.programs(station_id, id) on delete restrict
);
create table app.schedule_templates (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  code text not null, name text not null, active_from date, active_to date, is_active boolean not null default false,
  version integer not null default 1, created_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (station_id, code, version), check (active_to is null or active_from is null or active_to >= active_from)
);
create table app.schedule_template_items (
  id uuid primary key default gen_random_uuid(), template_id uuid not null references app.schedule_templates(id) on delete cascade,
  definition jsonb not null, position integer not null check (position >= 0), created_at timestamptz not null default now(),
  unique (template_id, position)
);

create table radio.schedule_occurrences (
  id uuid primary key default gen_random_uuid(), schedule_id uuid not null references app.schedules(id) on delete restrict,
  station_id uuid not null references app.stations(id) on delete restrict, occurrence_key text not null,
  scheduled_for timestamptz not null, local_date date not null, local_time time not null, timezone text not null, fold smallint not null default 0,
  priority app.priority_level not null, interrupt_policy app.interrupt_policy not null,
  status radio.occurrence_status not null default 'PENDING', claimed_by text, claimed_at timestamptz,
  started_at timestamptz, finished_at timestamptz, result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (schedule_id, occurrence_key)
);
create table radio.radio_commands (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  command_type radio.command_type not null, payload jsonb not null default '{}'::jsonb,
  priority app.priority_level not null default 'NORMAL', status radio.command_status not null default 'PENDING',
  idempotency_key text not null, created_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), claimed_by text, claimed_at timestamptz,
  executed_at timestamptz, error_code text, error_message text, updated_at timestamptz not null default now(),
  unique (station_id, idempotency_key)
);
create table radio.station_leases (
  station_id uuid primary key references app.stations(id) on delete cascade,
  owner_id text not null, fencing_token bigint not null check (fencing_token > 0),
  acquired_at timestamptz not null, renewed_at timestamptz not null, expires_at timestamptz not null,
  check (expires_at > renewed_at)
);
create table radio.engine_states (
  station_id uuid primary key references app.stations(id) on delete cascade,
  mode radio.engine_mode not null, previous_valid_mode radio.engine_mode,
  fencing_token bigint not null, revision bigint not null default 1,
  current_source_type text, current_source_id uuid, current_queue_item_id uuid,
  position_ms bigint check (position_ms is null or position_ms >= 0),
  state_data jsonb not null default '{}'::jsonb, last_checkpoint_at timestamptz not null,
  updated_at timestamptz not null default now()
);
create table radio.queue_snapshots (
  station_id uuid primary key references app.stations(id) on delete cascade,
  revision bigint not null, fencing_token bigint not null, snapshot jsonb not null,
  checksum text not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table radio.now_playing (
  station_id uuid primary key references app.stations(id) on delete cascade,
  mode radio.engine_mode not null, status app.station_status not null,
  media_id uuid references app.media(id) on delete set null, title text, artist text,
  started_at timestamptz, expected_end_at timestamptz, duration_ms bigint,
  next_media_id uuid references app.media(id) on delete set null, next_title text,
  revision bigint not null, updated_at timestamptz not null default now()
);
create table radio.radio_events (
  id bigint generated always as identity primary key, station_id uuid not null references app.stations(id) on delete restrict,
  event_type text not null, command_id uuid references radio.radio_commands(id) on delete set null,
  occurrence_id uuid references radio.schedule_occurrences(id) on delete set null,
  media_id uuid references app.media(id) on delete set null, fencing_token bigint,
  data jsonb not null default '{}'::jsonb, occurred_at timestamptz not null default now()
);
create table radio.play_history (
  id bigint generated always as identity primary key, station_id uuid not null references app.stations(id) on delete restrict,
  media_id uuid references app.media(id) on delete set null, source_type text not null, source_id uuid,
  started_at timestamptz not null, ended_at timestamptz, result text, played_ms bigint,
  command_id uuid references radio.radio_commands(id) on delete set null,
  occurrence_id uuid references radio.schedule_occurrences(id) on delete set null,
  created_at timestamptz not null default now()
);

create table app.app_config (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'), value jsonb not null,
  value_type text not null check (value_type in ('BOOLEAN','INTEGER','STRING','URL','UUID','JSON')),
  is_public boolean not null default false,
  description text, updated_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((value_type = 'BOOLEAN' and jsonb_typeof(value) = 'boolean')
      or (value_type = 'INTEGER' and jsonb_typeof(value) = 'number')
      or (value_type in ('STRING','URL','UUID') and jsonb_typeof(value) = 'string')
      or (value_type = 'JSON'))
);
create table app.audit_logs (
  id bigint generated always as identity primary key, actor_id uuid references app.administrators(id) on delete set null,
  action text not null, resource_type text not null, resource_id text,
  request_id uuid, ip_hash text, old_values jsonb, new_values jsonb,
  metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table app.system_logs (
  id bigint generated always as identity primary key, timestamp timestamptz not null default now(),
  service text not null, level text not null check (level in ('DEBUG','INFO','WARN','ERROR','FATAL')),
  station_id uuid references app.stations(id) on delete set null, event text not null,
  request_id uuid, command_id uuid, media_id uuid, message text not null, error jsonb, fields jsonb not null default '{}'::jsonb
);
create table app.service_heartbeats (
  service_instance_id text primary key, service text not null, station_id uuid references app.stations(id) on delete cascade,
  status text not null, version text not null, details jsonb not null default '{}'::jsonb,
  started_at timestamptz not null, last_seen_at timestamptz not null
);
create table app.station_metrics_minute (
  station_id uuid not null references app.stations(id) on delete cascade, bucket_at timestamptz not null,
  current_listeners integer not null default 0, peak_listeners integer not null default 0,
  stream_errors integer not null default 0, buffering_reports integer not null default 0,
  primary key (station_id, bucket_at)
);

create index media_filter_idx on app.media (status, category_id, reciter_id, created_at desc) where deleted_at is null;
create index reciters_search_ar_idx on app.reciters using gin (search_name_ar gin_trgm_ops) where deleted_at is null;
create index reciters_search_en_idx on app.reciters using gin (search_name_en gin_trgm_ops) where deleted_at is null;
create index surahs_name_ar_idx on app.surahs using gin (name_ar gin_trgm_ops);
create index surahs_name_en_idx on app.surahs using gin (name_en gin_trgm_ops);
create index reciter_tracks_catalog_idx on app.reciter_tracks (reciter_id, surah_id, is_active);
create index stations_catalog_idx on app.stations (is_active, production_enabled, health_status, category_id, sort_order) where deleted_at is null;
create index stations_search_ar_idx on app.stations using gin (search_name_ar gin_trgm_ops) where deleted_at is null;
create index stations_search_en_idx on app.stations using gin (search_name_en gin_trgm_ops) where deleted_at is null;
create index stations_provider_seen_idx on app.stations (provider_id, last_seen_at desc) where station_source='EXTERNAL' and deleted_at is null;
create index stream_health_station_time_idx on app.stream_health_checks (station_id, checked_at desc);
create index stream_health_jobs_pending_idx on app.stream_health_jobs (scheduled_at, priority desc, id) where status='PENDING';
create index provider_sync_provider_time_idx on app.provider_sync_runs (provider_id, created_at desc);
create index provider_station_records_station_idx on app.provider_station_records (station_id, provider_id);
create index playlist_items_order_idx on app.playlist_items (playlist_id, position);
create index schedules_due_idx on app.schedules (next_run_at, priority) where enabled and deleted_at is null;
create index occurrences_due_idx on radio.schedule_occurrences (station_id, scheduled_for, priority) where status='PENDING';
create index commands_pending_idx on radio.radio_commands (station_id, priority desc, created_at, id) where status='PENDING';
create index events_station_time_idx on radio.radio_events (station_id, occurred_at desc);
create index play_history_station_time_idx on radio.play_history (station_id, started_at desc);
create index audit_resource_idx on app.audit_logs (resource_type, resource_id, created_at desc);
create index audit_actor_time_idx on app.audit_logs (actor_id, created_at desc);
create index logs_service_time_idx on app.system_logs (service, timestamp desc);

do $$ declare r record; begin
  for r in
    select table_schema, table_name from information_schema.columns
    where column_name = 'updated_at' and table_schema in ('app','radio')
  loop
    execute format('create trigger set_updated_at before update on %I.%I for each row execute function app.set_updated_at()',
      r.table_schema, r.table_name);
  end loop;
end $$;

create function app.require_valid_timezone() returns trigger language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'invalid IANA timezone: %', new.timezone;
  end if;
  return new;
end $$;
revoke all on function app.require_valid_timezone() from public, anon, authenticated;

create trigger stations_valid_timezone before insert or update of timezone on app.stations
for each row when (new.timezone is not null) execute function app.require_valid_timezone();
create trigger schedules_valid_timezone before insert or update of timezone on app.schedules
for each row execute function app.require_valid_timezone();

create function app.require_internal_station() returns trigger language plpgsql set search_path = '' as $$
declare source app.station_source;
begin
  select s.station_source into source from app.stations s where s.id = new.station_id;
  if source is distinct from 'INTERNAL'::app.station_source then
    raise exception 'station must be INTERNAL for automation resources';
  end if;
  return new;
end $$;
revoke all on function app.require_internal_station() from public, anon, authenticated;

create trigger playlists_internal_station before insert or update of station_id on app.playlists
for each row execute function app.require_internal_station();
create trigger programs_internal_station before insert or update of station_id on app.programs
for each row execute function app.require_internal_station();
create trigger schedules_internal_station before insert or update of station_id on app.schedules
for each row execute function app.require_internal_station();
create trigger commands_internal_station before insert or update of station_id on radio.radio_commands
for each row execute function app.require_internal_station();

create function app.enforce_station_production_rights() returns trigger language plpgsql set search_path = '' as $$
declare p_active boolean; p_production boolean; p_rights app.rights_status; p_commercial app.commercial_use_status;
begin
  if new.production_enabled then
    select p.is_active, p.production_enabled, p.rights_status, p.commercial_use_status
      into p_active, p_production, p_rights, p_commercial
      from app.content_providers p where p.id = new.provider_id and p.deleted_at is null;
    if p_active is distinct from true
       or p_production is distinct from true
       or p_rights is distinct from 'APPROVED'::app.rights_status
       or p_commercial is distinct from 'ALLOWED'::app.commercial_use_status then
      raise exception 'provider rights do not permit production publication';
    end if;
  end if;
  return new;
end $$;
revoke all on function app.enforce_station_production_rights() from public, anon, authenticated;
create trigger stations_production_rights before insert or update of
  provider_id, production_enabled, rights_status, commercial_use_status on app.stations
for each row execute function app.enforce_station_production_rights();

create function app.disable_stations_for_unapproved_provider() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.is_active is distinct from true
     or new.production_enabled is distinct from true
     or new.rights_status is distinct from 'APPROVED'::app.rights_status
     or new.commercial_use_status is distinct from 'ALLOWED'::app.commercial_use_status then
    update app.stations set production_enabled = false
      where provider_id = new.id and production_enabled = true;
  end if;
  return new;
end $$;
revoke all on function app.disable_stations_for_unapproved_provider() from public, anon, authenticated;
create trigger providers_disable_unapproved_stations after update of
  is_active, production_enabled, rights_status, commercial_use_status on app.content_providers
for each row execute function app.disable_stations_for_unapproved_provider();

create function app.prevent_invalid_station_source_change() returns trigger language plpgsql set search_path = '' as $$
begin
  if old.station_source is distinct from new.station_source then
    raise exception 'station_source is immutable; create a new station record instead';
  end if;
  return new;
end $$;
revoke all on function app.prevent_invalid_station_source_change() from public, anon, authenticated;
create trigger stations_source_boundary before update of station_source on app.stations
for each row execute function app.prevent_invalid_station_source_change();

do $$ declare r record; begin
  for r in select schemaname, tablename from pg_tables where schemaname in ('app','radio') loop
    execute format('alter table %I.%I enable row level security', r.schemaname, r.tablename);
  end loop;
end $$;

revoke all on schema app, radio, api from public, anon, authenticated;
revoke all on all tables in schema app, radio from public, anon, authenticated;
revoke all on all sequences in schema app, radio from public, anon, authenticated;
revoke all on all functions in schema app, radio from public, anon, authenticated;
alter default privileges in schema app revoke all on tables from public, anon, authenticated;
alter default privileges in schema radio revoke all on tables from public, anon, authenticated;
alter default privileges in schema app revoke all on sequences from public, anon, authenticated;
alter default privileges in schema radio revoke all on sequences from public, anon, authenticated;
alter default privileges in schema app revoke all on functions from public, anon, authenticated;
alter default privileges in schema radio revoke all on functions from public, anon, authenticated;

-- Intentionally no anon/authenticated grants here. API projections and exact
-- policies are separate reviewed migrations after approval.

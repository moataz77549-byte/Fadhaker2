-- Phase 6: persistent deterministic automation state.
create type radio.queue_source as enum ('AUTO','SCHEDULED','MANUAL','FALLBACK','EMERGENCY','LIVE');
create type radio.queue_status as enum ('PENDING','DISPATCHED','PLAYING','COMPLETED','FAILED','CANCELLED');

alter table radio.schedule_occurrences
  add column schedule_version integer not null default 1 check (schedule_version > 0),
  add column content_type app.content_type,
  add column media_id uuid references app.media(id) on delete restrict,
  add column playlist_id uuid references app.playlists(id) on delete restrict,
  add column expires_at timestamptz,
  add column claimed_fencing_token bigint,
  add column failure_code text,
  add column failure_message text,
  add constraint occurrence_content_check check (
    (content_type is null and media_id is null and playlist_id is null)
    or (content_type='MEDIA' and media_id is not null and playlist_id is null)
    or (content_type='PLAYLIST' and playlist_id is not null and media_id is null)
  ),
  add constraint occurrence_expiry_check check (expires_at is null or expires_at >= scheduled_for);

alter table radio.radio_commands
  add column processing_fencing_token bigint,
  add column effect_key text,
  add column result jsonb not null default '{}'::jsonb,
  add constraint command_effect_key_unique unique(station_id,effect_key);

create table radio.queue_entries (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references app.stations(id) on delete restrict,
  source radio.queue_source not null,
  priority app.priority_level not null,
  interrupt_policy app.interrupt_policy not null default 'FINISH_CURRENT',
  media_id uuid not null references app.media(id) on delete restrict,
  playlist_id uuid references app.playlists(id) on delete restrict,
  playlist_item_id uuid references app.playlist_items(id) on delete restrict,
  occurrence_id uuid references radio.schedule_occurrences(id) on delete restrict,
  command_id uuid references radio.radio_commands(id) on delete restrict,
  idempotency_key text not null,
  status radio.queue_status not null default 'PENDING',
  intended_at timestamptz not null default now(),
  available_at timestamptz not null default now(),
  sequence bigint not null default 0 check (sequence >= 0),
  claimed_by text,
  claimed_at timestamptz,
  claimed_fencing_token bigint,
  dispatched_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  failure_code text,
  failure_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(station_id,idempotency_key),
  check (finished_at is null or started_at is null or finished_at >= started_at)
);

alter table radio.now_playing
  add column queue_entry_id uuid references radio.queue_entries(id) on delete set null,
  add column command_id uuid references radio.radio_commands(id) on delete set null,
  add column occurrence_id uuid references radio.schedule_occurrences(id) on delete set null,
  add column playlist_id uuid references app.playlists(id) on delete set null;

alter table radio.play_history
  add column queue_entry_id uuid references radio.queue_entries(id) on delete set null,
  add column playlist_id uuid references app.playlists(id) on delete set null,
  add column playout_id uuid not null default gen_random_uuid(),
  add column completed_naturally boolean,
  add column interrupted boolean not null default false,
  add column interruption_reason text,
  add column fencing_token bigint,
  add constraint play_history_playout_unique unique(playout_id),
  add constraint play_history_interruption_check check (
    (not interrupted and interruption_reason is null)
    or (interrupted and interruption_reason is not null)
  );

create index occurrences_claim_idx on radio.schedule_occurrences
  (station_id,status,scheduled_for,priority,created_at,id);
create index occurrences_schedule_time_idx on radio.schedule_occurrences(schedule_id,scheduled_for);
create index commands_claim_v2_idx on radio.radio_commands
  (station_id,status,priority,created_at,id);
create index queue_entries_boundary_idx on radio.queue_entries
  (station_id,status,priority,intended_at,created_at,id)
  where status in ('PENDING','DISPATCHED');
create index queue_entries_command_idx on radio.queue_entries(command_id) where command_id is not null;
create index queue_entries_occurrence_idx on radio.queue_entries(occurrence_id) where occurrence_id is not null;
create index play_history_queue_idx on radio.play_history(queue_entry_id) where queue_entry_id is not null;
create index now_playing_command_idx on radio.now_playing(command_id) where command_id is not null;
create index now_playing_occurrence_idx on radio.now_playing(occurrence_id) where occurrence_id is not null;

create trigger set_updated_at before update on radio.queue_entries
for each row execute function app.set_updated_at();

alter table radio.queue_entries enable row level security;
revoke all on table radio.queue_entries from public,anon,authenticated;
grant select,insert,update,delete on radio.queue_entries to service_role;


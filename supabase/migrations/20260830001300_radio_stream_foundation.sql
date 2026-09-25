-- Phase 5: atomic station ownership, fenced runtime checkpoints and stream projection.
alter table radio.engine_states
  add column source_connected boolean not null default false,
  add column stream_mount text,
  add column source_started_at timestamptz,
  add column last_error text,
  add column last_recovery_at timestamptz,
  add constraint engine_states_mount_check
    check (stream_mount is null or stream_mount ~ '^/[a-z0-9][a-z0-9._-]*$');

alter table radio.now_playing
  add column source_type text,
  add column processing_profile text,
  add column stream_mount text,
  add column fencing_token bigint,
  add constraint now_playing_mount_check
    check (stream_mount is null or stream_mount ~ '^/[a-z0-9][a-z0-9._-]*$');

create index station_leases_expiry_idx on radio.station_leases (expires_at);
create index service_heartbeats_radio_station_idx
  on app.service_heartbeats (station_id,last_seen_at desc)
  where service='radio-engine';

create function radio.acquire_station_lease(
  p_station_id uuid,
  p_owner_id text,
  p_ttl_seconds integer default 15
) returns table(station_id uuid,owner_id text,fencing_token bigint,expires_at timestamptz)
language plpgsql security invoker set search_path = '' as $$
declare
  v_station app.stations%rowtype;
  v_lease radio.station_leases%rowtype;
begin
  if p_owner_id is null or length(btrim(p_owner_id)) not between 3 and 200 then
    raise exception 'invalid owner id' using errcode='22023';
  end if;
  if p_ttl_seconds not between 10 and 120 then
    raise exception 'invalid lease duration' using errcode='22023';
  end if;

  select * into v_station from app.stations s where s.id=p_station_id for update;
  if not found or v_station.station_source <> 'INTERNAL'::app.station_source
     or not v_station.is_active or v_station.deleted_at is not null then
    raise exception 'station is not an active internal station' using errcode='22023';
  end if;

  select * into v_lease from radio.station_leases l where l.station_id=p_station_id for update;
  if not found then
    insert into radio.station_leases(station_id,owner_id,fencing_token,acquired_at,renewed_at,expires_at)
    values(p_station_id,p_owner_id,1,now(),now(),now()+make_interval(secs=>p_ttl_seconds))
    returning * into v_lease;
  elsif v_lease.owner_id=p_owner_id and v_lease.expires_at>now() then
    update radio.station_leases l set renewed_at=now(),expires_at=now()+make_interval(secs=>p_ttl_seconds)
      where l.station_id=p_station_id returning * into v_lease;
  elsif v_lease.expires_at<=now() then
    update radio.station_leases l set owner_id=p_owner_id,fencing_token=l.fencing_token+1,
      acquired_at=now(),renewed_at=now(),expires_at=now()+make_interval(secs=>p_ttl_seconds)
      where l.station_id=p_station_id returning * into v_lease;
  else
    return;
  end if;

  return query select v_lease.station_id,v_lease.owner_id,v_lease.fencing_token,v_lease.expires_at;
end $$;

create function radio.renew_station_lease(
  p_station_id uuid,
  p_owner_id text,
  p_fencing_token bigint,
  p_ttl_seconds integer default 15
) returns timestamptz
language plpgsql security invoker set search_path = '' as $$
declare v_expiry timestamptz;
begin
  if p_ttl_seconds not between 10 and 120 then
    raise exception 'invalid lease duration' using errcode='22023';
  end if;
  update radio.station_leases l set renewed_at=now(),expires_at=now()+make_interval(secs=>p_ttl_seconds)
  where l.station_id=p_station_id and l.owner_id=p_owner_id
    and l.fencing_token=p_fencing_token and l.expires_at>now()
  returning l.expires_at into v_expiry;
  if not found then raise exception 'station lease lost' using errcode='55000'; end if;
  return v_expiry;
end $$;

create function radio.release_station_lease(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint
) returns boolean
language sql security invoker set search_path = '' as $$
  with deleted as (
    delete from radio.station_leases l
    where l.station_id=p_station_id and l.owner_id=p_owner_id and l.fencing_token=p_fencing_token
    returning 1
  ) select exists(select 1 from deleted)
$$;

create function radio.checkpoint_engine_state(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint,p_mode radio.engine_mode,
  p_source_connected boolean,p_stream_mount text,p_current_media_id uuid,p_next_media_id uuid,
  p_current_title text,p_next_title text,p_started_at timestamptz,p_expected_end_at timestamptz,
  p_source_started_at timestamptz,p_processing_profile text,p_last_error text,p_last_recovery_at timestamptz,
  p_state_data jsonb default '{}'::jsonb,p_version text default 'unknown'
) returns bigint
language plpgsql security invoker set search_path = '' as $$
declare v_revision bigint;
begin
  if not exists (
    select 1 from radio.station_leases l where l.station_id=p_station_id and l.owner_id=p_owner_id
      and l.fencing_token=p_fencing_token and l.expires_at>now()
  ) then raise exception 'station lease lost' using errcode='55000'; end if;

  insert into radio.engine_states(station_id,mode,previous_valid_mode,fencing_token,revision,
    current_source_type,current_source_id,state_data,last_checkpoint_at,source_connected,stream_mount,
    source_started_at,last_error,last_recovery_at)
  values(p_station_id,p_mode,case when p_mode in ('AUTO','SCHEDULED','MANUAL','LIVE') then p_mode end,
    p_fencing_token,1,'MEDIA',p_current_media_id,coalesce(p_state_data,'{}'::jsonb),now(),
    p_source_connected,p_stream_mount,p_source_started_at,p_last_error,p_last_recovery_at)
  on conflict(station_id) do update set
    mode=excluded.mode,
    previous_valid_mode=coalesce(excluded.previous_valid_mode,radio.engine_states.previous_valid_mode),
    fencing_token=excluded.fencing_token,revision=radio.engine_states.revision+1,
    current_source_type=excluded.current_source_type,current_source_id=excluded.current_source_id,
    state_data=excluded.state_data,last_checkpoint_at=excluded.last_checkpoint_at,
    source_connected=excluded.source_connected,stream_mount=excluded.stream_mount,
    source_started_at=excluded.source_started_at,last_error=excluded.last_error,
    last_recovery_at=excluded.last_recovery_at,updated_at=now()
  returning revision into v_revision;

  insert into radio.now_playing(station_id,mode,status,media_id,title,started_at,expected_end_at,
    next_media_id,next_title,revision,source_type,processing_profile,stream_mount,fencing_token)
  values(p_station_id,p_mode,case when p_source_connected then 'ONLINE'::app.station_status else 'OFFLINE'::app.station_status end,
    p_current_media_id,p_current_title,p_started_at,p_expected_end_at,p_next_media_id,p_next_title,
    v_revision,'DEVELOPMENT_PLAYLIST',p_processing_profile,p_stream_mount,p_fencing_token)
  on conflict(station_id) do update set
    mode=excluded.mode,status=excluded.status,media_id=excluded.media_id,title=excluded.title,
    started_at=excluded.started_at,expected_end_at=excluded.expected_end_at,
    next_media_id=excluded.next_media_id,next_title=excluded.next_title,revision=excluded.revision,
    source_type=excluded.source_type,processing_profile=excluded.processing_profile,
    stream_mount=excluded.stream_mount,fencing_token=excluded.fencing_token,updated_at=now();

  insert into app.service_heartbeats(service_instance_id,service,station_id,status,version,details,started_at,last_seen_at)
  values(p_owner_id,'radio-engine',p_station_id,p_mode::text,p_version,
    jsonb_build_object('fencing_token',p_fencing_token,'source_connected',p_source_connected,'stream_mount',p_stream_mount),
    now(),now())
  on conflict(service_instance_id) do update set status=excluded.status,version=excluded.version,
    details=excluded.details,last_seen_at=now();
  return v_revision;
end $$;

revoke all on function radio.acquire_station_lease(uuid,text,integer) from public,anon,authenticated;
revoke all on function radio.renew_station_lease(uuid,text,bigint,integer) from public,anon,authenticated;
revoke all on function radio.release_station_lease(uuid,text,bigint) from public,anon,authenticated;
revoke all on function radio.checkpoint_engine_state(uuid,text,bigint,radio.engine_mode,boolean,text,uuid,uuid,text,text,timestamptz,timestamptz,timestamptz,text,text,timestamptz,jsonb,text) from public,anon,authenticated;
grant execute on function radio.acquire_station_lease(uuid,text,integer) to service_role;
grant execute on function radio.renew_station_lease(uuid,text,bigint,integer) to service_role;
grant execute on function radio.release_station_lease(uuid,text,bigint) to service_role;
grant execute on function radio.checkpoint_engine_state(uuid,text,bigint,radio.engine_mode,boolean,text,uuid,uuid,text,text,timestamptz,timestamptz,timestamptz,text,text,timestamptz,jsonb,text) to service_role;

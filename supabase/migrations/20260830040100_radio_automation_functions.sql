-- Phase 6 fenced claims, queue mutations and playout ledger.
create function radio.assert_station_lease(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint
) returns void language plpgsql security invoker set search_path='' as $$
begin
  if not exists(
    select 1 from radio.station_leases l
    where l.station_id=p_station_id and l.owner_id=p_owner_id
      and l.fencing_token=p_fencing_token and l.expires_at>clock_timestamp()
  ) then raise exception 'station lease lost' using errcode='55000'; end if;
end $$;

create function radio.claim_due_occurrence(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint,
  p_grace_seconds integer default 120,p_now timestamptz default clock_timestamp()
) returns setof radio.schedule_occurrences
language plpgsql security invoker set search_path='' as $$
declare v_id uuid;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  if p_grace_seconds not between 0 and 3600 then raise exception 'invalid grace' using errcode='22023'; end if;

  update radio.schedule_occurrences o set status='SKIPPED',finished_at=p_now,
    failure_code='MISSED',result=o.result||jsonb_build_object('reason','MISSED','evaluated_at',p_now)
  where o.station_id=p_station_id and o.status='PENDING'
    and o.scheduled_for < p_now-make_interval(secs=>p_grace_seconds);

  select o.id into v_id from radio.schedule_occurrences o
  join app.schedules s on s.id=o.schedule_id
  where o.station_id=p_station_id and o.status='PENDING'
    and o.scheduled_for<=p_now and o.scheduled_for>=p_now-make_interval(secs=>p_grace_seconds)
    and (o.expires_at is null or o.expires_at>=p_now)
    and s.enabled and s.deleted_at is null and s.version=o.schedule_version
  order by case o.priority when 'LIVE' then 5 when 'EMERGENCY' then 4 when 'HIGH' then 3 when 'NORMAL' then 2 else 1 end desc,
    o.scheduled_for,o.created_at,o.id
  for update of o skip locked limit 1;
  if v_id is null then return; end if;
  update radio.schedule_occurrences set status='CLAIMED',claimed_by=p_owner_id,
    claimed_at=p_now,claimed_fencing_token=p_fencing_token where id=v_id;
  insert into radio.radio_events(station_id,event_type,occurrence_id,fencing_token,data)
  values(p_station_id,'SCHEDULE_DUE',v_id,p_fencing_token,jsonb_build_object('claimed_by',p_owner_id));
  return query select * from radio.schedule_occurrences where id=v_id;
end $$;

create function radio.claim_radio_command(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint
) returns setof radio.radio_commands
language plpgsql security invoker set search_path='' as $$
declare v_id uuid;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  select c.id into v_id from radio.radio_commands c
  where c.station_id=p_station_id and c.status='PENDING'
  order by case c.priority when 'LIVE' then 5 when 'EMERGENCY' then 4 when 'HIGH' then 3 when 'NORMAL' then 2 else 1 end desc,
    c.created_at,c.id for update skip locked limit 1;
  if v_id is null then return; end if;
  update radio.radio_commands set status='PROCESSING',claimed_by=p_owner_id,
    claimed_at=clock_timestamp(),processing_fencing_token=p_fencing_token,
    effect_key=coalesce(effect_key,'command:'||id::text) where id=v_id;
  insert into radio.radio_events(station_id,event_type,command_id,fencing_token,data)
  values(p_station_id,'COMMAND_CLAIMED',v_id,p_fencing_token,jsonb_build_object('claimed_by',p_owner_id));
  return query select * from radio.radio_commands where id=v_id;
end $$;

create function radio.enqueue_media(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint,p_media_id uuid,
  p_source radio.queue_source,p_priority app.priority_level,p_interrupt_policy app.interrupt_policy,
  p_idempotency_key text,p_intended_at timestamptz,p_sequence bigint default 0,
  p_command_id uuid default null,p_occurrence_id uuid default null,p_playlist_id uuid default null,
  p_playlist_item_id uuid default null,p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid; v_source app.station_source;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  select station_source into v_source from app.stations
    where id=p_station_id and is_active and deleted_at is null;
  if v_source is distinct from 'INTERNAL' then raise exception 'station must be internal' using errcode='22023'; end if;
  if not exists(select 1 from app.media m where m.id=p_media_id and m.status='READY'
      and m.deleted_at is null and (m.station_id is null or m.station_id=p_station_id))
    then raise exception 'media is not READY for station' using errcode='22023'; end if;
  if p_playlist_id is not null and not exists(select 1 from app.playlists p
      where p.id=p_playlist_id and p.station_id=p_station_id and p.is_active and p.deleted_at is null)
    then raise exception 'playlist does not belong to station' using errcode='22023'; end if;

  insert into radio.queue_entries(station_id,source,priority,interrupt_policy,media_id,
    playlist_id,playlist_item_id,occurrence_id,command_id,idempotency_key,intended_at,
    sequence,claimed_by,claimed_at,claimed_fencing_token,metadata)
  values(p_station_id,p_source,p_priority,p_interrupt_policy,p_media_id,p_playlist_id,
    p_playlist_item_id,p_occurrence_id,p_command_id,p_idempotency_key,p_intended_at,
    p_sequence,p_owner_id,clock_timestamp(),p_fencing_token,coalesce(p_metadata,'{}'))
  on conflict(station_id,idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning id into v_id;
  insert into radio.radio_events(station_id,event_type,command_id,occurrence_id,media_id,fencing_token,data)
  values(p_station_id,'QUEUE_CHANGED',p_command_id,p_occurrence_id,p_media_id,p_fencing_token,
    jsonb_build_object('queue_entry_id',v_id,'source',p_source));
  return v_id;
end $$;

create function radio.complete_radio_command(
  p_command_id uuid,p_station_id uuid,p_owner_id text,p_fencing_token bigint,
  p_succeeded boolean,p_result jsonb default '{}'::jsonb,p_error_code text default null,
  p_error_message text default null
) returns boolean language plpgsql security invoker set search_path='' as $$
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  update radio.radio_commands set status=case when p_succeeded then 'COMPLETED'::radio.command_status else 'FAILED'::radio.command_status end,
    executed_at=clock_timestamp(),result=coalesce(p_result,'{}'),error_code=p_error_code,
    error_message=p_error_message
  where id=p_command_id and station_id=p_station_id and status='PROCESSING'
    and claimed_by=p_owner_id and processing_fencing_token=p_fencing_token;
  if not found then
    if exists(select 1 from radio.radio_commands where id=p_command_id and station_id=p_station_id
      and status in ('COMPLETED','FAILED') and processing_fencing_token=p_fencing_token) then return false; end if;
    raise exception 'command claim lost' using errcode='55000';
  end if;
  insert into radio.radio_events(station_id,event_type,command_id,fencing_token,data)
  values(p_station_id,case when p_succeeded then 'COMMAND_EXECUTED' else 'COMMAND_FAILED' end,
    p_command_id,p_fencing_token,coalesce(p_result,'{}'));
  return true;
end $$;

create function radio.record_playout_start(
  p_queue_entry_id uuid,p_playout_id uuid,p_station_id uuid,p_owner_id text,
  p_fencing_token bigint,p_started_at timestamptz
) returns bigint language plpgsql security invoker set search_path='' as $$
declare q radio.queue_entries%rowtype; h_id bigint; v_revision bigint;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  select * into q from radio.queue_entries where id=p_queue_entry_id and station_id=p_station_id for update;
  if not found then raise exception 'queue entry missing' using errcode='22023'; end if;
  update radio.queue_entries set status='PLAYING',started_at=coalesce(started_at,p_started_at),
    claimed_by=p_owner_id,claimed_fencing_token=p_fencing_token where id=q.id;
  insert into radio.play_history(station_id,media_id,source_type,source_id,started_at,
    command_id,occurrence_id,queue_entry_id,playlist_id,playout_id,fencing_token)
  values(p_station_id,q.media_id,q.source::text,q.id,p_started_at,q.command_id,q.occurrence_id,
    q.id,q.playlist_id,p_playout_id,p_fencing_token)
  on conflict(playout_id) do update set playout_id=excluded.playout_id returning id into h_id;
  select coalesce(revision,0)+1 into v_revision from radio.now_playing where station_id=p_station_id;
  v_revision:=coalesce(v_revision,1);
  insert into radio.now_playing(station_id,mode,status,media_id,title,started_at,duration_ms,
    revision,source_type,stream_mount,fencing_token,queue_entry_id,command_id,occurrence_id,playlist_id)
  select p_station_id,
    case q.source when 'SCHEDULED' then 'SCHEDULED'::radio.engine_mode
      when 'MANUAL' then 'MANUAL'::radio.engine_mode
      when 'EMERGENCY' then 'MANUAL'::radio.engine_mode else 'AUTO'::radio.engine_mode end,
    'ONLINE',m.id,m.title,p_started_at,m.duration_ms,v_revision,q.source::text,
    '/tarteel.mp3',p_fencing_token,q.id,q.command_id,q.occurrence_id,q.playlist_id
  from app.media m where m.id=q.media_id
  on conflict(station_id) do update set mode=excluded.mode,status=excluded.status,
    media_id=excluded.media_id,title=excluded.title,started_at=excluded.started_at,
    duration_ms=excluded.duration_ms,revision=excluded.revision,source_type=excluded.source_type,
    stream_mount=excluded.stream_mount,fencing_token=excluded.fencing_token,
    queue_entry_id=excluded.queue_entry_id,command_id=excluded.command_id,
    occurrence_id=excluded.occurrence_id,playlist_id=excluded.playlist_id,updated_at=clock_timestamp();
  return h_id;
end $$;

create function radio.record_playout_end(
  p_playout_id uuid,p_station_id uuid,p_owner_id text,p_fencing_token bigint,
  p_ended_at timestamptz,p_completed_naturally boolean,p_reason text default null
) returns boolean language plpgsql security invoker set search_path='' as $$
declare q_id uuid;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  update radio.play_history set ended_at=coalesce(ended_at,p_ended_at),
    completed_naturally=p_completed_naturally,interrupted=not p_completed_naturally,
    interruption_reason=case when p_completed_naturally then null else coalesce(p_reason,'INTERRUPTED') end,
    result=case when p_completed_naturally then 'COMPLETED' else 'INTERRUPTED' end,
    played_ms=greatest(0,(extract(epoch from (p_ended_at-started_at))*1000)::bigint)
  where playout_id=p_playout_id and station_id=p_station_id and ended_at is null
  returning queue_entry_id into q_id;
  if not found then return false; end if;
  update radio.queue_entries set status=case when p_completed_naturally then 'COMPLETED'::radio.queue_status else 'CANCELLED'::radio.queue_status end,
    finished_at=p_ended_at where id=q_id;
  return true;
end $$;

revoke all on function radio.assert_station_lease(uuid,text,bigint) from public,anon,authenticated;
revoke all on function radio.claim_due_occurrence(uuid,text,bigint,integer,timestamptz) from public,anon,authenticated;
revoke all on function radio.claim_radio_command(uuid,text,bigint) from public,anon,authenticated;
revoke all on function radio.enqueue_media(uuid,text,bigint,uuid,radio.queue_source,app.priority_level,app.interrupt_policy,text,timestamptz,bigint,uuid,uuid,uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function radio.complete_radio_command(uuid,uuid,text,bigint,boolean,jsonb,text,text) from public,anon,authenticated;
revoke all on function radio.record_playout_start(uuid,uuid,uuid,text,bigint,timestamptz) from public,anon,authenticated;
revoke all on function radio.record_playout_end(uuid,uuid,text,bigint,timestamptz,boolean,text) from public,anon,authenticated;
grant execute on all functions in schema radio to service_role;

-- Preserve monotonic fencing tokens, resolve exact-time schedule conflicts, and
-- make non-media command effects recoverable without replaying them blindly.
create table radio.command_effects (
  id uuid primary key default gen_random_uuid(),
  command_id uuid not null unique references radio.radio_commands(id) on delete restrict,
  station_id uuid not null references app.stations(id) on delete restrict,
  effect_type text not null check (effect_type in ('ENQUEUE','SKIP','STOP_AFTER_CURRENT','RESUME_AUTO')),
  status text not null default 'PREPARED' check (status in ('PREPARED','DISPATCHED','ACKED','FAILED')),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  fencing_token bigint not null check (fencing_token > 0),
  prepared_at timestamptz not null default now(), dispatched_at timestamptz, acknowledged_at timestamptz,
  result jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index command_effects_recovery_idx on radio.command_effects(station_id,status,prepared_at);
create trigger set_updated_at before update on radio.command_effects for each row execute function app.set_updated_at();
alter table radio.command_effects enable row level security;
revoke all on table radio.command_effects from public,anon,authenticated;
grant select,insert,update,delete on radio.command_effects to service_role;

create or replace function radio.release_station_lease(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint
) returns boolean language plpgsql security invoker set search_path='' as $$
begin
  update radio.station_leases set renewed_at=clock_timestamp()-interval '1 second',
    expires_at=clock_timestamp(),owner_id=p_owner_id
  where station_id=p_station_id and owner_id=p_owner_id and fencing_token=p_fencing_token;
  return found;
end $$;

create or replace function radio.claim_due_occurrence(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint,
  p_grace_seconds integer default 120,p_now timestamptz default clock_timestamp()
) returns setof radio.schedule_occurrences
language plpgsql security invoker set search_path='' as $$
declare v_id uuid;v_scheduled_for timestamptz;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  if p_grace_seconds not between 0 and 3600 then raise exception 'invalid grace' using errcode='22023'; end if;
  with missed as (
    update radio.schedule_occurrences o set status='SKIPPED',finished_at=p_now,failure_code='MISSED',
      result=o.result||jsonb_build_object('reason','MISSED','evaluated_at',p_now)
    where o.station_id=p_station_id and o.status='PENDING'
      and o.scheduled_for<p_now-make_interval(secs=>p_grace_seconds) returning o.id
  ) insert into radio.radio_events(station_id,event_type,occurrence_id,fencing_token,data)
    select p_station_id,'SCHEDULE_MISSED',id,p_fencing_token,jsonb_build_object('evaluated_at',p_now) from missed;

  select o.id,o.scheduled_for into v_id,v_scheduled_for from radio.schedule_occurrences o
  join app.schedules s on s.id=o.schedule_id
  where o.station_id=p_station_id and o.status='PENDING' and o.scheduled_for<=p_now
    and o.scheduled_for>=p_now-make_interval(secs=>p_grace_seconds)
    and (o.expires_at is null or o.expires_at>=p_now) and s.enabled and s.deleted_at is null and s.version=o.schedule_version
  order by case o.priority when 'LIVE' then 50 when 'EMERGENCY' then 40 when 'HIGH' then 30 when 'NORMAL' then 20 else 10 end desc,
    o.scheduled_for,s.created_at,o.id for update of o skip locked limit 1;
  if v_id is null then return; end if;

  with losers as (
    update radio.schedule_occurrences o set status='SKIPPED',finished_at=p_now,failure_code='CONFLICT_LOST',
      result=o.result||jsonb_build_object('reason','CONFLICT_LOST','winner_id',v_id)
    where o.station_id=p_station_id and o.status='PENDING' and o.scheduled_for=v_scheduled_for and o.id<>v_id returning o.id
  ) insert into radio.radio_events(station_id,event_type,occurrence_id,fencing_token,data)
    select p_station_id,'SCHEDULE_CONFLICT_LOST',id,p_fencing_token,jsonb_build_object('winner_id',v_id) from losers;
  update radio.schedule_occurrences set status='CLAIMED',claimed_by=p_owner_id,claimed_at=p_now,
    claimed_fencing_token=p_fencing_token where id=v_id;
  insert into radio.radio_events(station_id,event_type,occurrence_id,fencing_token,data)
  values(p_station_id,'SCHEDULE_DUE',v_id,p_fencing_token,jsonb_build_object('claimed_by',p_owner_id));
  return query select * from radio.schedule_occurrences where id=v_id;
end $$;

create function radio.record_command_effect(
  p_command_id uuid,p_station_id uuid,p_owner_id text,p_fencing_token bigint,
  p_effect_type text,p_payload_hash text,p_status text default 'PREPARED',p_result jsonb default '{}'::jsonb
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  if p_effect_type not in ('ENQUEUE','SKIP','STOP_AFTER_CURRENT','RESUME_AUTO') or p_status not in ('PREPARED','DISPATCHED','ACKED','FAILED')
    then raise exception 'invalid command effect' using errcode='22023'; end if;
  if not exists(select 1 from radio.radio_commands c where c.id=p_command_id and c.station_id=p_station_id
      and c.status='PROCESSING' and c.claimed_by=p_owner_id and c.processing_fencing_token=p_fencing_token)
    then raise exception 'command claim lost' using errcode='55000'; end if;
  insert into radio.command_effects(command_id,station_id,effect_type,status,payload_hash,fencing_token,
    dispatched_at,acknowledged_at,result)
  values(p_command_id,p_station_id,p_effect_type,p_status,p_payload_hash,p_fencing_token,
    case when p_status in ('DISPATCHED','ACKED') then clock_timestamp() end,
    case when p_status='ACKED' then clock_timestamp() end,coalesce(p_result,'{}'))
  on conflict(command_id) do update set
    status=case when radio.command_effects.status='ACKED' then 'ACKED' else excluded.status end,
    dispatched_at=coalesce(radio.command_effects.dispatched_at,excluded.dispatched_at),
    acknowledged_at=coalesce(radio.command_effects.acknowledged_at,excluded.acknowledged_at),
    result=radio.command_effects.result||excluded.result
  where radio.command_effects.payload_hash=excluded.payload_hash and radio.command_effects.effect_type=excluded.effect_type
  returning id into v_id;
  if v_id is null then raise exception 'command effect mismatch' using errcode='22000'; end if;
  return v_id;
end $$;

create function radio.complete_schedule_occurrence(
  p_occurrence_id uuid,p_station_id uuid,p_owner_id text,p_fencing_token bigint,
  p_succeeded boolean,p_result jsonb default '{}'::jsonb,p_error_code text default null,p_error_message text default null
) returns boolean language plpgsql security invoker set search_path='' as $$
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  update radio.schedule_occurrences set status=case when p_succeeded then 'COMPLETED'::radio.occurrence_status else 'FAILED'::radio.occurrence_status end,
    finished_at=clock_timestamp(),result=result||coalesce(p_result,'{}'),failure_code=p_error_code,failure_message=p_error_message
  where id=p_occurrence_id and station_id=p_station_id and status in ('CLAIMED','PLAYING')
    and claimed_by=p_owner_id and claimed_fencing_token=p_fencing_token;
  if not found then
    if exists(select 1 from radio.schedule_occurrences where id=p_occurrence_id and station_id=p_station_id
      and status in ('COMPLETED','FAILED') and claimed_fencing_token=p_fencing_token) then return false;end if;
    raise exception 'occurrence claim lost' using errcode='55000';
  end if;
  insert into radio.radio_events(station_id,event_type,occurrence_id,fencing_token,data)
  values(p_station_id,case when p_succeeded then 'SCHEDULE_COMPLETED' else 'SCHEDULE_FAILED' end,
    p_occurrence_id,p_fencing_token,coalesce(p_result,'{}'));
  return true;
end $$;

create function radio.recover_stale_automation(
  p_station_id uuid,p_owner_id text,p_fencing_token bigint
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_occurrences integer;v_commands integer;v_queue integer;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  update radio.schedule_occurrences o set status='PENDING',claimed_by=null,claimed_at=null,claimed_fencing_token=null,
    result=o.result||jsonb_build_object('recovered_by_token',p_fencing_token)
  where o.station_id=p_station_id and o.status='CLAIMED' and coalesce(o.claimed_fencing_token,0)<p_fencing_token
    and not exists(select 1 from radio.queue_entries q where q.occurrence_id=o.id);
  get diagnostics v_occurrences=row_count;
  update radio.radio_commands c set status='PENDING',claimed_by=null,claimed_at=null,processing_fencing_token=null
  where c.station_id=p_station_id and c.status='PROCESSING' and coalesce(c.processing_fencing_token,0)<p_fencing_token
    and not exists(select 1 from radio.command_effects e where e.command_id=c.id)
    and not exists(select 1 from radio.queue_entries q where q.command_id=c.id);
  get diagnostics v_commands=row_count;
  update radio.queue_entries q set status='PENDING',claimed_by=null,claimed_at=null,claimed_fencing_token=null,dispatched_at=null
  where q.station_id=p_station_id and q.status='DISPATCHED' and coalesce(q.claimed_fencing_token,0)<p_fencing_token;
  get diagnostics v_queue=row_count;
  return jsonb_build_object('occurrences',v_occurrences,'commands',v_commands,'queue_entries',v_queue);
end $$;

revoke all on function radio.release_station_lease(uuid,text,bigint) from public,anon,authenticated;
revoke all on function radio.claim_due_occurrence(uuid,text,bigint,integer,timestamptz) from public,anon,authenticated;
revoke all on function radio.record_command_effect(uuid,uuid,text,bigint,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function radio.complete_schedule_occurrence(uuid,uuid,text,bigint,boolean,jsonb,text,text) from public,anon,authenticated;
revoke all on function radio.recover_stale_automation(uuid,text,bigint) from public,anon,authenticated;
grant execute on function radio.release_station_lease(uuid,text,bigint) to service_role;
grant execute on function radio.claim_due_occurrence(uuid,text,bigint,integer,timestamptz) to service_role;
grant execute on function radio.record_command_effect(uuid,uuid,text,bigint,text,text,text,jsonb) to service_role;
grant execute on function radio.complete_schedule_occurrence(uuid,uuid,text,bigint,boolean,jsonb,text,text) to service_role;
grant execute on function radio.recover_stale_automation(uuid,text,bigint) to service_role;

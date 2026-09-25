-- PostgreSQL does not implicitly coerce CASE text arms to enum assignment targets.
create or replace function radio.complete_schedule_occurrence(
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
  values(p_station_id,case when p_succeeded then 'SCHEDULE_COMPLETED' else 'SCHEDULE_FAILED' end,p_occurrence_id,p_fencing_token,coalesce(p_result,'{}'));
  return true;
end $$;

create or replace function radio.complete_radio_command(
  p_command_id uuid,p_station_id uuid,p_owner_id text,p_fencing_token bigint,
  p_succeeded boolean,p_result jsonb default '{}'::jsonb,p_error_code text default null,p_error_message text default null
) returns boolean language plpgsql security invoker set search_path='' as $$
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  update radio.radio_commands set status=case when p_succeeded then 'COMPLETED'::radio.command_status else 'FAILED'::radio.command_status end,
    executed_at=clock_timestamp(),result=coalesce(p_result,'{}'),error_code=p_error_code,error_message=p_error_message
  where id=p_command_id and station_id=p_station_id and status='PROCESSING' and claimed_by=p_owner_id and processing_fencing_token=p_fencing_token;
  if not found then
    if exists(select 1 from radio.radio_commands where id=p_command_id and station_id=p_station_id
      and status in ('COMPLETED','FAILED') and processing_fencing_token=p_fencing_token) then return false;end if;
    raise exception 'command claim lost' using errcode='55000';
  end if;
  insert into radio.radio_events(station_id,event_type,command_id,fencing_token,data)
  values(p_station_id,case when p_succeeded then 'COMMAND_EXECUTED' else 'COMMAND_FAILED' end,p_command_id,p_fencing_token,coalesce(p_result,'{}'));
  return true;
end $$;

create or replace function radio.record_playout_end(
  p_playout_id uuid,p_station_id uuid,p_owner_id text,p_fencing_token bigint,
  p_ended_at timestamptz,p_completed_naturally boolean,p_reason text default null
) returns boolean language plpgsql security invoker set search_path='' as $$
declare q_id uuid;
begin
  perform radio.assert_station_lease(p_station_id,p_owner_id,p_fencing_token);
  update radio.play_history set ended_at=coalesce(ended_at,p_ended_at),completed_naturally=p_completed_naturally,
    interrupted=not p_completed_naturally,interruption_reason=case when p_completed_naturally then null else coalesce(p_reason,'INTERRUPTED') end,
    result=case when p_completed_naturally then 'COMPLETED' else 'INTERRUPTED' end,
    played_ms=greatest(0,(extract(epoch from (p_ended_at-started_at))*1000)::bigint)
  where playout_id=p_playout_id and station_id=p_station_id and ended_at is null returning queue_entry_id into q_id;
  if not found then return false;end if;
  update radio.queue_entries set status=case when p_completed_naturally then 'COMPLETED'::radio.queue_status else 'CANCELLED'::radio.queue_status end,
    finished_at=p_ended_at where id=q_id;
  return true;
end $$;

revoke all on function radio.complete_schedule_occurrence(uuid,uuid,text,bigint,boolean,jsonb,text,text) from public,anon,authenticated;
revoke all on function radio.complete_radio_command(uuid,uuid,text,bigint,boolean,jsonb,text,text) from public,anon,authenticated;
revoke all on function radio.record_playout_end(uuid,uuid,text,bigint,timestamptz,boolean,text) from public,anon,authenticated;
grant execute on function radio.complete_schedule_occurrence(uuid,uuid,text,bigint,boolean,jsonb,text,text) to service_role;
grant execute on function radio.complete_radio_command(uuid,uuid,text,bigint,boolean,jsonb,text,text) to service_role;
grant execute on function radio.record_playout_end(uuid,uuid,text,bigint,timestamptz,boolean,text) to service_role;

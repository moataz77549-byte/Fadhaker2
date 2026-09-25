begin;
do $$
declare
  station constant uuid:='00000000-0000-4000-8000-000000000006';
  media constant uuid:='00000000-0000-4000-8100-000000000001';
  schedule_hi constant uuid:='10000000-0000-4000-8000-000000000001';
  schedule_lo constant uuid:='10000000-0000-4000-8000-000000000002';
  occurrence_hi constant uuid:='20000000-0000-4000-8000-000000000001';
  occurrence_lo constant uuid:='20000000-0000-4000-8000-000000000002';
  command_hi constant uuid:='30000000-0000-4000-8000-000000000001';
  command_lo constant uuid:='30000000-0000-4000-8000-000000000002';
  lease record;claimed_occ record;claimed_command record;queue_a uuid;queue_b uuid;history_a bigint;history_b bigint;intended timestamptz:=clock_timestamp()-interval '1 second';
  stale_rejected boolean:=false;duplicate_rejected boolean:=false;effect_a uuid;effect_b uuid;new_token bigint;
begin
  update radio.station_leases set renewed_at=clock_timestamp()-interval '2 seconds',expires_at=clock_timestamp()-interval '1 second' where station_id=station;
  select * into lease from radio.acquire_station_lease(station,'phase6-validation-a',30);
  if lease.fencing_token is null then raise exception 'lease not acquired';end if;

  insert into app.schedules(id,station_id,name,content_type,media_id,schedule_type,start_date,start_time,timezone,priority,interrupt_policy)
  values(schedule_hi,station,'Validation High','MEDIA',media,'ONE_TIME',current_date,current_time,'UTC','HIGH','FINISH_CURRENT'),
        (schedule_lo,station,'Validation Low','MEDIA',media,'ONE_TIME',current_date,current_time,'UTC','NORMAL','FINISH_CURRENT');
  insert into radio.schedule_occurrences(id,schedule_id,station_id,occurrence_key,scheduled_for,local_date,local_time,timezone,priority,interrupt_policy,schedule_version,content_type,media_id,expires_at)
  values(occurrence_hi,schedule_hi,station,'validation-high',intended,current_date,current_time,'UTC','HIGH','FINISH_CURRENT',1,'MEDIA',media,clock_timestamp()+interval '1 minute'),
        (occurrence_lo,schedule_lo,station,'validation-low',intended,current_date,current_time,'UTC','NORMAL','FINISH_CURRENT',1,'MEDIA',media,clock_timestamp()+interval '1 minute');
  select * into claimed_occ from radio.claim_due_occurrence(station,lease.owner_id,lease.fencing_token,120,clock_timestamp());
  if claimed_occ.id<>occurrence_hi then raise exception 'priority conflict winner incorrect';end if;
  if (select status from radio.schedule_occurrences where id=occurrence_lo)<>'SKIPPED' then raise exception 'conflict loser not skipped';end if;
  if radio.complete_schedule_occurrence(occurrence_hi,station,lease.owner_id,lease.fencing_token,true,'{"test":true}') is not true then raise exception 'occurrence completion failed';end if;
  if radio.complete_schedule_occurrence(occurrence_hi,station,lease.owner_id,lease.fencing_token,true,'{}') is not false then raise exception 'occurrence completion not idempotent';end if;

  insert into radio.radio_commands(id,station_id,command_type,payload,priority,idempotency_key)
  values(command_hi,station,'PLAY_NOW',jsonb_build_object('media_id',media,'interrupt',true),'HIGH','validation-command-high'),
        (command_lo,station,'PLAY_NEXT',jsonb_build_object('media_id',media),'NORMAL','validation-command-low');
  begin
    insert into radio.radio_commands(station_id,command_type,payload,idempotency_key) values(station,'SKIP','{}','validation-command-high');
  exception when unique_violation then duplicate_rejected:=true;end;
  if not duplicate_rejected then raise exception 'duplicate idempotency key accepted';end if;
  select * into claimed_command from radio.claim_radio_command(station,lease.owner_id,lease.fencing_token);
  if claimed_command.id<>command_hi then raise exception 'command priority winner incorrect';end if;
  queue_a:=radio.enqueue_media(station,lease.owner_id,lease.fencing_token,media,'MANUAL','HIGH','INTERRUPT','validation-queue',clock_timestamp(),0,command_hi);
  queue_b:=radio.enqueue_media(station,lease.owner_id,lease.fencing_token,media,'MANUAL','HIGH','INTERRUPT','validation-queue',clock_timestamp(),0,command_hi);
  if queue_a<>queue_b then raise exception 'queue idempotency failed';end if;
  effect_a:=radio.record_command_effect(command_hi,station,lease.owner_id,lease.fencing_token,'ENQUEUE',repeat('a',64),'DISPATCHED','{}');
  effect_b:=radio.record_command_effect(command_hi,station,lease.owner_id,lease.fencing_token,'ENQUEUE',repeat('a',64),'ACKED','{}');
  if effect_a<>effect_b then raise exception 'command effect duplicated';end if;
  if radio.complete_radio_command(command_hi,station,lease.owner_id,lease.fencing_token,true,'{"queue_entry":true}') is not true then raise exception 'command completion failed';end if;
  if radio.complete_radio_command(command_hi,station,lease.owner_id,lease.fencing_token,true,'{}') is not false then raise exception 'command completion not idempotent';end if;

  history_a:=radio.record_playout_start(queue_a,'40000000-0000-4000-8000-000000000001',station,lease.owner_id,lease.fencing_token,clock_timestamp());
  history_b:=radio.record_playout_start(queue_a,'40000000-0000-4000-8000-000000000001',station,lease.owner_id,lease.fencing_token,clock_timestamp());
  if history_a<>history_b then raise exception 'duplicate ACK created duplicate history';end if;
  if radio.record_playout_end('40000000-0000-4000-8000-000000000001',station,lease.owner_id,lease.fencing_token,clock_timestamp(),false,'PLAY_NOW_INTERRUPT') is not true then raise exception 'playout end failed';end if;
  if radio.record_playout_end('40000000-0000-4000-8000-000000000001',station,lease.owner_id,lease.fencing_token,clock_timestamp(),false,'PLAY_NOW_INTERRUPT') is not false then raise exception 'playout end not idempotent';end if;

  perform radio.release_station_lease(station,lease.owner_id,lease.fencing_token);
  select fencing_token into new_token from radio.acquire_station_lease(station,'phase6-validation-b',30);
  if new_token<=lease.fencing_token then raise exception 'fencing token did not increase after release';end if;
  begin perform radio.assert_station_lease(station,lease.owner_id,lease.fencing_token);exception when sqlstate '55000' then stale_rejected:=true;end;
  if not stale_rejected then raise exception 'stale lease accepted';end if;
end $$;
select 'PASS' as status,
  (select count(*) from radio.queue_entries where idempotency_key='validation-queue') as idempotent_queue_rows,
  (select count(*) from radio.play_history where playout_id='40000000-0000-4000-8000-000000000001') as idempotent_history_rows;
rollback;

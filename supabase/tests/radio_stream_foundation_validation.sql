begin;
do $$
declare
  provider uuid; station uuid:=gen_random_uuid(); first_token bigint; second_token bigint;
  revision bigint; denied_count integer; rejected boolean:=false;
begin
  select id into provider from app.content_providers where slug='internal';
  insert into app.stations(id,provider_id,name_ar,name_en,slug,station_source,stream_type,stream_url,timezone,
    rights_status,commercial_use_status)
  values(station,provider,'محطة اختبار البث','Stream foundation test','radio-foundation-test',
    'INTERNAL','INTERNAL','https://radio.example.test/tarteel.mp3','UTC','APPROVED','ALLOWED');

  select fencing_token into first_token from radio.acquire_station_lease(station,'engine-a',15);
  if first_token<>1 then raise exception 'first lease token mismatch'; end if;
  select count(*) into denied_count from radio.acquire_station_lease(station,'engine-b',15);
  if denied_count<>0 then raise exception 'second engine acquired active lease'; end if;
  perform radio.renew_station_lease(station,'engine-a',first_token,15);

  update radio.station_leases set renewed_at=now()-interval '2 seconds',expires_at=now()-interval '1 second'
    where station_id=station;
  select fencing_token into second_token from radio.acquire_station_lease(station,'engine-b',15);
  if second_token<=first_token then raise exception 'fencing token did not increase'; end if;

  begin
    perform radio.renew_station_lease(station,'engine-a',first_token,15);
  exception when sqlstate '55000' then rejected:=true;
  end;
  if not rejected then raise exception 'stale owner renewal was accepted'; end if;

  select radio.checkpoint_engine_state(station,'engine-b',second_token,'AUTO',true,'/tarteel.mp3',
    null,null,'Development Track A','Development Track B',now(),now()+interval '20 seconds',now(),
    'LIVE_MP3_128K_V1',null,now(),'{}'::jsonb,'test') into revision;
  if revision<>1 then raise exception 'unexpected initial revision'; end if;
  if not exists(select 1 from radio.now_playing where station_id=station and stream_mount='/tarteel.mp3'
    and status='ONLINE' and fencing_token=second_token) then raise exception 'now playing projection missing'; end if;
  if not exists(select 1 from app.service_heartbeats where service_instance_id='engine-b'
    and service='radio-engine') then raise exception 'heartbeat missing'; end if;

  rejected:=false;
  begin
    perform radio.checkpoint_engine_state(station,'engine-a',first_token,'AUTO',true,'/tarteel.mp3',
      null,null,'stale',null,now(),null,now(),'LIVE_MP3_128K_V1',null,null,'{}'::jsonb,'test');
  exception when sqlstate '55000' then rejected:=true;
  end;
  if not rejected then raise exception 'stale fenced checkpoint was accepted'; end if;
end $$;
rollback;

-- Safe repeatable integration checks. Fixtures are removed before results are returned.
create temporary table database_test_results (
  test_name text primary key,
  passed boolean not null,
  detail text not null
) on commit drop;

do $$
declare
  internal_provider uuid;
  external_provider uuid;
  external_station uuid;
  category uuid;
  role_id uuid;
  station_a uuid := gen_random_uuid();
  station_b uuid := gen_random_uuid();
  media_id uuid := gen_random_uuid();
  playlist_a uuid := gen_random_uuid();
  playlist_b uuid := gen_random_uuid();
  original_updated_at timestamptz;
begin
  select id into internal_provider from app.content_providers where slug = 'internal';
  select id into external_provider from app.content_providers where slug = 'qurango';
  select id into external_station from app.stations where station_source='EXTERNAL' order by id limit 1;
  select id into category from app.categories where slug = 'QURAN_GENERAL';
  select id into role_id from app.roles where code = 'VIEWER';

  insert into app.stations
    (id, provider_id, category_id, name_ar, name_en, slug, station_source, stream_type,
     stream_url, timezone, rights_status, commercial_use_status)
  values
    (station_a, internal_provider, category, 'اختبار ترتيل أ', 'Tarteel Test A',
     'db-test-tarteel-a', 'INTERNAL', 'INTERNAL', 'https://radio.example.test/tarteel-a',
     'UTC', 'APPROVED', 'ALLOWED'),
    (station_b, internal_provider, category, 'اختبار ترتيل ب', 'Tarteel Test B',
     'db-test-tarteel-b', 'INTERNAL', 'INTERNAL', 'https://radio.example.test/tarteel-b',
     'UTC', 'APPROVED', 'ALLOWED');
  insert into app.media (id, title, original_path, file_size_bytes)
    values (media_id, 'Database fixture', null, 1);
  insert into app.playlists (id, station_id, name) values
    (playlist_a, station_a, 'Fixture A'), (playlist_b, station_b, 'Fixture B');

  update app.stations set default_playlist_id = playlist_a where id = station_a;
  insert into database_test_results values ('internal_default_playlist_supported', true, 'same-station composite FK accepted');

  begin
    update app.stations set default_playlist_id = playlist_b where id = station_a;
    insert into database_test_results values ('cross_station_default_playlist_rejected', false, 'unexpectedly accepted');
  exception when others then
    insert into database_test_results values ('cross_station_default_playlist_rejected', true, sqlstate);
  end;

  begin
    insert into app.surahs values (115,115,'غير صالح','Invalid',1,now());
    insert into database_test_results values ('surah_115_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('surah_115_rejected', true, sqlstate); end;
  begin
    insert into app.surahs values (0,0,'غير صالح','Invalid',1,now());
    insert into database_test_results values ('surah_0_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('surah_0_rejected', true, sqlstate); end;
  begin
    insert into app.stations
      (provider_id,name_ar,slug,station_source,stream_type,stream_url,timezone)
    values (internal_provider,'مكرر','db-test-tarteel-a','INTERNAL','INTERNAL','https://radio.example.test/duplicate','UTC');
    insert into database_test_results values ('duplicate_station_slug_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('duplicate_station_slug_rejected', true, sqlstate); end;
  begin
    insert into app.playlist_items (playlist_id,media_id,position) values (gen_random_uuid(),media_id,0);
    insert into database_test_results values ('orphan_playlist_item_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('orphan_playlist_item_rejected', true, sqlstate); end;
  begin
    insert into app.media (title,original_path,file_size_bytes,status)
      values ('Invalid ready media','tests/invalid-ready.mp3',1,'READY');
    insert into database_test_results values ('invalid_ready_media_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('invalid_ready_media_rejected', true, sqlstate); end;
  begin
    insert into app.schedules
      (station_id,name,content_type,schedule_type,start_date,start_time,timezone)
    values (station_a,'Invalid media','MEDIA','ONE_TIME',current_date,'12:00','UTC');
    insert into database_test_results values ('media_schedule_without_media_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('media_schedule_without_media_rejected', true, sqlstate); end;
  begin
    insert into app.schedules
      (station_id,name,content_type,schedule_type,start_date,start_time,timezone)
    values (station_a,'Invalid playlist','PLAYLIST','ONE_TIME',current_date,'12:00','UTC');
    insert into database_test_results values ('playlist_schedule_without_playlist_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('playlist_schedule_without_playlist_rejected', true, sqlstate); end;
  begin
    insert into app.schedules
      (station_id,name,content_type,media_id,schedule_type,start_date,start_time,days_of_week,timezone)
    values (station_a,'Duplicate weekday','MEDIA',media_id,'WEEKLY',current_date,'12:00',array[1,1]::smallint[],'UTC');
    insert into database_test_results values ('duplicate_weekdays_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('duplicate_weekdays_rejected', true, sqlstate); end;
  begin
    insert into app.schedules
      (station_id,name,content_type,media_id,schedule_type,start_date,start_time,timezone)
    values (station_a,'Invalid timezone','MEDIA',media_id,'ONE_TIME',current_date,'12:00','Mars/Olympus');
    insert into database_test_results values ('invalid_timezone_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('invalid_timezone_rejected', true, sqlstate); end;
  begin
    insert into radio.radio_commands (station_id,command_type,idempotency_key)
      values (station_a,'INVALID_COMMAND','invalid-enum');
    insert into database_test_results values ('invalid_command_enum_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('invalid_command_enum_rejected', true, sqlstate); end;

  insert into radio.radio_commands (station_id,command_type,idempotency_key)
    values (station_a,'PLAY_NEXT','duplicate-key');
  begin
    insert into radio.radio_commands (station_id,command_type,idempotency_key)
      values (station_a,'PLAY_NEXT','duplicate-key');
    insert into database_test_results values ('duplicate_command_key_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('duplicate_command_key_rejected', true, sqlstate); end;

  begin
    insert into app.playlists (station_id,name)
      select id,'External invalid playlist' from app.stations where station_source='EXTERNAL' limit 1;
    insert into database_test_results values ('external_automation_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('external_automation_rejected', true, sqlstate); end;
  begin
    update app.stations set production_enabled=true where id=external_station;
    insert into database_test_results values ('unapproved_external_production_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('unapproved_external_production_rejected', true, sqlstate); end;
  begin
    insert into app.stations
      (provider_id,name_ar,slug,station_source,stream_type,stream_url)
    values (external_provider,'خارجي غير صالح','db-test-invalid-external','EXTERNAL','INTERNAL','https://example.test/invalid');
    insert into database_test_results values ('external_internal_stream_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('external_internal_stream_rejected', true, sqlstate); end;
  begin
    insert into app.administrator_roles (administrator_id,role_id)
      values (gen_random_uuid(),role_id);
    insert into database_test_results values ('invalid_role_assignment_rejected', false, 'unexpectedly accepted');
  exception when others then insert into database_test_results values ('invalid_role_assignment_rejected', true, sqlstate); end;

  select updated_at into original_updated_at from app.categories where id=category;
  update app.categories set description='updated_at test' where id=category;
  insert into database_test_results values
    ('updated_at_changes', (select updated_at > original_updated_at from app.categories where id=category), 'shared trigger');

  insert into database_test_results values
    ('surah_sequence_complete',
     (select count(*)=114 and min(number)=1 and max(number)=114 and count(distinct number)=114 from app.surahs),
     'numbers 1..114');
  insert into database_test_results values
    ('external_station_without_playlist_supported',
     exists(select 1 from app.stations where station_source='EXTERNAL' and default_playlist_id is null),
     'unified station model');

  delete from radio.radio_commands where station_id in (station_a,station_b);
  update app.stations set default_playlist_id=null where id in (station_a,station_b);
  delete from app.playlists where id in (playlist_a,playlist_b);
  delete from app.media where id=media_id;
  delete from app.stations where id in (station_a,station_b);
  update app.categories set description=null where id=category;
end $$;

select test_name, passed, detail from database_test_results order by test_name;

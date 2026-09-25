-- Safe, repeatable database-side tests for Storage/Upload foundation.
create temporary table storage_test_results (
  test_name text primary key,
  passed boolean not null,
  detail text not null
) on commit drop;

do $$
declare
  provider_id uuid;
  category_id uuid;
  external_station_id uuid;
  station_a uuid := gen_random_uuid();
  station_b uuid := gen_random_uuid();
  media_valid uuid := gen_random_uuid();
  media_invalid uuid := gen_random_uuid();
  media_large uuid := gen_random_uuid();
  media_cross uuid := gen_random_uuid();
  media_expired uuid := gen_random_uuid();
  media_bad_key uuid := gen_random_uuid();
  media_flac uuid := gen_random_uuid();
  intent_id uuid;
  repeated_intent_id uuid;
  signed_intent_id uuid;
begin
  select id into provider_id from app.content_providers where slug='internal';
  select id into category_id from app.categories where slug='QURAN_GENERAL';
  select id into external_station_id from app.stations where station_source='EXTERNAL' order by id limit 1;

  insert into app.stations
    (id,provider_id,category_id,name_ar,name_en,slug,station_source,stream_type,stream_url,
     timezone,rights_status,commercial_use_status)
  values
    (station_a,provider_id,category_id,'اختبار تخزين ترتيل أ','Tarteel Storage Test A',
     'storage-test-tarteel-a','INTERNAL','INTERNAL','https://radio.example.test/storage-a','UTC','APPROVED','ALLOWED'),
    (station_b,provider_id,category_id,'اختبار تخزين ترتيل ب','Tarteel Storage Test B',
     'storage-test-tarteel-b','INTERNAL','INTERNAL','https://radio.example.test/storage-b','UTC','APPROVED','ALLOWED');

  insert into app.media (id,station_id,title,original_path,file_size_bytes,status) values
    (media_valid,station_a,'Valid upload',null,1024,'UPLOADING'),
    (media_invalid,station_a,'Invalid MIME',null,1024,'UPLOADING'),
    (media_large,station_a,'Oversized',null,52428801,'UPLOADING'),
    (media_cross,station_a,'Cross station',null,1024,'UPLOADING'),
    (media_expired,station_a,'Expired intent',null,1024,'UPLOADING'),
    (media_bad_key,station_a,'Bad key',null,1024,'UPLOADING'),
    (media_flac,station_a,'FLAC source',null,2048,'UPLOADING');

  select (app.create_media_upload_intent(media_valid,station_a,'sample.mp3','mp3','audio/mpeg',1024,
         'storage-test-valid',null,'storage-phase-test')).id into intent_id;
  insert into storage_test_results values
    ('authorized_service_intent_succeeds',intent_id is not null,'trusted service actor');

  select (app.create_media_upload_intent(media_valid,station_a,'sample.mp3','mp3','audio/mpeg',1024,
         'storage-test-valid',null,'storage-phase-test')).id into repeated_intent_id;
  insert into storage_test_results values
    ('idempotent_intent_reuse',repeated_intent_id=intent_id,'same key returns same intent');

  begin
    perform app.create_media_upload_intent(media_valid,station_a,'sample.mp3','mp3','audio/mpeg',1024,
      'storage-test-second',null,'storage-phase-test');
    insert into storage_test_results values ('second_active_intent_rejected',false,'unexpectedly accepted');
  exception when others then insert into storage_test_results values ('second_active_intent_rejected',true,sqlstate); end;

  begin
    perform app.create_media_upload_intent(media_invalid,station_a,'script.exe','exe','application/octet-stream',1024,
      'storage-test-mime',null,'storage-phase-test');
    insert into storage_test_results values ('invalid_mime_rejected',false,'unexpectedly accepted');
  exception when others then insert into storage_test_results values ('invalid_mime_rejected',true,sqlstate); end;

  begin
    perform app.create_media_upload_intent(media_large,station_a,'large.wav','wav','audio/wav',52428801,
      'storage-test-large',null,'storage-phase-test');
    insert into storage_test_results values ('oversized_file_rejected',false,'unexpectedly accepted');
  exception when others then insert into storage_test_results values ('oversized_file_rejected',true,sqlstate); end;

  begin
    perform app.create_media_upload_intent(media_invalid,station_a,'../escape.mp3','mp3','audio/mpeg',1024,
      'storage-test-filename',null,'storage-phase-test');
    insert into storage_test_results values ('unsafe_filename_rejected',false,'unexpectedly accepted');
  exception when others then insert into storage_test_results values ('unsafe_filename_rejected',true,sqlstate); end;

  begin
    perform app.create_media_upload_intent(media_cross,station_b,'cross.mp3','mp3','audio/mpeg',1024,
      'storage-test-cross',null,'storage-phase-test');
    insert into storage_test_results values ('cross_station_intent_rejected',false,'unexpectedly accepted');
  exception when others then insert into storage_test_results values ('cross_station_intent_rejected',true,sqlstate); end;

  begin
    insert into app.media (station_id,title,original_path,file_size_bytes,status)
      values (external_station_id,'External invalid upload',null,1024,'UPLOADING');
    insert into storage_test_results values ('external_station_media_rejected',false,'unexpectedly accepted');
  exception when others then insert into storage_test_results values ('external_station_media_rejected',true,sqlstate); end;

  select (app.create_media_upload_intent(media_expired,station_a,'expired.aac','aac','audio/aac',1024,
         'storage-test-expired',null,'storage-phase-test')).id into signed_intent_id;
  update app.media_upload_intents set created_at=now()-interval '1 hour',expires_at=now()-interval '30 minutes'
    where id=signed_intent_id;
  begin
    perform app.mark_media_upload_signed(signed_intent_id);
    insert into storage_test_results values ('expired_intent_rejected',false,'unexpectedly signed');
  exception when others then insert into storage_test_results values ('expired_intent_rejected',true,sqlstate); end;

  begin
    insert into app.media_upload_intents
      (media_id,station_id,object_key,original_filename,extension,declared_mime_type,
       expected_size_bytes,idempotency_key,created_by_service,expires_at)
    values
      (media_bad_key,station_a,'../invalid/path.mp3','bad.mp3','mp3','audio/mpeg',1024,
       'storage-test-bad-key','storage-phase-test',now()+interval '15 minutes');
    insert into storage_test_results values ('invalid_object_key_rejected',false,'unexpectedly accepted');
  exception when others then insert into storage_test_results values ('invalid_object_key_rejected',true,sqlstate); end;

  select (app.create_media_upload_intent(media_flac,station_a,'lossless.flac','flac','audio/flac',2048,
         'storage-test-flac',null,'storage-phase-test')).id into signed_intent_id;
  insert into storage_test_results values ('flac_source_allowed',signed_intent_id is not null,'source-only format');

  select (app.mark_media_upload_signed(intent_id)).id into signed_intent_id;
  begin
    perform app.complete_media_upload(intent_id);
    insert into storage_test_results values ('completion_requires_real_object',false,'completed without object');
  exception when others then insert into storage_test_results values ('completion_requires_real_object',true,sqlstate); end;

  insert into storage_test_results
  select 'upload_does_not_mark_ready',status='UPLOADING'::app.media_status,'intent alone leaves media UPLOADING'
  from app.media where id=media_valid;

  insert into storage_test_results values
    ('original_bucket_private',
     (select not public from storage.buckets where id='tarteel-media-originals'),'private bucket');
  insert into storage_test_results values
    ('processed_bucket_private',
     (select not public from storage.buckets where id='tarteel-media-processed'),'private bucket');
  insert into storage_test_results values
    ('artwork_bucket_public_read',
     (select public from storage.buckets where id='tarteel-artwork'),'public retrieval; writes remain protected');

  delete from app.audit_logs where metadata->>'created_by_service'='storage-phase-test';
  delete from app.media_upload_intents where media_id in
    (media_valid,media_invalid,media_large,media_cross,media_expired,media_bad_key,media_flac);
  delete from app.media where id in
    (media_valid,media_invalid,media_large,media_cross,media_expired,media_bad_key,media_flac);
  delete from app.stations where id in (station_a,station_b);
end $$;

select test_name,passed,detail from storage_test_results order by test_name;

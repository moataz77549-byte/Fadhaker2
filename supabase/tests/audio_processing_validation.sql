-- Phase 4 database-side concurrency, lease, fencing, retry and READY guards.
create temporary table audio_processing_test_results (
  test_name text primary key,
  passed boolean not null,
  detail text not null
) on commit drop;

do $$
declare
  media_a uuid := gen_random_uuid();
  media_b uuid := gen_random_uuid();
  upload_a uuid := gen_random_uuid();
  upload_b uuid := gen_random_uuid();
  claim_a record;
  claim_a_recovered record;
  claim_b record;
  claim_b_retry record;
  second_claim record;
  recovered_count integer;
begin
  insert into app.media
    (id,title,original_path,original_bucket,original_filename,original_mime_type,
     original_object_version,upload_completed_at,file_size_bytes,status)
  values
    (media_a,'Audio processing DB fixture A',
     'media/'||media_a||'/original/'||upload_a||'.mp3','tarteel-media-originals',
     'fixture-a.mp3','audio/mpeg','fixture-v1',now(),32000,'UPLOADED'),
    (media_b,'Audio processing DB fixture B',
     'media/'||media_b||'/original/'||upload_b||'.wav','tarteel-media-originals',
     'fixture-b.wav','audio/wav','fixture-v1',now(),176400,'UPLOADED');

  select * into claim_a from app.claim_media_processing_job('audio-worker-test-a','test',
    'AUDIO_STANDARD_V1',300,2::smallint);
  insert into audio_processing_test_results values
    ('atomic_claim_returns_job',claim_a.job_id is not null,'UPLOADED -> PROCESSING atomically');

  select * into second_claim from app.claim_media_processing_job('audio-worker-test-b','test',
    'AUDIO_STANDARD_V1',300,2::smallint);
  insert into audio_processing_test_results values
    ('two_workers_do_not_claim_same_media',second_claim.media_id is distinct from claim_a.media_id,
     'SKIP LOCKED selected a different media row');
  claim_b := second_claim;

  perform app.heartbeat_media_processing_job(claim_a.job_id,claim_a.attempt_id,
    'audio-worker-test-a',claim_a.claim_token,300);
  insert into audio_processing_test_results values
    ('heartbeat_extends_lease',exists(select 1 from app.media_processing_jobs
      where id=claim_a.job_id and heartbeat_at is not null and lease_expires_at>heartbeat_at),
     'lease heartbeat accepted');

  begin
    perform app.heartbeat_media_processing_job(claim_a.job_id,claim_a.attempt_id,
      'audio-worker-test-b',claim_a.claim_token,300);
    insert into audio_processing_test_results values ('wrong_worker_fenced',false,'unexpectedly accepted');
  exception when others then
    insert into audio_processing_test_results values ('wrong_worker_fenced',true,sqlstate);
  end;

  update app.media_processing_jobs set lease_expires_at=now()-interval '1 second'
    where id=claim_a.job_id;
  select count(*) into recovered_count from app.recover_stale_media_processing_jobs(10);
  insert into audio_processing_test_results values
    ('stale_job_recovered',recovered_count=1 and exists(select 1 from app.media_processing_jobs
      where id=claim_a.job_id and status='RETRY_WAIT'),'expired lease recovered exactly once');

  select * into claim_a_recovered from app.claim_media_processing_job('audio-worker-test-c','test',
    'AUDIO_STANDARD_V1',300,2::smallint);
  insert into audio_processing_test_results values
    ('reclaim_increments_fencing_token',claim_a_recovered.job_id=claim_a.job_id
      and claim_a_recovered.claim_token>claim_a.claim_token,'old worker token invalidated');

  begin
    perform app.record_media_probe(claim_a.job_id,claim_a.attempt_id,'audio-worker-test-a',
      claim_a.claim_token,repeat('a',64),'mp3','mp3',2000::bigint,44100,2::smallint,
      128,32000::bigint,5,'{}'::jsonb);
    insert into audio_processing_test_results values ('stale_probe_write_fenced',false,'unexpectedly accepted');
  exception when others then
    insert into audio_processing_test_results values ('stale_probe_write_fenced',true,sqlstate);
  end;

  perform app.record_media_probe(claim_a_recovered.job_id,claim_a_recovered.attempt_id,
    'audio-worker-test-c',claim_a_recovered.claim_token,repeat('a',64),'mp3','mp3',2000::bigint,
    44100,2::smallint,128,32000::bigint,5,'{"fixture":true}'::jsonb);
  insert into audio_processing_test_results values
    ('probe_metadata_recorded',exists(select 1 from app.media_processing_attempts
      where id=claim_a_recovered.attempt_id and input_sha256=repeat('a',64)),'trusted ffprobe fields stored');

  begin
    perform app.complete_media_processing_job(claim_a_recovered.job_id,claim_a_recovered.attempt_id,
      'audio-worker-test-c',claim_a_recovered.claim_token,'tarteel-media-processed',
      'media/'||claim_a_recovered.media_id||'/processed/audio-standard-v1/v1/'||claim_a_recovered.attempt_id||'.m4a',
      repeat('b',64),'mov,mp4,m4a,3gp,3g2,mj2','audio/mp4','aac',96,44100,2::smallint,
      2000::bigint,24000::bigint,100,'{}'::jsonb);
    insert into audio_processing_test_results values ('ready_requires_storage_object',false,'unexpected READY');
  exception when others then
    insert into audio_processing_test_results values ('ready_requires_storage_object',
      (select status<>'READY' from app.media where id=claim_a_recovered.media_id),sqlstate);
  end;

  perform app.fail_media_processing_job(claim_a_recovered.job_id,claim_a_recovered.attempt_id,
    'audio-worker-test-c',claim_a_recovered.claim_token,'OUTPUT_INVALID','fixture terminal failure',5);
  insert into audio_processing_test_results values
    ('terminal_failure_never_ready',exists(select 1 from app.media
      where id=claim_a_recovered.media_id and status='FAILED'),
     'OUTPUT_INVALID is not retried');

  perform app.fail_media_processing_job(claim_b.job_id,claim_b.attempt_id,'audio-worker-test-b',
    claim_b.claim_token,'STORAGE_FAILED','fixture transient failure',5);
  insert into audio_processing_test_results values
    ('transient_failure_waits_for_retry',exists(select 1 from app.media_processing_jobs
      where id=claim_b.job_id and status='RETRY_WAIT' and last_error_retryable),
     'bounded retry state');
  update app.media_processing_jobs set next_attempt_at=now() where id=claim_b.job_id;
  select * into claim_b_retry from app.claim_media_processing_job('audio-worker-test-d','test',
    'AUDIO_STANDARD_V1',300,2::smallint);
  perform app.fail_media_processing_job(claim_b_retry.job_id,claim_b_retry.attempt_id,
    'audio-worker-test-d',claim_b_retry.claim_token,'STORAGE_FAILED','retry exhausted',5);
  insert into audio_processing_test_results values
    ('retry_exhaustion_fails_media',exists(select 1 from app.media_processing_jobs
      where id=claim_b.job_id and status='FAILED' and attempts=2),'max attempts enforced');

  insert into app.media
    (title,original_path,original_bucket,original_filename,original_mime_type,
     original_object_version,upload_completed_at,file_size_bytes,status,sha256)
  values
    ('Duplicate checksum fixture','media/'||gen_random_uuid()||'/original/'||gen_random_uuid()||'.mp3',
     'tarteel-media-originals','duplicate.mp3','audio/mpeg','fixture-v1',now(),1,'FAILED',repeat('a',64));
  insert into audio_processing_test_results values
    ('duplicate_checksum_detected_not_blocked',(select count(*)>=2 from app.media where sha256=repeat('a',64)),
     'non-unique checksum index permits legitimate duplicates');

  begin
    execute 'set local role anon';
    perform app.claim_media_processing_job('unauthorized-worker','test','AUDIO_STANDARD_V1',300,2::smallint);
    execute 'reset role';
    insert into audio_processing_test_results values ('anonymous_claim_denied',false,'unexpectedly accepted');
  exception when others then
    execute 'reset role';
    insert into audio_processing_test_results values ('anonymous_claim_denied',true,sqlstate);
  end;

  begin
    execute 'set local role authenticated';
    perform app.claim_media_processing_job('unauthorized-auth-worker','test','AUDIO_STANDARD_V1',300,2::smallint);
    execute 'reset role';
    insert into audio_processing_test_results values ('authenticated_claim_denied',false,'unexpectedly accepted');
  exception when others then
    execute 'reset role';
    insert into audio_processing_test_results values ('authenticated_claim_denied',true,sqlstate);
  end;

  insert into audio_processing_test_results values
    ('processing_tables_rls_fail_closed',
     (select count(*)=4 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='app' and c.relname in ('processing_profiles','processing_error_codes',
        'media_processing_attempts','processed_media_variants') and c.relrowsecurity)
     and not has_table_privilege('anon','app.media_processing_attempts','INSERT')
     and not has_table_privilege('authenticated','app.processed_media_variants','UPDATE'),
     'RLS enabled; anonymous/authenticated table writes absent');

  delete from app.audit_logs where resource_id in (media_a::text,media_b::text)
     or metadata->>'job_id' in (claim_a.job_id::text,claim_b.job_id::text);
  delete from app.media where id in (media_a,media_b) or title='Duplicate checksum fixture';
end $$;

select test_name,passed,detail from audio_processing_test_results order by test_name;

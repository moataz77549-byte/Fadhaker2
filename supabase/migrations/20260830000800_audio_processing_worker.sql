-- Phase 4: durable audio processing queue, attempts, profiles and processed variants.
-- Queue operations are exposed only to the trusted service_role through SECURITY INVOKER RPCs.

create type app.processing_job_status as enum
  ('PENDING','PROCESSING','RETRY_WAIT','COMPLETED','FAILED','CANCELLED');
create type app.processing_attempt_status as enum
  ('PROCESSING','COMPLETED','FAILED','ABANDONED');
create type app.processed_variant_status as enum
  ('AVAILABLE','ORPHANED','DELETED');

create table app.processing_profiles (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  version smallint not null check (version > 0),
  output_container text not null,
  output_extension text not null check (output_extension ~ '^[a-z0-9]+$'),
  output_mime_type text not null,
  output_codec text not null,
  bitrate_kbps integer not null check (bitrate_kbps between 32 and 512),
  sample_rate_hz integer not null check (sample_rate_hz between 8000 and 192000),
  channels smallint not null check (channels between 1 and 8),
  loudness_i_lufs numeric(5,2) not null,
  loudness_tp_dbtp numeric(5,2) not null,
  loudness_lra_lu numeric(5,2) not null,
  max_duration_ms bigint not null check (max_duration_ms > 0),
  max_output_size_bytes bigint not null check (max_output_size_bytes > 0),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (code, version),
  check (code ~ '^[A-Z][A-Z0-9_]*$'),
  check (output_mime_type ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$')
);

insert into app.processing_profiles
  (code,version,output_container,output_extension,output_mime_type,output_codec,
   bitrate_kbps,sample_rate_hz,channels,loudness_i_lufs,loudness_tp_dbtp,
   loudness_lra_lu,max_duration_ms,max_output_size_bytes,metadata)
values
  ('AUDIO_STANDARD_V1',1,'mov,mp4,m4a,3gp,3g2,mj2','m4a','audio/mp4','aac',
   96,44100,2,-16.00,-1.50,11.00,3600000,52428800,
   '{"normalization":"ebu_r128_two_pass","quran_audio_policy":"no_trim_no_tempo_no_pitch_no_crossfade"}'::jsonb);

alter table app.storage_upload_formats
  add column ffprobe_format_names text[] not null default '{}'::text[],
  add column allowed_audio_codecs text[] not null default '{}'::text[],
  add column allow_video_stream boolean not null default false;

update app.storage_upload_formats set
  ffprobe_format_names = case extension
    when 'mp3' then array['mp3']
    when 'm4a' then array['mov','mp4','m4a','3gp','3g2','mj2']
    when 'aac' then array['aac']
    when 'wav' then array['wav']
    when 'flac' then array['flac']
  end,
  allowed_audio_codecs = case extension
    when 'mp3' then array['mp3']
    when 'm4a' then array['aac']
    when 'aac' then array['aac']
    when 'wav' then array['pcm_s16le','pcm_s24le','pcm_s32le','pcm_f32le']
    when 'flac' then array['flac']
  end;

alter table app.storage_upload_formats
  alter column ffprobe_format_names drop default,
  alter column allowed_audio_codecs drop default,
  add constraint storage_upload_formats_probe_rules_check
    check (cardinality(ffprobe_format_names) > 0 and cardinality(allowed_audio_codecs) > 0);

create table app.processing_error_codes (
  code text primary key check (code ~ '^[A-Z][A-Z0-9_]*$'),
  retryable boolean not null,
  description text not null,
  created_at timestamptz not null default now()
);

insert into app.processing_error_codes(code,retryable,description) values
  ('INVALID_MEDIA',false,'Input is not a valid supported media file'),
  ('UNSUPPORTED_FORMAT',false,'Container or codec is not allowed'),
  ('NO_AUDIO_STREAM',false,'No audio stream was detected'),
  ('VIDEO_STREAM_REJECTED',false,'MVP rejects containers containing video'),
  ('CORRUPT_INPUT',false,'Input is corrupt or structurally invalid'),
  ('DURATION_LIMIT_EXCEEDED',false,'Input duration exceeds the active profile limit'),
  ('INPUT_SIZE_MISMATCH',false,'Downloaded bytes differ from the recorded upload size'),
  ('OBJECT_KEY_MISMATCH',false,'Original object identity does not match the media record'),
  ('DOWNLOAD_FAILED',true,'Original download failed transiently'),
  ('STORAGE_FAILED',true,'Storage operation failed transiently'),
  ('FFPROBE_FAILED',false,'ffprobe could not parse the input'),
  ('FFPROBE_TIMEOUT',true,'ffprobe exceeded its deadline'),
  ('PROCESSING_TIMEOUT',true,'FFmpeg exceeded its deadline'),
  ('FFMPEG_FAILED',false,'FFmpeg failed deterministically'),
  ('OUTPUT_INVALID',false,'Processed output failed verification'),
  ('DATABASE_FAILED',true,'Database operation failed transiently'),
  ('WORKER_INTERNAL_ERROR',true,'Unexpected worker failure');

alter table app.media_processing_jobs
  alter column status type app.processing_job_status using (
    case status::text
      when 'PROCESSING' then 'PROCESSING'
      when 'READY' then 'COMPLETED'
      when 'FAILED' then 'FAILED'
      when 'ARCHIVED' then 'CANCELLED'
      else 'PENDING'
    end::app.processing_job_status
  ),
  add column profile_id uuid references app.processing_profiles(id) on delete restrict,
  add column priority integer not null default 0,
  add column max_attempts smallint not null default 3 check (max_attempts between 1 and 10),
  add column next_attempt_at timestamptz not null default now(),
  add column lease_expires_at timestamptz,
  add column claim_token bigint not null default 0 check (claim_token >= 0),
  add column worker_version text,
  add column completed_at timestamptz,
  add column failed_at timestamptz,
  add column last_error_retryable boolean,
  add column recovery_count integer not null default 0 check (recovery_count >= 0);

update app.media_processing_jobs j
set profile_id = p.id
from app.processing_profiles p
where p.code='AUDIO_STANDARD_V1' and p.version=1 and j.profile_id is null;

alter table app.media_processing_jobs
  alter column profile_id set not null,
  add constraint media_processing_jobs_media_profile_unique unique (media_id,profile_id),
  add constraint media_processing_jobs_lease_check check (
    (status='PROCESSING' and claimed_by is not null and claimed_at is not null
      and heartbeat_at is not null and lease_expires_at is not null)
    or status<>'PROCESSING'
  ),
  add constraint media_processing_jobs_terminal_check check (
    (status='COMPLETED') = (completed_at is not null)
    and (status='FAILED') = (failed_at is not null)
  );

create table app.media_processing_attempts (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references app.media_processing_jobs(id) on delete cascade,
  media_id uuid not null references app.media(id) on delete cascade,
  attempt_number smallint not null check (attempt_number > 0),
  claim_token bigint not null check (claim_token > 0),
  worker_id text not null,
  worker_version text not null,
  status app.processing_attempt_status not null default 'PROCESSING',
  started_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),
  ended_at timestamptz,
  input_sha256 text check (input_sha256 is null or input_sha256 ~ '^[0-9a-f]{64}$'),
  detected_format text,
  detected_codec text,
  duration_ms bigint check (duration_ms is null or duration_ms > 0),
  sample_rate_hz integer check (sample_rate_hz is null or sample_rate_hz > 0),
  channels smallint check (channels is null or channels between 1 and 8),
  source_bitrate_kbps integer check (source_bitrate_kbps is null or source_bitrate_kbps > 0),
  source_size_bytes bigint check (source_size_bytes is null or source_size_bytes > 0),
  ffprobe_duration_ms integer check (ffprobe_duration_ms is null or ffprobe_duration_ms >= 0),
  ffmpeg_duration_ms integer check (ffmpeg_duration_ms is null or ffmpeg_duration_ms >= 0),
  error_code text references app.processing_error_codes(code) on delete restrict,
  error_message text,
  diagnostics jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (job_id,attempt_number),
  unique (job_id,claim_token),
  check ((status='PROCESSING') = (ended_at is null)),
  check (length(worker_id) between 3 and 128 and worker_id ~ '^[A-Za-z0-9._:-]+$'),
  check (length(worker_version) between 1 and 64)
);

create table app.processed_media_variants (
  id uuid primary key default gen_random_uuid(),
  media_id uuid not null references app.media(id) on delete restrict,
  job_id uuid not null references app.media_processing_jobs(id) on delete restrict,
  attempt_id uuid not null references app.media_processing_attempts(id) on delete restrict,
  profile_id uuid not null references app.processing_profiles(id) on delete restrict,
  bucket_id text not null default 'tarteel-media-processed'
    check (bucket_id='tarteel-media-processed'),
  object_key text not null unique,
  storage_object_id uuid,
  storage_object_version text,
  status app.processed_variant_status not null default 'AVAILABLE',
  format text not null,
  mime_type text not null,
  codec text not null,
  bitrate_kbps integer not null check (bitrate_kbps > 0),
  sample_rate_hz integer not null check (sample_rate_hz > 0),
  channels smallint not null check (channels between 1 and 8),
  duration_ms bigint not null check (duration_ms > 0),
  size_bytes bigint not null check (size_bytes > 0),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (job_id,attempt_id)
);

create index media_processing_jobs_claim_idx
  on app.media_processing_jobs (profile_id,priority desc,next_attempt_at,created_at,id)
  where status in ('PENDING','RETRY_WAIT');
create index media_processing_jobs_stale_idx
  on app.media_processing_jobs (lease_expires_at,id) where status='PROCESSING';
create index media_processing_attempts_media_time_idx
  on app.media_processing_attempts (media_id,started_at desc);
create index media_processing_attempts_error_idx
  on app.media_processing_attempts (error_code,started_at desc) where error_code is not null;
create index processed_media_variants_media_idx
  on app.processed_media_variants (media_id,created_at desc) where status='AVAILABLE';
create index processed_media_variants_profile_idx on app.processed_media_variants (profile_id);
create index processed_media_variants_attempt_idx on app.processed_media_variants (attempt_id);
create index media_sha256_idx on app.media (sha256) where sha256 is not null and deleted_at is null;

create trigger processing_profiles_updated_at before update on app.processing_profiles
for each row execute function app.set_updated_at();
create trigger media_processing_attempts_updated_at before update on app.media_processing_attempts
for each row execute function app.set_updated_at();
create trigger processed_media_variants_updated_at before update on app.processed_media_variants
for each row execute function app.set_updated_at();

alter table app.processing_profiles enable row level security;
alter table app.processing_error_codes enable row level security;
alter table app.media_processing_attempts enable row level security;
alter table app.processed_media_variants enable row level security;
revoke all on app.processing_profiles,app.processing_error_codes,
  app.media_processing_attempts,app.processed_media_variants from public,anon,authenticated;
grant select,insert,update,delete on app.processing_profiles,app.processing_error_codes,
  app.media_processing_attempts,app.processed_media_variants to service_role;

create function app.claim_media_processing_job(
  p_worker_id text,
  p_worker_version text,
  p_profile_code text default 'AUDIO_STANDARD_V1',
  p_lease_seconds integer default 300,
  p_max_attempts smallint default 3
) returns table (
  job_id uuid, attempt_id uuid, media_id uuid, claim_token bigint,
  original_bucket text, original_path text, original_object_version text,
  original_filename text, declared_mime_type text, expected_size_bytes bigint,
  source_extension text, allowed_formats text[], allowed_codecs text[],
  profile jsonb
)
language plpgsql security invoker set search_path='' as $$
declare
  v_job app.media_processing_jobs;
  v_media app.media;
  v_profile app.processing_profiles;
  v_attempt_id uuid;
  v_extension text;
  v_formats text[];
  v_codecs text[];
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted worker context required' using errcode='42501';
  end if;
  if p_worker_id is null or length(p_worker_id) not between 3 and 128
     or p_worker_id !~ '^[A-Za-z0-9._:-]+$' then raise exception 'invalid worker id'; end if;
  if p_worker_version is null or length(p_worker_version) not between 1 and 64 then
    raise exception 'invalid worker version';
  end if;
  if p_lease_seconds not between 60 and 3600 then raise exception 'invalid lease duration'; end if;
  if p_max_attempts not between 1 and 10 then raise exception 'invalid max attempts'; end if;

  select * into v_profile from app.processing_profiles
  where code=upper(p_profile_code) and is_active order by version desc limit 1;
  if not found then raise exception 'active processing profile not found'; end if;

  select j.* into v_job
  from app.media_processing_jobs j
  where j.profile_id=v_profile.id and j.status in ('PENDING','RETRY_WAIT')
    and j.next_attempt_at<=now() and j.attempts<j.max_attempts
  order by j.priority desc,j.next_attempt_at,j.created_at,j.id
  for update of j skip locked limit 1;

  if found then
    select * into v_media from app.media where id=v_job.media_id for update;
    if v_media.status not in ('UPLOADED','PROCESSING') or v_media.deleted_at is not null then
      update app.media_processing_jobs set status='CANCELLED',claimed_by=null,lease_expires_at=null
      where id=v_job.id;
      return;
    end if;
  else
    select m.* into v_media
    from app.media m
    where m.status='UPLOADED' and m.deleted_at is null
      and m.original_bucket='tarteel-media-originals' and m.original_path is not null
      and not exists (select 1 from app.media_processing_jobs j
                      where j.media_id=m.id and j.profile_id=v_profile.id)
    order by m.created_at,m.id
    for update of m skip locked limit 1;
    if not found then return; end if;

    insert into app.media_processing_jobs
      (media_id,idempotency_key,status,attempts,profile_version,profile_id,priority,
       max_attempts,next_attempt_at)
    values
      (v_media.id,v_media.id::text||':'||v_profile.id::text||':'||coalesce(v_media.original_object_version,'unversioned'),
       'PENDING',0,v_profile.code||':v'||v_profile.version,v_profile.id,0,p_max_attempts,now())
    returning * into v_job;
  end if;

  update app.media_processing_jobs as claimed_job set
    status='PROCESSING',attempts=claimed_job.attempts+1,claimed_by=p_worker_id,claimed_at=now(),
    heartbeat_at=now(),lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
    claim_token=claimed_job.claim_token+1,worker_version=p_worker_version,error_code=null,
    error_message=null,last_error_retryable=null,completed_at=null,failed_at=null
  where id=v_job.id returning * into v_job;

  update app.media set status='PROCESSING',failure_code=null,failure_message=null
  where id=v_media.id and status in ('UPLOADED','PROCESSING');
  if not found then raise exception 'media could not enter PROCESSING'; end if;

  insert into app.media_processing_attempts
    (job_id,media_id,attempt_number,claim_token,worker_id,worker_version)
  values (v_job.id,v_media.id,v_job.attempts,v_job.claim_token,p_worker_id,p_worker_version)
  returning id into v_attempt_id;

  select lower(regexp_replace(v_media.original_path,'^.*\.','','g')) into v_extension;
  select f.ffprobe_format_names,f.allowed_audio_codecs into v_formats,v_codecs
  from app.storage_upload_formats f
  where f.extension=v_extension and f.mime_type=v_media.original_mime_type and f.is_active;
  if not found then raise exception 'active source format configuration not found'; end if;

  insert into app.audit_logs(action,resource_type,resource_id,metadata)
  values ('PROCESSING_CLAIMED','media',v_media.id::text,
          jsonb_build_object('job_id',v_job.id,'attempt_id',v_attempt_id,
            'worker_id',p_worker_id,'claim_token',v_job.claim_token,'profile_id',v_profile.id));

  return query select v_job.id,v_attempt_id,v_media.id,v_job.claim_token,
    v_media.original_bucket,v_media.original_path,v_media.original_object_version,
    v_media.original_filename,v_media.original_mime_type,v_media.file_size_bytes,
    v_extension,v_formats,v_codecs,
    jsonb_build_object('id',v_profile.id,'code',v_profile.code,'version',v_profile.version,
      'container',v_profile.output_container,'extension',v_profile.output_extension,
      'mime_type',v_profile.output_mime_type,'codec',v_profile.output_codec,
      'bitrate_kbps',v_profile.bitrate_kbps,'sample_rate_hz',v_profile.sample_rate_hz,
      'channels',v_profile.channels,'loudness_i_lufs',v_profile.loudness_i_lufs,
      'loudness_tp_dbtp',v_profile.loudness_tp_dbtp,'loudness_lra_lu',v_profile.loudness_lra_lu,
      'max_duration_ms',v_profile.max_duration_ms,'max_output_size_bytes',v_profile.max_output_size_bytes);
end $$;

create function app.heartbeat_media_processing_job(
  p_job_id uuid,p_attempt_id uuid,p_worker_id text,p_claim_token bigint,p_lease_seconds integer default 300
) returns timestamptz
language plpgsql security invoker set search_path='' as $$
declare v_expiry timestamptz;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted worker context required' using errcode='42501';
  end if;
  if p_lease_seconds not between 60 and 3600 then raise exception 'invalid lease duration'; end if;
  update app.media_processing_jobs set heartbeat_at=now(),
    lease_expires_at=now()+make_interval(secs=>p_lease_seconds)
  where id=p_job_id and status='PROCESSING' and claimed_by=p_worker_id
    and claim_token=p_claim_token and lease_expires_at>now()
  returning lease_expires_at into v_expiry;
  if not found then raise exception 'processing lease lost' using errcode='55000'; end if;
  update app.media_processing_attempts set heartbeat_at=now()
  where id=p_attempt_id and job_id=p_job_id and claim_token=p_claim_token and status='PROCESSING';
  if not found then raise exception 'processing attempt is not active'; end if;
  return v_expiry;
end $$;

create function app.record_media_probe(
  p_job_id uuid,p_attempt_id uuid,p_worker_id text,p_claim_token bigint,
  p_sha256 text,p_detected_format text,p_detected_codec text,p_duration_ms bigint,
  p_sample_rate_hz integer,p_channels smallint,p_source_bitrate_kbps integer,
  p_source_size_bytes bigint,p_ffprobe_duration_ms integer,p_diagnostics jsonb default '{}'::jsonb
) returns void
language plpgsql security invoker set search_path='' as $$
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted worker context required' using errcode='42501';
  end if;
  if not exists (select 1 from app.media_processing_jobs where id=p_job_id and status='PROCESSING'
    and claimed_by=p_worker_id and claim_token=p_claim_token and lease_expires_at>now()) then
    raise exception 'processing lease lost' using errcode='55000';
  end if;
  update app.media_processing_attempts set input_sha256=p_sha256,
    detected_format=left(p_detected_format,100),detected_codec=left(p_detected_codec,100),
    duration_ms=p_duration_ms,sample_rate_hz=p_sample_rate_hz,channels=p_channels,
    source_bitrate_kbps=p_source_bitrate_kbps,source_size_bytes=p_source_size_bytes,
    ffprobe_duration_ms=p_ffprobe_duration_ms,diagnostics=coalesce(p_diagnostics,'{}'::jsonb)
  where id=p_attempt_id and job_id=p_job_id and claim_token=p_claim_token and status='PROCESSING';
  if not found then raise exception 'processing attempt is not active'; end if;
  update app.media set sha256=p_sha256 where id=(select media_id from app.media_processing_jobs where id=p_job_id);
  insert into app.audit_logs(action,resource_type,resource_id,metadata)
  select 'FFPROBE_VALIDATED','media',media_id::text,
    jsonb_build_object('job_id',p_job_id,'attempt_id',p_attempt_id,'format',p_detected_format,'codec',p_detected_codec)
  from app.media_processing_jobs where id=p_job_id;
end $$;

create function app.fail_media_processing_job(
  p_job_id uuid,p_attempt_id uuid,p_worker_id text,p_claim_token bigint,
  p_error_code text,p_error_message text default null,p_retry_delay_seconds integer default 30
) returns app.processing_job_status
language plpgsql security invoker set search_path='' as $$
declare v_job app.media_processing_jobs; v_retryable boolean; v_status app.processing_job_status;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted worker context required' using errcode='42501';
  end if;
  select * into v_job from app.media_processing_jobs where id=p_job_id for update;
  if not found or v_job.status<>'PROCESSING' or v_job.claimed_by<>p_worker_id
     or v_job.claim_token<>p_claim_token then
    raise exception 'processing lease lost' using errcode='55000';
  end if;
  select retryable into v_retryable from app.processing_error_codes where code=p_error_code;
  if not found then raise exception 'unknown processing error code'; end if;
  if p_retry_delay_seconds not between 5 and 86400 then raise exception 'invalid retry delay'; end if;

  update app.media_processing_attempts set status='FAILED',ended_at=now(),
    error_code=p_error_code,error_message=left(p_error_message,2000)
  where id=p_attempt_id and job_id=p_job_id and claim_token=p_claim_token and status='PROCESSING';
  if not found then raise exception 'processing attempt is not active'; end if;

  if v_retryable and v_job.attempts<v_job.max_attempts then
    v_status := 'RETRY_WAIT';
    update app.media_processing_jobs set status=v_status,next_attempt_at=now()+make_interval(secs=>p_retry_delay_seconds),
      claimed_by=null,claimed_at=null,heartbeat_at=null,lease_expires_at=null,
      error_code=p_error_code,error_message=left(p_error_message,2000),last_error_retryable=true
    where id=p_job_id;
    update app.media set status='UPLOADED',failure_code=p_error_code,
      failure_message=left(p_error_message,1000) where id=v_job.media_id and status='PROCESSING';
  else
    v_status := 'FAILED';
    update app.media_processing_jobs set status=v_status,failed_at=now(),
      claimed_by=null,heartbeat_at=null,lease_expires_at=null,error_code=p_error_code,
      error_message=left(p_error_message,2000),last_error_retryable=v_retryable
    where id=p_job_id;
    update app.media set status='FAILED',failure_code=p_error_code,
      failure_message=left(p_error_message,1000) where id=v_job.media_id and status='PROCESSING';
  end if;
  insert into app.audit_logs(action,resource_type,resource_id,metadata)
  values ('PROCESSING_FAILED','media',v_job.media_id::text,
    jsonb_build_object('job_id',p_job_id,'attempt_id',p_attempt_id,'error_code',p_error_code,
      'retryable',v_retryable,'job_status',v_status));
  return v_status;
end $$;

create function app.recover_stale_media_processing_jobs(p_limit integer default 50)
returns table(job_id uuid,media_id uuid,new_status app.processing_job_status)
language plpgsql security invoker set search_path='' as $$
declare v_job app.media_processing_jobs; v_status app.processing_job_status;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted worker context required' using errcode='42501';
  end if;
  if p_limit not between 1 and 500 then raise exception 'invalid recovery limit'; end if;
  for v_job in
    select j.* from app.media_processing_jobs j
    where j.status='PROCESSING' and j.lease_expires_at<=now()
    order by j.lease_expires_at,j.id for update of j skip locked limit p_limit
  loop
    update app.media_processing_attempts as stale_attempt set status='ABANDONED',ended_at=now(),
      error_code='WORKER_INTERNAL_ERROR',error_message='processing lease expired'
    where stale_attempt.job_id=v_job.id and stale_attempt.claim_token=v_job.claim_token
      and stale_attempt.status='PROCESSING';
    if v_job.attempts<v_job.max_attempts then
      v_status='RETRY_WAIT';
      update app.media_processing_jobs set status=v_status,next_attempt_at=now(),
        claimed_by=null,claimed_at=null,heartbeat_at=null,lease_expires_at=null,
        error_code='WORKER_INTERNAL_ERROR',error_message='processing lease expired',
        last_error_retryable=true,recovery_count=recovery_count+1 where id=v_job.id;
      update app.media set status='UPLOADED',failure_code='WORKER_INTERNAL_ERROR',
        failure_message='processing lease expired' where id=v_job.media_id and status='PROCESSING';
    else
      v_status='FAILED';
      update app.media_processing_jobs set status=v_status,failed_at=now(),
        claimed_by=null,heartbeat_at=null,lease_expires_at=null,
        error_code='WORKER_INTERNAL_ERROR',error_message='retry exhaustion after stale lease',
        last_error_retryable=true,recovery_count=recovery_count+1 where id=v_job.id;
      update app.media set status='FAILED',failure_code='WORKER_INTERNAL_ERROR',
        failure_message='retry exhaustion after stale lease' where id=v_job.media_id and status='PROCESSING';
    end if;
    insert into app.audit_logs(action,resource_type,resource_id,metadata)
    values ('PROCESSING_STALE_RECOVERED','media',v_job.media_id::text,
      jsonb_build_object('job_id',v_job.id,'claim_token',v_job.claim_token,'new_status',v_status));
    job_id:=v_job.id; media_id:=v_job.media_id; new_status:=v_status; return next;
  end loop;
end $$;

create function app.complete_media_processing_job(
  p_job_id uuid,p_attempt_id uuid,p_worker_id text,p_claim_token bigint,
  p_bucket_id text,p_object_key text,p_output_sha256 text,p_output_format text,
  p_output_mime_type text,p_output_codec text,p_output_bitrate_kbps integer,
  p_output_sample_rate_hz integer,p_output_channels smallint,p_output_duration_ms bigint,
  p_output_size_bytes bigint,p_ffmpeg_duration_ms integer,p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security invoker set search_path='' as $$
declare
  v_job app.media_processing_jobs; v_profile app.processing_profiles;
  v_attempt app.media_processing_attempts; v_object storage.objects; v_variant_id uuid;
  v_expected_key text; v_storage_size bigint; v_storage_mime text;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted worker context required' using errcode='42501';
  end if;
  select * into v_job from app.media_processing_jobs where id=p_job_id for update;
  if not found or v_job.status<>'PROCESSING' or v_job.claimed_by<>p_worker_id
     or v_job.claim_token<>p_claim_token or v_job.lease_expires_at<=now() then
    raise exception 'processing lease lost' using errcode='55000';
  end if;
  select * into v_attempt from app.media_processing_attempts
    where id=p_attempt_id and job_id=p_job_id and claim_token=p_claim_token and status='PROCESSING' for update;
  if not found or v_attempt.input_sha256 is null then raise exception 'validated attempt not found'; end if;
  select * into v_profile from app.processing_profiles where id=v_job.profile_id;
  v_expected_key := 'media/'||v_job.media_id::text||'/processed/'||lower(replace(v_profile.code,'_','-'))
                    ||'/v'||v_profile.version::text||'/'||p_attempt_id::text||'.'||v_profile.output_extension;
  if p_bucket_id<>'tarteel-media-processed' or p_object_key<>v_expected_key then
    raise exception 'processed object key mismatch';
  end if;
  if p_output_format<>v_profile.output_container or p_output_mime_type<>v_profile.output_mime_type
     or p_output_codec<>v_profile.output_codec or p_output_bitrate_kbps<>v_profile.bitrate_kbps
     or p_output_sample_rate_hz<>v_profile.sample_rate_hz or p_output_channels<>v_profile.channels
     or p_output_duration_ms>v_profile.max_duration_ms or p_output_size_bytes>v_profile.max_output_size_bytes then
    raise exception 'processed output does not match profile';
  end if;
  if abs(p_output_duration_ms-v_attempt.duration_ms)>greatest(250,(v_attempt.duration_ms*0.001)::bigint) then
    raise exception 'processed duration drift exceeds tolerance';
  end if;
  select * into v_object from storage.objects where bucket_id=p_bucket_id and name=p_object_key
    and archived_at is null and not is_delete_marker;
  if not found then raise exception 'processed object not found'; end if;
  v_storage_size:=nullif(v_object.metadata->>'size','')::bigint;
  v_storage_mime:=lower(coalesce(v_object.metadata->>'mimetype',''));
  if v_storage_size<>p_output_size_bytes or v_storage_mime<>p_output_mime_type then
    raise exception 'processed Storage metadata mismatch';
  end if;
  if lower(coalesce(v_object.user_metadata->>'sha256',''))<>p_output_sha256 then
    raise exception 'processed Storage checksum metadata mismatch';
  end if;

  insert into app.processed_media_variants
    (media_id,job_id,attempt_id,profile_id,bucket_id,object_key,storage_object_id,
     storage_object_version,format,mime_type,codec,bitrate_kbps,sample_rate_hz,
     channels,duration_ms,size_bytes,sha256,metadata)
  values
    (v_job.media_id,p_job_id,p_attempt_id,v_profile.id,p_bucket_id,p_object_key,v_object.id,
     v_object.version,p_output_format,p_output_mime_type,p_output_codec,p_output_bitrate_kbps,
     p_output_sample_rate_hz,p_output_channels,p_output_duration_ms,p_output_size_bytes,
     p_output_sha256,coalesce(p_metadata,'{}'::jsonb))
  on conflict (job_id,attempt_id) do update set metadata=excluded.metadata
  returning id into v_variant_id;

  update app.media_processing_attempts set status='COMPLETED',ended_at=now(),
    ffmpeg_duration_ms=p_ffmpeg_duration_ms where id=p_attempt_id;
  update app.media_processing_jobs set status='COMPLETED',completed_at=now(),
    claimed_by=null,heartbeat_at=null,lease_expires_at=null,error_code=null,error_message=null
    where id=p_job_id;
  update app.media set status='READY',processed_path=p_object_key,
    duration_ms=p_output_duration_ms,format=p_output_format,bitrate_kbps=p_output_bitrate_kbps,
    sample_rate_hz=p_output_sample_rate_hz,channels=p_output_channels,
    processing_profile_version=v_profile.code||':v'||v_profile.version,
    failure_code=null,failure_message=null where id=v_job.media_id and status='PROCESSING';
  if not found then raise exception 'media could not enter READY'; end if;

  insert into app.audit_logs(action,resource_type,resource_id,metadata)
  values ('MEDIA_READY','media',v_job.media_id::text,
    jsonb_build_object('job_id',p_job_id,'attempt_id',p_attempt_id,'variant_id',v_variant_id,
      'profile',v_profile.code||':v'||v_profile.version,'object_key',p_object_key));
  return v_variant_id;
end $$;

revoke all on function app.claim_media_processing_job(text,text,text,integer,smallint) from public,anon,authenticated;
revoke all on function app.heartbeat_media_processing_job(uuid,uuid,text,bigint,integer) from public,anon,authenticated;
revoke all on function app.record_media_probe(uuid,uuid,text,bigint,text,text,text,bigint,integer,smallint,integer,bigint,integer,jsonb) from public,anon,authenticated;
revoke all on function app.fail_media_processing_job(uuid,uuid,text,bigint,text,text,integer) from public,anon,authenticated;
revoke all on function app.recover_stale_media_processing_jobs(integer) from public,anon,authenticated;
revoke all on function app.complete_media_processing_job(uuid,uuid,text,bigint,text,text,text,text,text,text,integer,integer,smallint,bigint,bigint,integer,jsonb) from public,anon,authenticated;
grant execute on function app.claim_media_processing_job(text,text,text,integer,smallint) to service_role;
grant execute on function app.heartbeat_media_processing_job(uuid,uuid,text,bigint,integer) to service_role;
grant execute on function app.record_media_probe(uuid,uuid,text,bigint,text,text,text,bigint,integer,smallint,integer,bigint,integer,jsonb) to service_role;
grant execute on function app.fail_media_processing_job(uuid,uuid,text,bigint,text,text,integer) to service_role;
grant execute on function app.recover_stale_media_processing_jobs(integer) to service_role;
grant execute on function app.complete_media_processing_job(uuid,uuid,text,bigint,text,text,text,text,text,text,integer,integer,smallint,bigint,bigint,integer,jsonb) to service_role;

insert into app.app_config(key,value,value_type,is_public,description) values
  ('audio_worker_concurrency','1','INTEGER',false,'Concurrent jobs per DEVELOPMENT worker'),
  ('audio_worker_lease_seconds','300','INTEGER',false,'Processing lease duration'),
  ('audio_worker_heartbeat_seconds','30','INTEGER',false,'Heartbeat interval'),
  ('audio_worker_processing_timeout_seconds','900','INTEGER',false,'FFmpeg deadline per pass'),
  ('audio_worker_probe_timeout_seconds','30','INTEGER',false,'ffprobe deadline'),
  ('audio_worker_max_attempts','3','INTEGER',false,'Bounded processing attempts'),
  ('audio_worker_profile','"AUDIO_STANDARD_V1"','STRING',false,'Active processing profile code')
on conflict (key) do update set value=excluded.value,value_type=excluded.value_type,
  is_public=excluded.is_public,description=excluded.description;

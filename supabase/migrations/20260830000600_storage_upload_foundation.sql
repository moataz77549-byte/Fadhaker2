create type app.upload_intent_status as enum
  ('PENDING','SIGNED','UPLOADING','COMPLETED','EXPIRED','FAILED','CANCELLED');

alter table app.media
  add column station_id uuid references app.stations(id) on delete restrict,
  add column original_bucket text,
  add column original_filename text,
  add column original_mime_type text,
  add column original_object_version text,
  add column upload_completed_at timestamptz,
  alter column original_path drop not null;

alter table app.media add constraint media_original_storage_check check (
  (status = 'UPLOADING' and original_path is null and original_bucket is null and upload_completed_at is null)
  or
  (status in ('UPLOADED','PROCESSING','READY','FAILED','ARCHIVED') and (
    (original_path is null and original_bucket is null and upload_completed_at is null)
    or
    (original_path is not null and original_bucket = 'tarteel-media-originals'
      and original_mime_type is not null and upload_completed_at is not null)
  ))
);

create index media_station_time_idx on app.media (station_id, created_at desc)
  where station_id is not null and deleted_at is null;

create trigger media_internal_station
before insert or update of station_id on app.media
for each row when (new.station_id is not null)
execute function app.require_internal_station();

create table app.storage_upload_formats (
  extension text not null check (extension ~ '^[a-z0-9]+$'),
  mime_type text not null check (mime_type ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  max_size_bytes bigint not null check (max_size_bytes > 0),
  is_active boolean not null default true,
  description text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (extension, mime_type)
);

insert into app.storage_upload_formats
  (extension, mime_type, max_size_bytes, description)
values
  ('mp3','audio/mpeg',52428800,'MPEG Layer III source'),
  ('m4a','audio/mp4',52428800,'MPEG-4 audio container'),
  ('m4a','audio/x-m4a',52428800,'MPEG-4 audio alternate MIME'),
  ('aac','audio/aac',52428800,'Raw or ADTS AAC source'),
  ('wav','audio/wav',52428800,'WAVE source'),
  ('wav','audio/x-wav',52428800,'WAVE alternate MIME'),
  ('flac','audio/flac',52428800,'Lossless FLAC source'),
  ('flac','audio/x-flac',52428800,'Lossless FLAC alternate MIME');

create table app.media_upload_intents (
  id uuid primary key default gen_random_uuid(),
  media_id uuid not null references app.media(id) on delete restrict,
  station_id uuid references app.stations(id) on delete restrict,
  bucket_id text not null default 'tarteel-media-originals'
    check (bucket_id = 'tarteel-media-originals'),
  object_key text not null unique,
  original_filename text not null check (length(original_filename) between 1 and 255),
  extension text not null,
  declared_mime_type text not null,
  expected_size_bytes bigint not null check (expected_size_bytes between 1 and 52428800),
  status app.upload_intent_status not null default 'PENDING',
  idempotency_key text not null check (length(idempotency_key) between 8 and 128),
  created_by uuid references app.administrators(id) on delete restrict,
  created_by_service text,
  signed_at timestamptz,
  expires_at timestamptz not null,
  completed_at timestamptz,
  failed_at timestamptz,
  failure_code text,
  failure_message text,
  storage_object_id uuid,
  storage_object_version text,
  actual_size_bytes bigint check (actual_size_bytes is null or actual_size_bytes > 0),
  actual_mime_type text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (media_id, idempotency_key),
  foreign key (extension, declared_mime_type)
    references app.storage_upload_formats(extension, mime_type) on delete restrict,
  check ((created_by is not null) <> (created_by_service is not null)),
  check (created_by_service is null or created_by_service ~ '^[a-z0-9][a-z0-9._-]{2,63}$'),
  check (expires_at > created_at),
  check (object_key ~ ('^media/' || media_id::text || '/original/' || id::text || '\\.' || extension || '$')),
  check ((status = 'COMPLETED') = (completed_at is not null)),
  check ((status = 'FAILED') = (failed_at is not null))
);

create unique index media_upload_one_active_idx on app.media_upload_intents (media_id)
  where status in ('PENDING','SIGNED','UPLOADING');
create index media_upload_expiry_idx on app.media_upload_intents (expires_at, id)
  where status in ('PENDING','SIGNED','UPLOADING');
create index media_upload_station_time_idx on app.media_upload_intents (station_id, created_at desc)
  where station_id is not null;

create trigger media_upload_intents_updated_at before update on app.media_upload_intents
for each row execute function app.set_updated_at();
create trigger storage_upload_formats_updated_at before update on app.storage_upload_formats
for each row execute function app.set_updated_at();

alter table app.storage_upload_formats enable row level security;
alter table app.media_upload_intents enable row level security;
revoke all on app.storage_upload_formats, app.media_upload_intents from public, anon, authenticated;
grant select, insert, update, delete on app.storage_upload_formats, app.media_upload_intents to service_role;

create function app.create_media_upload_intent(
  p_media_id uuid,
  p_station_id uuid,
  p_original_filename text,
  p_extension text,
  p_declared_mime_type text,
  p_expected_size_bytes bigint,
  p_idempotency_key text,
  p_created_by uuid default null,
  p_created_by_service text default null
) returns app.media_upload_intents
language plpgsql security invoker set search_path = '' as $$
declare
  media_row app.media;
  intent_row app.media_upload_intents;
  new_intent_id uuid := gen_random_uuid();
  normalized_extension text := lower(trim(leading '.' from p_extension));
  normalized_mime text := lower(trim(p_declared_mime_type));
  format_limit bigint;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted backend context required' using errcode = '42501';
  end if;
  if (p_created_by is null) = (p_created_by_service is null) then
    raise exception 'exactly one uploader identity is required';
  end if;
  if p_original_filename is null or length(p_original_filename) not between 1 and 255
     or p_original_filename ~ '[[:cntrl:]/\\\\]' then
    raise exception 'invalid original filename';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128
     or p_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'invalid idempotency key';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_media_id::text, 0));
  select * into media_row from app.media where id=p_media_id and deleted_at is null for update;
  if not found then raise exception 'media not found'; end if;
  if media_row.status <> 'UPLOADING'::app.media_status or media_row.original_path is not null then
    raise exception 'media is not accepting an original upload';
  end if;
  if media_row.station_id is distinct from p_station_id then
    raise exception 'station context does not match media ownership';
  end if;
  if p_created_by is not null and not exists (
    select 1 from app.administrators a
    where a.id=p_created_by and a.is_active and a.deleted_at is null
  ) then raise exception 'uploader administrator is not active'; end if;

  select f.max_size_bytes into format_limit
  from app.storage_upload_formats f
  where f.extension=normalized_extension and f.mime_type=normalized_mime and f.is_active;
  if format_limit is null then raise exception 'unsupported extension or MIME type'; end if;
  if p_expected_size_bytes < 1 or p_expected_size_bytes > format_limit then
    raise exception 'file size is outside the allowed range';
  end if;

  update app.media_upload_intents set status='EXPIRED'
  where media_id=p_media_id and status in ('PENDING','SIGNED','UPLOADING') and expires_at <= now();

  select * into intent_row from app.media_upload_intents
  where media_id=p_media_id and idempotency_key=p_idempotency_key;
  if found then
    if intent_row.station_id is distinct from p_station_id
       or intent_row.extension <> normalized_extension
       or intent_row.declared_mime_type <> normalized_mime
       or intent_row.expected_size_bytes <> p_expected_size_bytes then
      raise exception 'idempotency key payload mismatch';
    end if;
    return intent_row;
  end if;
  if exists (select 1 from app.media_upload_intents
             where media_id=p_media_id and status in ('PENDING','SIGNED','UPLOADING')) then
    raise exception 'another active upload intent exists';
  end if;

  insert into app.media_upload_intents
    (id,media_id,station_id,object_key,original_filename,extension,declared_mime_type,
     expected_size_bytes,idempotency_key,created_by,created_by_service,expires_at)
  values
    (new_intent_id,p_media_id,p_station_id,
     'media/'||p_media_id::text||'/original/'||new_intent_id::text||'.'||normalized_extension,
     p_original_filename,normalized_extension,normalized_mime,p_expected_size_bytes,
     p_idempotency_key,p_created_by,p_created_by_service,now()+interval '15 minutes')
  returning * into intent_row;

  insert into app.audit_logs(actor_id,action,resource_type,resource_id,metadata)
  values (p_created_by,'UPLOAD_INTENT_CREATED','media_upload_intent',intent_row.id::text,
          jsonb_build_object('media_id',p_media_id,'bucket',intent_row.bucket_id,
                             'object_key',intent_row.object_key,'expected_size_bytes',p_expected_size_bytes,
                             'created_by_service',p_created_by_service));
  return intent_row;
end $$;

create function app.mark_media_upload_signed(p_intent_id uuid)
returns app.media_upload_intents
language plpgsql security invoker set search_path = '' as $$
declare intent_row app.media_upload_intents;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted backend context required' using errcode = '42501';
  end if;
  select * into intent_row from app.media_upload_intents where id=p_intent_id for update;
  if not found then raise exception 'upload intent not found'; end if;
  if intent_row.status='SIGNED' then return intent_row; end if;
  if intent_row.status<>'PENDING' or intent_row.expires_at<=now() then
    raise exception 'upload intent cannot be signed';
  end if;
  update app.media_upload_intents set status='SIGNED',signed_at=now()
  where id=p_intent_id returning * into intent_row;
  return intent_row;
end $$;

create function app.complete_media_upload(p_intent_id uuid)
returns app.media_upload_intents
language plpgsql security invoker set search_path = '' as $$
declare
  intent_row app.media_upload_intents;
  object_row storage.objects;
  actual_size bigint;
  actual_mime text;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted backend context required' using errcode = '42501';
  end if;
  select * into intent_row from app.media_upload_intents where id=p_intent_id for update;
  if not found then raise exception 'upload intent not found'; end if;
  if intent_row.status='COMPLETED' then return intent_row; end if;
  if intent_row.status not in ('SIGNED','UPLOADING') or intent_row.expires_at<=now() then
    raise exception 'upload intent is not completable';
  end if;

  select * into object_row from storage.objects
  where bucket_id=intent_row.bucket_id and name=intent_row.object_key
    and archived_at is null and not is_delete_marker;
  if not found then raise exception 'uploaded object not found'; end if;
  actual_size := nullif(object_row.metadata->>'size','')::bigint;
  actual_mime := lower(coalesce(object_row.metadata->>'mimetype',''));
  if actual_size is null or actual_size<>intent_row.expected_size_bytes then
    raise exception 'uploaded object size mismatch';
  end if;
  if actual_mime<>intent_row.declared_mime_type or not exists (
    select 1 from app.storage_upload_formats f
    where f.extension=intent_row.extension and f.mime_type=actual_mime
      and f.is_active and actual_size<=f.max_size_bytes
  ) then raise exception 'uploaded object MIME mismatch'; end if;

  update app.media set
    original_bucket=intent_row.bucket_id,
    original_path=intent_row.object_key,
    original_filename=intent_row.original_filename,
    original_mime_type=actual_mime,
    original_object_version=object_row.version,
    file_size_bytes=actual_size,
    upload_completed_at=now(),
    status='UPLOADED'
  where id=intent_row.media_id and status='UPLOADING' and original_path is null;
  if not found then raise exception 'media state changed during upload completion'; end if;

  update app.media_upload_intents set
    status='COMPLETED',completed_at=now(),storage_object_id=object_row.id,
    storage_object_version=object_row.version,actual_size_bytes=actual_size,
    actual_mime_type=actual_mime
  where id=p_intent_id returning * into intent_row;

  insert into app.audit_logs(actor_id,action,resource_type,resource_id,metadata)
  values (intent_row.created_by,'UPLOAD_COMPLETED','media',intent_row.media_id::text,
          jsonb_build_object('intent_id',intent_row.id,'bucket',intent_row.bucket_id,
                             'object_key',intent_row.object_key,'size_bytes',actual_size,
                             'created_by_service',intent_row.created_by_service));
  return intent_row;
end $$;

create function app.fail_media_upload_intent(
  p_intent_id uuid, p_failure_code text, p_failure_message text default null
) returns app.media_upload_intents
language plpgsql security invoker set search_path = '' as $$
declare intent_row app.media_upload_intents;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'trusted backend context required' using errcode = '42501';
  end if;
  update app.media_upload_intents set
    status='FAILED',failed_at=now(),failure_code=left(p_failure_code,100),
    failure_message=left(p_failure_message,1000)
  where id=p_intent_id and status in ('PENDING','SIGNED','UPLOADING')
  returning * into intent_row;
  if not found then raise exception 'upload intent is not fail-able'; end if;
  insert into app.audit_logs(actor_id,action,resource_type,resource_id,metadata)
  values (intent_row.created_by,'UPLOAD_FAILED','media_upload_intent',intent_row.id::text,
          jsonb_build_object('media_id',intent_row.media_id,'failure_code',intent_row.failure_code,
                             'created_by_service',intent_row.created_by_service));
  return intent_row;
end $$;

revoke all on function app.create_media_upload_intent(uuid,uuid,text,text,text,bigint,text,uuid,text) from public,anon,authenticated;
revoke all on function app.mark_media_upload_signed(uuid) from public,anon,authenticated;
revoke all on function app.complete_media_upload(uuid) from public,anon,authenticated;
revoke all on function app.fail_media_upload_intent(uuid,text,text) from public,anon,authenticated;
grant execute on function app.create_media_upload_intent(uuid,uuid,text,text,text,bigint,text,uuid,text) to service_role;
grant execute on function app.mark_media_upload_signed(uuid) to service_role;
grant execute on function app.complete_media_upload(uuid) to service_role;
grant execute on function app.fail_media_upload_intent(uuid,text,text) to service_role;

create view app.upload_cleanup_candidates with (security_invoker=true) as
select i.id,i.media_id,i.bucket_id,i.object_key,i.status,i.expires_at,i.created_at,
       (o.id is not null) as object_exists
from app.media_upload_intents i
left join storage.objects o on o.bucket_id=i.bucket_id and o.name=i.object_key
where (i.status in ('PENDING','SIGNED','UPLOADING') and i.expires_at<=now())
   or (i.status in ('FAILED','CANCELLED','EXPIRED') and i.updated_at<=now()-interval '24 hours');
revoke all on app.upload_cleanup_candidates from public,anon,authenticated;
grant select on app.upload_cleanup_candidates to service_role;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values
  ('tarteel-media-originals','tarteel-media-originals',false,52428800,
   array['audio/mpeg','audio/mp4','audio/x-m4a','audio/aac','audio/wav','audio/x-wav','audio/flac','audio/x-flac']),
  ('tarteel-media-processed','tarteel-media-processed',false,52428800,
   array['audio/mpeg','audio/mp4','audio/aac']),
  ('tarteel-artwork','tarteel-artwork',true,5242880,
   array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types,
  updated_at=now();

insert into app.app_config(key,value,value_type,is_public,description) values
  ('upload_intent_ttl_seconds','900','INTEGER',false,'Server intent validity; signed Storage token may remain valid longer'),
  ('upload_orphan_retention_hours','24','INTEGER',false,'Delay before failed or expired upload cleanup'),
  ('storage_environment','"development"','STRING',false,'Current Supabase Storage environment classification')
on conflict (key) do update set value=excluded.value,value_type=excluded.value_type,
  is_public=excluded.is_public,description=excluded.description;

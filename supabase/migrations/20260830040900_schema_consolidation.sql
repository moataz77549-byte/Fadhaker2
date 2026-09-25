-- ============================================================================
-- 20260830040900_schema_consolidation.sql
--
-- توحيد الـ schema: يُقارب أي حالة قاعدة بيانات إلى الـ schema الموحّد المختار.
--
-- السياق: يوجد جيلان من الـ migrations —
--   * الجيل القديم: 20260101* / 20260201* / 20260301* (quran_yutla)
--   * الجيل الجديد: 20260830* (baseline tarteel/fadhkur المعتمد)
-- زائد الملفات الأربعة الأخيرة 40500..40800.
-- قرارات التوحيد (جدولاً بجدول) موثقة في docs/MIGRATION_CONSOLIDATION.md.
--
-- ضمانات هذا الملف:
--   * Idempotent بالكامل: CREATE TABLE IF NOT EXISTS،
--     ALTER TABLE ... ADD COLUMN IF NOT EXISTS، كتل DO $$ للـ policies،
--     INSERT ... ON CONFLICT DO NOTHING للبيانات.
--   * آمن سواء طُبّقت الملفات السابقة كلها أو بعضها أو لم تُطبَّق.
--   * لا يعدّل ولا يحذف أي migration قديم — التاريخ محفوظ كما هو.
--   * لا أسرار حقيقية هنا إطلاقاً.
--
-- ترتيب التطبيق: يُطبَّق بعد كل الملفات السابقة (supabase db push بالترتيب
-- الزمني، أو SQL Editor بنفس الترتيب). انظر docs/MIGRATION_CONSOLIDATION.md.
-- ============================================================================

-- --------------------------------------------------------------------------
-- A. Extensions & schemas
-- --------------------------------------------------------------------------
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists "uuid-ossp"; -- legacy tables use uuid_generate_v4()

create schema if not exists app;
create schema if not exists radio;
create schema if not exists api;
create schema if not exists extensions;

-- --------------------------------------------------------------------------
-- B. Enums (chosen = new generation; created only when missing)
-- --------------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'media_status' and n.nspname = 'app') then
    create type app.media_status as enum ('UPLOADING','UPLOADED','PROCESSING','READY','FAILED','ARCHIVED');
  end if;
end $$;
-- 'UPLOADED' أُضيفت لاحقاً (00500) — نضمن وجودها في أي قاعدة قديمة.
do $$ begin
  if exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
             where t.typname = 'media_status' and n.nspname = 'app')
     and not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                     join pg_namespace n on n.oid = t.typnamespace
                     where t.typname = 'media_status' and n.nspname = 'app' and e.enumlabel = 'UPLOADED') then
    alter type app.media_status add value if not exists 'UPLOADED' after 'UPLOADING';
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'station_status' and n.nspname = 'app') then
    create type app.station_status as enum ('ONLINE','DEGRADED','OFFLINE','MAINTENANCE');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'schedule_type' and n.nspname = 'app') then
    create type app.schedule_type as enum ('ONE_TIME','DAILY','WEEKLY');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'content_type' and n.nspname = 'app') then
    create type app.content_type as enum ('MEDIA','PLAYLIST','PROGRAM');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'interrupt_policy' and n.nspname = 'app') then
    create type app.interrupt_policy as enum ('FINISH_CURRENT','INTERRUPT','PLAY_NEXT');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'priority_level' and n.nspname = 'app') then
    create type app.priority_level as enum ('LOW','NORMAL','HIGH','EMERGENCY','LIVE');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'station_source' and n.nspname = 'app') then
    create type app.station_source as enum ('INTERNAL','EXTERNAL');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'stream_health_status' and n.nspname = 'app') then
    create type app.stream_health_status as enum ('HEALTHY','DEGRADED','UNREACHABLE','INVALID','UNKNOWN');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'rights_status' and n.nspname = 'app') then
    create type app.rights_status as enum ('UNKNOWN','REVIEW_REQUIRED','APPROVED','RESTRICTED','DISABLED');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'commercial_use_status' and n.nspname = 'app') then
    create type app.commercial_use_status as enum ('UNKNOWN','REVIEW_REQUIRED','ALLOWED','NOT_ALLOWED');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'upload_intent_status' and n.nspname = 'app') then
    create type app.upload_intent_status as enum ('PENDING','SIGNED','UPLOADING','COMPLETED','EXPIRED','FAILED','CANCELLED');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'processing_job_status' and n.nspname = 'app') then
    create type app.processing_job_status as enum ('PENDING','PROCESSING','COMPLETED','FAILED','CANCELLED','RETRY_WAIT');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'processing_attempt_status' and n.nspname = 'app') then
    create type app.processing_attempt_status as enum ('PROCESSING','COMPLETED','FAILED');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'processed_variant_status' and n.nspname = 'app') then
    create type app.processed_variant_status as enum ('AVAILABLE','ARCHIVED');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'command_type' and n.nspname = 'radio') then
    create type radio.command_type as enum ('PLAY_NOW','PLAY_NEXT','SKIP','STOP_AFTER_CURRENT','RESUME_AUTO','START_LIVE','STOP_LIVE');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'command_status' and n.nspname = 'radio') then
    create type radio.command_status as enum ('PENDING','PROCESSING','COMPLETED','FAILED','CANCELLED');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'engine_mode' and n.nspname = 'radio') then
    create type radio.engine_mode as enum ('STARTING','AUTO','SCHEDULED','MANUAL','LIVE','RECOVERING','ERROR','STOPPED');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'occurrence_status' and n.nspname = 'radio') then
    create type radio.occurrence_status as enum ('PENDING','CLAIMED','PLAYING','COMPLETED','SKIPPED','FAILED','CANCELLED');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'queue_source' and n.nspname = 'radio') then
    create type radio.queue_source as enum ('AUTO','SCHEDULED','MANUAL','FALLBACK','EMERGENCY','LIVE');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'queue_status' and n.nspname = 'radio') then
    create type radio.queue_status as enum ('PENDING','DISPATCHED','PLAYING','COMPLETED','FAILED','CANCELLED');
  end if;
end $$;

-- --------------------------------------------------------------------------
-- C. Shared trigger helper
-- --------------------------------------------------------------------------
create or replace function app.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;
revoke all on function app.set_updated_at() from public, anon, authenticated;

-- --------------------------------------------------------------------------
-- D. Core tables — chosen schema (new generation wins on conflicts)
-- --------------------------------------------------------------------------

-- D.1 RBAC (new gen: UUID ids + UPPER_SNAKE_CASE codes)
create table if not exists app.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z_]+$'),
  name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z]+([.:_-][a-z]+)*$'),
  description text not null,
  created_at timestamptz not null default now()
);
create table if not exists app.role_permissions (
  role_id uuid not null references app.roles(id) on delete cascade,
  permission_id uuid not null references app.permissions(id) on delete cascade,
  created_at timestamptz not null default now(), primary key (role_id, permission_id)
);
create table if not exists app.administrators (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null, is_active boolean not null default true,
  last_login_at timestamptz, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table if not exists app.administrator_roles (
  administrator_id uuid not null references app.administrators(id) on delete cascade,
  role_id uuid not null references app.roles(id) on delete restrict,
  granted_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), primary key (administrator_id, role_id)
);

-- Convergence: الشكل القديم لجدول administrators يفتقد أعمدة النموذج الجديد
-- التي يفترضها app.has_permission (is_active / deleted_at) — نضيفها دفاعياً.
alter table app.administrators add column if not exists display_name text;
alter table app.administrators add column if not exists is_active boolean not null default true;
alter table app.administrators add column if not exists updated_at timestamptz not null default now();
alter table app.administrators add column if not exists deleted_at timestamptz;

-- Convergence: قواعد قديمة بالشكل النصي (super_admin…) تحصل على code تلقائياً.
alter table app.roles add column if not exists code text;
alter table app.roles add column if not exists name text;
alter table app.roles add column if not exists updated_at timestamptz not null default now();
alter table app.permissions add column if not exists code text;
alter table app.permissions add column if not exists description text;
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema='app' and table_name='roles' and column_name='code') then
    update app.roles set code = upper(id::text)
      where code is null and pg_typeof(id)::text = 'text';
  end if;
exception when others then
  raise notice 'roles legacy code backfill skipped: %', sqlerrm;
end $$;

-- D.2 Catalog
create table if not exists app.categories (
  id uuid primary key default gen_random_uuid(), parent_id uuid references app.categories(id) on delete restrict,
  slug text not null unique, name_ar text not null, name_en text, description text, icon_key text,
  is_active boolean not null default true, sort_order integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
-- Convergence مع الشكل القديم (icon / is_system): نضيف الأعمدة الناقصة فقط.
alter table app.categories add column if not exists name_ar text;
alter table app.categories add column if not exists name_en text;
alter table app.categories add column if not exists description text;
alter table app.categories add column if not exists icon_key text;
alter table app.categories add column if not exists icon text;
alter table app.categories add column if not exists is_system boolean not null default false;
alter table app.categories add column if not exists is_active boolean not null default true;
alter table app.categories add column if not exists sort_order integer not null default 0;
alter table app.categories add column if not exists parent_id uuid;
alter table app.categories add column if not exists updated_at timestamptz not null default now();
alter table app.categories add column if not exists deleted_at timestamptz;

create table if not exists app.reciters (
  id uuid primary key default gen_random_uuid(), name_ar text not null, name_en text,
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  image_url text, country text, rewaya text, description text,
  search_name_ar text, search_name_en text, is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
-- Convergence مع الأعمدة القديمة (name_arabic / canonical_slug / …).
alter table app.reciters add column if not exists name_ar text;
alter table app.reciters add column if not exists name_en text;
alter table app.reciters add column if not exists slug text;
alter table app.reciters add column if not exists canonical_slug text;
alter table app.reciters add column if not exists name_arabic text;
alter table app.reciters add column if not exists name_english text;
alter table app.reciters add column if not exists canonical_name text;
alter table app.reciters add column if not exists default_riwayah text not null default 'حفص عن عاصم';
alter table app.reciters add column if not exists bio_ar text;
alter table app.reciters add column if not exists bio_en text;
alter table app.reciters add column if not exists bio_arabic text;
alter table app.reciters add column if not exists image_url text;
alter table app.reciters add column if not exists avatar_url text;
alter table app.reciters add column if not exists country text;
alter table app.reciters add column if not exists rewaya text;
alter table app.reciters add column if not exists description text;
alter table app.reciters add column if not exists search_name_ar text;
alter table app.reciters add column if not exists search_name_en text;
alter table app.reciters add column if not exists is_active boolean not null default true;
alter table app.reciters add column if not exists is_featured boolean not null default false;
alter table app.reciters add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table app.reciters add column if not exists primary_provider_id text;
alter table app.reciters add column if not exists updated_at timestamptz not null default now();
alter table app.reciters add column if not exists deleted_at timestamptz;

create table if not exists app.surahs (
  id smallint primary key, number smallint not null unique check (number between 1 and 114),
  name_ar text not null, name_en text not null, ayah_count smallint not null check (ayah_count > 0),
  created_at timestamptz not null default now(), check (id = number)
);

-- D.3 Providers (new gen: content_providers; old app.providers kept below as legacy)
create table if not exists app.content_provider_types (
  code text primary key check (code ~ '^[A-Z][A-Z0-9_]*$'),
  description text not null, created_at timestamptz not null default now()
);
create table if not exists app.stream_types (
  code text primary key check (code ~ '^[A-Z][A-Z0-9_]*$'),
  description text not null, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.content_providers (
  id uuid primary key default gen_random_uuid(),
  name text not null, slug text not null unique,
  provider_type text not null references app.content_provider_types(code) on delete restrict,
  website_url text, api_base_url text, is_active boolean not null default true,
  production_enabled boolean not null default false,
  priority integer not null default 100 check (priority >= 0),
  health_status app.stream_health_status not null default 'UNKNOWN',
  last_checked_at timestamptz, last_success_at timestamptz,
  rights_status app.rights_status not null default 'REVIEW_REQUIRED',
  commercial_use_status app.commercial_use_status not null default 'UNKNOWN',
  attribution_required boolean not null default false, attribution_text text,
  terms_url text, source_url text, verified_at timestamptz, internal_notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  check (not production_enabled or (rights_status = 'APPROVED' and commercial_use_status = 'ALLOWED'))
);

-- D.4 Stations (new gen wins — matches mobile RadioCatalogService columns)
create table if not exists app.stations (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  name_ar text not null, name_en text, search_name_ar text, search_name_en text,
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'), description text, logo_url text,
  category_id uuid references app.categories(id) on delete restrict,
  station_source app.station_source not null,
  stream_type text not null references app.stream_types(code) on delete restrict,
  stream_url text not null, fallback_stream_url text, timezone text,
  status app.station_status not null default 'OFFLINE', default_playlist_id uuid,
  is_active boolean not null default true, is_featured boolean not null default false,
  production_enabled boolean not null default false,
  health_status app.stream_health_status not null default 'UNKNOWN',
  last_health_check timestamptz, last_success_at timestamptz,
  consecutive_failures integer not null default 0 check (consecutive_failures >= 0),
  sort_order integer not null default 0,
  external_key text, last_seen_at timestamptz, source_url text,
  rights_status app.rights_status not null default 'REVIEW_REQUIRED',
  commercial_use_status app.commercial_use_status not null default 'UNKNOWN',
  attribution_required boolean not null default false, attribution_text text,
  terms_url text, rights_verified_at timestamptz, internal_notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (provider_id, external_key),
  check (station_source = 'EXTERNAL' or timezone is not null),
  check (station_source = 'INTERNAL' or default_playlist_id is null),
  check (not production_enabled or (rights_status = 'APPROVED' and commercial_use_status = 'ALLOWED'))
);
-- Convergence مع الشكل القديم (source_type / is_playable / provider_name …).
alter table app.stations add column if not exists name_ar text;
alter table app.stations add column if not exists name_en text;
alter table app.stations add column if not exists logo_url text;
alter table app.stations add column if not exists stream_url text;
alter table app.stations add column if not exists fallback_stream_url text;
alter table app.stations add column if not exists source_type text;
alter table app.stations add column if not exists is_playable boolean not null default true;
alter table app.stations add column if not exists provider_name text;
alter table app.stations add column if not exists country text;
alter table app.stations add column if not exists rights_note text;
alter table app.stations add column if not exists is_active boolean not null default true;
alter table app.stations add column if not exists is_featured boolean not null default false;
alter table app.stations add column if not exists sort_order integer not null default 0;
alter table app.stations add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table app.stations add column if not exists deleted_at timestamptz;
alter table app.stations add column if not exists updated_at timestamptz not null default now();

-- D.5 Media pipeline (new gen)
create table if not exists app.media (
  id uuid primary key default gen_random_uuid(), title text not null, description text,
  category_id uuid references app.categories(id) on delete restrict,
  reciter_id uuid references app.reciters(id) on delete set null,
  station_id uuid references app.stations(id) on delete restrict,
  original_path text, processed_path text unique,
  original_bucket text, original_filename text, original_mime_type text,
  original_object_version text, upload_completed_at timestamptz,
  duration_ms bigint check (duration_ms > 0), format text, bitrate_kbps integer check (bitrate_kbps > 0),
  sample_rate_hz integer check (sample_rate_hz > 0), channels smallint check (channels between 1 and 8),
  file_size_bytes bigint not null check (file_size_bytes > 0), sha256 text check (sha256 ~ '^[0-9a-f]{64}$'),
  status app.media_status not null default 'UPLOADING', processing_profile_version text,
  metadata jsonb not null default '{}'::jsonb, failure_code text, failure_message text,
  created_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  check ((status <> 'READY') or (processed_path is not null and duration_ms is not null and sha256 is not null))
);
create table if not exists app.storage_upload_formats (
  extension text not null check (extension ~ '^[a-z0-9]+$'),
  mime_type text not null check (mime_type ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  max_size_bytes bigint not null check (max_size_bytes > 0),
  is_active boolean not null default true,
  description text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (extension, mime_type)
);
create table if not exists app.media_upload_intents (
  id uuid primary key default gen_random_uuid(),
  media_id uuid not null references app.media(id) on delete restrict,
  station_id uuid references app.stations(id) on delete restrict,
  bucket_id text not null default 'tarteel-media-originals'
    check (bucket_id = 'tarteel-media-originals'),
  object_key text not null,
  extension text not null,
  status app.upload_intent_status not null default 'PENDING',
  expires_at timestamptz not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.processing_profiles (
  id uuid primary key default gen_random_uuid(),
  code text not null, version integer not null default 1,
  description text not null, parameters jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (code, version)
);
create table if not exists app.processing_error_codes (
  code text primary key, retryable boolean not null default false,
  description text not null, created_at timestamptz not null default now()
);
create table if not exists app.media_processing_jobs (
  id uuid primary key default gen_random_uuid(), media_id uuid not null references app.media(id) on delete cascade,
  profile_id uuid references app.processing_profiles(id) on delete restrict,
  idempotency_key text not null unique, status app.processing_job_status not null,
  attempts smallint not null default 0 check (attempts >= 0),
  max_attempts smallint not null default 3 check (max_attempts between 1 and 10),
  priority integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease_expires_at timestamptz,
  claim_token bigint not null default 0 check (claim_token >= 0),
  profile_version text not null default 'AUDIO_STANDARD_V1',
  claimed_by text, claimed_at timestamptz, heartbeat_at timestamptz,
  worker_version text, completed_at timestamptz, failed_at timestamptz,
  last_error_retryable boolean, recovery_count integer not null default 0 check (recovery_count >= 0),
  error_code text, error_message text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.media_processing_attempts (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references app.media_processing_jobs(id) on delete cascade,
  media_id uuid not null references app.media(id) on delete cascade,
  attempt_number smallint not null check (attempt_number > 0),
  claim_token bigint not null check (claim_token > 0),
  worker_id text not null, worker_version text not null,
  status app.processing_attempt_status not null default 'PROCESSING',
  started_at timestamptz not null default now(), heartbeat_at timestamptz not null default now(), ended_at timestamptz,
  error_code text references app.processing_error_codes(code) on delete restrict,
  error_message text, diagnostics jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (job_id, attempt_number), unique (job_id, claim_token)
);
create table if not exists app.processed_media_variants (
  id uuid primary key default gen_random_uuid(),
  media_id uuid not null references app.media(id) on delete restrict,
  job_id uuid not null references app.media_processing_jobs(id) on delete restrict,
  attempt_id uuid not null references app.media_processing_attempts(id) on delete restrict,
  profile_id uuid not null references app.processing_profiles(id) on delete restrict,
  bucket_id text not null default 'tarteel-media-processed' check (bucket_id = 'tarteel-media-processed'),
  object_key text not null unique,
  status app.processed_variant_status not null default 'AVAILABLE',
  format text not null, mime_type text not null, codec text not null,
  bitrate_kbps integer not null check (bitrate_kbps > 0),
  sample_rate_hz integer not null check (sample_rate_hz > 0),
  channels smallint not null check (channels between 1 and 8),
  duration_ms bigint not null check (duration_ms > 0),
  size_bytes bigint not null check (size_bytes > 0),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (job_id, attempt_id)
);
create table if not exists app.reciter_tracks (
  id uuid primary key default gen_random_uuid(), reciter_id uuid not null references app.reciters(id) on delete restrict,
  surah_id smallint not null references app.surahs(id) on delete restrict,
  provider_id uuid references app.content_providers(id) on delete restrict,
  media_id uuid references app.media(id) on delete restrict, audio_url text,
  duration_ms bigint check (duration_ms > 0), quality text not null, rewaya text not null default 'UNKNOWN',
  format text, bitrate_kbps integer check (bitrate_kbps is null or bitrate_kbps > 0),
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((media_id is not null) <> (audio_url is not null))
);

-- D.6 Station automation: playlists / programs / schedules (new gen wins)
create table if not exists app.playlists (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  name text not null, description text, shuffle boolean not null default false, repeat boolean not null default true,
  is_active boolean not null default true, version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (station_id, name), unique (station_id, id)
);
create table if not exists app.playlist_items (
  id uuid primary key default gen_random_uuid(), playlist_id uuid not null references app.playlists(id) on delete cascade,
  media_id uuid not null references app.media(id) on delete restrict,
  position integer not null check (position >= 0), weight integer not null default 1 check (weight > 0),
  created_at timestamptz not null default now(), unique (playlist_id, position)
);
create table if not exists app.programs (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  name text not null, description text, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (station_id, id)
);
create table if not exists app.program_items (
  id uuid primary key default gen_random_uuid(), program_id uuid not null references app.programs(id) on delete cascade,
  media_id uuid not null references app.media(id) on delete restrict, position integer not null check (position >= 0),
  created_at timestamptz not null default now(), unique (program_id, position)
);
create table if not exists app.schedules (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  name text not null, content_type app.content_type not null,
  media_id uuid references app.media(id) on delete restrict, playlist_id uuid,
  program_id uuid, schedule_type app.schedule_type not null,
  start_date date not null, end_date date, start_time time not null, days_of_week smallint[], timezone text not null,
  priority app.priority_level not null default 'NORMAL', interrupt_policy app.interrupt_policy not null default 'FINISH_CURRENT',
  enabled boolean not null default true, next_run_at timestamptz, version integer not null default 1 check (version > 0),
  created_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  check (end_date is null or end_date >= start_date)
);
create table if not exists app.schedule_templates (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  code text not null, name text not null, active_from date, active_to date, is_active boolean not null default false,
  version integer not null default 1, created_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (station_id, code, version)
);
create table if not exists app.schedule_template_items (
  id uuid primary key default gen_random_uuid(), template_id uuid not null references app.schedule_templates(id) on delete cascade,
  definition jsonb not null, position integer not null check (position >= 0), created_at timestamptz not null default now(),
  unique (template_id, position)
);

-- D.7 External catalog & health
create table if not exists app.stream_health_checks (
  id bigint generated always as identity primary key,
  station_id uuid not null references app.stations(id) on delete cascade,
  checked_at timestamptz not null default now(),
  status app.stream_health_status not null,
  http_status integer check (http_status is null or http_status between 100 and 599),
  response_time_ms integer check (response_time_ms is null or response_time_ms >= 0),
  content_type text, detected_stream_type text references app.stream_types(code) on delete restrict,
  audio_detected boolean, bytes_sampled bigint check (bytes_sampled is null or bytes_sampled >= 0),
  error_code text, error_message text, metadata jsonb not null default '{}'::jsonb
);
create table if not exists app.stream_health_jobs (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references app.stations(id) on delete cascade,
  idempotency_key text not null unique,
  status text not null check (status in ('PENDING','PROCESSING','COMPLETED','FAILED','CANCELLED')),
  priority integer not null default 100 check (priority >= 0),
  scheduled_at timestamptz not null default now(), attempts smallint not null default 0 check (attempts >= 0),
  claimed_by text, claimed_at timestamptz, heartbeat_at timestamptz,
  requested_by uuid references app.administrators(id) on delete set null,
  error_code text, error_message text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.provider_sync_runs (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  idempotency_key text not null unique,
  status text not null check (status in ('PENDING','RUNNING','COMPLETED','PARTIAL','FAILED','CANCELLED')),
  claimed_by text, claimed_at timestamptz, heartbeat_at timestamptz,
  started_at timestamptz, finished_at timestamptz,
  fetched_count integer not null default 0, inserted_count integer not null default 0,
  updated_count integer not null default 0, unchanged_count integer not null default 0,
  missing_count integer not null default 0, invalid_count integer not null default 0,
  cursor_data jsonb not null default '{}'::jsonb,
  error_code text, error_message text, metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.provider_station_records (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references app.content_providers(id) on delete restrict,
  station_id uuid not null references app.stations(id) on delete restrict,
  external_key text not null, discovered_name text, discovered_stream_url text,
  normalized_hash text, last_seen_at timestamptz not null,
  missing_since timestamptz, raw_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (provider_id, external_key)
);

-- D.8 Radio runtime (new gen wins — matches radio automation functions)
create table if not exists radio.schedule_occurrences (
  id uuid primary key default gen_random_uuid(), schedule_id uuid not null references app.schedules(id) on delete restrict,
  station_id uuid not null references app.stations(id) on delete restrict, occurrence_key text not null,
  scheduled_for timestamptz not null, local_date date not null, local_time time not null, timezone text not null, fold smallint not null default 0,
  priority app.priority_level not null, interrupt_policy app.interrupt_policy not null,
  status radio.occurrence_status not null default 'PENDING', claimed_by text, claimed_at timestamptz,
  started_at timestamptz, finished_at timestamptz, result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (schedule_id, occurrence_key)
);
create table if not exists radio.radio_commands (
  id uuid primary key default gen_random_uuid(), station_id uuid not null references app.stations(id) on delete restrict,
  command_type radio.command_type not null, payload jsonb not null default '{}'::jsonb,
  priority app.priority_level not null default 'NORMAL', status radio.command_status not null default 'PENDING',
  idempotency_key text not null, created_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), claimed_by text, claimed_at timestamptz,
  executed_at timestamptz, error_code text, error_message text, updated_at timestamptz not null default now(),
  unique (station_id, idempotency_key)
);
create table if not exists radio.station_leases (
  station_id uuid primary key references app.stations(id) on delete cascade,
  owner_id text not null, fencing_token bigint not null check (fencing_token > 0),
  acquired_at timestamptz not null, renewed_at timestamptz not null, expires_at timestamptz not null,
  check (expires_at > renewed_at)
);
create table if not exists radio.engine_states (
  station_id uuid primary key references app.stations(id) on delete cascade,
  mode radio.engine_mode not null, previous_valid_mode radio.engine_mode,
  fencing_token bigint not null, revision bigint not null default 1,
  current_source_type text, current_source_id uuid, current_queue_item_id uuid,
  position_ms bigint check (position_ms is null or position_ms >= 0),
  state_data jsonb not null default '{}'::jsonb, last_checkpoint_at timestamptz not null,
  updated_at timestamptz not null default now()
);
create table if not exists radio.queue_snapshots (
  station_id uuid primary key references app.stations(id) on delete cascade,
  revision bigint not null, fencing_token bigint not null, snapshot jsonb not null,
  checksum text not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists radio.queue_entries (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references app.stations(id) on delete restrict,
  source radio.queue_source not null,
  priority app.priority_level not null,
  interrupt_policy app.interrupt_policy not null default 'FINISH_CURRENT',
  media_id uuid not null references app.media(id) on delete restrict,
  playlist_id uuid references app.playlists(id) on delete restrict,
  playlist_item_id uuid references app.playlist_items(id) on delete restrict,
  occurrence_id uuid references radio.schedule_occurrences(id) on delete restrict,
  command_id uuid references radio.radio_commands(id) on delete restrict,
  idempotency_key text not null,
  status radio.queue_status not null default 'PENDING',
  intended_at timestamptz not null default now(),
  available_at timestamptz not null default now(),
  sequence bigint not null default 0 check (sequence >= 0),
  claimed_by text, claimed_at timestamptz, claimed_fencing_token bigint,
  dispatched_at timestamptz, started_at timestamptz, finished_at timestamptz,
  failure_code text, failure_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (station_id, idempotency_key),
  check (finished_at is null or started_at is null or finished_at >= started_at)
);
create table if not exists radio.command_effects (
  id uuid primary key default gen_random_uuid(),
  command_id uuid not null references radio.radio_commands(id) on delete cascade,
  station_id uuid not null references app.stations(id) on delete cascade,
  effect_type text not null, status text not null,
  payload_hash text, fencing_token bigint,
  created_at timestamptz not null default now(),
  unique (command_id, effect_type)
);
create table if not exists radio.now_playing (
  station_id uuid primary key references app.stations(id) on delete cascade,
  mode radio.engine_mode not null, status app.station_status not null,
  media_id uuid references app.media(id) on delete set null, title text, artist text,
  started_at timestamptz, expected_end_at timestamptz, duration_ms bigint,
  next_media_id uuid references app.media(id) on delete set null, next_title text,
  queue_entry_id uuid references radio.queue_entries(id) on delete set null,
  command_id uuid references radio.radio_commands(id) on delete set null,
  occurrence_id uuid references radio.schedule_occurrences(id) on delete set null,
  playlist_id uuid references app.playlists(id) on delete set null,
  revision bigint not null, updated_at timestamptz not null default now()
);
-- Convergence مع الشكل القديم (reciter_name / surah_name / listeners_count …).
alter table radio.now_playing add column if not exists mode radio.engine_mode;
alter table radio.now_playing add column if not exists status app.station_status;
alter table radio.now_playing add column if not exists media_id uuid;
alter table radio.now_playing add column if not exists title text;
alter table radio.now_playing add column if not exists artist text;
alter table radio.now_playing add column if not exists started_at timestamptz;
alter table radio.now_playing add column if not exists expected_end_at timestamptz;
alter table radio.now_playing add column if not exists duration_ms bigint;
alter table radio.now_playing add column if not exists next_media_id uuid;
alter table radio.now_playing add column if not exists next_title text;
alter table radio.now_playing add column if not exists revision bigint;
alter table radio.now_playing add column if not exists updated_at timestamptz not null default now();
create table if not exists radio.radio_events (
  id bigint generated always as identity primary key, station_id uuid not null references app.stations(id) on delete restrict,
  event_type text not null, command_id uuid references radio.radio_commands(id) on delete set null,
  occurrence_id uuid references radio.schedule_occurrences(id) on delete set null,
  media_id uuid references app.media(id) on delete set null, fencing_token bigint,
  data jsonb not null default '{}'::jsonb, occurred_at timestamptz not null default now()
);
create table if not exists radio.play_history (
  id bigint generated always as identity primary key, station_id uuid not null references app.stations(id) on delete restrict,
  media_id uuid references app.media(id) on delete set null, source_type text not null, source_id uuid,
  started_at timestamptz not null, ended_at timestamptz, result text, played_ms bigint,
  command_id uuid references radio.radio_commands(id) on delete set null,
  occurrence_id uuid references radio.schedule_occurrences(id) on delete set null,
  queue_entry_id uuid references radio.queue_entries(id) on delete set null,
  playlist_id uuid references app.playlists(id) on delete set null,
  playout_id uuid not null default gen_random_uuid(),
  completed_naturally boolean, interrupted boolean not null default false,
  interruption_reason text, fencing_token bigint,
  created_at timestamptz not null default now(),
  unique (playout_id)
);

-- D.9 Runtime config (new gen wins — matches admin settings page + seed 05)
create table if not exists app.app_config (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'), value jsonb not null,
  value_type text not null check (value_type in ('BOOLEAN','INTEGER','STRING','URL','UUID','JSON')),
  is_public boolean not null default false,
  description text, updated_by uuid references app.administrators(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((value_type = 'BOOLEAN' and jsonb_typeof(value) = 'boolean')
      or (value_type = 'INTEGER' and jsonb_typeof(value) = 'number')
      or (value_type in ('STRING','URL','UUID') and jsonb_typeof(value) = 'string')
      or (value_type = 'JSON'))
);
-- Convergence: الشكل القديم (key/value/jsonb بلا value_type) يُستكمل تلقائياً.
alter table app.app_config add column if not exists value jsonb;
alter table app.app_config add column if not exists value_type text;
alter table app.app_config add column if not exists is_public boolean not null default false;
alter table app.app_config add column if not exists description text;
alter table app.app_config add column if not exists created_at timestamptz not null default now();
alter table app.app_config add column if not exists updated_at timestamptz not null default now();
do $$ begin
  -- استنتاج value_type من نوع الـ JSON للصفوف القديمة التي تفتقده.
  if exists (select 1 from information_schema.columns
             where table_schema='app' and table_name='app_config' and column_name='value_type') then
    update app.app_config
       set value_type = case jsonb_typeof(value)
                          when 'boolean' then 'BOOLEAN'
                          when 'number'  then 'INTEGER'
                          when 'string'  then 'STRING'
                          else 'JSON' end
     where value_type is null;
  end if;
exception when others then
  raise notice 'app_config value_type backfill skipped: %', sqlerrm;
end $$;

-- D.10 Audit & ops (new gen wins)
create table if not exists app.audit_logs (
  id bigint generated always as identity primary key, actor_id uuid references app.administrators(id) on delete set null,
  action text not null, resource_type text not null, resource_id text,
  request_id uuid, ip_hash text, old_values jsonb, new_values jsonb,
  metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table if not exists app.system_logs (
  id bigint generated always as identity primary key, timestamp timestamptz not null default now(),
  service text not null, level text not null check (level in ('DEBUG','INFO','WARN','ERROR','FATAL')),
  station_id uuid references app.stations(id) on delete set null, event text not null,
  request_id uuid, command_id uuid, media_id uuid, message text not null, error jsonb, fields jsonb not null default '{}'::jsonb
);
create table if not exists app.service_heartbeats (
  service_instance_id text primary key, service text not null, station_id uuid references app.stations(id) on delete cascade,
  status text not null, version text not null, details jsonb not null default '{}'::jsonb,
  started_at timestamptz not null, last_seen_at timestamptz not null
);
create table if not exists app.station_metrics_minute (
  station_id uuid not null references app.stations(id) on delete cascade, bucket_at timestamptz not null,
  current_listeners integer not null default 0, peak_listeners integer not null default 0,
  stream_errors integer not null default 0, buffering_reports integer not null default 0,
  primary key (station_id, bucket_at)
);

-- --------------------------------------------------------------------------
-- E. Old-generation tables retained (no name conflicts — kept as-is)
-- --------------------------------------------------------------------------

-- E.1 Quran canonical dataset (used for integrity verification; mobile reads
--     surah metadata from app.surahs, full text stays bundled/local)
create table if not exists app.quran_surahs (
  number int primary key check (number between 1 and 114),
  name_ar text not null, name_en text not null,
  revelation_type text not null check (revelation_type in ('meccan', 'medinan')),
  ayah_count int not null,
  page_start int not null check (page_start between 1 and 604),
  page_end int not null check (page_end between 1 and 604)
);
create table if not exists app.quran_ayahs (
  id serial primary key,
  surah_number int not null references app.quran_surahs(number) on delete cascade,
  ayah_number int not null,
  verse_key text not null unique,
  page_number int not null check (page_number between 1 and 604),
  juz_number int not null check (juz_number between 1 and 30),
  hizb_number int not null, ruku_number int not null,
  text_uthmani text not null, text_tajweed text,
  created_at timestamptz not null default now(),
  unique (surah_number, ayah_number)
);
create table if not exists app.quran_pages (
  page_number int primary key check (page_number between 1 and 604),
  edition text not null default 'madinah-hafs-v1',
  asset_path text not null, sha256 text not null,
  width int not null default 1200, height int not null default 1800,
  manifest_version text not null default '1.0.0',
  created_at timestamptz not null default now()
);
-- app.audio_providers must be created BEFORE app.quran_audio_tracks:
-- the latter carries an inline FK reference to it.
create table if not exists app.audio_providers (
  id text primary key, key text not null unique, name text not null,
  base_url text, enabled boolean not null default true, priority int not null default 1,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.quran_audio_tracks (
  id uuid primary key default gen_random_uuid(),
  reciter_id uuid not null references app.reciters(id) on delete cascade,
  provider_id text references app.audio_providers(id) on delete set null,
  surah_number int not null references app.quran_surahs(number) on delete restrict,
  ayah_number int, bitrate int not null default 192,
  audio_url text not null, duration_seconds int not null default 0,
  metadata jsonb not null default '{}'::jsonb, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists app.providers (
  id text primary key, name_arabic text not null, name_english text not null,
  website_url text, license_type text not null default 'Public Waqf / Open Islamic Heritage',
  provenance_details text, is_trusted boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists app.reciter_provider_mappings (
  id uuid primary key default gen_random_uuid(),
  reciter_id uuid not null references app.reciters(id) on delete cascade,
  provider_id text not null references app.audio_providers(id) on delete cascade,
  provider_reciter_id text not null,
  riwayah text not null default 'حفص عن عاصم', moshaf text not null default 'مرتل',
  bitrate int not null default 192, metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  unique (reciter_id, provider_id, riwayah, moshaf)
);

-- E.3 Announcements (richer 202603 shape wins; 202602-only columns converged)
create table if not exists app.announcements (
  id uuid primary key default gen_random_uuid(),
  title_arabic text not null, title_en text not null,
  body_ar text not null, body_en text not null,
  deep_link text not null default '/',
  starts_at timestamptz not null default now(), ends_at timestamptz,
  dismissible boolean not null default true, is_active boolean not null default true,
  priority int not null default 1,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table app.announcements add column if not exists content_arabic text;
alter table app.announcements add column if not exists target_route text not null default '/';
alter table app.announcements add column if not exists is_published boolean not null default true;
alter table app.announcements add column if not exists published_at timestamptz not null default now();
alter table app.announcements add column if not exists expires_at timestamptz;

-- E.4 Notification architecture (202603 shapes — used by notifications Edge Function;
--     operational fields added by 40600 / consolidated in 41100)
create table if not exists app.installations (
  id uuid primary key,
  installation_secret_hash text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  app_version text not null, build_number int not null default 1,
  locale text not null default 'ar', timezone text not null default 'Asia/Riyadh',
  notifications_enabled boolean not null default true,
  firebase_token_encrypted text not null,
  consent_version text not null, consented_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(), revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.notification_preferences (
  installation_id uuid primary key references app.installations(id) on delete cascade,
  prayer_enabled boolean not null default false, adhkar_enabled boolean not null default true,
  learning_enabled boolean not null default true, announcements_enabled boolean not null default true,
  product_updates_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
create table if not exists app.notification_campaigns (
  id uuid primary key default gen_random_uuid(),
  title text not null, body text not null,
  notification_type text not null default 'announcement',
  target_type text not null check (target_type in ('all', 'segment', 'device')),
  target jsonb not null default '{}'::jsonb, payload jsonb not null default '{}'::jsonb,
  scheduled_at timestamptz not null default now(),
  status text not null default 'draft' check (status in ('draft', 'scheduled', 'processing', 'completed', 'cancelled')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists app.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references app.notification_campaigns(id) on delete cascade,
  installation_id uuid not null references app.installations(id) on delete cascade,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed', 'revoked')),
  firebase_message_id text, error_code text, error_message text,
  sent_at timestamptz, delivered_at timestamptz
);
-- قاعدة 202602 للتسجيل/الإلغاء عبر quran-yutla-api (أعمدة مختلفة — تُحفظ كما هي)
create table if not exists app.notification_installations (
  installation_id uuid primary key,
  hashed_secret text not null,
  fcm_token text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  app_version text not null, locale text not null default 'ar', timezone text not null default 'Asia/Riyadh',
  consent_version text not null, consented_at timestamptz not null default now(),
  preferences jsonb not null default '{"prayer_alerts": false, "daily_verse": true, "live_radio_alerts": false}'::jsonb,
  is_active boolean not null default true, revoked_at timestamptz,
  updated_at timestamptz not null default now()
);

-- E.5 User content (legacy, unused by current clients — retained for history)
create table if not exists app.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text, avatar_url text, locale text not null default 'ar',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.featured_items (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('surah', 'reciter', 'station', 'playlist', 'announcement')),
  reference_id text not null, title_ar text not null, title_en text not null,
  subtitle_ar text, subtitle_en text, image_url text,
  sort_order int not null default 0,
  starts_at timestamptz not null default now(), ends_at timestamptz,
  is_active boolean not null default true
);
create table if not exists app.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  installation_id uuid,
  entity_type text not null check (entity_type in ('surah', 'reciter', 'station', 'ayah')),
  entity_id text not null,
  created_at timestamptz not null default now(),
  check (user_id is not null or installation_id is not null)
);
create table if not exists app.playback_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  installation_id uuid,
  content_type text not null check (content_type in ('surah', 'radio', 'track')),
  reference_id text not null,
  reciter_id uuid references app.reciters(id) on delete set null,
  surah_number int, ayah_number int,
  position_seconds int not null default 0,
  played_at timestamptz not null default now()
);
create table if not exists app.external_sources (
  id text primary key, source_type text not null, provider text not null,
  base_url text not null, status text not null default 'active',
  last_checked_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
create table if not exists app.virtual_radio_channels (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique, name text not null,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);
create table if not exists app.virtual_radio_schedule (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references app.virtual_radio_channels(id) on delete cascade,
  day_of_week int not null check (day_of_week between 0 and 6),
  starts_at time not null, ends_at time not null,
  priority int not null default 1, is_active boolean not null default true
);
create table if not exists app.virtual_radio_candidates (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references app.virtual_radio_channels(id) on delete cascade,
  station_id uuid not null references app.stations(id) on delete cascade,
  priority int not null default 1, weight int not null default 100,
  is_active boolean not null default true
);
create table if not exists app.media_assets (
  id uuid primary key default gen_random_uuid(),
  title text not null, media_type text not null default 'audio/mp3',
  storage_bucket text not null, storage_path text not null,
  mime_type text not null default 'audio/mpeg', size_bytes bigint not null default 0,
  sha256 text not null, duration_seconds int not null default 0,
  status text not null default 'UPLOADED' check (status in ('UPLOADED', 'PROCESSING', 'READY', 'FAILED')),
  rights_status text not null default 'OWNED_OR_VERIFIED_WAQF',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.processing_jobs (
  id uuid primary key default gen_random_uuid(),
  media_asset_id uuid not null references app.media_assets(id) on delete cascade,
  job_type text not null default 'EBU_R128_NORMALIZATION',
  status text not null default 'PENDING' check (status in ('PENDING', 'LEASED', 'PROCESSING', 'COMPLETED', 'FAILED')),
  attempt_count int not null default 0, lease_owner text, lease_expires_at timestamptz,
  heartbeat_at timestamptz, error_message text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- E.6 Legacy public-schema tables (20260101) — retained for history; no code use
create table if not exists public.surahs (
  id serial primary key, number int not null unique check (number between 1 and 114),
  name_arabic text not null, name_english text not null, name_transliteration text not null,
  ayah_count int not null,
  revelation_type text not null check (revelation_type in ('meccan', 'medinan')),
  page_number int not null, created_at timestamptz not null default now()
);
create table if not exists public.reciters (
  id uuid primary key default uuid_generate_v4(),
  name_arabic text not null, name_english text not null, slug text not null unique,
  bio_arabic text, rewaya text not null default 'حفص عن عاصم', avatar_url text,
  is_featured boolean not null default false, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.audio_tracks (
  id uuid primary key default uuid_generate_v4(),
  reciter_id uuid not null references public.reciters(id) on delete cascade,
  surah_number int not null references public.surahs(number) on delete restrict,
  audio_url text not null, duration_seconds int not null default 0,
  file_size_bytes bigint not null default 0, bitrate_kbps int not null default 128,
  format text not null default 'mp3', loudness_lufs numeric(5,2) default -16.0,
  waveform jsonb, checksum_sha256 text not null,
  created_at timestamptz not null default now(),
  unique (reciter_id, surah_number)
);
create table if not exists public.radio_stations (
  id uuid primary key default uuid_generate_v4(),
  title_arabic text not null, title_english text not null, slug text not null unique,
  stream_url text not null, fallback_stream_url text,
  status text not null default 'active' check (status in ('active', 'scheduled', 'offline')),
  current_reciter_id uuid references public.reciters(id) on delete set null,
  current_surah_number int references public.surahs(number) on delete set null,
  listeners_count int not null default 0, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.radio_schedules (
  id uuid primary key default uuid_generate_v4(),
  radio_id uuid not null references public.radio_stations(id) on delete cascade,
  audio_track_id uuid not null references public.audio_tracks(id) on delete cascade,
  scheduled_start timestamptz not null, scheduled_end timestamptz not null,
  order_index int not null default 0, created_at timestamptz not null default now()
);
create table if not exists public.app_remote_config (
  id serial primary key, key text not null unique,
  config_value jsonb not null, updated_at timestamptz not null default now()
);
create table if not exists public.audit_logs (
  id uuid primary key default uuid_generate_v4(),
  actor_id uuid, action text not null, resource_type text not null, resource_id text,
  payload jsonb, ip_address text, created_at timestamptz not null default now()
);

-- E.7 Legacy managed radio.stations (202602) — used by quran-yutla-api /stations
create table if not exists radio.stations (
  id uuid primary key default uuid_generate_v4(),
  slug text not null unique, title_arabic text not null, title_english text not null,
  stream_url text not null, fallback_stream_url text,
  bitrate_kbps int not null default 128,
  status text not null default 'active' check (status in ('active', 'paused', 'maintenance')),
  is_featured boolean not null default false, order_index int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists radio.engine_state (
  id text primary key, is_healthy boolean not null default true,
  active_encoder text not null default 'liquidsoap-2.2',
  connected_icecast_nodes int not null default 2,
  last_heartbeat timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- --------------------------------------------------------------------------
-- F. Key indexes (idempotent)
-- --------------------------------------------------------------------------
create index if not exists stations_catalog_idx on app.stations (is_active, production_enabled, health_status, category_id, sort_order) where deleted_at is null;
create index if not exists media_filter_idx on app.media (status, category_id, reciter_id, created_at desc) where deleted_at is null;
create index if not exists schedules_due_idx on app.schedules (next_run_at, priority) where enabled and deleted_at is null;
create index if not exists occurrences_due_idx on radio.schedule_occurrences (station_id, scheduled_for, priority) where status = 'PENDING';
create index if not exists commands_pending_idx on radio.radio_commands (station_id, priority desc, created_at, id) where status = 'PENDING';
create index if not exists audit_resource_idx on app.audit_logs (resource_type, resource_id, created_at desc);
create index if not exists idx_notif_campaigns_status on app.notification_campaigns (status);
create index if not exists idx_notif_campaigns_sched_at on app.notification_campaigns (scheduled_at);

-- --------------------------------------------------------------------------
-- G. RLS: enabled on every app/radio table (fail-closed baseline stays)
-- --------------------------------------------------------------------------
do $$ declare r record; begin
  for r in select schemaname, tablename from pg_tables
           where schemaname in ('app', 'radio') loop
    execute format('alter table %I.%I enable row level security', r.schemaname, r.tablename);
  end loop;
end $$;

-- --------------------------------------------------------------------------
-- H. Helper functions (recreated against the chosen schema)
-- --------------------------------------------------------------------------

-- H.1 Permission check against the new RBAC model (with legacy fallback).
-- Idempotent: create or replace (return type boolean is stable across generations).
create or replace function app.has_permission(p_perm text)
returns boolean language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_admin uuid;
  v_has boolean := false;
  v_legacy_role_col boolean;
begin
  select id into v_admin from app.administrators
   where id = auth.uid() and is_active = true and deleted_at is null;
  if v_admin is null then return false; end if;

  -- New model: administrator_roles -> roles(code)
  if exists (select 1 from information_schema.tables
             where table_schema='app' and table_name='administrator_roles') then
    select exists (
      select 1
        from app.administrator_roles ar
        join app.roles r on r.id = ar.role_id
        left join app.role_permissions rp on rp.role_id = r.id
        left join app.permissions p on p.id = rp.permission_id
       where ar.administrator_id = v_admin
         and (r.code = 'SUPER_ADMIN' or p.code = p_perm)
    ) into v_has;
    if v_has then return true; end if;
  end if;

  -- Legacy fallback: single role_id column on administrators (202602 shape).
  select exists (select 1 from information_schema.columns
                 where table_schema='app' and table_name='administrators'
                   and column_name='role_id') into v_legacy_role_col;
  if v_legacy_role_col then
    execute format(
      'select exists (select 1 from app.administrators a ' ||
      'left join app.roles r on r.id::text = a.role_id::text ' ||
      'left join app.role_permissions rp on rp.role_id::text = a.role_id::text ' ||
      'left join app.permissions p on p.id::text = rp.permission_id::text ' ||
      'where a.id = %L and (r.code = ''SUPER_ADMIN'' or r.id::text = ''super_admin'' or p.code = %L))',
      v_admin, p_perm) into v_has;
    return v_has;
  end if;

  return false;
end $$;
revoke all on function app.has_permission(text) from public, anon, authenticated;

-- H.2 Compatibility alias used by old-generation policies (202603).
-- Idempotent: create or replace (return type boolean is stable).
create or replace function app.admin_has_permission(p_perm text)
returns boolean language sql security definer set search_path = app, pg_temp as $$
  select app.has_permission(p_perm);
$$;
revoke all on function app.admin_has_permission(text) from public, anon, authenticated;

-- H.3 Audit event writer for the new app.audit_logs shape (bigint id, actor_id,
--     request_id uuid). Called by the notifications Edge Function as:
--       app.create_audit_event(p_action, p_resource_type, p_resource_id, p_request_id, p_metadata)
-- Idempotent WITHOUT dropping: the old generation created a UUID-returning
-- variant with the same name — create or replace would fail on return-type
-- mismatch, so the new shape is created only when the function does not exist
-- at all. An existing function (either shape) is respected and left untouched.
do $$ begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'create_audit_event'
  ) then
    create function app.create_audit_event(
      p_action text, p_resource_type text, p_resource_id text,
      p_request_id text, p_metadata jsonb default '{}'::jsonb
    )
    returns bigint language plpgsql security definer set search_path = app, pg_temp as $fn$
    declare
      v_actor uuid;
      v_req uuid;
      v_id bigint;
    begin
      select id into v_actor from app.administrators
       where id = auth.uid() and is_active = true and deleted_at is null;
      begin
        v_req := p_request_id::uuid;
      exception when others then
        v_req := null;
      end;
      insert into app.audit_logs (actor_id, action, resource_type, resource_id, request_id, metadata)
      values (v_actor, p_action, p_resource_type, p_resource_id, v_req, coalesce(p_metadata, '{}'::jsonb))
      returning id into v_id;
      return v_id;
    end $fn$;
    revoke all on function app.create_audit_event(text, text, text, text, jsonb) from public, anon, authenticated;
  else
    raise notice 'app.create_audit_event already exists — kept as-is (no replace).';
  end if;
end $$;

-- --------------------------------------------------------------------------
-- I. Grants (idempotent; service_role = backend workers & Edge Functions)
-- --------------------------------------------------------------------------
grant usage on schema app, radio, api to service_role;
grant select, insert, update, delete on all tables in schema app, radio to service_role;
grant usage, select on all sequences in schema app, radio to service_role;
grant execute on all functions in schema app, radio to service_role;

alter default privileges in schema app grant select, insert, update, delete on tables to service_role;
alter default privileges in schema radio grant select, insert, update, delete on tables to service_role;
alter default privileges in schema app grant usage, select on sequences to service_role;
alter default privileges in schema radio grant usage, select on sequences to service_role;
alter default privileges in schema app grant execute on functions to service_role;
alter default privileges in schema radio grant execute on functions to service_role;

comment on schema app is
  'Unified application schema (consolidated 20260830040900). See docs/MIGRATION_CONSOLIDATION.md.';

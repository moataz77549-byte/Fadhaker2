-- Fadhkur Smart Radio: prayer-aware personalized virtual station.
-- Extends the existing virtual_radio_channels foundation without replacing
-- managed-radio/radio-schedule or the legacy candidate/schedule tables.

alter table app.virtual_radio_channels
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists app.virtual_radio_sources (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references app.virtual_radio_channels(id) on delete cascade,
  program_key text not null check (program_key ~ '^[a-z0-9_]{2,80}$'),
  source_type text not null check (
    source_type in ('LIVE_STATION','RECITER_TRACK','PLAYLIST','MEDIA','ADHKAR_AUDIO')
  ),
  station_id uuid references app.stations(id) on delete restrict,
  reciter_track_id uuid references app.reciter_tracks(id) on delete restrict,
  playlist_id uuid references app.playlists(id) on delete restrict,
  media_id uuid references app.media(id) on delete restrict,
  title_override text,
  priority integer not null default 0,
  weight integer not null default 100 check (weight between 1 and 10000),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint virtual_radio_sources_target_chk check (
    (source_type = 'LIVE_STATION' and station_id is not null
      and reciter_track_id is null and playlist_id is null and media_id is null)
    or
    (source_type = 'RECITER_TRACK' and reciter_track_id is not null
      and station_id is null and playlist_id is null and media_id is null)
    or
    (source_type = 'PLAYLIST' and playlist_id is not null
      and station_id is null and reciter_track_id is null and media_id is null)
    or
    (source_type in ('MEDIA','ADHKAR_AUDIO') and media_id is not null
      and station_id is null and reciter_track_id is null and playlist_id is null)
  )
);

create unique index if not exists virtual_radio_sources_live_unique
  on app.virtual_radio_sources(channel_id, program_key, station_id)
  where station_id is not null;
create unique index if not exists virtual_radio_sources_track_unique
  on app.virtual_radio_sources(channel_id, program_key, reciter_track_id)
  where reciter_track_id is not null;
create index if not exists virtual_radio_sources_pool_idx
  on app.virtual_radio_sources(channel_id, program_key, is_active, priority desc);
create index if not exists virtual_radio_sources_station_idx
  on app.virtual_radio_sources(station_id) where station_id is not null;

create table if not exists app.virtual_radio_rules (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references app.virtual_radio_channels(id) on delete cascade,
  rule_key text not null check (rule_key ~ '^[a-z0-9_]{2,100}$'),
  title_ar text not null,
  trigger_type text not null check (
    trigger_type in ('CLOCK','PRAYER_RELATIVE','DAY_OF_WEEK','FRIDAY',
      'NIGHT_THIRD','SEASONAL','MANUAL_OVERRIDE')
  ),
  prayer_name text check (
    prayer_name is null or prayer_name in ('fajr','dhuhr','asr','maghrib','isha')
  ),
  start_offset_minutes integer check (
    start_offset_minutes is null or start_offset_minutes between -720 and 720
  ),
  end_offset_minutes integer check (
    end_offset_minutes is null or end_offset_minutes between -720 and 720
  ),
  starts_at time,
  ends_at time,
  days_of_week smallint[] not null default '{}'::smallint[],
  priority integer not null default 1,
  source_pool_key text not null check (source_pool_key ~ '^[a-z0-9_]{2,80}$'),
  transition_policy text not null default 'FINISH_ITEM' check (
    transition_policy in ('FINISH_ITEM','SOFT_DEADLINE','IMMEDIATE')
  ),
  refresh_minutes integer not null default 15 check (refresh_minutes between 5 and 120),
  valid_from date,
  valid_until date,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(channel_id, rule_key),
  constraint virtual_radio_rules_days_chk check (
    days_of_week <@ array[1,2,3,4,5,6,7]::smallint[]
  ),
  constraint virtual_radio_rules_validity_chk check (
    valid_until is null or valid_from is null or valid_until >= valid_from
  ),
  constraint virtual_radio_rules_prayer_chk check (
    trigger_type <> 'PRAYER_RELATIVE'
    or (
      prayer_name is not null
      and start_offset_minutes is not null
      and end_offset_minutes is not null
      and end_offset_minutes >= start_offset_minutes
    )
  ),
  constraint virtual_radio_rules_clock_chk check (
    trigger_type <> 'CLOCK' or (starts_at is not null and ends_at is not null)
  )
);

create index if not exists virtual_radio_rules_resolution_idx
  on app.virtual_radio_rules(channel_id, is_active, priority desc);
create index if not exists virtual_radio_rules_channel_idx
  on app.virtual_radio_rules(channel_id);

create table if not exists app.virtual_radio_overrides (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references app.virtual_radio_channels(id) on delete cascade,
  source_id uuid references app.virtual_radio_sources(id) on delete restrict,
  source_pool_key text,
  title_ar text not null,
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  reason text not null check (length(trim(reason)) >= 3),
  transition_policy text not null default 'IMMEDIATE' check (
    transition_policy in ('FINISH_ITEM','SOFT_DEADLINE','IMMEDIATE')
  ),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint virtual_radio_overrides_target_chk check (
    (source_id is not null) <> (source_pool_key is not null)
  ),
  constraint virtual_radio_overrides_expiry_chk check (expires_at > starts_at)
);

create index if not exists virtual_radio_overrides_active_idx
  on app.virtual_radio_overrides(channel_id, starts_at, expires_at)
  where is_active;

-- Cover the legacy smart-radio foreign keys flagged by the DB advisor too.
create index if not exists virtual_radio_candidates_channel_idx
  on app.virtual_radio_candidates(channel_id);
create index if not exists virtual_radio_candidates_station_idx
  on app.virtual_radio_candidates(station_id);
create index if not exists virtual_radio_schedule_channel_idx
  on app.virtual_radio_schedule(channel_id);

-- Updated-at triggers.
drop trigger if exists virtual_radio_channels_set_updated_at on app.virtual_radio_channels;
create trigger virtual_radio_channels_set_updated_at
before update on app.virtual_radio_channels
for each row execute function app.set_updated_at();

drop trigger if exists virtual_radio_sources_set_updated_at on app.virtual_radio_sources;
create trigger virtual_radio_sources_set_updated_at
before update on app.virtual_radio_sources
for each row execute function app.set_updated_at();

drop trigger if exists virtual_radio_rules_set_updated_at on app.virtual_radio_rules;
create trigger virtual_radio_rules_set_updated_at
before update on app.virtual_radio_rules
for each row execute function app.set_updated_at();

drop trigger if exists virtual_radio_overrides_set_updated_at on app.virtual_radio_overrides;
create trigger virtual_radio_overrides_set_updated_at
before update on app.virtual_radio_overrides
for each row execute function app.set_updated_at();

-- RBAC permissions.
insert into app.permissions(code, description) values
  ('smart_radio.read', 'View Smart Fadhkur Radio configuration and previews'),
  ('smart_radio.write', 'Edit Smart Fadhkur Radio rules and source pools'),
  ('smart_radio.publish', 'Enable or disable Smart Fadhkur Radio programming'),
  ('smart_radio.override', 'Create time-limited Smart Fadhkur Radio overrides')
on conflict(code) do update set description=excluded.description;

insert into app.role_permissions(role_id, permission_id)
select r.id, p.id
from app.roles r
join app.permissions p on p.code in (
  'smart_radio.read','smart_radio.write','smart_radio.publish'
)
where r.code in ('SUPER_ADMIN','RADIO_ADMIN')
on conflict do nothing;

insert into app.role_permissions(role_id, permission_id)
select r.id, p.id
from app.roles r
join app.permissions p on p.code='smart_radio.override'
where r.code in ('SUPER_ADMIN','RADIO_ADMIN')
on conflict do nothing;

-- Admin RLS; the mobile client resolves via the Edge Function, not direct table reads.
alter table app.virtual_radio_sources enable row level security;
alter table app.virtual_radio_rules enable row level security;
alter table app.virtual_radio_overrides enable row level security;

drop policy if exists smart_radio_channels_admin_read on app.virtual_radio_channels;
create policy smart_radio_channels_admin_read on app.virtual_radio_channels
for select to authenticated using (
  app.has_permission('smart_radio.read') or app.has_permission('smart_radio.write')
);
drop policy if exists smart_radio_channels_admin_insert on app.virtual_radio_channels;
create policy smart_radio_channels_admin_insert on app.virtual_radio_channels
for insert to authenticated with check (app.has_permission('smart_radio.write'));
drop policy if exists smart_radio_channels_admin_update on app.virtual_radio_channels;
create policy smart_radio_channels_admin_update on app.virtual_radio_channels
for update to authenticated
using (app.has_permission('smart_radio.write'))
with check (app.has_permission('smart_radio.write'));
drop policy if exists smart_radio_channels_admin_delete on app.virtual_radio_channels;
create policy smart_radio_channels_admin_delete on app.virtual_radio_channels
for delete to authenticated using (app.has_permission('smart_radio.write'));

drop policy if exists smart_radio_sources_admin_read on app.virtual_radio_sources;
create policy smart_radio_sources_admin_read on app.virtual_radio_sources
for select to authenticated using (
  app.has_permission('smart_radio.read') or app.has_permission('smart_radio.write')
);
drop policy if exists smart_radio_sources_admin_write on app.virtual_radio_sources;
create policy smart_radio_sources_admin_write on app.virtual_radio_sources
for all to authenticated
using (app.has_permission('smart_radio.write'))
with check (app.has_permission('smart_radio.write'));

drop policy if exists smart_radio_rules_admin_read on app.virtual_radio_rules;
create policy smart_radio_rules_admin_read on app.virtual_radio_rules
for select to authenticated using (
  app.has_permission('smart_radio.read') or app.has_permission('smart_radio.write')
);
drop policy if exists smart_radio_rules_admin_write on app.virtual_radio_rules;
create policy smart_radio_rules_admin_write on app.virtual_radio_rules
for all to authenticated
using (app.has_permission('smart_radio.write'))
with check (app.has_permission('smart_radio.write'));

drop policy if exists smart_radio_overrides_admin_read on app.virtual_radio_overrides;
create policy smart_radio_overrides_admin_read on app.virtual_radio_overrides
for select to authenticated using (app.has_permission('smart_radio.read'));
drop policy if exists smart_radio_overrides_admin_insert on app.virtual_radio_overrides;
create policy smart_radio_overrides_admin_insert on app.virtual_radio_overrides
for insert to authenticated with check (app.has_permission('smart_radio.override'));
drop policy if exists smart_radio_overrides_admin_update on app.virtual_radio_overrides;
create policy smart_radio_overrides_admin_update on app.virtual_radio_overrides
for update to authenticated
using (app.has_permission('smart_radio.override'))
with check (app.has_permission('smart_radio.override'));
drop policy if exists smart_radio_overrides_admin_delete on app.virtual_radio_overrides;
create policy smart_radio_overrides_admin_delete on app.virtual_radio_overrides
for delete to authenticated using (app.has_permission('smart_radio.override'));

-- Canonical personalized channel.
insert into app.virtual_radio_channels(slug,name,is_active,metadata)
values (
  'fadhkur-smart',
  'إذاعة فذكر الذكية',
  true,
  '{"personalized":true,"prayer_aware":true,"privacy":"no_precise_location",
    "description_ar":"محتوى قرآني يتغير حسب وقتك ومواقيت الصلاة"}'::jsonb
)
on conflict(slug) do update
set name=excluded.name,
    metadata=coalesce(app.virtual_radio_channels.metadata,'{}'::jsonb) || excluded.metadata,
    updated_at=now();

-- Seed live sources from the already-public, healthy MP3Quran API-linked catalog.
-- These rows do not change station rights or production_enabled.
with ch as (
  select id from app.virtual_radio_channels where slug='fadhkur-smart'
),
seed(program_key, external_key, weight) as (
  values
    ('qiyam','8',120), ('qiyam','18',110), ('qiyam','38',110),
    ('qiyam','42',100), ('qiyam','58',120),
    ('pre_fajr','8',120), ('pre_fajr','18',110), ('pre_fajr','38',110),
    ('pre_fajr','42',100), ('pre_fajr','58',120),
    ('morning','1',120), ('morning','17',110), ('morning','46',120),
    ('morning','52',100),
    ('daytime','17',100), ('daytime','30',100), ('daytime','32',100),
    ('daytime','33',100), ('daytime','46',100), ('daytime','53',100),
    ('pre_prayer','1',110), ('pre_prayer','33',100), ('pre_prayer','46',120),
    ('evening','2',110), ('evening','8',120), ('evening','46',120),
    ('evening','58',110),
    ('night','2',110), ('night','8',120), ('night','18',100),
    ('night','38',110), ('night','42',100), ('night','58',120),
    ('sleep','2',100), ('sleep','46',120), ('sleep','109060',180),
    ('morning_adhkar','10906',300),
    ('evening_adhkar','10907',300),
    ('friday','17',100), ('friday','33',100), ('friday','46',120),
    ('friday','58',100)
)
insert into app.virtual_radio_sources(
  channel_id,program_key,source_type,station_id,weight,is_active,metadata
)
select ch.id, seed.program_key, 'LIVE_STATION', s.id, seed.weight, true,
  jsonb_build_object(
    'seeded_from','mp3quran_official_api_link',
    'external_key',s.external_key,
    'source_url',s.source_url
  )
from ch
join seed on true
join app.stations s
  on s.external_key=seed.external_key
 and s.source_url='https://www.mp3quran.net/api/v3/radios?language=ar'
 and s.is_active=true and s.is_playable=true and s.deleted_at is null
 and s.health_status='HEALTHY'
on conflict do nothing;

-- Seed rules. Higher priority wins; a rule with no eligible source is skipped.
with ch as (
  select id from app.virtual_radio_channels where slug='fadhkur-smart'
),
rules(
  rule_key,title_ar,trigger_type,prayer_name,start_offset_minutes,end_offset_minutes,
  starts_at,ends_at,days_of_week,priority,source_pool_key,transition_policy,
  refresh_minutes,metadata
) as (
  values
    ('base_day','تلاوات قرآنية','CLOCK',null,null,null,
      '05:30'::time,'19:00'::time,'{}'::smallint[],10,'daytime','SOFT_DEADLINE',20,'{}'::jsonb),
    ('night','تلاوات الليل','CLOCK',null,null,null,
      '19:00'::time,'05:30'::time,'{}'::smallint[],20,'night','SOFT_DEADLINE',15,'{}'::jsonb),
    ('sleep','تلاوات ما قبل النوم','CLOCK',null,null,null,
      '22:30'::time,'02:00'::time,'{}'::smallint[],30,'sleep','SOFT_DEADLINE',15,
      '{"note":"Includes Surah Al-Mulk when available; no fabricated sleep-adhkar audio."}'::jsonb),
    ('last_third','تلاوات الثلث الأخير من الليل','NIGHT_THIRD',null,null,null,
      null,null,'{}'::smallint[],50,'qiyam','SOFT_DEADLINE',10,'{}'::jsonb),
    ('friday','تلاوات يوم الجمعة','FRIDAY',null,null,null,
      null,null,'{}'::smallint[],55,'friday','SOFT_DEADLINE',20,
      '{"note":"General Friday recitation pool until a traceable Surah Al-Kahf source is curated."}'::jsonb),
    ('pre_fajr','تلاوات ما قبل الفجر','PRAYER_RELATIVE','fajr',-45,0,
      null,null,'{}'::smallint[],60,'pre_fajr','SOFT_DEADLINE',10,'{}'::jsonb),
    ('post_fajr','تلاوات الصباح','PRAYER_RELATIVE','fajr',0,45,
      null,null,'{}'::smallint[],65,'morning','SOFT_DEADLINE',10,'{}'::jsonb),
    ('morning_adhkar','أذكار الصباح','PRAYER_RELATIVE','fajr',0,35,
      null,null,'{}'::smallint[],75,'morning_adhkar','SOFT_DEADLINE',10,'{}'::jsonb),
    ('post_maghrib','تلاوات المساء','PRAYER_RELATIVE','maghrib',0,45,
      null,null,'{}'::smallint[],65,'evening','SOFT_DEADLINE',10,'{}'::jsonb),
    ('evening_adhkar','أذكار المساء','PRAYER_RELATIVE','maghrib',0,35,
      null,null,'{}'::smallint[],75,'evening_adhkar','SOFT_DEADLINE',10,'{}'::jsonb),
    ('pre_dhuhr','تلاوة قبل الظهر','PRAYER_RELATIVE','dhuhr',-15,0,
      null,null,'{}'::smallint[],80,'pre_prayer','SOFT_DEADLINE',5,'{}'::jsonb),
    ('pre_asr','تلاوة قبل العصر','PRAYER_RELATIVE','asr',-15,0,
      null,null,'{}'::smallint[],80,'pre_prayer','SOFT_DEADLINE',5,'{}'::jsonb),
    ('pre_maghrib','تلاوة قبل المغرب','PRAYER_RELATIVE','maghrib',-15,0,
      null,null,'{}'::smallint[],80,'pre_prayer','SOFT_DEADLINE',5,'{}'::jsonb),
    ('pre_isha','تلاوة قبل العشاء','PRAYER_RELATIVE','isha',-15,0,
      null,null,'{}'::smallint[],80,'pre_prayer','SOFT_DEADLINE',5,'{}'::jsonb)
)
insert into app.virtual_radio_rules(
  channel_id,rule_key,title_ar,trigger_type,prayer_name,start_offset_minutes,
  end_offset_minutes,starts_at,ends_at,days_of_week,priority,source_pool_key,
  transition_policy,refresh_minutes,metadata
)
select ch.id,r.rule_key,r.title_ar,r.trigger_type,r.prayer_name,
  r.start_offset_minutes,r.end_offset_minutes,r.starts_at,r.ends_at,
  r.days_of_week,r.priority,r.source_pool_key,r.transition_policy,
  r.refresh_minutes,r.metadata
from ch join rules r on true
on conflict(channel_id,rule_key) do update
set title_ar=excluded.title_ar,
    trigger_type=excluded.trigger_type,
    prayer_name=excluded.prayer_name,
    start_offset_minutes=excluded.start_offset_minutes,
    end_offset_minutes=excluded.end_offset_minutes,
    starts_at=excluded.starts_at,
    ends_at=excluded.ends_at,
    days_of_week=excluded.days_of_week,
    priority=excluded.priority,
    source_pool_key=excluded.source_pool_key,
    transition_policy=excluded.transition_policy,
    refresh_minutes=excluded.refresh_minutes,
    metadata=excluded.metadata,
    updated_at=now();

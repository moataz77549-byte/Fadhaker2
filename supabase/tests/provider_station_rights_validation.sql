-- Run against a disposable database or as a transaction-safe validation.
-- Creates no lasting records; checks both closed and approved paths as anon.
begin;
insert into app.stations (
  id, provider_id, name_ar, name_en, slug, station_source,
  stream_type, stream_url, timezone, rights_status, commercial_use_status
)
select gen_random_uuid(), id, 'اختبار بوابة الحقوق', 'Rights gate test',
       'rights-gate-rls-test', 'INTERNAL', 'INTERNAL',
       'https://radio.example.test/rights-gate.mp3', 'UTC',
       'APPROVED', 'ALLOWED'
from app.content_providers where slug = 'internal';

update app.content_providers
set production_enabled = false
where slug = 'internal';

set local role anon;
do $test$
begin
  if exists (select 1 from app.stations where slug = 'rights-gate-rls-test') then
    raise exception 'Unapproved provider exposed to anon';
  end if;
end $test$;
reset role;

update app.content_providers
set production_enabled = true
where slug = 'internal';

set local role anon;
do $test$
begin
  if not exists (select 1 from app.stations where slug = 'rights-gate-rls-test') then
    raise exception 'Approved provider and station hidden from anon';
  end if;
end $test$;
rollback;

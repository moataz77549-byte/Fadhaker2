-- Prefer the healthy MP3Quran-linked Saudi Quran radio during the short
-- pre-prayer window. It is audio programming only: the app's local prayer
-- calculation remains the timing authority and this source does not replace
-- local adhan/reminder behavior.

with ch as (
  select id from app.virtual_radio_channels where slug='fadhkur-smart'
),
station as (
  select id, external_key, source_url
  from app.stations
  where external_key='109082'
    and source_url='https://www.mp3quran.net/api/v3/radios?language=ar'
    and is_active=true
    and is_playable=true
    and deleted_at is null
    and health_status='HEALTHY'
  limit 1
)
insert into app.virtual_radio_sources(
  channel_id, program_key, source_type, station_id,
  priority, weight, is_active, metadata
)
select ch.id, 'pre_prayer', 'LIVE_STATION', station.id,
       50, 500, true,
       jsonb_build_object(
         'seeded_from','mp3quran_official_api_link',
         'external_key',station.external_key,
         'source_url',station.source_url,
         'usage_note','pre_prayer_quran_programming_not_adhan_timing_authority'
       )
from ch join station on true
where not exists (
  select 1
  from app.virtual_radio_sources s
  where s.channel_id=ch.id
    and s.program_key='pre_prayer'
    and s.station_id=station.id
);

update app.virtual_radio_sources s
set priority=50,
    weight=500,
    is_active=true,
    metadata=coalesce(s.metadata,'{}'::jsonb) ||
      '{"usage_note":"pre_prayer_quran_programming_not_adhan_timing_authority"}'::jsonb,
    updated_at=now()
from app.virtual_radio_channels ch, app.stations st
where ch.slug='fadhkur-smart'
  and st.external_key='109082'
  and st.source_url='https://www.mp3quran.net/api/v3/radios?language=ar'
  and s.channel_id=ch.id
  and s.program_key='pre_prayer'
  and s.station_id=st.id;

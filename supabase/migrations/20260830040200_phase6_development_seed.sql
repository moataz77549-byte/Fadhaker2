-- Development-only, idempotent Phase 6 station/catalog fixtures.
insert into app.stations(
 id,provider_id,category_id,name_ar,name_en,search_name_ar,search_name_en,slug,description,
 station_source,stream_type,stream_url,timezone,status,health_status,is_active,is_featured,
 production_enabled,rights_status,commercial_use_status,metadata
)
select '00000000-0000-4000-8000-000000000006',p.id,c.id,
 'ترتيل — تطوير','Tarteel Development','ترتيل تطوير','tarteel development','tarteel-dev',
 'محطة داخلية مخصصة لاختبارات بيئة التطوير فقط','INTERNAL','INTERNAL',
 'http://127.0.0.1:8000/tarteel.mp3','Asia/Aden','OFFLINE','UNKNOWN',true,false,false,
 'APPROVED','ALLOWED','{"environment":"development","stream_mount":"/tarteel.mp3","seed":"phase6"}'
from app.content_providers p join app.categories c on c.slug='QURAN_GENERAL'
where p.slug='internal'
on conflict(slug) do update set stream_url=excluded.stream_url,timezone=excluded.timezone,
 production_enabled=false,is_active=true,metadata=app.stations.metadata||excluded.metadata,updated_at=now();

insert into app.media(id,station_id,title,description,original_path,processed_path,duration_ms,
 format,bitrate_kbps,sample_rate_hz,channels,file_size_bytes,sha256,status,
 processing_profile_version,metadata)
values
 ('00000000-0000-4000-8100-000000000001','00000000-0000-4000-8000-000000000006','Development Track A','440Hz test fixture',
  null,'development/phase6/a.m4a',20000,'M4A',96,44100,2,1,repeat('a',64),'READY','AUDIO_STANDARD_V1','{"development_fixture":true,"frequency_hz":440}'),
 ('00000000-0000-4000-8100-000000000002','00000000-0000-4000-8000-000000000006','Development Track B','550Hz test fixture',
  null,'development/phase6/b.m4a',20000,'M4A',96,44100,2,1,repeat('b',64),'READY','AUDIO_STANDARD_V1','{"development_fixture":true,"frequency_hz":550}'),
 ('00000000-0000-4000-8100-000000000003','00000000-0000-4000-8000-000000000006','Development Track C','660Hz test fixture',
  null,'development/phase6/c.m4a',20000,'M4A',96,44100,2,1,repeat('c',64),'READY','AUDIO_STANDARD_V1','{"development_fixture":true,"frequency_hz":660}'),
 ('00000000-0000-4000-8100-000000000004','00000000-0000-4000-8000-000000000006','Development Track D','770Hz manual test fixture',
  null,'development/phase6/d.m4a',20000,'M4A',96,44100,2,1,repeat('d',64),'READY','AUDIO_STANDARD_V1','{"development_fixture":true,"frequency_hz":770}')
on conflict(id) do update set title=excluded.title,processed_path=excluded.processed_path,
 duration_ms=excluded.duration_ms,status='READY',metadata=excluded.metadata,updated_at=now();

insert into app.playlists(id,station_id,name,description,shuffle,repeat,is_active)
values('00000000-0000-4000-8200-000000000001','00000000-0000-4000-8000-000000000006',
 'Development Default','Phase 6 deterministic default playlist',false,true,true)
on conflict(id) do update set is_active=true,shuffle=false,repeat=true,updated_at=now();

insert into app.playlist_items(id,playlist_id,media_id,position,weight) values
 ('00000000-0000-4000-8300-000000000001','00000000-0000-4000-8200-000000000001','00000000-0000-4000-8100-000000000001',0,1),
 ('00000000-0000-4000-8300-000000000002','00000000-0000-4000-8200-000000000001','00000000-0000-4000-8100-000000000002',1,1)
on conflict(playlist_id,position) do update set media_id=excluded.media_id,weight=excluded.weight;

update app.stations set default_playlist_id='00000000-0000-4000-8200-000000000001',updated_at=now()
where id='00000000-0000-4000-8000-000000000006';

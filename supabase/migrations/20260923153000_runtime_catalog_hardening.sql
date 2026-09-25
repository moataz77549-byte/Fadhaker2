-- Fadhkur production catalog + least-privilege API exposure.
alter role authenticator set pgrst.db_schemas = 'public,app,radio,graphql_public';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';

revoke all on all tables in schema app, radio from anon;
revoke all on all sequences in schema app, radio from anon;
grant usage on schema app, radio to anon, authenticated, service_role;

grant select on app.app_config, app.categories, app.reciters, app.reciter_tracks,
  app.stations, app.surahs, app.video_channels to anon, authenticated;

grant execute on function app.has_permission(text) to authenticated;
grant execute on function app.admin_has_permission(text) to authenticated;

create or replace function app.has_permission(p_perm text)
returns boolean
language plpgsql
security definer
set search_path = app, pg_temp
as $function$
declare v_admin uuid; v_has boolean := false;
begin
  select id into v_admin
  from app.administrators
  where (id = auth.uid() or user_id = auth.uid())
    and is_active = true
    and deleted_at is null;
  if v_admin is null then return false; end if;
  select exists (
    select 1
    from app.administrator_roles ar
    join app.roles r on r.id = ar.role_id
    left join app.role_permissions rp on rp.role_id = r.id
    left join app.permissions p on p.id = rp.permission_id
    where ar.administrator_id = v_admin
      and (r.code = 'SUPER_ADMIN' or p.code = p_perm)
  ) into v_has;
  return v_has;
end
$function$;

grant select, insert, update, delete on
  app.stations, app.reciters, app.reciter_tracks, app.video_channels,
  app.notification_campaigns, app.media, app.media_processing_jobs,
  app.identity_settings, app.app_config, app.categories
to authenticated;

do $$
declare item record;
begin
  for item in
    select * from (values
      ('stations','stations.read','stations.write'),
      ('reciters','reciters.read','reciters.write'),
      ('reciter_tracks','reciters.read','reciters.write'),
      ('video_channels','media.read','media.write'),
      ('notification_campaigns','notifications.read','notifications.write'),
      ('media','media.read','media.write'),
      ('media_processing_jobs','media.read','media.write'),
      ('identity_settings','settings.read','settings.write'),
      ('app_config','settings.read','settings.write'),
      ('categories','categories.read','categories.write')
    ) as x(table_name,read_perm,write_perm)
  loop
    execute format('drop policy if exists "admin_read_%s" on app.%I', item.table_name, item.table_name);
    execute format('create policy "admin_read_%s" on app.%I for select to authenticated using (app.has_permission(%L))', item.table_name, item.table_name, item.read_perm);
    execute format('drop policy if exists "admin_write_%s" on app.%I', item.table_name, item.table_name);
    execute format('create policy "admin_write_%s" on app.%I for all to authenticated using (app.has_permission(%L)) with check (app.has_permission(%L))', item.table_name, item.table_name, item.write_perm, item.write_perm);
  end loop;
end $$;

drop policy if exists "Public read active reciter tracks" on app.reciter_tracks;
create policy "Public read active reciter tracks"
on app.reciter_tracks for select to anon
using (is_active = true);

insert into app.surahs (id,number,name_ar,name_en,ayah_count) values
(1,1,'الفاتحة','The Opening',7),
(2,2,'البقرة','The Cow',286),
(3,3,'آل عمران','Family of Imran',200),
(4,4,'النساء','The Women',176),
(5,5,'المائدة','The Table Spread',120),
(6,6,'الأنعام','The Cattle',165),
(7,7,'الأعراف','The Heights',206),
(8,8,'الأنفال','The Spoils of War',75),
(9,9,'التوبة','The Repentance',129),
(10,10,'يونس','Jonah',109),
(11,11,'هود','Hud',123),
(12,12,'يوسف','Joseph',111),
(13,13,'الرعد','The Thunder',43),
(14,14,'إبراهيم','Abraham',52),
(15,15,'الحجر','The Rocky Tract',99),
(16,16,'النحل','The Bee',128),
(17,17,'الإسراء','The Night Journey',111),
(18,18,'الكهف','The Cave',110),
(19,19,'مريم','Mary',98),
(20,20,'طه','Ta-Ha',135),
(21,21,'الأنبياء','The Prophets',112),
(22,22,'الحج','The Pilgrimage',78),
(23,23,'المؤمنون','The Believers',118),
(24,24,'النور','The Light',64),
(25,25,'الفرقان','The Criterion',77),
(26,26,'الشعراء','The Poets',227),
(27,27,'النمل','The Ant',93),
(28,28,'القصص','The Stories',88),
(29,29,'العنكبوت','The Spider',69),
(30,30,'الروم','The Romans',60),
(31,31,'لقمان','Luqman',34),
(32,32,'السجدة','The Prostration',30),
(33,33,'الأحزاب','The Combined Forces',73),
(34,34,'سبأ','Sheba',54),
(35,35,'فاطر','Originator',45),
(36,36,'يس','Ya-Sin',83),
(37,37,'الصافات','Those Who Set The Ranks',182),
(38,38,'ص','Sad',88),
(39,39,'الزمر','The Troops',75),
(40,40,'غافر','The Forgiver',85),
(41,41,'فصلت','Explained In Detail',54),
(42,42,'الشورى','The Consultation',53),
(43,43,'الزخرف','The Ornaments of Gold',89),
(44,44,'الدخان','The Smoke',59),
(45,45,'الجاثية','The Crouching',37),
(46,46,'الأحقاف','The Wind-Curved Sandhills',35),
(47,47,'محمد','Muhammad',38),
(48,48,'الفتح','The Victory',29),
(49,49,'الحجرات','The Rooms',18),
(50,50,'ق','Qaf',45),
(51,51,'الذاريات','The Winnowing Winds',60),
(52,52,'الطور','The Mount',49),
(53,53,'النجم','The Star',62),
(54,54,'القمر','The Moon',55),
(55,55,'الرحمن','The Beneficent',78),
(56,56,'الواقعة','The Inevitable',96),
(57,57,'الحديد','The Iron',29),
(58,58,'المجادلة','The Pleading Woman',22),
(59,59,'الحشر','The Exile',24),
(60,60,'الممتحنة','She That Is To Be Examined',13),
(61,61,'الصف','The Ranks',14),
(62,62,'الجمعة','The Congregation',11),
(63,63,'المنافقون','The Hypocrites',11),
(64,64,'التغابن','The Mutual Disillusion',18),
(65,65,'الطلاق','The Divorce',12),
(66,66,'التحريم','The Prohibition',12),
(67,67,'الملك','The Sovereignty',30),
(68,68,'القلم','The Pen',52),
(69,69,'الحاقة','The Reality',52),
(70,70,'المعارج','The Ascending Stairways',44),
(71,71,'نوح','Noah',28),
(72,72,'الجن','The Jinn',28),
(73,73,'المزمل','The Enshrouded One',20),
(74,74,'المدثر','The Cloaked One',56),
(75,75,'القيامة','The Resurrection',40),
(76,76,'الإنسان','Man',31),
(77,77,'المرسلات','The Emissaries',50),
(78,78,'النبأ','The Tidings',40),
(79,79,'النازعات','Those Who Drag Forth',46),
(80,80,'عبس','He Frowned',42),
(81,81,'التكوير','The Overthrowing',29),
(82,82,'الانفطار','The Cleaving',19),
(83,83,'المطففين','The Defrauding',36),
(84,84,'الانشقاق','The Splitting Open',25),
(85,85,'البروج','The Mansions of the Stars',22),
(86,86,'الطارق','The Morning Star',17),
(87,87,'الأعلى','The Most High',19),
(88,88,'الغاشية','The Overwhelming',26),
(89,89,'الفجر','The Dawn',30),
(90,90,'البلد','The City',20),
(91,91,'الشمس','The Sun',15),
(92,92,'الليل','The Night',21),
(93,93,'الضحى','The Morning Hours',11),
(94,94,'الشرح','The Relief',8),
(95,95,'التين','The Fig',8),
(96,96,'العلق','The Clot',19),
(97,97,'القدر','The Power',5),
(98,98,'البينة','The Clear Proof',8),
(99,99,'الزلزلة','The Earthquake',8),
(100,100,'العاديات','The Courser',11),
(101,101,'القارعة','The Calamity',11),
(102,102,'التكاثر','The Rivalry in World Increase',8),
(103,103,'العصر','The Declining Day',3),
(104,104,'الهمزة','The Traducer',9),
(105,105,'الفيل','The Elephant',5),
(106,106,'قريش','Quraysh',4),
(107,107,'الماعون','The Small Kindnesses',7),
(108,108,'الكوثر','The Abundance',3),
(109,109,'الكافرون','The Disbelievers',6),
(110,110,'النصر','The Divine Support',3),
(111,111,'المسد','The Palm Fiber',5),
(112,112,'الإخلاص','The Sincerity',4),
(113,113,'الفلق','The Daybreak',5),
(114,114,'الناس','Mankind',6)
on conflict (id) do update set number=excluded.number,name_ar=excluded.name_ar,name_en=excluded.name_en,ayah_count=excluded.ayah_count;

insert into app.reciters
  (name_ar,name_en,slug,rewaya,description,search_name_ar,search_name_en,canonical_slug,
   name_arabic,name_english,canonical_name,default_riwayah,bio_arabic,is_active,is_featured,metadata)
values
  ('الشيخ عبد الباسط عبد الصمد','Abdul Basit Abdus Samad','abdulbasit','حفص عن عاصم','تلاوات مرتلة عبر مصدر صوتي خارجي مُدار من الكتالوج.','عبد الباسط عبد الصمد','Abdul Basit Abdus Samad','abdulbasit-abdussamad','الشيخ عبد الباسط عبد الصمد','Abdul Basit Abdus Samad','Abdul Basit Abdus Samad','حفص عن عاصم','المصدر الصوتي: Al Quran Cloud / Islamic Network.',true,true,'{"audioSource":"Al Quran Cloud","audioEdition":"ar.abdulbasit"}'),
  ('الشيخ محمد صديق المنشاوي','Mohamed Siddiq Al-Minshawi','minshawi','حفص عن عاصم','تلاوات مرتلة عبر مصدر صوتي خارجي مُدار من الكتالوج.','محمد صديق المنشاوي','Mohamed Siddiq Al-Minshawi','mohamed-siddiq-el-minshawi','الشيخ محمد صديق المنشاوي','Mohamed Siddiq Al-Minshawi','Mohamed Siddiq Al-Minshawi','حفص عن عاصم','المصدر الصوتي: Al Quran Cloud / Islamic Network.',true,true,'{"audioSource":"Al Quran Cloud","audioEdition":"ar.minshawi"}'),
  ('الشيخ محمود خليل الحصري','Mahmoud Khalil Al-Husary','husary','حفص عن عاصم','تلاوات مرتلة عبر مصدر صوتي خارجي مُدار من الكتالوج.','محمود خليل الحصري','Mahmoud Khalil Al-Husary','mahmoud-khalil-al-hussary','الشيخ محمود خليل الحصري','Mahmoud Khalil Al-Husary','Mahmoud Khalil Al-Husary','حفص عن عاصم','المصدر الصوتي: Al Quran Cloud / Islamic Network.',true,true,'{"audioSource":"Al Quran Cloud","audioEdition":"ar.husary"}')
on conflict (slug) do update set
  name_ar=excluded.name_ar,name_en=excluded.name_en,rewaya=excluded.rewaya,description=excluded.description,
  search_name_ar=excluded.search_name_ar,search_name_en=excluded.search_name_en,canonical_slug=excluded.canonical_slug,
  name_arabic=excluded.name_arabic,name_english=excluded.name_english,canonical_name=excluded.canonical_name,
  default_riwayah=excluded.default_riwayah,bio_arabic=excluded.bio_arabic,is_active=true,is_featured=excluded.is_featured,metadata=excluded.metadata,updated_at=now();

insert into app.reciter_tracks
  (reciter_id,surah_id,audio_url,quality,rewaya,format,bitrate_kbps,metadata,is_active)
select r.id,s.id,
  'https://cdn.islamic.network/quran/audio-surah/' ||
  case r.slug when 'abdulbasit' then '192' else '128' end || '/' ||
  case r.slug when 'abdulbasit' then 'ar.abdulbasit' when 'minshawi' then 'ar.minshawi' else 'ar.husary' end ||
  '/' || s.number || '.mp3',
  case r.slug when 'abdulbasit' then '192kbps' else '128kbps' end,
  'حفص عن عاصم','mp3',case r.slug when 'abdulbasit' then 192 else 128 end,
  jsonb_build_object('source','Al Quran Cloud',
    'edition',case r.slug when 'abdulbasit' then 'ar.abdulbasit' when 'minshawi' then 'ar.minshawi' else 'ar.husary' end),
  true
from app.reciters r cross join app.surahs s
where r.slug in ('abdulbasit','minshawi','husary')
on conflict (reciter_id,surah_id,rewaya,quality) where provider_id is null
do update set audio_url=excluded.audio_url,format=excluded.format,bitrate_kbps=excluded.bitrate_kbps,metadata=excluded.metadata,is_active=true,updated_at=now();

insert into app.video_channels (slug,name_ar,name_en,stream_url,is_active,sort_order,metadata)
values
 ('quran-tv','قناة القرآن الكريم','Quran TV','https://shd-gcp-live.edgenextcdn.net/live/bitmovin-saudi-tv/index.m3u8',true,10,'{"sourceType":"hls","provider":"user_configured","notes":"HLS channel URL; changeable from admin"}'),
 ('sunnah-tv','قناة السنة النبوية','Sunnah TV','https://www.youtube.com/watch?v=ATMosZ7Xq1c',true,20,'{"sourceType":"youtube","provider":"YouTube","notes":"Changeable from admin"}')
on conflict (slug) do update set stream_url=excluded.stream_url,is_active=true,sort_order=excluded.sort_order,metadata=excluded.metadata,updated_at=now();

update app.stations
set is_active=false,is_playable=false,
    internal_notes='Development-only localhost mount; disabled until a public production stream URL is deployed.',
    updated_at=now()
where slug='tarteel-dev' or stream_url like 'http://127.0.0.1:%';

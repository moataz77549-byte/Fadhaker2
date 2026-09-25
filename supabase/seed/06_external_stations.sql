-- Repeatable technical source inventory. No row is production-enabled or rights-approved.
with inventory(provider_slug, category_slug, slug, external_key, name_ar, name_en, stream_type, stream_url, metadata) as (
  values
  ('qurango','QURAN_GENERAL','qurango-mix','mix','الإذاعة العامة - قراء متنوعون','General Quran - Multiple Reciters','SHOUTCAST','https://backup.qurango.net/radio/mix','{"seed_group":"general"}'::jsonb),
  ('qurango','QURAN_GENERAL','qurango-humble-recitations','salma','تلاوات خاشعة','Humble Recitations','SHOUTCAST','https://backup.qurango.net/radio/salma','{"seed_group":"general"}'::jsonb),
  ('qurango','HADITH','qurango-sahih-bukhari','saheh-bokharee','صحيح البخاري','Sahih al-Bukhari','SHOUTCAST','https://backup.qurango.net/radio/saheh-bokharee','{"seed_group":"general"}'::jsonb),
  ('qurango','HADITH','qurango-sahih-muslim','saheh-muslim','صحيح مسلم','Sahih Muslim','SHOUTCAST','https://backup.qurango.net/radio/saheh-muslim','{"seed_group":"general"}'::jsonb),
  ('qurango','HADITH','qurango-riyad-al-salihin','riyad','رياض الصالحين','Riyad as-Salihin','SHOUTCAST','https://backup.qurango.net/radio/riyad','{"seed_group":"general"}'::jsonb),
  ('qurango','SEERAH','qurango-stories-prophets','alanbiya','قصص الأنبياء','Stories of the Prophets','SHOUTCAST','https://backup.qurango.net/radio/alanbiya','{"seed_group":"general"}'::jsonb),
  ('qurango','SAHABAH','qurango-lives-companions','sahabah','صور من حياة الصحابة','Lives of the Companions','SHOUTCAST','https://backup.qurango.net/radio/sahabah','{"seed_group":"general"}'::jsonb),
  ('qurango','SEERAH','qurango-prophetic-biography','almukhtasar_fi_alsiyra','السيرة النبوية','Prophetic Biography','SHOUTCAST','https://backup.qurango.net/radio/almukhtasar_fi_alsiyra','{"seed_group":"general"}'::jsonb),
  ('qurango','SEERAH','qurango-in-shade-seerah','fi_zilal_alsiyra','في ظلال السيرة النبوية','In the Shade of the Prophetic Biography','SHOUTCAST','https://backup.qurango.net/radio/fi_zilal_alsiyra','{"seed_group":"general"}'::jsonb),
  ('qurango','TAFSEER','qurango-tafseer','tafseer','تفسير القرآن','Quran Tafseer','SHOUTCAST','https://backup.qurango.net/radio/tafseer','{"seed_group":"general"}'::jsonb),
  ('qurango','TAFSEER','qurango-concise-tafseer','mukhtasartafsir','المختصر في تفسير القرآن','Concise Quran Tafseer','SHOUTCAST','https://backup.qurango.net/radio/mukhtasartafsir','{"seed_group":"general"}'::jsonb),
  ('qurango','TAFSEER','qurango-tabari-summary','tabri','الخلاصة من تفسير الطبري','Summary of Tafsir al-Tabari','SHOUTCAST','https://backup.qurango.net/radio/tabri','{"seed_group":"general"}'::jsonb),
  ('qurango','TAFSEER','qurango-gharib-quran','gareeb-quran','تفسير غريب القرآن','Explanation of Uncommon Quranic Words','SHOUTCAST','https://backup.qurango.net/radio/gareeb-quran','{"seed_group":"general"}'::jsonb),
  ('qurango','FATWA','qurango-fatwa','fatwa','الفتاوى','Fatwas','SHOUTCAST','https://backup.qurango.net/radio/fatwa','{"seed_group":"general"}'::jsonb),
  ('qurango','RUQYAH','qurango-ruqyah','roqiah','الرقية الشرعية','Ruqyah','SHOUTCAST','https://backup.qurango.net/radio/roqiah','{"seed_group":"general"}'::jsonb),
  ('qurango','ADHKAR','qurango-morning-adhkar','athkar_sabah','أذكار الصباح','Morning Adhkar','SHOUTCAST','https://backup.qurango.net/radio/athkar_sabah','{"seed_group":"general"}'::jsonb),
  ('qurango','ADHKAR','qurango-evening-adhkar','athkar_masa','أذكار المساء','Evening Adhkar','SHOUTCAST','https://backup.qurango.net/radio/athkar_masa','{"seed_group":"general"}'::jsonb),
  ('qurango','QURAN_SURAH','qurango-surah-al-baqarah','albaqarah','سورة البقرة - عدة قراء','Surah Al-Baqarah - Multiple Reciters','SHOUTCAST','https://backup.qurango.net/radio/albaqarah','{"seed_group":"general"}'::jsonb),
  ('qurango','QURAN_SURAH','qurango-surah-al-mulk','Surah_Al-Mulk','سورة الملك','Surah Al-Mulk','SHOUTCAST','https://backup.qurango.net/radio/Surah_Al-Mulk','{"seed_group":"general"}'::jsonb),

  ('qurango','RECITER','qurango-abdulrahman-alsudais','abdulrahman_alsudaes','عبدالرحمن السديس','Abdulrahman Al-Sudais','SHOUTCAST','https://backup.qurango.net/radio/abdulrahman_alsudaes','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-saud-alshuraim','saud_alshuraim','سعود الشريم','Saud Al-Shuraim','SHOUTCAST','https://backup.qurango.net/radio/saud_alshuraim','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-maher-almuaiqly','maher','ماهر المعيقلي','Maher Al-Muaiqly','SHOUTCAST','https://backup.qurango.net/radio/maher','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-yasser-aldosari','yasser_aldosari','ياسر الدوسري','Yasser Al-Dosari','SHOUTCAST','https://backup.qurango.net/radio/yasser_aldosari','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-mishary-alafasi','mishary_alafasi','مشاري العفاسي','Mishary Alafasy','SHOUTCAST','https://backup.qurango.net/radio/mishary_alafasi','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-ahmad-alajmy','ahmad_alajmy','أحمد العجمي','Ahmad Al-Ajmy','SHOUTCAST','https://backup.qurango.net/radio/ahmad_alajmy','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-idrees-abkr','idrees_abkr','إدريس أبكر','Idrees Abkar','SHOUTCAST','https://backup.qurango.net/radio/idrees_abkr','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-khalid-aljileel','khalid_aljileel','خالد الجليل','Khalid Al-Jaleel','SHOUTCAST','https://backup.qurango.net/radio/khalid_aljileel','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-saad-alghamdi','saad_alghamdi','سعد الغامدي','Saad Al-Ghamdi','SHOUTCAST','https://backup.qurango.net/radio/saad_alghamdi','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-nasser-alqatami','nasser_alqatami','ناصر القطامي','Nasser Al-Qatami','SHOUTCAST','https://backup.qurango.net/radio/nasser_alqatami','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-fares-abbad','fares_abbad','فارس عباد','Fares Abbad','SHOUTCAST','https://backup.qurango.net/radio/fares_abbad','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-hazza-albalushi','hazza','هزاع البلوشي','Hazza Al-Balushi','SHOUTCAST','https://backup.qurango.net/radio/hazza','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-abdullah-aljohany','abdullah_aljohany','عبدالله عواد الجهني','Abdullah Awad Al-Juhany','SHOUTCAST','https://backup.qurango.net/radio/abdullah_aljohany','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-abdulmohsen-alqasim','abdulmohsen_alqasim','عبدالمحسن القاسم','Abdulmohsen Al-Qasim','SHOUTCAST','https://backup.qurango.net/radio/abdulmohsen_alqasim','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-bandar-balilah','bandar_balilah','بندر بليلة','Bandar Balilah','SHOUTCAST','https://backup.qurango.net/radio/bandar_balilah','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-ali-alhuthaifi','ali_alhuthaifi','علي الحذيفي','Ali Al-Hudhaifi','SHOUTCAST','https://backup.qurango.net/radio/ali_alhuthaifi','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-abdulbasit','abdulbasit_abdulsamad','عبدالباسط عبدالصمد','Abdulbasit Abdulsamad','SHOUTCAST','https://backup.qurango.net/radio/abdulbasit_abdulsamad','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-abdulbasit-mojawwad','abdulbasit_abdulsamad_mojawwad','عبدالباسط عبدالصمد - مجود','Abdulbasit Abdulsamad - Mujawwad','SHOUTCAST','https://backup.qurango.net/radio/abdulbasit_abdulsamad_mojawwad','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-minshawi','mohammed_siddiq_alminshawi','محمد صديق المنشاوي','Muhammad Siddiq Al-Minshawi','SHOUTCAST','https://backup.qurango.net/radio/mohammed_siddiq_alminshawi','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-minshawi-mojawwad','mohammed_siddiq_alminshawi_mojawwad','المنشاوي - مجود','Al-Minshawi - Mujawwad','SHOUTCAST','https://backup.qurango.net/radio/mohammed_siddiq_alminshawi_mojawwad','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-hussary','mahmoud_khalil_alhussary','محمود خليل الحصري','Mahmoud Khalil Al-Hussary','SHOUTCAST','https://backup.qurango.net/radio/mahmoud_khalil_alhussary','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-hussary-mojawwad','mahmoud_khalil_alhussary_mojawwad','الحصري - مجود','Al-Hussary - Mujawwad','SHOUTCAST','https://backup.qurango.net/radio/mahmoud_khalil_alhussary_mojawwad','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-tablawy','mohammad_altablaway','محمد الطبلاوي','Muhammad Al-Tablawi','SHOUTCAST','https://backup.qurango.net/radio/mohammad_altablaway','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-mustafa-ismail','mustafa_ismail','مصطفى إسماعيل','Mustafa Ismail','SHOUTCAST','https://backup.qurango.net/radio/mustafa_ismail','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-mohammed-ayyub','mohammed_ayyub','محمد أيوب','Muhammad Ayyub','SHOUTCAST','https://backup.qurango.net/radio/mohammed_ayyub','{"seed_group":"reciter"}'::jsonb),
  ('qurango','RECITER','qurango-ali-jaber','ali_jaber','علي جابر','Ali Jaber','SHOUTCAST','https://backup.qurango.net/radio/ali_jaber','{"seed_group":"reciter"}'::jsonb),

  ('qurango','QURAN_TRANSLATION','qurango-translation-english','translation_quran_english_bsfr','ترجمة معاني القرآن - الإنجليزية','Quran Translation - English','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_english_bsfr','{"seed_group":"translation","language":"en"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-french','translation_quran_french','ترجمة معاني القرآن - الفرنسية','Quran Translation - French','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_french','{"seed_group":"translation","language":"fr"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-german','translation_quran_german','ترجمة معاني القرآن - الألمانية','Quran Translation - German','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_german','{"seed_group":"translation","language":"de"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-spanish','translation_quran_spanish_afs','ترجمة معاني القرآن - الإسبانية','Quran Translation - Spanish','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_spanish_afs','{"seed_group":"translation","language":"es"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-turkish','translation_quran_turkish','ترجمة معاني القرآن - التركية','Quran Translation - Turkish','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_turkish','{"seed_group":"translation","language":"tr"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-urdu','translation_quran_urdu_basit','ترجمة معاني القرآن - الأردية','Quran Translation - Urdu','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_urdu_basit','{"seed_group":"translation","language":"ur"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-farsi','translation_quran_farsi','ترجمة معاني القرآن - الفارسية','Quran Translation - Farsi','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_farsi','{"seed_group":"translation","language":"fa"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-russian','translation_quran_Russia','ترجمة معاني القرآن - الروسية','Quran Translation - Russian','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_Russia','{"seed_group":"translation","language":"ru"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-chinese','translation_quran_chinese','ترجمة معاني القرآن - الصينية','Quran Translation - Chinese','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_chinese','{"seed_group":"translation","language":"zh"}'::jsonb),
  ('qurango','QURAN_TRANSLATION','qurango-translation-korean','translation_quran_Korean','ترجمة معاني القرآن - الكورية','Quran Translation - Korean','SHOUTCAST','https://backup.qurango.net/radio/translation_quran_Korean','{"seed_group":"translation","language":"ko"}'::jsonb),

  ('holol','LIVE_TV_AUDIO','holol-quran-live','quran-live','قناة القرآن الكريم','Quran TV Live','HLS','https://win.holol.com/live/quran/playlist.m3u8','{"seed_group":"hls","contains_video":true}'::jsonb),
  ('holol','LIVE_TV_AUDIO','holol-sunnah-live','sunnah-live','قناة السنة النبوية','Sunnah TV Live','HLS','https://win.holol.com/live/sunnah/playlist.m3u8','{"seed_group":"hls","contains_video":true}'::jsonb),
  ('radiojar','QURAN_GENERAL','saudi-quran-radio','0tpy1h0kxtzuv','إذاعة القرآن الكريم السعودية','Saudi Quran Radio','UNKNOWN_STREAM','https://stream.radiojar.com/0tpy1h0kxtzuv','{"seed_group":"radiojar","redirect_observed":true}'::jsonb)
)
insert into app.stations
  (provider_id, category_id, slug, external_key, name_ar, name_en, search_name_ar, search_name_en,
   station_source, stream_type, stream_url, source_url, is_active,
   production_enabled, health_status, rights_status, commercial_use_status, metadata)
select p.id, c.id, i.slug, i.external_key, i.name_ar, i.name_en, i.name_ar, lower(i.name_en),
       'EXTERNAL', i.stream_type, i.stream_url, i.stream_url, true,
       false, 'UNKNOWN', 'REVIEW_REQUIRED', 'UNKNOWN', i.metadata
from inventory i
join app.content_providers p on p.slug = i.provider_slug
join app.categories c on c.slug = i.category_slug
on conflict (slug) do nothing;

insert into app.provider_station_records
  (provider_id, station_id, external_key, discovered_name, discovered_stream_url, last_seen_at, raw_metadata)
select s.provider_id, s.id, s.external_key, s.name_ar, s.stream_url, now(), s.metadata
from app.stations s
where s.station_source = 'EXTERNAL' and s.external_key is not null
on conflict (provider_id, external_key) do nothing;

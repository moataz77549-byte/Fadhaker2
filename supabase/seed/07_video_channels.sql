-- ============================================================================
-- 07_video_channels.sql — بيانات اختبار لقنوات الفيديو (ليست دائمة)
-- ============================================================================
-- تنبيه واضح:
--   * هذه الروابط للاختبار والتطوير فقط وليست محتوى دائمًا.
--   * لا توجد روابط فيديو ثابتة في كود Dart إطلاقًا — القنوات تُقرأ
--     ديناميكيًا من جدول app.video_channels (انظر docs/VIDEO_CHANNELS.md).
--   * الجدول غير موجود بعد في الـ migrations، لذا هذا الملف دفاعي:
--     يُدخل الصفوف فقط إذا كان الجدول موجودًا، ويتجاهل بأمان (NOTICE) otherwise.
--   * لاستبدال روابط الاختبار بروابط الإنتاج: حدّث هذا الملف أو أدخل
--     الصفوف مباشرة في app.video_channels عبر لوحة الإدارة/seed.
--
-- روابط الاختبار المقدمة:
--   1) قرآن HLS:        http://m.live.net.sa:1935/live/quran/playlist.m3u8
--      ملاحظة: http (غير مشفّر) — يتطلب Android: usesCleartextTraffic
--      أو إعداد Network Security Config في التطبيق (موثّق في docs/VIDEO_CHANNELS.md).
--   2) البديل HLS:      https://shd-gcp-live.edgenextcdn.net/live/bitmovin-saudi-tv/index.m3u8
--   3) يوتيوب (السنة):  https://www.youtube.com/watch?v=ATMosZ7Xq1c
-- ============================================================================

do $$
begin
  if to_regclass('app.video_channels') is null then
    raise notice 'app.video_channels table does not exist yet — skipping video channel test seed (see docs/VIDEO_CHANNELS.md).';
    return;
  end if;

  insert into app.video_channels (slug, name_ar, name_en, stream_url, logo_url, is_active, sort_order, metadata)
  values
    ('test-quran-hls',
     'قناة القرآن الكريم — بث تجريبي',
     'Quran Live (test stream)',
     'http://m.live.net.sa:1935/live/quran/playlist.m3u8',
     null,
     true,
     10,
     '{"seed":"test","note":"روابط اختبار فقط — ليست دائمة","requires_cleartext":true}'::jsonb),
    ('test-quran-hls-alt',
     'قناة القرآن الكريم — البديل التجريبي',
     'Quran Live alternate (test stream)',
     'https://shd-gcp-live.edgenextcdn.net/live/bitmovin-saudi-tv/index.m3u8',
     null,
     true,
     20,
     '{"seed":"test","note":"روابط اختبار فقط — ليست دائمة"}'::jsonb),
    ('test-sunnah-youtube',
     'قناة السنة — يوتيوب (تجريبي)',
     'Sunnah YouTube (test link)',
     'https://www.youtube.com/watch?v=ATMosZ7Xq1c',
     null,
     true,
     30,
     '{"seed":"test","note":"روابط اختبار فقط — ليست دائمة"}'::jsonb)
  on conflict (slug) do update set
    name_ar = excluded.name_ar,
    name_en = excluded.name_en,
    stream_url = excluded.stream_url,
    logo_url = excluded.logo_url,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order,
    metadata = excluded.metadata,
    updated_at = now();
end
$$;

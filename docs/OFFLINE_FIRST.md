# Offline-First — فذكر يعمل من الصندوق دون باك-إند

**التاريخ:** 2026-09-23 — **الـ commit:** `fix: offline-first fallbacks - app works out of the box without backend`

## المبدأ

القاعدة الصارمة: **أول تشغيل للتطبيق (دون حسابات، دون باك-إند مُعدّ، دون شبكة)
يجب أن يعرض محتوى حقيقيًا يعمل في كل شاشة رئيسية.** لا شاشات ميتة،
لا بيانات وهمية — إما محتوى حقيقي من مصدر عام موثّق، أو حالة صادقة
(empty/error) مع زر إعادة المحاولة.

ترتيب السقوط الموحّد في كل مستودع:
`Supabase/Edge Function` → `الكاش المحلي` → `المصدر العام/المضمّن` → `حالة صادقة`.

## مصفوفة الميزات

| الميزة | تعمل دون باك-إند؟ | مصدر الـ fallback | ملاحظات |
| :--- | :--- | :--- | :--- |
| شاشة المصحف (وضع الصور) | ✅ كامل | `QuranRuntimeConfig.fallback()` من `MushafEditionRegistry.builtin` — نسختا المصحف المدني (عادي + تجويد ملوّن) بروابط QuranHub المحققة + كاش قرص للصور | 604 صفحات لكل نسخة (حفص) |
| شاشة المصحف (وضع النص — حفص) | ✅ كامل | `QuranPublicTextSource`: خريطة الصفحات من `api.quran.com/api/v4` (بلا مفتاح) + نص حفص العثماني من `fawazahmed0/quran-api` عبر jsDelivr (بلا مفتاح)، سور مخزّنة على القرص ملفًا لكل سورة | الروايات الأخرى: رسالة صادقة (بلا مصدر نص عام موثّق) |
| إعدادات القرآن (الرواية/الخط/النسخة) | ✅ كامل | السجلات المضمّنة: `RiwayaRegistry` (4 روايات)، `MushafEditionRegistry` (نسختان)، `QuranFontRegistry` (4 خطوط — اثنان بروابط تحميل محققة) | `QuranConfigRepository.load()` لا ترمي أبدًا عند أول تشغيل |
| الخطوط العثمانية | ✅ كامل | تحميل عند أول استخدام من tarteel/jsDelivr + كاش قرص، وfallback لخط النظام مع ملاحظة صادقة | QCF وUthmanic-vector بلا مصدر موثّق — ملاحظة صادقة في الواجهة |
| الراديو | ✅ كامل | 4 محطات مضمّنة مُتحققة حيًّا (HTTP 200 + audio/mpeg): الحصري، المنشاوي، المعيقلي، الشاطري — عبر `backup.qurango.net` (واجهة mp3quran العامة)؛ محطات Supabase الإنتاجية (`production_enabled`) أولًا ثم المضمّنة بلا تكرار | محطة التطوير (`127.0.0.1`) لا تظهر — يُشترط `production_enabled=true` |
| التلاوات الصوتية (سور) | ✅ كامل | روابط `server7.mp3quran.net` العامة (مُتحققة: HTTP 206 + audio/mpeg) + قائمة قرّاء مضمّنة + بيانات السور المضمّنة (114 سورة) | البث يحتاج إنترنت (طبيعي للصوت)؛ التحميل للاستماع دون اتصال موجود |
| الأذكار | ✅ كامل | حصن المسلم (مصدر مفتوح) يُنزَّل مرة واحدة إلى SQLite ثم offline بالكامل | — |
| المسبحة الإلكترونية | ✅ كامل | محلية بالكامل (SharedPreferences) | — |
| أسماء الله الحسنى | ✅ كامل | بيانات حقيقية مضمّنة | — |
| حديث اليوم | ✅ كامل | الأربعون النووية مضمّنة | — |
| متتبع الختمة / تقدم القراءة | ✅ كامل | محلي (SQLite/SharedPreferences) | المزامنة عبر الأجهزة تحتاج حسابات — متابعة |
| التاريخ الهجري | ✅ كامل | حساب تقريبي offline موسوم «تقريبي» | — |
| مؤقت النوم / سرعة التشغيل | ✅ كامل | محلي | — |
| مواقيت الصلاة | ✅ كامل | حساب فلكي offline (Umm Al-Qura) مع fallback للكاش | الموقع اختياري؛ المدينة اليدوية تعمل دون GPS |
| المفضلة / التحميلات | ✅ كامل | محلية | — |
| البحث عن سورة | ✅ كامل | بيانات السور المضمّنة | — |
| التفسير (نص التفسير) | ⚠️ يتطلب الباك-إند | لا يوجد مصدر عام موثّق لنصوص التفاسير — رسالة صادقة «تعذّر جلب التفسير من الخادم» مع زر إعادة | فهرس التفاسير (الأسماء) يعمل من القائمة المضمّنة؛ المحتوى المخزّن سابقًا يُعرض من الكاش |
| الفيديو | ⚠️ جزئي | القنوات من Supabase مع empty state صادق؛ روابط الفيديو نفسها عامة | لا قنوات مضمّنة (تتطلب مراجعة حقوق) |
| الإشعارات (FCM) | ⚠️ تتطلب الباك-إند | التسجيل المحلي يعمل؛ الإرسال عبر Edge Function فقط | الحملات المجدولة تحتاج `campaign-dispatcher` منشورًا |
| Force Update | ✅ متدهور بأمان | يُتابع العمل دون حجب عند تعذّر الشبكة | يحتاج `app_config` في قاعدة البيانات ليكون فعّالًا |

## المصادر العامة المُتحقق منها (2026-09-23)

| المصدر | الرابط | التحقق |
| :--- | :--- | :--- |
| صور المصحف المدني (عادي) | `raw.githubusercontent.com/QuranHub/quran-pages-images/main/kfgqpc/hafs-wasat/{page}.jpg` | صفحات 1/100/300/500/604: HTTP 200 + image/jpeg + بايتات JPEG |
| صور المصحف الملوّن (تجويد) | `raw.githubusercontent.com/QuranHub/quran-pages-images/main/easyquran.com/hafs-tajweed/{page}.jpg` | نفس المنهجية + 604 ملفات بلا فجوات |
| خريطة صفحات النص | `api.quran.com/api/v4/verses/by_page/{page}?words=false&per_page=all` | HTTP 200 بلا مفتاح — verse_key/page_number/juz_number |
| نص حفص العثماني | `cdn.jsdelivr.net/gh/fawazahmed0/quran-api@1/editions/ara-quranuthmanihaf/{chapter}.json` | HTTP 200 — `{"chapter":[{"chapter":N,"verse":M,"text":"..."}]}` |
| بث الحصري | `backup.qurango.net/radio/mahmoud_khalil_alhussary` | HTTP 200 + audio/mpeg |
| بث المنشاوي | `backup.qurango.net/radio/mohammed_siddiq_alminshawi` | HTTP 200 + audio/mpeg |
| بث المعيقلي | `backup.qurango.net/radio/maher` | HTTP 200 + audio/mpeg |
| بث الشاطري | `backup.qurango.net/radio/shaik_abu_bakr_al_shatri` | HTTP 200 + audio/mpeg |
| صوت السور (mp3quran) | `server7.mp3quran.net/{basit,minsh,husary}/{NNN}.mp3` | HTTP 206 + audio/mpeg |
| خط UthmanicHafs | `static-cdn.tarteel.ai/qul/fonts/UthmanicHafs_V22.ttf` | HTTP 200 — 297,700 بايت (تحقق سابق 2026-09-23) |
| خط KFGQPC-Hafs | `cdn.jsdelivr.net/gh/mohammed-2-5/islamic-library-data@master/fonts/UthmanicHafs_v18.ttf` | HTTP 200 — 242,368 بايت (تحقق سابق 2026-09-23) |

## ما بقي يحتاج الباك-إند فعلًا (بصراحة)

1. **نشر Edge Function** `quran-yutla-api` بالكود الجديد (v5 المنشورة قديمة) — المصادر العامة تغطي القراءة، لكن التفسير ومزايا الخادم تحتاجها.
2. **تطبيق migrations** `20260830040900` → `20260830041500` على قاعدة البيانات الحية (يدوي من مالك DB).
3. **أسرار** Quran Foundation (`QF_CLIENT_ID`/`QF_CLIENT_SECRET`) وFCM — عبر `supabase secrets set`.
4. **محطات إنتاج حقيقية** في `app.stations` مع `production_enabled=true` (المضمّنة تغطي التشغيل، لكن الإدارة الكاملة تحتاجها).
5. **سياسة وصول الإدارة** للجداول المقيدة بـ service-role (admin-JWT أو وكيل Edge Function).
6. **مزامنة تقدم القراءة عبر الأجهزة** — تحتاج نظام حسابات/هوية حقيقيًا.

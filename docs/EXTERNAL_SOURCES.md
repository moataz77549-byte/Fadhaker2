> تحديث 2026-09-24: الجدول أدناه يصف سجل البذور التاريخي، لا حالة Supabase الحالية. قاعدة فذكر الحالية تحتوي 174 محطة MP3Quran نشطة موثقة برابط `/api/v3/radios?language=ar` وبمفتاح خارجي وحالة `HEALTHY`. أذن مالك التطبيق بربط هذه المحطات عبر API؛ تمت إضافة `api_stream_links_enabled` وشرط RLS المحدد في [ISLAMIC_CONTENT_SOURCES.md](ISLAMIC_CONTENT_SOURCES.md). لا يغيّر ذلك حالة `REVIEW_REQUIRED` لبقية استخدامات المصدر، ولا يجيز نسخ الصوت أو إعادة استضافته.

# ترتيل — External Sources Inventory

هذه الوثيقة سجل تقني، وليست إثباتًا لحقوق إعادة التوزيع أو الاستخدام التجاري. محطات الجرد الأولي الـ58 تبدأ `REVIEW_REQUIRED / UNKNOWN / production_enabled=false`.

## Inventory applied to Supabase

| Provider record | Provider type | Station rows | Source | Rights | Production | Verification |
|---|---|---:|---|---|---|---|
| Qurango | `QURANGO` | 55 | `backup.qurango.net` inventory | `REVIEW_REQUIRED / UNKNOWN` | Disabled | URL format + mapping validated؛ stream availability not certified |
| Holol Live | `OTHER` | 2 | Quran/Sunnah HLS manifests | `REVIEW_REQUIRED / UNKNOWN` | Disabled | Stored as `HLS`; mobile compatibility deferred |
| Radiojar | `OTHER` | 1 | Saudi Quran Radio technical source | `REVIEW_REQUIRED / UNKNOWN` | Disabled | Stored as `UNKNOWN_STREAM`; probe deferred |
| MP3Quran | `MP3QURAN` | 0 seed stations | API/catalog metadata | `REVIEW_REQUIRED / UNKNOWN` | Disabled | Provider + adapter metadata ready؛ sync worker deferred |
| Custom | `CUSTOM` | 0 | Admin-managed future sources | `REVIEW_REQUIRED / UNKNOWN` | Disabled | Placeholder provider record |
| Internal Platform | `INTERNAL` | 0 external | Tarteel-owned future station | `APPROVED / ALLOWED` | Provider enabled | Not an external rights claim |

`CUSTOM` موجود كـprovider type وكـprovider record افتراضي. النوع يصنف adapters، والrecord يتيح إضافة روابط يدوية دون إنشاء provider جديد لكل رابط؛ يمكن للإدارة إنشاء providers إضافيين من النوع نفسه لاحقًا.

## Verified database invariants

- 58 station rows و58 `provider_station_records` mappings.
- 55 `SHOUTCAST`، 2 `HLS`، 1 `UNKNOWN_STREAM`.
- 0 malformed HTTP(S) URL، 0 duplicate URL group، 0 missing provider mapping.
- 0 external station production-enabled.
- 58/58 rights status = `REVIEW_REQUIRED` وcommercial status = `UNKNOWN`.
- Provider sync failure لا يملك FK أو trigger يستطيع تعطيل INTERNAL station.
- لا يمكن لمحطة EXTERNAL امتلاك Playlist/Program/Schedule/Radio Command.

## Production rights gate

قبل تغيير أي source إلى production:

1. توثيق صاحب المحتوى وشروط embedding/commercial use.
2. حفظ evidence و`terms_url/source_url/verified_at`.
3. تحديد attribution النصي إن كان مطلوبًا.
4. موافقة دور يملك `rights.approve` عبر Backend API مع audit.
5. نجاح stream/mobile validation المستقل، خصوصًا HLS على Android وiOS.

لا يؤدي health status وحده إلى موافقة الحقوق، ولا تؤدي موافقة الحقوق وحدها إلى إثبات صحة stream.

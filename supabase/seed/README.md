# Seed Data Order

هذه Seeds التنفيذية لمشروع ترتيل، ويشغّلها Supabase CLI بالترتيب المعجمي من `config.toml`:

1. `01_rbac.sql`
2. `02_categories.sql`
3. `03_surahs.sql`
4. `04_providers.sql`
5. `05_app_config.sql`
6. `06_external_stations.sql`
7. `07_video_channels.sql` — روابط اختبار لقنوات الفيديو فقط (ليست دائمة)؛
   يتجاوز بأمان إذا لم يكن جدول `app.video_channels` موجودًا بعد
   (الـ schema المطلوب موثّق في `docs/VIDEO_CHANNELS.md`).

`06_external_stations.sql` يحتوي 58 مصدرًا من inventory المقدم. كل external row:

- `station_source=EXTERNAL`
- `health_status=UNKNOWN`
- `rights_status=REVIEW_REQUIRED`
- `commercial_use_status=UNKNOWN`
- `production_enabled=false`

إعادة التشغيل تستخدم unique slugs/provider keys وعمليات upsert محددة. بيانات الكتالوج الأساسية تُحدّث، بينما records الخارجية الموجودة لا تُستبدل عشوائيًا حمايةً لتعديلات الإدارة. Sync jobs لا تستخدم هذه الملفات كـbusiness logic؛ adapters ستكتب normalized provider records وفق العقود في `docs/EXTERNAL_STATIONS.md`.

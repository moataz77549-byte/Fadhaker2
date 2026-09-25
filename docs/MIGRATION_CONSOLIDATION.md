# توثيق توحيد السكيما — Schema Consolidation

تاريخ التوثيق: 2026-09-23
الفرع: `release/v1.0.64` (مطابق لـ `main` عند `9f226e0`)

هذا المستند يوثّق قرارات توحيد الـ schema في الملفات الجديدة:

```
supabase/migrations/20260830040900_schema_consolidation.sql
supabase/migrations/20260830041000_rbac_seed_consolidation.sql
supabase/migrations/20260830041100_campaign_fields_consolidation.sql
supabase/migrations/20260830041200_video_channels_consolidation.sql
supabase/migrations/20260830041300_public_read_policies_consolidation.sql
supabase/migrations/20260830041400_campaign_dispatcher_cron.sql
supabase/migrations/20260830041500_admin_content_tables.sql
```

لا شيء هنا يُعيد تطبيق migrations سابقة أو يحذف جداول/بيانات. الملفات القديمة
محفوظة كاملةً للتاريخ.

---

## 1. خلفية التعارض

المستودع فيه جيلان من migrations:

- **الجيل القديم**: `20260101000000`، `20260201000000`، `20260301000000`
  (مخططات مبسطة مبكرة: قرآن، إذاعة، إشعارات).
- **الجيل الجديد**: `20260830000100` … `20260830040800`
  (supabase schema كامل: media pipeline، radio automation، RBAC، سياسات RLS…).

الجيلان متعارضان في أسماء/أشكال الجداول، لكنهما غير قابلين للتراجع (لا إعادة
تطبيق ولا حذف). ملفات التوحيد تُنشئ الـ schema التشغيلي النهائي بشكل idempotent
فوق أي حالة قاعدة موجودة.

---

## 2. جدول القرارات (لكل جدول متعارض)

| الجدول | الجيل القديم | الجيل الجديد | المختار (التشغيلي) | السبب |
|---|---|---|---|---|
| `app.roles` / `app.permissions` / `app.role_permissions` / `app.administrators` | — | `20260830040500` + `seed/01_rbac.sql` | الجيل الجديد (40900 + 41000) | RBAC UUID مع `roles.code` بأسماء `UPPER_SNAKE_CASE` (`SUPER_ADMIN`…`MEDIA_ADMIN`)؛ الإنفاذ server-side فقط |
| `app.categories` | — | `20260830000100` | الجيل الجديد | يستخدمه الجوال والإدارة؛ seed `02_categories.sql` قائم. لا يُنشأ جدول `app.media_categories` موازٍ |
| `app.reciters` | — | `20260830000200` | الجيل الجديد | كتالوج القرّاء للوسائط والتشغيل |
| `app.quran_surahs` / `app.quran_ayahs` / `app.quran_pages` / `app.quran_audio_tracks` | `20260101000000` | — (لا يعيد إنشاءها) | الجيل القديم (محفوظ) | لا تعارض؛ جداول نصوص/صفحات/صوتيات القرآن تُحفظ كما هي |
| `app.surahs` | — | `20260830000200` | الجيل الجديد | يقرأها تطبيق Flutter (`quran_download_service`: `number`, `name_ar`, `ayah_count`) |
| `app.content_providers` / `app.audio_providers` | — | `20260830000200` | الجيل الجديد | `station.provider_id` مرجع إلزامي في نموذج المحطات الموحّد |
| `app.stations` | `202601…` (قديم: `source_type`, `is_playable`) | `20260830000100` (نموذج غني: provider/media pipeline/health/rights) | الجيل الجديد + أعمدة convergence للقديم | تطبيق Flutter يقرأ `app.stations` (`name_ar/name_en`, `stream_url`, `fallback_stream_url`, `logo_url`, `stream_type`, `station_source`, `is_active`, `is_featured`, `sort_order`, `metadata`، و`categories(slug)`) بشرط `is_active=true` و`deleted_at IS NULL` مرتبةً بـ `sort_order` |
| `app.playlists` / `app.playlist_items` | — | `20260830000200` | الجيل الجديد (موجود) | نموذج مرتبط بالمحطة لأتمتة الراديو (`provider-sync`, `radio-schedule`) |
| `app.schedules` | — | `20260830000300` | الجيل الجديد (موجود) | جداول البث الزمني التي تقرأها دالة `radio-schedule` |
| `radio.stations` | `20260101000000` | — | الجيل القديم (محفوظ) | دالة `quran-yutla-api` ما زالت تستعلمه؛ يبقى للتوافق ولا يُحذف |
| `radio.now_playing` / `radio.queue_entries` / `radio.schedule_occurrences` | — | `20260830040000…40400` | الجيل الجديد | حالة التشغيل الحية التي تعرضها الإدارة |
| `app.app_config` | `202603` (شكل `key/value` نصي) | `20260830000300` + `seed/05_app_config.sql` | الجيل الجديد: `key`, `value jsonb`, `value_type`, `is_public` | يقرأه الجوال علناً للإعدادات العامة؛ انظر قسم «App config keys» أدناه |
| `app.audit_logs` | `202603` (`id UUID`, `actor_user_id`, `request_id TEXT`) | `20260830000300` (`id BIGINT`, `actor_id`, `request_id UUID`) | الجيل الجديد عند غياب الدالة القديمة؛ والقديمة تُحترم إن وُجدت | ملف 40900 لا يستبدل دالة `create_audit_event` قائمة (return type مختلف) — ينشئها فقط عند غيابها |
| `app.media` / `app.media_processing_jobs` | — | `20260830000200` | الجيل الجديد | مسار معالجة الوسائط الذي تعرضه الإدارة |
| `app.notification_campaigns` / `app.notification_deliveries` | `202603` (حملات مبسطة) | `20260830040600` (حقول تشغيلية) | الجيل الجديد (41100 يجمع النية idempotent) | `sent_at`, `deep_link`, `sent_count`, `failed_count`, `last_error`، والحالة `failed` الصريحة |
| `app.notification_installations` | — | `202602…` (تسجيل FCM للجوال) | محفوظ للتوافق | تنبيه معماري: دالة `quran-yutla-api` تسجّل FCM هنا، بينما دالة `notifications` تُرسل من `app.installations` — راجع `docs/CAMPAIGN_SCHEDULER.md` |
| `app.installations` | — | `202603` | الجيل الجديد (التشغيلي للإرسال) | الإرسال الفعلي (FCM) يستهدف هذا الجدول و`notification_deliveries` تسجّل عليه |
| `app.video_channels` | — | `20260830040700` | الجيل الجديد (41200 يجمع النية idempotent) | يقرأه Flutter (`video_channel_repository`)؛ عمود `stream_url` واحد ويُشتق النوع في التطبيق |
| سياسات RLS العامة | — | `20260830040800` | الجيل الجديد (41300 يجمع النية idempotent) | قراءة عامة دنيا لـ `stations`/`reciters`/`surahs`/`categories`/`video_channels`/`app_config`/`radio.now_playing` فقط؛ كل ما عداها service_role |

---

## 3. ترتيب التطبيق (إلزامي)

```
40900  schema consolidation          (الجداول، الأعمدة، الفهارس، RLS، الدوال)
41000  rbac seed consolidation       (الأدوار والصلاحيات والمصفوفة)
41100  campaign fields consolidation (حقول الحملات التشغيلية)
41200  video channels consolidation  (جدول القنوات)
41300  public read policies          (السياسات العامة الدنيا)
41400  campaign dispatcher cron      (جدولة pg_cron — تتطلب تعبئة يدوية)
41500  admin content tables          (app.identity_settings الناقص فعلاً)
```

ثم:

```
supabase/seed/09_app_config.sql     (مفاتيح النسخة الأدنى — انظر أدناه)
```

- الملفات 40900–41300 **تغني عن إعادة تطبيق** 40500–40800: كل نية فيها مدمجة
  بصيغة idempotent.
- لا تُعَد تطبيق أي migration قديم مطبّق، ولا تُحذف جداول أو بيانات.

---

## 4. كيف تُطبَّق: SQL Editor مقابل `supabase db push`

**الحالة الطبيعية (التاريخ السابق مسجّل applied):**
`supabase db push` — يطبّق فقط migrations الجديدة 40900→41500 فوق القاعدة الحالية.

**قاعدة بيانات جزئية/مكسورة التاريخ:**
نفّذ ملفات 40900→41500 يدوياً بالترتيب عبر **Supabase Dashboard → SQL Editor**
(كل ملف idempotent وقابل لإعادة التشغيل)، ثم صحّح سجل الـ migrations عبر
`supabase migration repair` حسب حالة المشروع. لا تعيد تطبيق الملفات القديمة
المطبقة.

**ملاحظة معروفة:** الملفات القديمة نفسها ليست كلها قابلة للتطبيق من الصفر
بالترتيب (جيل `20260830*` الأول يستخدم `CREATE` غير دفاعي بعد جيل قديم
متعارض). هذا ليس عيباً في التوحيد: التوحيد مصمّم للبناء فوق التاريخ الموجود،
وليس لإعادة بنائه.

---

## 5. App config keys

المفاتيح الدقيقة التي يقرأها تطبيق الجوال من `app.app_config` العام:

| المفتاح | القيمة | `value_type` | الوصف |
|---|---|---|---|
| `min_supported_version` | `"1.0.64"` (نص JSON) | `STRING` | النسخة الدنيا المدعومة من التطبيق |
| `min_supported_build` | `64` (رقم JSON) | `INTEGER` | رقم البناء الأدنى المدعوم |

تُزرع عبر `supabase/seed/09_app_config.sql` (`INSERT … ON CONFLICT (key) DO UPDATE`).

---

## 6. مبادئ أمنية مطبّقة في التوحيد

- لا أسرار حقيقية في أي migration أو seed أو كود — أسماء بيئية/عناصر نائبة فقط.
- عميل Flutter لا يحمل service-role key إطلاقاً ولا يفرّع على الأدوار؛
  إنفاذ RBAC يتم server-side (Edge Functions بمفتاح service_role).
- `last_error` في الحملات ملخص خطأ فقط — لا توكنز أجهزة ولا مفاتيح.
- سياسات RLS العامة: `SELECT` فقط على صفوف/أعمدة عامة صراحةً؛
  `installations` و`campaigns` و`audit` و`administrators` و`radio.*`
  (عدا `now_playing`) تبقى service_role فقط.

---

## 7. ما لم يُختبر

لم يتوفر اتصال بقاعدة بيانات في بيئة العمل؛ التحقق كان نصياً فقط:
لا أسرار حقيقية، لا بيانات demo/test جديدة ظاهرة للمستخدم،
`CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` / `DO $$` /
`ON CONFLICT DO NOTHING` في كل الملفات، `git diff --check` نظيف.
يُنصح بتشغيل migrations على قاعدة تجريبية قبل الإنتاج.

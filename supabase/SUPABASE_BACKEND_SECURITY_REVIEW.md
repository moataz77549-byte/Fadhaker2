# مراجعة أمان وتشغيل خلفية Supabase — Fadhkur

> تاريخ المراجعة: 2026-09-23 · النطاق: `supabase/migrations/` + `supabase/functions/notifications/`
> الملفات الجديدة من هذه المراجعة موسومة بـ ⚠️ **تطبيق يدوي** (لا credentials
> للإنتاج في بيئة العمل — تُطبَّق من Supabase Dashboard → SQL Editor بعد مراجعة
> مالك قاعدة البيانات).

---

## 1) مصفوفة الوصول RLS (ملخص تنفيذي)

الفلسفة المعتمدة في الـ baseline الجديد (`20260830000100`): **fail-closed** —
كل الجداول عليها RLS مفعّل، و`anon`/`authenticated` مسحوب منهما كل شيء، ولا
يصل للبيانات إلا `service_role` عبر Edge Functions / Backend API. التطبيق
(Flutter) لا يحمل إلا المفتاح العام (publishable).

| الجدول / المجموعة | anon (التطبيق) | authenticated | service_role | ملاحظة |
|---|---|---|---|---|
| `app.stations` (نشطة) | SELECT ✅ (عبر `20260830040800`) | — | كامل | كتالوج الراديو العام |
| `app.categories` (نشطة) | SELECT ✅ | — | كامل | تضمين `categories(slug)` في الكتالوج |
| `app.reciters` (نشطون) | SELECT ✅ | — | كامل | |
| `app.surahs` | SELECT ✅ | — | كامل | بيانات مرجعية ثابتة |
| `app.video_channels` (نشطة) | SELECT ✅ | — | كامل | جدول جديد `20260830040700` |
| `app.app_config` | SELECT حيث `is_public=true` ✅ | — | كامل | |
| `radio.now_playing` | SELECT ✅ | — | كامل | حالة البث الحالية |
| `app.installations`, `notification_*` | ❌ | ❌ | كامل | خصوصية الأجهزة |
| `app.media*`, `processing_*`, `storage_upload_*` | ❌ | ❌ | كامل | رفع/معالجة |
| `app.playlists/schedules/programs` | ❌ | ❌ | كامل | إدارة الراديو |
| `radio.*` (عدا now_playing) | ❌ | ❌ | كامل | المحرك والأوامر |
| `app.administrators`, `roles`, `permissions`, `audit_logs`, `system_logs` | ❌ | ❌ | كامل | إدارة وتدقيق |

**لا تُنشأ سياسات كتابة للعميل إطلاقاً.** أي عملية حساسة (رفع، إرسال
إشعارات، أوامر راديو، إدارة محتوى) يجب أن تكون server-side.

### ⚠️ تعارض بين جيلي الـ migrations (مخاطر — انظر §8)
ملفات `202601/202602/202603` (جيل quran_yutla) أنشأت سياسات عامة تشير لأعمدة
غير موجودة في السكيما الجديدة (مثل `is_playable` في `app.stations`)، ودالة
`app.admin_has_permission` تشير لعمود `administrators.user_id` غير الموجود
ولـ `role_id` نصي بينما الأدوار الجديدة UUID. ملف `20260830040800` يحذف
السياسة المكسورة على `app.stations` ويستبدلها. إن كانت قاعدة الإنتاج مبنية
على جيل quran_yutla فقط، فهذه المراجعة تفترض الـ baseline الجديد
(`20260830*`) كمرجع — **يجب توحيد الجيل المطبَّق قبل تطبيق ملفات ⚠️**.

---

## 2) RBAC — الأدوار والصلاحيات

الجداول: `app.roles` / `app.permissions` / `app.role_permissions` /
`app.administrators` / `app.administrator_roles`
(`app.roles.code` مقيّد بـ `^[A-Z_]+$` — أسماء UPPER_SNAKE_CASE حصراً).

الأدوار بعد هذه المراجعة:

| الدور | النطاق |
|---|---|
| `SUPER_ADMIN` | كل الصلاحيات (موجود مسبقاً) |
| `RADIO_ADMIN` | إدارة الراديو: stations/playlists/schedules + أوامر `radio.*` والبث المباشر |
| `CONTENT_ADMIN` | المحتوى: media/reciters/categories (كتابة) + قراءة stations/providers/rights |
| `NOTIFICATION_ADMIN` | `notifications.read` + `notifications.write` فقط |
| `MEDIA_ADMIN` | مكتبة الوسائط: قراءة/كتابة/أرشفة |
| `RADIO_MANAGER`, `CONTENT_EDITOR`, `VIEWER` | أدوار قديمة من الـ seed — محفوظة للتوافق، لا تُستخدم في الكود الجديد |

ملف الزرع: `supabase/migrations/20260830040500_rbac_roles_permissions_seed.sql` ⚠️.
كما أضاف الصلاحيتين **`notifications.read` / `notifications.write`** اللتين كانت
تشير إليهما سياسة RLS موجودة ("Admins manage campaigns") دون أن تُزرعا أبداً.

**قاعدة صارمة:** إنفاذ الأدوار server-side فقط. Flutter لا يفرّع على الأدوار
ولا يحمل service-role key.

---

## 3) Storage — الـ Buckets وسياسات الوصول

| الـ Bucket | عام/خاص | الاستخدام |
|---|---|---|
| `tarteel-media-originals` | خاص | ملفات الرفع الأصلية (عبر upload intents موقّعة) |
| `tarteel-media-processed` | خاص | مخرجات المعالجة (AUDIO_STANDARD_V1) |
| `tarteel-artwork` | **عام** | صور/أغلفة |
| `quran-mushaf`, `reciter-artwork`, `station-artwork`, `app-content` | عام (قراءة) | أصول عامة — سياسات `Public read *` في جيل quran_yutla |

### متى Public URL ومتى Signed URL
- **Public URL**: للأصول في الـ buckets العامة فقط (`tarteel-artwork` وأصول
  المحتوى العام). تُستخدم مباشرة في التطبيق (شعارات، صور قرّاء).
- **Signed URL**: لكل ما في الـ buckets الخاصة (الأصول الصوتية الأصلية
  والمعالَجة). تُولَّد server-side بصلاحية قصيرة عند الحاجة للتشغيل/التحميل
  المصرّح — لا تُكشف روابط دائمة لملفات خاصة.

### سياسات الرفع/التعديل/الحذف
- الرفع يتم حصرياً عبر **upload intents** (`app.create_media_upload_intent`)
  بتحقق صارم: امتداد/MIME من قائمة بيضاء (`app.storage_upload_formats`)، حد
  50MB، مفتاح idempotency، مسار كائن مُشتق حتمياً
  `media/<media_id>/original/<intent_id>.<ext>`، وانتهاء صلاحية 15 دقيقة.
- لا سياسات `storage.objects` تسمح للعميل بالكتابة/الحذف — كل عمليات الكتابة
  عبر service_role. سياسة "Service role and admins access private storage"
  تمنح `FOR ALL` لمن يملك `media.write` — **تُستخدم بحذر**: أي admin يملك
  `media.write` يستطيع حذف/استبدال ملفات الآخرين في الخاصة. التوصية: تقييد
  الحذف لخدمة التنظيف الخلفية فقط (راجع §8).

---

## 4) معالجة الصوت — دورة الحياة الكاملة

الجداول: `app.media` / `app.media_processing_jobs` /
`app.media_processing_attempts` / `app.processed_media_variants` /
`app.processing_profiles` / `app.processing_error_codes`.

```
UPLOAD (intent موقّع → اكتمال → media.status='UPLOADED')
  → job يُنشأ (PENDING)
  → worker يستدعي app.claim_media_processing_job (advisory lock + lease)
  → PROCESSING (heartbeat دوري عبر app.heartbeat_media_processing_job)
  → app.record_media_probe (تحقق ffprobe: صيغة/ترميز/مدة)
  → app.complete_media_processing_job
      → تحقق صارم: مسار الكائن، بصمة الإخراج، مطابقة ملف المعالجة
         (AUDIO_STANDARD_V1: m4a/AAC 96kbps/44.1kHz، تطبيع EBU R128،
          سياسة "no_trim_no_tempo_no_pitch_no_crossfade" لصوت القرآن)
      → processed_media_variants (AVAILABLE) + media.status='READY'
         + processed_path/duration/sha256
  → التشغيل يقرأ الـ variant الجاهز (Signed URL من البكت الخاص)
```

**الفشل وإعادة المحاولة** (`app.fail_media_processing_job`):
- رمز الخطأ يجب أن يكون من `app.processing_error_codes` (17 رمزاً موثّقاً).
- `retryable=true` (مثل `DOWNLOAD_FAILED`, `STORAGE_FAILED`, `FFPROBE_TIMEOUT`,
  `PROCESSING_TIMEOUT`, `DATABASE_FAILED`, `WORKER_INTERNAL_ERROR`) **و**
  `attempts < max_attempts` → الحالة `RETRY_WAIT` مع `next_attempt_at`
  (تأخير 5ث–24س).
- غير قابل لإعادة المحاولة أو نفاد المحاولات → `FAILED` نهائياً، و`media`
  تُوسم `FAILED` مع `failure_code/message`.
- **الاسترداد التلقائي** (`app.recover_stale_media_processing_jobs`): أي job
  عالق في `PROCESSING` بعد انتهاء الـ lease تُهجر محاولته (`ABANDONED`) ويعاد
  للطابور أو يُفشل نهائياً — لا توجد jobs عالقة للأبد.
- **التطبيق لا يحظر المعالجة**: لا يوجد أي blocking في Flutter — المعالجة
  خلفية بالكامل، والواجهة تعرض الحالات فقط.

---

## 5) أتمتة الراديو

المكوّنات: `app.stations` (+`stream_url`/`fallback_stream_url`)،
`app.playlists`/`playlist_items`، `app.programs`، `app.schedules` (+القوالب)،
`radio.schedule_occurrences`، `radio.radio_commands` (+`radio.command_effects`)،
`radio.queue_entries`، `radio.station_leases`، `radio.engine_states`،
`radio.queue_snapshots`، `radio.now_playing`، `radio.radio_events`،
`radio.play_history`.

- **تغيير المحطة من الإدارة لا يحتاج تحديث التطبيق**: التطبيق يجلب الكتالوج
  (`app.stations` العامة) و`stream_url` عند كل تحميل/تحديث — أي تعديل على
  الاسم/الرابط/الشعار/التفعيل/الترتيب ينعكس فوراً (مع كاش محلي للطوارئ).
- **Schedules**: `ONE_TIME`/`DAILY`/`WEEKLY` بمناطق زمنية IANA مُتحقق منها،
  أولويات (`LOW`→`EMERGENCY`/`LIVE`)، وسياسات مقاطعة (`FINISH_CURRENT`/
  `INTERRUPT`/`PLAY_NEXT`). سلامة الجدولة (`station_schedule_integrity`).
- **المحطة النشطة**: `radio.engine_states.mode` (`AUTO`/`SCHEDULED`/`MANUAL`/
  `LIVE`/`RECOVERING`…) + `radio.now_playing` (مقروءة علناً).
- **Failover**: `fallback_stream_url` في `app.stations` + `health_status`
  (`HEALTHY`/`DEGRADED`/`UNREACHABLE`/`INVALID`) مع `consecutive_failures`
  وفحوصات `app.stream_health_checks` الدورية.
- **Recovery**: `radio.recover_stale_automation` يعيد العناصر العالقة
  (`CLAIMED`/`PROCESSING`/`DISPATCHED`) إلى `PENDING` عند تجاوز الـ fencing
  token — مع `radio.station_leases` لمنع مالكين متزامنين (fencing).
- **الأوامر الإدارية** (`PLAY_NOW`/`SKIP`/`START_LIVE`…): عبر `radio_commands`
  بـ `idempotency_key` — server-side فقط.

⚠️ ملاحظة: دالة `supabase/functions/radio-schedule` الحالية تُرجع **بيانات
تجريبية ثابتة** (محطة وهمية وعدد مستمعين ثابت) ولا تقرأ قاعدة البيانات —
يجب استبدالها بالقراءة الحية من `radio.now_playing`/`app.schedules` أو إيقافها
قبل الإنتاج. ودالة `managed-radio` تقرأ `radio.now_playing` بمفتاح service_role
(النمط الصحيح).

---

## 6) الإشعارات (Notification Center backend)

- الجدول `app.notification_campaigns` **موجود مسبقاً** — أُضيفت له الحقول
  التشغيلية عبر `20260830040600` ⚠️: `sent_at`, `deep_link`, `sent_count`,
  `failed_count`, `last_error` + حالة `failed` الصريحة.
- التسجيل/الإلغاء من التطبيق عبر `quran-yutla-api/notifications/{register,revoke}`
  (مفتاح عام) — جدول `app.installations` (موافقة صريحة + `revoked_at`).
- **الإرسال من Edge Function فقط** (`supabase/functions/notifications/index.ts`
  — أُعيدت كتابتها في هذه المراجعة):
  1. تحقق JWT ثم **تفويض إداري حقيقي**: مدير نشط يملك `notifications.write`
     أو دور `SUPER_ADMIN` (النسخة السابقة كانت تقبل أي مستخدم مسجّل — ثغرة
     أُغلقت).
  2. تحقق `title`/`body` + تعقيم deep link بقائمة بيضاء لمسارات التطبيق.
  3. حفظ الحملة أولاً (`processing` أو `scheduled` إذا `scheduled_at` مستقبلي —
     يُرجع 202 دون إرسال).
  4. أنواع: `announcement` / `urgent` / `live_broadcast` /
     `featured_recitation` / `reminder` — الطارئ والبث المباشر بأولوية HIGH.
  5. إرسال FCM HTTP v1 بحساب خدمة تُقرأ أسراره **من Supabase Secrets وقت
     التشغيل فقط** (`FIREBASE_PROJECT_ID`/`FIREBASE_CLIENT_EMAIL`/
     `FIREBASE_PRIVATE_KEY`) — لا أسرار في الكود إطلاقاً.
  6. تسجيل كل تسليم في `app.notification_deliveries` + تحديث عدّادات الحملة
     + سجل تدقيق عبر `app.create_audit_event` (دون طباعة توكنز أو مفاتيح).
- **ممنوع الإرسال من Flutter** — لا يوجد أي service key في التطبيق.

---

## 7) الفيديو

الجدول `app.video_channels` لم يكن موجوداً في أي migration (الـ seed
`07_video_channels.sql` كان يتجاوز بأمان). أُنشئ عبر
`supabase/migrations/20260830040700_video_channels_table.sql` ⚠️ بالـ schema
الموثّق في `docs/VIDEO_CHANNELS.md`:
`slug`, `name_ar`, `name_en`, `stream_url` (يُشتق منه النوع: `.m3u8`→HLS،
روابط يوتيوب→YouTube، `.mp4`→MP4), `logo_url`, `is_active`, `sort_order`,
`metadata` + قراءة عامة للقنوات النشطة فقط، والكتابة service_role (إدارة).
أي قناة تُضاف/تُفعّل/تُرتَّب من الإدارة تظهر في التطبيق دون تحديث.

---

## 8) مخاطر أمنية وملاحظات (بدون عرض أي قيم سرية)

1. **تعارض جيلي الـ migrations** (حرج): ملفات quran_yutla (`202601–202603`)
   وملفات tarteel (`20260830*`) تعرّفان نفس الجداول بأعمدة مختلفة؛ تطبيق
   الاثنين معاً على قاعدة واحدة سيفشل (`create table` بدون `IF NOT EXISTS`
   بعد `CREATE TABLE IF NOT EXISTS`) أو يُنتج سياسات مكسورة (عمود
   `is_playable` غير موجود، دالة `admin_has_permission` تشير لـ
   `administrators.user_id` غير الموجود). **التوصية:** تثبيت جيل واحد مرجعي
   (المقترح: tarteel الجديد) وتطبيق ملفات ⚠️ عليه فقط.
2. **دالة الإرسال السابقة** كانت تقبل أي JWT صالح دون تحقق من دور إداري —
   أُصلحت في النسخة الجديدة (فحص `notifications.write`/`SUPER_ADMIN`).
3. **سياسة التخزين الخاصة** تمنح `FOR ALL` لأي admin يملك `media.write` —
   تشمل الحذف. التوصية: قصر الحذف على خدمة التنظيف الخلفية وتقييد السياسة
   لـ SELECT/INSERT/UPDATE.
4. **عمود `installations.firebase_token_encrypted`**: الاسم يوحي بتشفير، لكن
   الدالة تمرّره خاماً إلى FCM — إن كان غير مشفّر فعلياً فهو PII حساس في
   قاعدة البيانات؛ يُوصى بالتحقق من آلية التشفير عند التسجيل وتوثيقها.
5. **`radio-schedule` Edge Function** تُرجع mock ثابت — خطر تسرب بيانات
   وهمية للإنتاج إن استُخدمت.
6. **لا أسرار في Flutter**: تم التحقق — `supabase_config.dart` يحمل المفتاح
   العام فقط عبر `--dart-define`. لا service-role key في الكود.
7. **ملف `~/workspace/user/files/fadhkur-2f78c-firebase-adminsdk-*.json`**
   (مفتاح حساب خدمة Firebase) موجود خارج الريبو — لم يُقرأ ولم يُنسخ ولم
   يُدخل للريبو. التوصية: تدويره إن لامس أي قناة غير آمنة، وحفظ الأسرار في
   Supabase Secrets فقط.

---

## 9) تطبيق ملفات ⚠️ يدوياً (ترتيب مقترح)

```sql
-- 1. supabase/migrations/20260830040500_rbac_roles_permissions_seed.sql
-- 2. supabase/migrations/20260830040600_notifications_campaign_fields.sql
-- 3. supabase/migrations/20260830040700_video_channels_table.sql
-- 4. supabase/migrations/20260830040800_public_read_policies.sql
```
ثم من Supabase Dashboard → Edge Functions → Secrets:
`FIREBASE_PROJECT_ID` / `FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY`
(لدالة `notifications`)، ثم `supabase functions deploy notifications`.

بعد التطبيق: `supabase/seed/07_video_channels.sql` سيعمل فعلياً (بعد أن كان
يتجاوز)، و`supabase/seed/01_rbac.sql` يبقى متوافقاً (الأدوار القديمة محفوظة).

# Deployment & Infrastructure Guide — Fadhkur (فذكر)

> **آخر تحديث:** 2026-09-23 (إصدار `1.0.64`, build `64`).
> ⚠️ لا تضع أي secret أو مفتاح خاص في هذا الملف — فقط أسماء الأسرار والمتغيرات.

## ⚠️ تحذير حرج: تعارض جيلي الـ Migrations (اقرأ قبل أي `supabase db push`)

يوجد في `supabase/migrations/` **جيلان متعارضان** يعرّفان نفس الجداول بأعمدة
غير متوافقة:

- **الجيل القديم:** `20260101000000` … `20260301000000` (مثال: `app.roles`
  بمفتاح `id TEXT` وعمود `name_arabic`)
- **الجيل الجديد:** `20260830000100` … `20260830040800` (مثال: `app.roles`
  بمفتاح `id uuid` وأعمدة `code`/`name`)

**الحل (2026-09-23):** أُضيفت ملفات توحيد **idempotent بالكامل**
`20260830040900` → `20260830041500` تُقارب أي حالة DB إلى schema موحّد
(اختيار الأفضل لكل جدول موثّق في `docs/MIGRATION_CONSOLIDATION.md`)، وتُغني
عن إعادة تطبيق `20260830040500`…`20260830040800` (نيّتها مدمجة فيها بأمان
حتى لو طُبّق بعضها جزئياً). كل الملفات تستخدم `IF NOT EXISTS` وكتل `DO`
و`ON CONFLICT DO NOTHING` — آمنة لإعادة التشغيل.

**ترتيب التطبيق الإلزامي** (بعد تثبيت الجيل المرجعي من مالك قاعدة البيانات):

```
20260830040900_schema_consolidation.sql   # تقارب الـ schema الأساسي
20260830041000_rbac_seed_consolidation.sql # زرع الأدوار الخمسة
20260830041100_campaign_fields_consolidation.sql
20260830041200_video_channels_consolidation.sql
20260830041300_public_read_policies_consolidation.sql
20260830041400_campaign_dispatcher_cron.sql  # pg_cron (عناصر نائبة تُملأ يدوياً)
20260830041500_admin_content_tables.sql
```

ثم `supabase/seed/09_app_config.sql` (مفاتيح force update — idempotent).

لا تُعَد تشغيل migrations مطبَّقة سابقًا، ولا تحذف جداول أو بيانات قائمة.

### متابعة معلّقة: وصول لوحة الإدارة للجداول المقيدة
الجداول `playlists` و`schedules` و`audit_logs` و`installations`
و`identity_settings` مقيدة بـ `service_role` في RLS، وعميل الإدارة يستخدم
anon key — الصفحات تعرض حالة «غير متاح» الصادقة حالياً. الحل: سياسة
admin-JWT (custom claim) أو وكيل عبر Edge Function يتحقق من جدول
`administrators` — يُنفَّذ من مالك الباك-إند قبل منح الإدارة صلاحيات الكتابة.

## 1. Local Development Quickstart

### Prerequisites
- Node.js 20+ & npm
- JDK 17 & Android SDK (for Android app)
- Docker & Docker Compose (for Supabase & Icecast/Liquidsoap)

### Verify Canonical Quran Dataset
```bash
./scripts/validate-checksums.sh
```

### Run Supabase Database & Migrations Locally
```bash
supabase start
supabase db reset
```

### Run Admin Web Dashboard
```bash
cd apps/admin
npm install
npm run dev
# Dashboard accessible at http://localhost:3000
```

### Run Audio Processing Worker
```bash
cd services/audio-worker
npm install
npm run start
```

### Run Managed Radio Engine
```bash
cd services/radio-engine
npm install
npm run start
```

---

## 2. Production Deployment Topology
- **Database & Auth**: Supabase Managed Cloud or Self-Hosted PostgreSQL 15+ with pg_crypto.
- **Edge API**: Supabase Edge Functions (`fadhkur-api` and `notifications`).
- **Web Admin**: Next.js deployed on Vercel or containerized on Cloud Run.
- **Radio Engine & Audio Worker**: Dedicated compute nodes running Liquidsoap 2.2 and Icecast 2 with persistent volumes for audio cache.
- **Android Client**: Signed release APK distributed via Google Play Store and official APK mirrors.

## 3. Edge Functions — النشر

الدوال في `supabase/functions/` (انظر كل مجلد لملف README الخاص به عند توفره):

| Function | الدور |
|---|---|
| `notifications` | إرسال FCM عبر HTTP v1 **حصريًا** — أسرار الخادم فقط (`FIREBASE_PROJECT_ID` / `FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY` كـ Supabase Secrets) |
| `quran-yutla-api` | واجهة التطبيق العامة (تسجيل/سحب الإشعارات بالمفتاح العام) |
| `managed-radio` | حالة الإذاعة المدارة (يقرأ `radio.now_playing` بمفتاح `service_role`) |
| `provider-sync` | مزامنة المحطات الخارجية |
| `radio-schedule` | جدولة البث |
| `audio-metadata` | بيانات الصوت |
| `health` | فحص الصحة |

النشر: `supabase functions deploy <name>` ثم ضبط الأسرار عبر
`supabase secrets set` — لا تُضمَّن الأسرار في الكود أو الريبو أبدًا.

## 4. عملية الإصدار (Android)

1. تحديث `versionName`/`versionCode` في `apps/mobile/android/app/build.gradle.kts`
   (الحالي: `1.0.64` / `64`, `minSdk = 26`).
2. التأكد من GitHub Secrets (انظر `docs/FIREBASE_SETUP.md` — الأسماء فقط).
3. تشغيل workflow `android-release.yml`: يحقن `google-services.json` من
   `FIREBASE_GOOGLE_SERVICES_JSON_BASE64` ويبني بـ `--dart-define`، ثم يوقّع
   بمخزن `ANDROID_KEYSTORE_BASE64`.
4. فحص سلامة النص القرآني `./scripts/validate-checksums.sh` (بوابة fail-closed)
   قبل أي إصدار.
5. النشر على Google Play / مرايا APK الرسمية.


## 5. Release 1.0.64 — source verification

- Release source commit: `c43aade613b4a2ec0acc5d92c7c68b3931651dbe`.
- This branch is configured to run `android-release.yml` on pushes to `release/v1.0.64` as well as manual dispatch.
- The release gate must keep `versionCode=64` and `versionName=1.0.64`.

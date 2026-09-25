# Security Review & Privacy Posture — Fadhkur (فذكر)

> **آخر فحص شامل:** 2026-09-23 (حالة الفرع `main` كاملة + تاريخ git الأخير).
> هذا الملف يذكر الملفات فقط — لا قيم أسرار إطلاقًا.

## 0. نتائج الفحص الأمني (2026-09-23)

- **لم يُعثر على أي secret حقيقي** في الشجرة الحالية: لا private keys، لا JWT
  حقيقية، لا `sb_secret_*`، لا مفاتيح Google (`AIza...`)، ولا service account JSON.
- المواضع التي تطابقت مع أنماط البحث هي **ثوابت برمجية/توثيق فقط**:
  - `supabase/functions/notifications/index.ts`: السلسلة النصية
    `'-----BEGIN PRIVATE KEY-----'` مستخدمة لتنظيف المفتاح المقروء من
    Supabase Secrets وقت التشغيل — ليست مفتاحًا حقيقيًا.
  - `services/audio-worker/src/errors.ts` + `test/security.test.ts`: تعمية
    (redaction) لأنماط `sb_secret_*` في رسائل الأخطاء — اختبارات فقط.
  - `docs/*`: إشارات توثيقية لأسماء الأسرار (`service_role`، `client_secret`…)
    دون قيم.
  - `.github/workflows/phase5b-real-icecast.yml` و`phase6-radio-automation.yml`:
    القيم الحرفية `<redacted>` مُثبَّتة في الملف (كلمات مرور Icecast أُخفيت
    يدويًا) — ليست تسريبًا لكنها **تجعل الـ workflows غير صالحة للتشغيل**
    (تُنشئ بيانات اعتماد غير حقيقية). يوصى بتوليد كلمات مرور مؤقتة ديناميكيًا
    بدل القيم المثبتة.
- **تاريخ git:** لا أثر لأي ملف service account حقيقي (بحث `--diff-filter=A`
  عن `*adminsdk*` / `*service*account*.json` — فارغ). الملف المحظور
  `fadhkur-2f78c-firebase-adminsdk-*.json` موجود فقط خارج الريبو
  (`~/workspace/user/files/`) ولم يُقرأ أو يُنسخ أو يُدخل للريبو.
- `apps/mobile/android/app/google-services.json` موجود محليًا لكنه
  **gitignored وغير متعقَّد** — لا يُضمَّن في الريبو.

## 1. Secrets Management & Zero-Leakage Policy
- **Client-Facing Apps (Android / Web)**: Strictly bundle only the **public Supabase publishable anonymous key**.
- **Backend Secrets**: `SUPABASE_SERVICE_ROLE_KEY`, `ICECAST_SOURCE_PASSWORD`, `ICECAST_ADMIN_PASSWORD`, and `FCM_SERVER_KEY` are strictly server-side environment variables and are never bundled into client packages, APK assets, or Git history.
- **Git Repo Scans**: Verified clean from hardcoded production credentials.

## 2. Row-Level Security (RLS) & Authorization
- Every table across `app` and `radio` schemas has `ENABLE ROW LEVEL SECURITY;` actively enforced.
- Direct anonymous writes or updates to Quran text, reciters, or radio engine states are strictly blocked with `FOR ALL USING (false)`.
- Administrative mutations enforce `app.has_permission(...)` evaluated securely inside PostgreSQL using `SECURITY DEFINER` and a fixed search path (`SET search_path = app, public`).

## 3. Privacy & Zero-Surveillance Architecture
- **Location Privacy**: Prayer times and Islamic calendar calculations are executed completely offline on-device. No user GPS coordinates or precise IP locations are recorded or transmitted.
- **Pseudonymous Device Identifiers**: The push notification registration system uses a client-generated UUID `installation_id` paired with a SHA-256 hashed secret. No personal identity (name, email, phone number, IMEI) is gathered.
- **Opt-in & Immediate Revocation**: Notifications require explicit user consent (`consent_version` / `fcm_user_consent`). No OS permission dialog is shown on startup; no FCM topic is subscribed before consent (`NotificationPreferences.topics` are opt-in only). When disabled, the server replaces the FCM token with `'REVOKED'`, disabling all outbound alerts, and legacy topics (`daily_content`, `app_announcements`) are unsubscribed for hygiene.

## 4. Audio & Quran Integrity Defense (Fail-Closed)
- Canonical Quran text is cryptographically anchored via SHA-256 checksums (`manifest.json`). Any drift or attempted mutation halts build and serving pipelines immediately.
- Audio normalization mandates EBU R128 (-16.0 LUFS) with SHA-256 asset verification before deployment to public CDN distribution.

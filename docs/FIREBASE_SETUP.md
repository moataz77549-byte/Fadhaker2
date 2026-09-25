# Firebase & FCM Setup Guide — Fadhkur (فذكر)

> **آخر تحديث:** 2026-09-23 (إصدار `1.0.64`, build `64`).
> ⚠️ لا تضع أي secret أو مفتاح خاص في هذا الملف أو في أي وثيقة — فقط أسماء
> المتغيرات والأسرار المطلوبة.

## 1. مشروع Firebase

- **Project ID:** `fadhkur-2f78c` (مشروع الإنتاج)
- **Android package:** `app.fadhkur`
- ملف `apps/mobile/lib/firebase_options.dart` مولّد، و**لا يحتوي أي مفاتيح ثابتة**:
  القيم تُحقن عبر `--dart-define` عند البناء (انظر `.github/workflows/android-release.yml`)
  وحارس `AppEnvironmentConfig.assertFirebaseProject()` يمنع أن يشير بناء غير الإنتاج
  إلى مشروع الإنتاج.
- ملف `android/app/google-services.json` **gitignored وغير متعقَّد**؛ يُحقن وقت البناء
  من GitHub Secret (انظر أدناه). لا تضفه إلى الريبو أبدًا.

## 2. GitHub Secrets المطلوبة (الأسماء فقط)

للإصدار عبر `.github/workflows/android-release.yml` (قيم `--dart-define` + حقن
`google-services.json`):

| Secret | الغرض |
|---|---|
| `FIREBASE_PROJECT_ID` | `fadhkur-2f78c` للإنتاج |
| `FIREBASE_API_KEY` | مفتاح واجهة Firebase العام للعميل |
| `FIREBASE_ANDROID_APP_ID` | معرّف تطبيق Android |
| `FIREBASE_MESSAGING_SENDER_ID` | مرسِل FCM |
| `FIREBASE_STORAGE_BUCKET` | حاوية التخزين |
| `FIREBASE_GOOGLE_SERVICES_JSON_BASE64` | `google-services.json` مشفّرًا بـ base64 |
| `SUPABASE_PUBLISHABLE_KEY` | المفتاح العام لـ Supabase |
| `ANDROID_KEYSTORE_BASE64` | مخزن مفاتيح التوقيع |
| `ANDROID_KEY_ALIAS` | اسم مستعار للمفتاح |
| `ANDROID_KEY_PASSWORD` | كلمة مرور المفتاح |
| `ANDROID_STORE_PASSWORD` | كلمة مرور المخزن |

أسرار الخادم (Supabase Edge Functions) — تُضبط عبر **Supabase Secrets** وليس GitHub:

| Secret | الغرض |
|---|---|
| `FIREBASE_PROJECT_ID` | مشروع الإرسال (`notifications`) |
| `FIREBASE_CLIENT_EMAIL` | بريد حساب الخدمة |
| `FIREBASE_PRIVATE_KEY` | المفتاح الخاص (يُقرأ وقت التشغيل فقط) |
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | وصول الخادم لقاعدة البيانات |

## 3. Firebase Admin SDK — ملف ممنوع

ملف JSON لحساب الخدمة (نمط `fadhkur-2f78c-firebase-adminsdk-*.json`)
**محظور تمامًا**: لا يقرأ، لا ينسخ، لا يدخل الريبو أو أي وثيقة أو log.
الاستخدام المشروع الوحيد: استخراج `FIREBASE_CLIENT_EMAIL` و`FIREBASE_PRIVATE_KEY`
لضبطهما كـ Supabase Secrets على الخادم، ثم تدويره دوريًا من وحدة تحكم Firebase.
مصدر الحقيقة المفقودة: لا نسخة منه في هذا الريبو (تم التحقق 2026-09-23).

## 4. Privacy-First Consent Flow

1. التطبيق لا يعرض أي نافذة إذن نظام عند الإقلاع.
2. `main()` يستدعي `ensureFirebaseInitialized()` (تهيئة idempotent عبر
   `DefaultFirebaseOptions` المدفوعة بالبيئة) قبل Supabase و`AppServices.init`؛
   معالج الخلفية يعيد التهيئة في عزلته الخاصة.
3. ورقة موافقة توضيحية تشرح الغرض الديني والإذاعي من الإشعارات.
4. عند الموافقة، يستخرج العميل رمز FCM من Firebase SDK.
5. يُسجَّل `installation_id` عشوائي (UUID) في Supabase عبر
   `POST /installations/register` — معرفات مستعارة، بلا هوية شخصية.
6. لا يُشترَك في أي topic قبل الموافقة الصريحة؛ تفضيلات كل topic
   (`fcm_pref_*` في SharedPreferences، opt-in افتراضيًا) تقود
   `subscribeToTopic`/`unsubscribeFromTopic`. الاشتراك الافتراضي **opt-in = false**.
7. دورة حياة الرمز (التحديث، السحب، تنظيف الرموز غير الصالحة) موثقة في
   `docs/FCM_TOKENS.md`.

### تصنيف الـ topics (مصدر الحقيقة: `NotificationPreferences.topics`)

| Topic | التسمية العربية |
|---|---|
| `morning_athkar` | أذكار الصباح |
| `evening_athkar` | أذكار المساء |
| `sleep_athkar` | أذكار النوم |
| `friday_kahf` | تذكير سورة الكهف (الجمعة) |
| `live_radio` | تنبيهات البث المباشر |
| `general` | إشعارات عامة |
| `prayer_fajr` | تنبيه صلاة الفجر (سحابي) |
| `prayer_dhuhr` | تنبيه صلاة الظهر (سحابي) |
| `prayer_asr` | تنبيه صلاة العصر (سحابي) |
| `prayer_maghrib` | تنبيه صلاة المغرب (سحابي) |
| `prayer_isha` | تنبيه صلاة العشاء (سحابي) |

Topics قديمة (`daily_content`, `app_announcements`) تُزال تلقائيًا عند
السحب/الاستعادة (نظافة hygiene).

## 5. Server-Side Dispatch — Edge Function `notifications`

- إرسال FCM عبر **FCM HTTP v1 API** يتم حصريًا من Edge Function
  `supabase/functions/notifications/` — العميل لا يرسل بثًا أبدًا.
- المفتاح الخاص يُقرأ من Supabase Secrets **وقت التشغيل فقط**، ولا يُكتب في
  الكود ولا يُسجَّل ولا يُعاد في الردود.
- التفويض: الـ Bearer الخاص بالمشرف يجب أن ينتمي لمسؤول نشط في
  `app.administrators` يحمل صلاحية `notifications.write` (أو دور SUPER_ADMIN).
- أنواع الحملات: `announcement | urgent | live_broadcast | featured_recitation | reminder`
  (العاجلة والمباشرة بأولوية HIGH).
- دورة حياة الحملة: `draft → scheduled → processing → completed|failed|cancelled`،
  وكل تسليم جهاز يُسجَّل في `app.notification_deliveries` قبل/بعد الإرسال.
- الـ deep links مقيدة بقائمة بيضاء لمسارات داخل التطبيق فقط (دفاع ضد open-redirect).
- التسجيل/السحب من العميل يتم عبر `quran-yutla-api/notifications/{register,revoke}`
  بالمفتاح العام فقط.

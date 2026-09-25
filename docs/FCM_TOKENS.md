# FCM Tokens — Supabase Storage & Lifecycle — Fadhkur (فذكر)

> لا تُنشأ migrations جديدة لهذا الملف — الجدول موجود ومطبّق. هذه الوثيقة مرجع فقط.

## 1. الجدول: `app.notification_installations`

المصدر: `supabase/migrations/20260201000000_quran_yutla_core_schemas.sql` (قسم 1.11).

| العمود | النوع | ملاحظات |
|---|---|---|
| `installation_id` | UUID PK | يولّده العميل عشوائياً (v4) ويُحفظ في `SharedPreferences` |
| `hashed_secret` | TEXT | SHA-256 لسرّ عشوائي يولّده العميل — للتحقق من ملكية السجل |
| `fcm_token` | TEXT NOT NULL | توكن FCM الحالي للجهاز |
| `platform` | TEXT | `android` / `ios` / `web` |
| `app_version` | TEXT | يقرأه العميل ديناميكياً عبر `package_info_plus` (لا قيمة ثابتة في العميل) |
| `locale` / `timezone` | TEXT | افتراضي `ar` / `Asia/Riyadh` |
| `consent_version` | TEXT | نسخة سياسة الخصوصية التي وافق عليها المستخدم |
| `preferences` | JSONB | خريطة التفضيلات الحبيبية (مفاتيح `NotificationPreferences.topics`) + المفاتيح القديمة المشتقة (`prayer_alerts`, `daily_verse`, `live_radio_alerts`) للتوافق مع لوحة الإدارة |
| `is_active` | BOOLEAN | `true` للسجلات النشطة |
| `revoked_at` | TIMESTAMPTZ | يُضبط عند سحب الموافقة |
| `updated_at` | TIMESTAMPTZ | يُحدّث مع كل تسجيل |

## 2. RLS — الكتابة عبر Service Role فقط

```sql
ALTER TABLE app.notification_installations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role manages installations"
  ON app.notification_installations FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');
```

لا توجد سياسة كتابة للمستخدمين العاديين — لذلك **العميل لا يكتب في الجدول مباشرة**،
بل عبر Supabase Edge Function التي تعمل بمفتاح service-role.

## 3. تدفق التسجيل (منع التكرار)

1. العميل (`PushNotificationService._registerOrUpdateSupabaseInstallation`) يرسل:
   `POST /functions/v1/quran-yutla-api/notifications/register`
   مع `installationId` + `hashedSecret` + `fcmToken` + `platform` + `appVersion` + `consentVersion` + `preferences`.
2. الـ Edge Function (`supabase/functions/quran-yutla-api/index.ts`) تنفّذ **upsert على `installation_id`**
   (المفتاح الأساسي) — نفس الجهاز يُحدّث سجله ولا تُنشأ صفوف مكررة.
3. عند `onTokenRefresh` يعيد العميل التسجيل **بنفس `installation_id`** → التوكن الجديد
   يحلّ محل القديم في نفس الصف، فقط إذا كانت موافقة المستخدم ما تزال سارية.

## 4. سحب الموافقة

`POST /functions/v1/quran-yutla-api/notifications/revoke` مع `installationId` + `hashedSecret` →
`is_active=false`، `revoked_at=NOW()`، `fcm_token=NULL`.
بالتوازي يحذف العميل توكن FCM (`deleteToken()`) ويلغي الاشتراك في كل الـ topics
المعروفة والقديمة (`daily_content`, `app_announcements`).

## 5. تنظيف التوكنات غير الصالحة (Invalid Token Cleanup)

آلية التنظيف تقع على الـ backend (لا يملك العميل service-role):

- عند الإرسال عبر FCM HTTP v1 من Edge Function، أي استجابة بخطأ
  `UNREGISTERED` / `NotRegistered` / `InvalidRegistration` تعني أن التوكن ميت.
- الإجراء المطلوب في طبقة الإرسال: تحديث السجل المطابق
  (`SET is_active=false, fcm_token=NULL, revoked_at=NOW() WHERE fcm_token=<dead>`)
  حتى لا يُعاد الإرسال لتوكن ميت.
- يُنصح بمهمة دورية (cron) تُعطّل السجلات التي فشل إرسالها N مرات متتالية
  أو التي لم تُحدّث منذ 90 يوماً.

## 6. ضوابط الخصوصية

- لا اشتراك في أي FCM topic قبل موافقة صريحة داخل التطبيق + إذن النظام.
- التفضيلات opt-in افتراضياً (`false`) وتُحفظ في `SharedPreferences`
  (`fcm_pref_<key>`)؛ عند التفعيل `subscribeToTopic` وعند التعطيل `unsubscribeFromTopic`.
- الـ topics المعتمدة: `morning_athkar`, `evening_athkar`, `sleep_athkar`,
  `friday_kahf`, `live_radio`, `general`, `prayer_fajr`, `prayer_dhuhr`,
  `prayer_asr`, `prayer_maghrib`, `prayer_isha` — ممنوع الاشتراك التلقائي في الكل.
- لا مفاتيح service-role في Flutter أبداً.

# جدولة الحملات — Campaign Scheduler

تاريخ التوثيق: 2026-09-23

المكوّنات:

| المكوّن | المسار | الدور |
|---|---|---|
| الدالة | `supabase/functions/campaign-dispatcher/index.ts` | تلتقط الحملات المستحقة وترسلها عبر FCM HTTP v1 |
| الجدولة | `supabase/migrations/20260830041400_campaign_dispatcher_cron.sql` | مهمة pg_cron كل 5 دقائق تستدعي الدالة |
| التوحيد | `supabase/migrations/20260830041100_campaign_fields_consolidation.sql` | حقول `sent_at`/`deep_link`/`sent_count`/`failed_count`/`last_error` |

---

## 1. إعداد الأسرار (بالأسماء فقط — لا قيم في هذا المستند)

تُضبط الأسرار في: **Supabase Dashboard → Edge Functions → campaign-dispatcher → Secrets**

| اسم الـ Secret | الوصف |
|---|---|
| `SUPABASE_URL` | رابط مشروع Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | مفتاح service_role (يُستخدم server-side فقط داخل الدوال) |
| `FIREBASE_PROJECT_ID` | معرّف مشروع Firebase |
| `FIREBASE_CLIENT_EMAIL` | بريد حساب الخدمة (service account) |
| `FIREBASE_PRIVATE_KEY` | المفتاح الخاص لحساب الخدمة |

⚠️ الأسرار **وقت التشغيل فقط**: تُقرأ داخل الدالة من البيئة، ولا تظهر إطلاقاً
في الكود أو الـ SQL أو السجلات. **لا تُسجَّل توكنز الأجهزة ولا المفاتيح الخاصة**
في `notification_deliveries` أو `last_error` (ملخص خطأ فقط).

## 2. نشر الدالة

```bash
supabase functions deploy campaign-dispatcher
```

تحقق من نجاح النشر في Dashboard → Edge Functions → campaign-dispatcher.

## 3. استبدال العناصر النائبة وتطبيق الـ cron

1. افتح `supabase/migrations/20260830041400_campaign_dispatcher_cron.sql`.
2. استبدل العناصر النائبة يدوياً بالقيم الحقيقية (من Project Settings → API):
   - `<SUPABASE_FUNCTIONS_URL>` — مثال الشكل: `https://<ref>.supabase.co/functions/v1`
   - `<SUPABASE_SERVICE_ROLE_KEY>` — مفتاح service_role
3. نفّذ الملف في **Dashboard → SQL Editor** (مهمة cron تعيش في قاعدة البيانات،
   لا في الكود الموزّع).
4. تحقق من الجدولة:

```sql
select jobname, schedule, active, database
from cron.job
where jobname = 'campaign-dispatcher';
```

## 4. فحص سجل الحملات وتشغيلات الـ cron

```sql
-- آخر تشغيلات المهمة المجدولة
select jobname, status, start_time, end_time, return_message
from cron.job_run_details
order by start_time desc
limit 10;

-- الحملات المرسلة/الفاشلة مؤخراً
select id, title, status, sent_count, failed_count, sent_at,
       left(coalesce(last_error, ''), 120) as last_error
from app.notification_campaigns
order by sent_at desc nulls last
limit 20;

-- تفاصيل التسليم لحملة معينة (بدون توكنز — الجدول لا يخزنها)
select installation_id, status, firebase_message_id,
       left(coalesce(error_message, ''), 120) as error, sent_at
from app.notification_deliveries
where campaign_id = '<CAMPAIGN_UUID>';
```

## 5. تعطيل/إلغاء الجدولة

```sql
-- إيقاف مؤقت (تبقى المهمة مسجلة)
update cron.job set active = false where jobname = 'campaign-dispatcher';

-- إلغاء نهائي
select cron.unschedule('campaign-dispatcher');
```

## 6. سلوك الدالة (للمراجعة السريعة)

- تلتقط `status='scheduled' AND scheduled_at <= now()` (بحد أقصى 10 في التشغيل).
- **Claim متفائل**: تحدّث كل حملة إلى `processing` قبل الإرسال لمنع الإرسال المكرر.
- التفويض: مفتاح service_role (مسار pg_cron) أو JWT إداري يحمل `notifications.write`
  (تشغيل يدوي).
- تستهدف `app.installations` حيث `notifications_enabled=true` و`revoked_at IS NULL`.
- `deep_link` يُقبل فقط إذا بدأ بـ `/` (مسار عميل آمن).
- النهاية: `status='sent'` مع `sent_at`، أو `status='failed'` مع `last_error`.
  عند عدم تهيئة FCM لا يُفبرك إرسال ناجح — تُعلَّم الحملة `failed` بصراحة.
- كل تشغيل يُسجَّل في سجل التدقيق (`NOTIFICATION_CRON_DISPATCH`).

## 7. ملاحظة معمارية: جدولا التسجيل

- تسجيل أجهزة الجوال الحالي (دالة `quran-yutla-api`) يكتب في
  `app.notification_installations`.
- الإرسال الفعلي (دالتا `notifications` و`campaign-dispatcher`) يستهدف
  `app.installations`، و`app.notification_deliveries` مرتبطة به.

إذا لم تظهر الأجهزة المستهدفة، فهذا التعارض هو أول ما يُفحص قبل أي شيء آخر —
يجب توحيد مسار التسجيل أو بناء جسر مزامنة بين الجدولين.

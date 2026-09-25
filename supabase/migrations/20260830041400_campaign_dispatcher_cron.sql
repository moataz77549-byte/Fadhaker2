-- ============================================================================
-- 20260830041400_campaign_dispatcher_cron.sql
--
-- جدولة دالة campaign-dispatcher عبر pg_cron: تلتقط الحملات المستحقة
-- (status='scheduled' و scheduled_at <= now()) وترسلها عبر FCM.
--
-- ⚠️  تطبيق يدوي إلزامي: هذا الملف يحتوي عناصر نائبة <...> يجب أن يملأها
-- مالك قاعدة البيانات يدوياً عبر Supabase Dashboard → SQL Editor.
-- لا توجد credentials للإنتاج في بيئة العمل، ولا أسرار حقيقية في هذا الملف
-- إطلاقاً — أي قيمة حقيقية تُملأ وقت التطبيق فقط ولا تُحفظ في المستودع.
--
-- خطوات المالك:
--   1) راجع هذا الملف كاملاً.
--   2) استبدل العناصر النائبة أدناه بالقيم الحقيقية من:
--        Supabase Dashboard → Project Settings → API
--        (URL للمشروع + service_role key)
--      و Supabase Dashboard → Edge Functions → campaign-dispatcher → Secrets
--        (FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY)
--      علماً أن أسرار Firebase تُضبط كـ Function Secrets (وقت التشغيل فقط)
--      ولا تظهر في SQL إطلاقاً.
--   3) نفّذ الملف في SQL Editor.
--   4) تحقق: select * from cron.job where jobname = 'campaign-dispatcher';
--   5) راقب: select * from cron.job_run_details order by start_time desc limit 10;
--
-- إلغاء الجدولة عند الحاجة:
--   select cron.unschedule('campaign-dispatcher');
-- ============================================================================

-- pg_cron و pg_net (للاتصال HTTP بالـ Edge Function)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- إزالة أي جدولة سابقة بنفس الاسم قبل إعادة الجدولة (idempotent)
do $$ begin
  if exists (select 1 from cron.job where jobname = 'campaign-dispatcher') then
    perform cron.unschedule('campaign-dispatcher');
  end if;
end $$;

-- ⚠️  املأ العناصر النائبة قبل التنفيذ — لا تُنفّذ والدوال <...> موجودة.
-- <SUPABASE_FUNCTIONS_URL> مثال: https://xyzcompany.supabase.co/functions/v1
-- <SUPABASE_SERVICE_ROLE_KEY> : مفتاح service_role من Project Settings → API
--                               (يُستخدم هنا فقط لاستدعاء الدالة المجدولة،
--                               ولا يُخزَّن في أي جدول — يبقى داخل تعريف مهمة cron)
select cron.schedule(
  'campaign-dispatcher',      -- اسم المهمة
  '*/5 * * * *',              -- كل 5 دقائق (عدّل حسب الحاجة، مثلاً '*/1 * * * *')
  $$
  select net.http_post(
    url := '<SUPABASE_FUNCTIONS_URL>/campaign-dispatcher',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <SUPABASE_SERVICE_ROLE_KEY>',
      'apikey', '<SUPABASE_SERVICE_ROLE_KEY>'
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $$
);

-- توثيق داخل قاعدة البيانات
comment on extension pg_cron is
  'Schedules campaign-dispatcher every 5 minutes. Owner must fill <...> placeholders before applying.';

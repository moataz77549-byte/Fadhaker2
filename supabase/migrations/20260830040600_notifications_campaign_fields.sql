-- ============================================================================
-- 20260830040600_notifications_campaign_fields.sql
--
-- ⚠️  تطبيق يدوي إلزامي: طبّقه مالك قاعدة البيانات يدوياً عبر Supabase
-- Dashboard → SQL Editor بعد المراجعة (لا credentials للإنتاج في بيئة العمل).
--
-- الغرض: جدول app.notification_campaigns موجود مسبقاً (من
-- 20260301000000_quran_yutla_complete_cloud_backend.sql) لكنه يفتقد الحقول
-- التشغيلية التي تحتاجها دالة الإرسال: sent_at / sent|failed counts / error،
-- وحالة 'failed' الصريحة. هذا الملف يضيفها دون المساس بالبيانات القائمة.
-- (لا حذف جداول، لا إعادة تشغيل migrations، لا تغيير للأعمدة الموجودة).
-- ============================================================================

alter table app.notification_campaigns
  add column if not exists sent_at timestamptz,
  add column if not exists deep_link text,
  add column if not exists sent_count integer not null default 0,
  add column if not exists failed_count integer not null default 0,
  add column if not exists last_error text;

alter table app.notification_campaigns
  add constraint notification_campaigns_counts_check
  check (sent_count >= 0 and failed_count >= 0)
  not valid;

-- توسيع حالات الحملة لتشمل الفشل الصريح (بدل إبقاء failed داخل completed)
do $$
begin
  alter table app.notification_campaigns
    drop constraint if exists notification_campaigns_status_check;
  alter table app.notification_campaigns
    add constraint notification_campaigns_status_check
    check (status in ('draft','scheduled','processing','completed','failed','cancelled'))
    not valid;
exception when others then
  -- إن كان اسم القيد مختلفاً في بيئة مطبَّقة قديماً، اترك القيد الأصلي ووثّق
  raise notice 'Could not replace status check constraint: %', sqlerrm;
end $$;

create index if not exists notification_campaigns_status_scheduled_idx
  on app.notification_campaigns (status, scheduled_at)
  where status in ('scheduled','processing');

comment on column app.notification_campaigns.sent_at is
  'When dispatch finished (null while draft/scheduled/processing).';
comment on column app.notification_campaigns.deep_link is
  'Validated client route (allow-listed by the Edge Function), e.g. /radio.';
comment on column app.notification_campaigns.last_error is
  'Last dispatch error summary. Never contains secrets or device tokens.';

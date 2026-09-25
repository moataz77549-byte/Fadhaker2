-- ============================================================================
-- 20260830041100_campaign_fields_consolidation.sql
--
-- توحيد الحقول التشغيلية لجدول app.notification_campaigns — يجمع نية الملف
-- 20260830040600_notifications_campaign_fields.sql بصيغة idempotent بالكامل.
--
--   * آمن حتى لو طُبّق 40600 (أو جزء منه) سابقاً: كل الأعمدة
--     ADD COLUMN IF NOT EXISTS، والقيود تُفحص في pg_constraint قبل إضافتها،
--     والفهرس IF NOT EXISTS.
--   * الحقول: sent_at / deep_link / sent_count / failed_count / last_error،
--     وحالة 'failed' الصريحة في قيد الحالة.
--   * last_error لا يحمل أسراراً أو توكنز أجهزة أبداً (ملخص خطأ فقط).
-- ============================================================================

alter table app.notification_campaigns
  add column if not exists sent_at timestamptz,
  add column if not exists deep_link text,
  add column if not exists sent_count integer not null default 0,
  add column if not exists failed_count integer not null default 0,
  add column if not exists last_error text;

-- قيد عدم السلبية (يفحص الوجود أولاً — النسخة الأصلية لم تكن idempotent)
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'notification_campaigns_counts_check') then
    alter table app.notification_campaigns
      add constraint notification_campaigns_counts_check
      check (sent_count >= 0 and failed_count >= 0)
      not valid;
  end if;
end $$;

-- توسيع حالات الحملة لتشمل 'failed' الصريح
do $$ begin
  alter table app.notification_campaigns
    drop constraint if exists notification_campaigns_status_check;
  alter table app.notification_campaigns
    add constraint notification_campaigns_status_check
    check (status in ('draft','scheduled','processing','completed','failed','cancelled'))
    not valid;
exception when others then
  raise notice 'Could not replace status check constraint (kept existing): %', sqlerrm;
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

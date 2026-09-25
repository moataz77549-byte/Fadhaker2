-- Immutable audit trail for Smart Fadhkur Radio administration.
-- Captures old/new row snapshots server-side so admin UI clients cannot skip logging.

create or replace function private.audit_smart_radio_change()
returns trigger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_actor uuid;
  v_resource_id text;
begin
  select a.id
    into v_actor
  from app.administrators a
  where a.id = auth.uid()
    and a.is_active = true
    and a.deleted_at is null;

  v_resource_id := case
    when tg_op = 'DELETE' then old.id::text
    else new.id::text
  end;

  insert into app.audit_logs (
    actor_id,
    action,
    resource_type,
    resource_id,
    old_values,
    new_values,
    metadata
  )
  values (
    v_actor,
    'smart_radio.' || lower(tg_op),
    'smart_radio.' || tg_table_name,
    v_resource_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end,
    jsonb_build_object(
      'source', 'database_trigger',
      'schema', tg_table_schema,
      'table', tg_table_name
    )
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.audit_smart_radio_change() from public;

drop trigger if exists audit_smart_radio_channels on app.virtual_radio_channels;
create trigger audit_smart_radio_channels
after insert or update or delete on app.virtual_radio_channels
for each row execute function private.audit_smart_radio_change();

drop trigger if exists audit_smart_radio_sources on app.virtual_radio_sources;
create trigger audit_smart_radio_sources
after insert or update or delete on app.virtual_radio_sources
for each row execute function private.audit_smart_radio_change();

drop trigger if exists audit_smart_radio_rules on app.virtual_radio_rules;
create trigger audit_smart_radio_rules
after insert or update or delete on app.virtual_radio_rules
for each row execute function private.audit_smart_radio_change();

drop trigger if exists audit_smart_radio_overrides on app.virtual_radio_overrides;
create trigger audit_smart_radio_overrides
after insert or update or delete on app.virtual_radio_overrides
for each row execute function private.audit_smart_radio_change();

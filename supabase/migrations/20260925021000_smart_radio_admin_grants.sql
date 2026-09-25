-- Smart Radio admin tables are never exposed directly to anon.
-- Authenticated users still need SQL table privileges before RLS/RBAC can
-- evaluate the fine-grained smart_radio.* permissions.
revoke all on table
  app.virtual_radio_channels,
  app.virtual_radio_sources,
  app.virtual_radio_rules,
  app.virtual_radio_overrides
from anon;

grant select, insert, update, delete on table
  app.virtual_radio_channels,
  app.virtual_radio_sources,
  app.virtual_radio_rules,
  app.virtual_radio_overrides
to authenticated;

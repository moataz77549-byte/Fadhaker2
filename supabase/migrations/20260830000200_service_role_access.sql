-- Backend services use server-side credentials only. Listener and admin clients do not query
-- app/radio directly; service_role access supports the protected Backend API and workers.
grant usage on schema app, radio, api to service_role;
grant select, insert, update, delete on all tables in schema app, radio to service_role;
grant usage, select on all sequences in schema app, radio to service_role;
grant execute on all functions in schema app, radio to service_role;

alter default privileges in schema app grant select, insert, update, delete on tables to service_role;
alter default privileges in schema radio grant select, insert, update, delete on tables to service_role;
alter default privileges in schema app grant usage, select on sequences to service_role;
alter default privileges in schema radio grant usage, select on sequences to service_role;
alter default privileges in schema app grant execute on functions to service_role;
alter default privileges in schema radio grant execute on functions to service_role;

-- Keep browser-facing roles fail-closed. Public projections will be added only with the API phase.
revoke all on schema app, radio, api from anon, authenticated;

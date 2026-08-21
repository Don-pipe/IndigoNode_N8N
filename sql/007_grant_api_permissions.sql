-- White Node / IndigoNode
-- Run order: 7 (after 001-005)
-- Purpose: Allow Supabase Data API / n8n to read tenant and messaging schemas
--
-- Symptom: n8n Supabase node can see public.messages but not tenant/messaging tables.
-- Cause: custom schemas need USAGE + SELECT grants for API roles.

grant usage on schema tenant to anon, authenticated, service_role;
grant usage on schema messaging to anon, authenticated, service_role;

grant select on all tables in schema tenant to anon, authenticated, service_role;
grant select on all tables in schema messaging to anon, authenticated, service_role;

grant select on tenant.v_automation_config to anon, authenticated, service_role;

alter default privileges in schema tenant
  grant select on tables to anon, authenticated, service_role;

alter default privileges in schema messaging
  grant select on tables to anon, authenticated, service_role;

-- Verify (optional):
-- select table_schema, table_name, privilege_type
-- from information_schema.table_privileges
-- where grantee in ('anon', 'authenticated', 'service_role')
--   and table_schema in ('tenant', 'messaging')
-- order by table_schema, table_name;

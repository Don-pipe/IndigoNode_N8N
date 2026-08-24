-- White Node / IndigoNode
-- Run order: 17 (after 013 view; before 018 cleanup)
-- Purpose: Grants + RLS for tenant v2 and messaging_channels
--
-- STATUS: APPLIED in production — 2026-08-24 (all sections, no errors)
-- Next: 018_cleanup_legacy.sql

-- ---------------------------------------------------------------------------
-- Schema usage
-- ---------------------------------------------------------------------------
grant usage on schema tenant to anon, authenticated, service_role;
grant usage on schema messaging_channels to anon, authenticated, service_role;

-- Revoke old messaging schema after 018 cleanup (safe to run now too)
-- grant usage on schema messaging ... — dropped in 018

-- ---------------------------------------------------------------------------
-- Table grants — tenant v2
-- ---------------------------------------------------------------------------
grant select on tenant.tenants to anon, authenticated, service_role;
grant select on tenant.tenant_settings to anon, authenticated, service_role;
grant select on tenant.tenant_businesses to anon, authenticated, service_role;
grant select on tenant.business_pricing to anon, authenticated, service_role;
grant select on tenant.business_knowledge to anon, authenticated, service_role;
grant select on tenant.whatsapp_accounts to anon, authenticated, service_role;

-- Legacy table (until 018)
grant select on tenant.business_profiles to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Table grants — messaging_channels
-- ---------------------------------------------------------------------------
grant select on messaging_channels.contacts to anon, authenticated, service_role;
grant select on messaging_channels.conversations to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- View + function grants
-- ---------------------------------------------------------------------------
grant select on tenant.v_automation_config to anon, authenticated, service_role;

grant execute on function messaging_channels.get_conversation_summary(uuid, text, text, text, text)
  to postgres, service_role;

grant execute on function messaging_channels.update_conversation_summary(uuid, text)
  to postgres, service_role;

-- Default privileges for future tenant / messaging_channels tables
alter default privileges in schema tenant
  grant select on tables to anon, authenticated, service_role;

alter default privileges in schema messaging_channels
  grant select on tables to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS — tenant v2 tables
-- ---------------------------------------------------------------------------
alter table tenant.tenant_settings enable row level security;
alter table tenant.tenant_businesses enable row level security;
alter table tenant.business_pricing enable row level security;
alter table tenant.business_knowledge enable row level security;

alter table messaging_channels.contacts enable row level security;
alter table messaging_channels.conversations enable row level security;

-- n8n uses service_role (bypasses RLS). Policies prepare for future dashboard.

drop policy if exists "tenant_settings_select_authenticated" on tenant.tenant_settings;
create policy "tenant_settings_select_authenticated"
  on tenant.tenant_settings
  for select
  to authenticated
  using (true);

drop policy if exists "tenant_businesses_select_authenticated" on tenant.tenant_businesses;
create policy "tenant_businesses_select_authenticated"
  on tenant.tenant_businesses
  for select
  to authenticated
  using (true);

drop policy if exists "business_pricing_select_authenticated" on tenant.business_pricing;
create policy "business_pricing_select_authenticated"
  on tenant.business_pricing
  for select
  to authenticated
  using (true);

drop policy if exists "business_knowledge_select_authenticated" on tenant.business_knowledge;
create policy "business_knowledge_select_authenticated"
  on tenant.business_knowledge
  for select
  to authenticated
  using (true);

drop policy if exists "messaging_contacts_select_authenticated" on messaging_channels.contacts;
create policy "messaging_contacts_select_authenticated"
  on messaging_channels.contacts
  for select
  to authenticated
  using (true);

drop policy if exists "messaging_conversations_select_authenticated" on messaging_channels.conversations;
create policy "messaging_conversations_select_authenticated"
  on messaging_channels.conversations
  for select
  to authenticated
  using (true);

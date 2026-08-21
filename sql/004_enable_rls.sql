-- White Node / IndigoNode
-- Run order: 4
-- Purpose: Enable RLS on tenant and messaging tables

-- Tenant tables
alter table tenant.tenants enable row level security;
alter table tenant.business_profiles enable row level security;
alter table tenant.whatsapp_accounts enable row level security;

-- Messaging tables
alter table messaging.contacts enable row level security;
alter table messaging.conversations enable row level security;
alter table messaging.messages enable row level security;

-- n8n uses the service_role key server-side, which bypasses RLS.
-- These policies prepare the schema for a future admin dashboard.

create policy "tenants_select_authenticated"
  on tenant.tenants
  for select
  to authenticated
  using (true);

create policy "business_profiles_select_authenticated"
  on tenant.business_profiles
  for select
  to authenticated
  using (true);

create policy "whatsapp_accounts_select_authenticated"
  on tenant.whatsapp_accounts
  for select
  to authenticated
  using (true);

create policy "contacts_select_authenticated"
  on messaging.contacts
  for select
  to authenticated
  using (true);

create policy "conversations_select_authenticated"
  on messaging.conversations
  for select
  to authenticated
  using (true);

create policy "messages_select_authenticated"
  on messaging.messages
  for select
  to authenticated
  using (true);

-- White Node / IndigoNode
-- Run order: 3
-- Purpose: Enable RLS on tenant tables (required for Supabase exposed schemas)

alter table tenant.tenants enable row level security;
alter table tenant.business_profiles enable row level security;
alter table tenant.whatsapp_accounts enable row level security;
alter table tenant.integrations enable row level security;

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

create policy "integrations_select_authenticated"
  on tenant.integrations
  for select
  to authenticated
  using (true);

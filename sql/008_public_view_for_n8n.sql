-- White Node / IndigoNode
-- Run order: 8 (optional workaround for n8n Supabase node)
-- Purpose: Expose tenant lookup view in public schema so n8n can list/select it
--
-- Use this if n8n shows "Error fetching options from Supabase" for schema tenant.
-- n8n Supabase node works reliably with public; this view proxies tenant data.

create or replace view public.v_automation_config as
select *
from tenant.v_automation_config;

grant select on public.v_automation_config to anon, authenticated, service_role;

comment on view public.v_automation_config is
  'n8n-friendly proxy view for tenant.v_automation_config';

-- n8n settings after running this:
-- Use Custom Schema: OFF
-- Table: v_automation_config
-- Filter: whatsapp_phone_number_id equals {{ $('Edit Fields').item.json.phone_number_id }}

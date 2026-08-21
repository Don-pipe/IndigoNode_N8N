-- White Node / IndigoNode
-- Run order: 3
-- Purpose: Single-query tenant lookup for n8n workflows

create or replace view tenant.v_automation_config as
select
  t.id as tenant_id,
  t.slug,
  t.display_name as tenant_name,
  t.business_type,
  t.specialty,
  t.is_active as tenant_active,

  bp.service_fee,
  bp.service_currency,
  bp.address,
  bp.timezone,
  bp.maps_url,
  bp.metadata as business_metadata,

  wa.whatsapp_phone_number_id,
  wa.whatsapp_business_number,
  wa.waba_id
from tenant.tenants t
join tenant.business_profiles bp
  on bp.tenant_id = t.id
join tenant.whatsapp_accounts wa
  on wa.tenant_id = t.id
 and wa.is_primary = true
where t.is_active = true
  and wa.is_active = true;

comment on view tenant.v_automation_config is
  'Tenant config lookup by whatsapp_phone_number_id for reusable n8n automations.';

-- Example n8n Supabase filter:
-- whatsapp_phone_number_id = eq.{{ $('Edit Fields').item.json.phone_number_id }}

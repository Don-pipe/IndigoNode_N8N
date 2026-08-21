-- White Node / IndigoNode
-- Run order: 2
-- Purpose: Single-query tenant lookup for n8n workflows

create or replace view tenant.v_automation_config as
select
  t.id as tenant_id,
  t.slug,
  t.display_name as doctor_name,
  t.specialty,
  t.is_active as tenant_active,

  bp.consultation_fee,
  bp.consultation_currency,
  bp.address,
  bp.office_hours_start,
  bp.office_hours_end,
  bp.timezone,
  bp.maps_url,

  wa.whatsapp_phone_number_id,
  wa.whatsapp_business_number,

  gi.external_id as google_calendar_id
from tenant.tenants t
join tenant.business_profiles bp
  on bp.tenant_id = t.id
join tenant.whatsapp_accounts wa
  on wa.tenant_id = t.id
 and wa.is_primary = true
left join tenant.integrations gi
  on gi.tenant_id = t.id
 and gi.provider = 'google_calendar'
 and gi.is_active = true
where t.is_active = true
  and wa.is_active = true;

-- Example n8n Supabase filter:
-- whatsapp_phone_number_id = eq.{{ $('Edit Fields').item.json.phone_number_id }}

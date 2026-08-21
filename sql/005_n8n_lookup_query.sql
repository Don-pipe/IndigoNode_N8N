-- White Node / IndigoNode
-- Reference query for n8n Supabase node or Postgres node
--
-- Lookup tenant config when a WhatsApp message arrives.
-- Use phone_number_id from webhook metadata (NOT patient wa_id).

select *
from tenant.v_automation_config
where whatsapp_phone_number_id = :phone_number_id
limit 1;

-- n8n Supabase node equivalent:
-- Table/View: tenant.v_automation_config
-- Operation: Get Many / Get
-- Filter: whatsapp_phone_number_id = eq.{{ $('Edit Fields').item.json.phone_number_id }}
-- Limit: 1

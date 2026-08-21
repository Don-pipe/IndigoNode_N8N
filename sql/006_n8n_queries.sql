-- White Node / IndigoNode
-- Run order: reference only (do not execute as migration)
-- Purpose: n8n query examples for tenant lookup and message storage

-- ---------------------------------------------------------------------------
-- 1) Lookup tenant config by WhatsApp business line
-- Use phone_number_id from webhook metadata (NOT patient wa_id)
-- ---------------------------------------------------------------------------
select *
from tenant.v_automation_config
where whatsapp_phone_number_id = :phone_number_id
limit 1;

-- n8n Supabase node:
-- View: tenant.v_automation_config
-- Filter: whatsapp_phone_number_id = eq.{{ $('Edit Fields').item.json.phone_number_id }}
-- Limit: 1

-- ---------------------------------------------------------------------------
-- 2) Record inbound message (recommended: Postgres node / RPC)
-- Creates/updates contact + conversation and inserts inbound message
-- ---------------------------------------------------------------------------
select *
from messaging.record_inbound_message(
  p_phone_number_id := :phone_number_id,
  p_wa_id := :wa_id,
  p_display_name := :display_name,
  p_body := :message_body,
  p_whatsapp_message_id := :whatsapp_message_id,
  p_message_type := 'text',
  p_raw_payload := :raw_payload::jsonb,
  p_sent_at := :sent_at::timestamptz
);

-- n8n expression examples:
-- :phone_number_id -> {{ $('Edit Fields').item.json.phone_number_id }}
-- :wa_id -> {{ $('Edit Fields').item.json.wa_id }}
-- :display_name -> {{ $('Edit Fields').item.json.Name }}
-- :message_body -> {{ $('Edit Fields').item.json.message }}
-- :whatsapp_message_id -> {{ $('WhatsApp Trigger').item.json.messages[0].id }}

-- ---------------------------------------------------------------------------
-- 3) Store outbound message after AI response
-- Run after Send message node (or before, depending on your flow)
-- ---------------------------------------------------------------------------
insert into messaging.messages (
  tenant_id,
  conversation_id,
  contact_id,
  direction,
  message_type,
  body,
  status,
  sent_at
)
values (
  :tenant_id,
  :conversation_id,
  :contact_id,
  'outbound',
  'text',
  :agent_output,
  'sent',
  now()
)
returning id;

-- Also update conversation timestamp:
-- update messaging.conversations
-- set last_message_at = now(), updated_at = now()
-- where id = :conversation_id;

-- ---------------------------------------------------------------------------
-- 4) Read recent conversation history for a contact
-- ---------------------------------------------------------------------------
select
  m.direction,
  m.message_type,
  m.body,
  m.created_at
from messaging.messages m
where m.tenant_id = :tenant_id
  and m.contact_id = :contact_id
order by m.created_at desc
limit 20;

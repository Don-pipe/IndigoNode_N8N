-- White Node / IndigoNode
-- Reference only — copy into n8n (DO NOT run this file in Supabase)
-- Memory: conversation summaries only (no raw messages)

-- =============================================================================
-- FLOW ORDER
-- =============================================================================
-- Important WPP message fields
--   → Is text message? (IF)              true → continue | false → reply + stop
--   → Get tenant configuration
--   → Active verification
--   → Get Message Summary               (Postgres)
--   → AI Agent
--   → Code in JavaScript                (splits reply + summary from output string)
--   → Send message
--   → Update Conversation Summary       (Postgres)

-- AI Agent returns JSON: {"reply":"...","summary":"..."}
-- Remove: Simple Memory, Google Calendar, second OpenAI node

-- =============================================================================
-- POSTGRES: Get Conversation Summary
-- After Active verification (true branch)
-- =============================================================================
select
  contact_id,
  conversation_id,
  summary,
  summary_updated_at,
  message_count
from messaging.get_conversation_summary(
  p_tenant_id := '{{ $json.tenant_id }}'::uuid,
  p_wa_id := '{{ $('Important WPP message fields').item.json.wa_id }}',
  p_phone_number_id := '{{ $('Important WPP message fields').item.json.phone_number_id }}',
  p_display_name := '{{ $('Important WPP message fields').item.json.Name }}'
);

-- =============================================================================
-- AI AGENT PROMPT — add these blocks
-- =============================================================================
-- RESUMEN PREVIO:
-- {{ $('Get Conversation Summary').item.json.summary }}
--
-- MENSAJE ACTUAL:
-- {{ $('Important WPP message fields').item.json.message }}
--
-- (Keep your tenant fields from Get tenant configuration via $json.*)

-- =============================================================================
-- AI AGENT — append to prompt (single call for reply + summary)
-- =============================================================================
-- FORMATO DE RESPUESTA (OBLIGATORIO)
-- Responde ÚNICAMENTE con JSON válido, sin markdown:
-- {"reply":"mensaje para WhatsApp","summary":"resumen actualizado en 2-4 oraciones"}

-- =============================================================================
-- CODE NODE: Parse Agent Response (JavaScript, after AI Agent)
-- =============================================================================
-- const raw = $input.first().json.output ?? '';
-- const previousSummary = $('Get Message Summary').first().json.summary ?? '';
--
-- let reply = raw;
-- let summary = previousSummary;
--
-- try {
--   const cleaned = raw.replace(/```json\n?|```/g, '').trim();
--   const parsed = JSON.parse(cleaned);
--   reply = parsed.reply ?? raw;
--   summary = parsed.summary ?? previousSummary;
-- } catch (error) {
--   reply = raw;
--   summary = previousSummary;
-- }
--
-- return [{ json: { reply, summary } }];
--
-- Send message uses: {{ $json.reply }}
-- Update summary uses: {{ $('Code in JavaScript').item.json.summary }}
-- Note: node names in $('...') must match your canvas exactly.

-- =============================================================================
-- POSTGRES: Update Conversation Summary (after Send message)
-- =============================================================================
select messaging.update_conversation_summary(
  '{{ $('Get Message Summary').item.json.conversation_id }}'::uuid,
  '{{ $('Code in JavaScript').item.json.summary }}'
) as summary_updated_at;

-- =============================================================================
-- VERIFY in Supabase SQL Editor
-- =============================================================================
-- select c.summary, c.summary_updated_at, ct.wa_id, ct.display_name
-- from messaging.conversations c
-- join messaging.contacts ct on ct.id = c.contact_id
-- order by c.summary_updated_at desc nulls last;

-- =============================================================================
-- SET: Important WPP message fields — add these assignments
-- =============================================================================
-- message_type = {{ $('WhatsApp Trigger').item.json.messages[0].type }}
-- image        = {{ $('WhatsApp Trigger').item.json.messages[0].image ?? null }}
-- sticker      = {{ $('WhatsApp Trigger').item.json.messages[0].sticker ?? null }}

-- =============================================================================
-- IF: Is text message? (after Important WPP message fields)
-- Proceed only when image AND sticker are null/empty (text conversation).
-- Do NOT use .toJsonString() on null — it throws an error.
-- =============================================================================
-- Option A (recommended — one condition):
--   leftValue: {{ !$json.image && !$json.sticker }}
--   operator:  boolean → is true
--
-- Option B (two conditions, combinator AND):
--   {{ $json.image }}   → is empty
--   {{ $json.sticker }} → is empty
--
-- TRUE branch  → Get tenant configuration (normal AI flow)
-- FALSE branch → Send message (no AI), e.g.:
--   "Por ahora solo puedo leer mensajes de texto. Escribe tu consulta."

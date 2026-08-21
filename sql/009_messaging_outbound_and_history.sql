-- White Node / IndigoNode
-- Run order: 9 (after 002)
-- Purpose: Outbound message recording + conversation history for AI memory

-- ---------------------------------------------------------------------------
-- Record outbound bot reply
-- ---------------------------------------------------------------------------
create or replace function messaging.record_outbound_message(
  p_tenant_id uuid,
  p_conversation_id uuid,
  p_contact_id uuid,
  p_body text,
  p_message_type text default 'text'
)
returns uuid
language plpgsql
as $$
declare
  v_message_id uuid;
begin
  insert into messaging.messages (
    tenant_id,
    conversation_id,
    contact_id,
    direction,
    message_type,
    body,
    status,
    sent_at
  ) values (
    p_tenant_id,
    p_conversation_id,
    p_contact_id,
    'outbound',
    coalesce(p_message_type, 'text'),
    p_body,
    'sent',
    now()
  )
  returning id into v_message_id;

  update messaging.conversations
  set last_message_at = now(),
      updated_at = now()
  where id = p_conversation_id;

  return v_message_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Conversation history as rows (newest first)
-- ---------------------------------------------------------------------------
create or replace function messaging.get_conversation_history(
  p_tenant_id uuid,
  p_wa_id text,
  p_limit int default 20
)
returns table (
  direction text,
  body text,
  created_at timestamptz
)
language sql
stable
as $$
  select
    m.direction,
    m.body,
    m.created_at
  from messaging.messages m
  join messaging.contacts c on c.id = m.contact_id
  where c.tenant_id = p_tenant_id
    and c.wa_id = p_wa_id
  order by m.created_at desc
  limit greatest(p_limit, 1);
$$;

-- ---------------------------------------------------------------------------
-- Conversation history as one text block for AI prompt (oldest first)
-- ---------------------------------------------------------------------------
create or replace function messaging.get_conversation_history_text(
  p_tenant_id uuid,
  p_wa_id text,
  p_limit int default 20
)
returns text
language sql
stable
as $$
  select coalesce(
    string_agg(
      case
        when h.direction = 'inbound' then 'cliente: ' || coalesce(h.body, '')
        else 'asistente: ' || coalesce(h.body, '')
      end,
      E'\n'
      order by h.created_at asc
    ),
    'Sin historial previo.'
  )
  from (
    select direction, body, created_at
    from messaging.get_conversation_history(p_tenant_id, p_wa_id, p_limit)
  ) h;
$$;

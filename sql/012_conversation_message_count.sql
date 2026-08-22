-- White Node / IndigoNode
-- Run order: 12
-- Purpose: Track inbound message count per conversation (for usage limits / cost control)

-- ---------------------------------------------------------------------------
-- 1) Counter column on conversations
-- ---------------------------------------------------------------------------
alter table messaging.conversations
  add column if not exists message_count integer not null default 0;

comment on column messaging.conversations.message_count is
  'Number of inbound WhatsApp messages processed for this conversation. Incremented on each get_conversation_summary call.';

-- ---------------------------------------------------------------------------
-- 2) get_conversation_summary — increment on each inbound message, return count
--    Must DROP first: return type adds message_count column.
-- ---------------------------------------------------------------------------
drop function if exists messaging.get_conversation_summary(uuid, text, text, text);

create function messaging.get_conversation_summary(
  p_tenant_id uuid,
  p_wa_id text,
  p_phone_number_id text,
  p_display_name text default null
)
returns table (
  contact_id uuid,
  conversation_id uuid,
  summary text,
  summary_updated_at timestamptz,
  message_count integer
)
language plpgsql
as $$
#variable_conflict use_column
declare
  v_contact_id uuid;
  v_conversation_id uuid;
  v_summary text;
  v_summary_updated_at timestamptz;
  v_message_count integer;
begin
  insert into messaging.contacts (tenant_id, wa_id, display_name, last_seen_at)
  values (p_tenant_id, p_wa_id, p_display_name, now())
  on conflict (tenant_id, wa_id) do update
    set display_name = coalesce(excluded.display_name, messaging.contacts.display_name),
        last_seen_at = now(),
        updated_at = now()
  returning id into v_contact_id;

  if v_contact_id is null then
    select c.id into v_contact_id
    from messaging.contacts c
    where c.tenant_id = p_tenant_id
      and c.wa_id = p_wa_id;
  end if;

  insert into messaging.conversations as conv (
    tenant_id,
    contact_id,
    whatsapp_phone_number_id,
    last_message_at,
    message_count
  ) values (
    p_tenant_id,
    v_contact_id,
    p_phone_number_id,
    now(),
    1
  )
  on conflict (tenant_id, contact_id, whatsapp_phone_number_id) do update
    set last_message_at = now(),
        updated_at = now(),
        message_count = conv.message_count + 1
  returning conv.id, conv.summary, conv.summary_updated_at, conv.message_count
  into v_conversation_id, v_summary, v_summary_updated_at, v_message_count;

  if v_conversation_id is null then
    select c.id, c.summary, c.summary_updated_at, c.message_count
    into v_conversation_id, v_summary, v_summary_updated_at, v_message_count
    from messaging.conversations c
    where c.tenant_id = p_tenant_id
      and c.contact_id = v_contact_id
      and c.whatsapp_phone_number_id = p_phone_number_id;
  end if;

  contact_id := v_contact_id;
  conversation_id := v_conversation_id;
  summary := coalesce(v_summary, 'Sin conversación previa.');
  summary_updated_at := v_summary_updated_at;
  message_count := v_message_count;
  return next;
end;
$$;

grant execute on function messaging.get_conversation_summary(uuid, text, text, text)
  to postgres, service_role;

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- select id, summary, message_count, summary_updated_at
-- from messaging.conversations
-- order by last_message_at desc nulls last;

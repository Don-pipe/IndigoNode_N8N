-- White Node / IndigoNode
-- Run order: 10
-- Purpose:
--   1) Remove legacy public.messages table
--   2) Add conversation summary support (no individual message storage)

-- ---------------------------------------------------------------------------
-- 1) Drop legacy test table (public.messages)
-- ---------------------------------------------------------------------------
drop table if exists public.messages cascade;

-- ---------------------------------------------------------------------------
-- 2) Summary fields on conversations (one rolling summary per contact)
-- ---------------------------------------------------------------------------
alter table messaging.conversations
  add column if not exists summary text,
  add column if not exists summary_updated_at timestamptz;

comment on column messaging.conversations.summary is
  'Rolling AI-generated summary of the conversation. Updated each turn. No raw messages stored.';

comment on column messaging.conversations.summary_updated_at is
  'When the summary was last updated.';

-- ---------------------------------------------------------------------------
-- 3) Load or create contact + conversation, return current summary
-- ---------------------------------------------------------------------------
create or replace function messaging.get_conversation_summary(
  p_tenant_id uuid,
  p_wa_id text,
  p_phone_number_id text,
  p_display_name text default null
)
returns table (
  contact_id uuid,
  conversation_id uuid,
  summary text,
  summary_updated_at timestamptz
)
language plpgsql
as $$
#variable_conflict use_column
declare
  v_contact_id uuid;
  v_conversation_id uuid;
  v_summary text;
  v_summary_updated_at timestamptz;
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
    last_message_at
  ) values (
    p_tenant_id,
    v_contact_id,
    p_phone_number_id,
    now()
  )
  on conflict (tenant_id, contact_id, whatsapp_phone_number_id) do update
    set last_message_at = now(),
        updated_at = now()
  returning conv.id, conv.summary, conv.summary_updated_at
  into v_conversation_id, v_summary, v_summary_updated_at;

  if v_conversation_id is null then
    select c.id, c.summary, c.summary_updated_at
    into v_conversation_id, v_summary, v_summary_updated_at
    from messaging.conversations c
    where c.tenant_id = p_tenant_id
      and c.contact_id = v_contact_id
      and c.whatsapp_phone_number_id = p_phone_number_id;
  end if;

  contact_id := v_contact_id;
  conversation_id := v_conversation_id;
  summary := coalesce(v_summary, 'Sin conversación previa.');
  summary_updated_at := v_summary_updated_at;
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Save updated summary after AI reply
-- ---------------------------------------------------------------------------
create or replace function messaging.update_conversation_summary(
  p_conversation_id uuid,
  p_summary text
)
returns timestamptz
language plpgsql
as $$
declare
  v_updated_at timestamptz := now();
begin
  update messaging.conversations
  set summary = p_summary,
      summary_updated_at = v_updated_at,
      last_message_at = v_updated_at,
      updated_at = v_updated_at
  where id = p_conversation_id;

  if not found then
    raise exception 'Conversation not found: %', p_conversation_id;
  end if;

  return v_updated_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants for n8n Postgres connection
-- ---------------------------------------------------------------------------
grant execute on function messaging.get_conversation_summary(uuid, text, text, text)
  to postgres, service_role;

grant execute on function messaging.update_conversation_summary(uuid, text)
  to postgres, service_role;

-- Verify:
-- select * from messaging.get_conversation_summary(
--   'YOUR_TENANT_ID'::uuid,
--   '59177944841',
--   '1248499035016959',
--   'Test User'
-- );

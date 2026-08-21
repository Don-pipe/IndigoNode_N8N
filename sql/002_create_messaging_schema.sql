-- White Node / IndigoNode
-- Run order: 2
-- Purpose: Generic messaging schema linked to tenants via WhatsApp IDs
-- Scope: contacts, conversations, messages
-- Deferred: appointments and scheduling

create schema if not exists messaging;

-- ---------------------------------------------------------------------------
-- End users who message a tenant (patients, customers, etc.)
-- ---------------------------------------------------------------------------
create table if not exists messaging.contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  wa_id text not null,
  display_name text,
  phone_number text,
  is_active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (tenant_id, wa_id)
);

comment on column messaging.contacts.wa_id is
  'WhatsApp ID of the person messaging the tenant (NOT the tenant business line).';

create index if not exists idx_contacts_tenant_wa_id
  on messaging.contacts (tenant_id, wa_id);

-- ---------------------------------------------------------------------------
-- Conversation thread between one contact and one tenant business line
-- ---------------------------------------------------------------------------
create table if not exists messaging.conversations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  contact_id uuid not null references messaging.contacts(id) on delete cascade,
  whatsapp_phone_number_id text not null,
  status text not null default 'open',
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (tenant_id, contact_id, whatsapp_phone_number_id),
  constraint conversations_status_check
    check (status in ('open', 'closed', 'archived'))
);

create index if not exists idx_conversations_tenant_last_message
  on messaging.conversations (tenant_id, last_message_at desc nulls last);

-- ---------------------------------------------------------------------------
-- Individual messages (inbound and outbound)
-- ---------------------------------------------------------------------------
create table if not exists messaging.messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  conversation_id uuid not null references messaging.conversations(id) on delete cascade,
  contact_id uuid not null references messaging.contacts(id) on delete cascade,
  whatsapp_message_id text,
  direction text not null,
  message_type text not null default 'text',
  body text,
  status text,
  raw_payload jsonb,
  sent_at timestamptz,
  created_at timestamptz not null default now(),

  constraint messages_direction_check
    check (direction in ('inbound', 'outbound')),
  constraint messages_type_check
    check (message_type in ('text', 'image', 'audio', 'video', 'document', 'location', 'other'))
);

comment on column messaging.messages.whatsapp_message_id is
  'Meta WhatsApp message ID. Used for idempotency when storing webhook events.';

create unique index if not exists idx_messages_whatsapp_message_id
  on messaging.messages (tenant_id, whatsapp_message_id)
  where whatsapp_message_id is not null;

create index if not exists idx_messages_conversation_created
  on messaging.messages (conversation_id, created_at desc);

create index if not exists idx_messages_tenant_created
  on messaging.messages (tenant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
create or replace function messaging.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_contacts_updated_at on messaging.contacts;
create trigger trg_contacts_updated_at
before update on messaging.contacts
for each row execute function messaging.set_updated_at();

drop trigger if exists trg_conversations_updated_at on messaging.conversations;
create trigger trg_conversations_updated_at
before update on messaging.conversations
for each row execute function messaging.set_updated_at();

-- ---------------------------------------------------------------------------
-- Helper: record inbound WhatsApp message in one call (for n8n Postgres node)
-- ---------------------------------------------------------------------------
create or replace function messaging.record_inbound_message(
  p_phone_number_id text,
  p_wa_id text,
  p_display_name text default null,
  p_body text default null,
  p_whatsapp_message_id text default null,
  p_message_type text default 'text',
  p_raw_payload jsonb default null,
  p_sent_at timestamptz default null
)
returns table (
  tenant_id uuid,
  contact_id uuid,
  conversation_id uuid,
  message_id uuid
)
language plpgsql
as $$
declare
  v_tenant_id uuid;
  v_contact_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
begin
  select wa.tenant_id
  into v_tenant_id
  from tenant.whatsapp_accounts wa
  join tenant.tenants t on t.id = wa.tenant_id
  where wa.whatsapp_phone_number_id = p_phone_number_id
    and wa.is_active = true
    and wa.is_primary = true
    and t.is_active = true
  limit 1;

  if v_tenant_id is null then
    raise exception 'No active tenant found for whatsapp_phone_number_id: %', p_phone_number_id;
  end if;

  insert into messaging.contacts (tenant_id, wa_id, display_name, last_seen_at)
  values (v_tenant_id, p_wa_id, p_display_name, coalesce(p_sent_at, now()))
  on conflict (tenant_id, wa_id) do update
    set display_name = coalesce(excluded.display_name, messaging.contacts.display_name),
        last_seen_at = coalesce(p_sent_at, now()),
        updated_at = now()
  returning id into v_contact_id;

  insert into messaging.conversations (
    tenant_id,
    contact_id,
    whatsapp_phone_number_id,
    last_message_at
  ) values (
    v_tenant_id,
    v_contact_id,
    p_phone_number_id,
    coalesce(p_sent_at, now())
  )
  on conflict (tenant_id, contact_id, whatsapp_phone_number_id) do update
    set last_message_at = coalesce(p_sent_at, now()),
        updated_at = now()
  returning id into v_conversation_id;

  if p_whatsapp_message_id is not null then
    select m.id
    into v_message_id
    from messaging.messages m
    where m.tenant_id = v_tenant_id
      and m.whatsapp_message_id = p_whatsapp_message_id
    limit 1;

    if v_message_id is not null then
      tenant_id := v_tenant_id;
      contact_id := v_contact_id;
      conversation_id := v_conversation_id;
      message_id := v_message_id;
      return next;
      return;
    end if;
  end if;

  insert into messaging.messages (
    tenant_id,
    conversation_id,
    contact_id,
    whatsapp_message_id,
    direction,
    message_type,
    body,
    status,
    raw_payload,
    sent_at
  ) values (
    v_tenant_id,
    v_conversation_id,
    v_contact_id,
    p_whatsapp_message_id,
    'inbound',
    coalesce(p_message_type, 'text'),
    p_body,
    'received',
    p_raw_payload,
    coalesce(p_sent_at, now())
  )
  returning id into v_message_id;

  tenant_id := v_tenant_id;
  contact_id := v_contact_id;
  conversation_id := v_conversation_id;
  message_id := v_message_id;
  return next;
end;
$$;

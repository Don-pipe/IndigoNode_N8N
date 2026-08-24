-- White Node / IndigoNode
-- Run order: 15
-- Purpose: messaging_channels schema + tables (summary-only memory, multi-channel ready)
-- Prerequisites: 014_tenant_v2_migration.sql
-- Next: 016_messaging_channels_functions.sql
--
-- STATUS: APPLIED in production — 2026-08-24 (no errors)
-- Verify: contacts count 0, conversations count 0 (expected — empty until first message)
--
-- Note: old messaging.* data is NOT migrated (test reset approved). Drop in 018.

create schema if not exists messaging_channels;

-- ---------------------------------------------------------------------------
-- contacts — end users messaging a business (patients, customers, leads)
-- ---------------------------------------------------------------------------
create table if not exists messaging_channels.contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  business_id uuid not null references tenant.tenant_businesses(id) on delete cascade,
  channel text not null,
  external_id text not null,
  display_name text,
  is_active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (tenant_id, business_id, channel, external_id),

  constraint contacts_channel_check
    check (channel in ('whatsapp', 'instagram', 'facebook', 'sms', 'email', 'other'))
);

comment on column messaging_channels.contacts.external_id is
  'Channel user ID. WhatsApp: webhook contacts[].wa_id.';

create index if not exists idx_messaging_contacts_lookup
  on messaging_channels.contacts (tenant_id, business_id, channel, external_id);

-- ---------------------------------------------------------------------------
-- conversations — rolling summary + 24h message window counter
-- ---------------------------------------------------------------------------
create table if not exists messaging_channels.conversations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  business_id uuid not null references tenant.tenant_businesses(id) on delete cascade,
  contact_id uuid not null references messaging_channels.contacts(id) on delete cascade,
  channel text not null,
  channel_endpoint_id text not null,
  status text not null default 'open',
  summary text,
  summary_updated_at timestamptz,
  message_count integer not null default 0,
  message_window_started_at timestamptz,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (tenant_id, contact_id, channel, channel_endpoint_id),

  constraint conversations_channel_check
    check (channel in ('whatsapp', 'instagram', 'facebook', 'sms', 'email', 'other')),
  constraint conversations_status_check
    check (status in ('open', 'closed', 'archived'))
);

comment on column messaging_channels.conversations.summary is
  'Rolling AI-generated summary. No raw message bodies stored.';
comment on column messaging_channels.conversations.message_count is
  'Inbound messages in the current 24h window. Reset when window expires.';
comment on column messaging_channels.conversations.channel_endpoint_id is
  'Channel routing ID. WhatsApp: metadata.phone_number_id.';

create index if not exists idx_messaging_conversations_tenant_last
  on messaging_channels.conversations (tenant_id, last_message_at desc nulls last);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
create or replace function messaging_channels.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_messaging_contacts_updated_at on messaging_channels.contacts;
create trigger trg_messaging_contacts_updated_at
before update on messaging_channels.contacts
for each row execute function messaging_channels.set_updated_at();

drop trigger if exists trg_messaging_conversations_updated_at on messaging_channels.conversations;
create trigger trg_messaging_conversations_updated_at
before update on messaging_channels.conversations
for each row execute function messaging_channels.set_updated_at();

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- select count(*) from messaging_channels.contacts;
-- select count(*) from messaging_channels.conversations;

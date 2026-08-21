-- White Node / IndigoNode
-- Run order: 1
-- Purpose: Core tenant schema for multi-doctor WhatsApp automation routing

create schema if not exists tenant;

-- ---------------------------------------------------------------------------
-- Core tenant record
-- ---------------------------------------------------------------------------
create table if not exists tenant.tenants (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  display_name text not null,
  specialty text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Business profile used by the AI agent (doctor-specific details)
-- ---------------------------------------------------------------------------
create table if not exists tenant.business_profiles (
  tenant_id uuid primary key references tenant.tenants(id) on delete cascade,
  consultation_fee numeric(10, 2),
  consultation_currency text not null default 'BOB',
  address text,
  office_hours_start time not null default '09:00',
  office_hours_end time not null default '12:00',
  timezone text not null default 'America/La_Paz',
  maps_url text,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- WhatsApp account mapping
-- Lookup key: whatsapp_phone_number_id (from WhatsApp webhook metadata)
-- ---------------------------------------------------------------------------
create table if not exists tenant.whatsapp_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  whatsapp_phone_number_id text not null unique,
  whatsapp_business_number text,
  waba_id text,
  display_name text,
  is_primary boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_whatsapp_accounts_phone_number_id
  on tenant.whatsapp_accounts (whatsapp_phone_number_id)
  where is_active = true;

-- ---------------------------------------------------------------------------
-- External integrations per tenant (e.g. Google Calendar)
-- ---------------------------------------------------------------------------
create table if not exists tenant.integrations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  provider text not null,
  external_id text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, provider)
);

-- ---------------------------------------------------------------------------
-- updated_at trigger helper
-- ---------------------------------------------------------------------------
create or replace function tenant.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_tenants_updated_at on tenant.tenants;
create trigger trg_tenants_updated_at
before update on tenant.tenants
for each row execute function tenant.set_updated_at();

drop trigger if exists trg_business_profiles_updated_at on tenant.business_profiles;
create trigger trg_business_profiles_updated_at
before update on tenant.business_profiles
for each row execute function tenant.set_updated_at();

drop trigger if exists trg_whatsapp_accounts_updated_at on tenant.whatsapp_accounts;
create trigger trg_whatsapp_accounts_updated_at
before update on tenant.whatsapp_accounts
for each row execute function tenant.set_updated_at();

drop trigger if exists trg_integrations_updated_at on tenant.integrations;
create trigger trg_integrations_updated_at
before update on tenant.integrations
for each row execute function tenant.set_updated_at();

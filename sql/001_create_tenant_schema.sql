-- White Node / IndigoNode
-- Run order: 1
-- Purpose: Generic multi-tenant schema for WhatsApp automation routing
-- Scope: tenant identity + WhatsApp connection + basic business profile
-- Deferred: schedules, appointments, calendar integrations

create schema if not exists tenant;

-- ---------------------------------------------------------------------------
-- Core tenant record (business-agnostic)
-- ---------------------------------------------------------------------------
create table if not exists tenant.tenants (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  display_name text not null,
  business_type text not null default 'doctor',
  specialty text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint tenants_business_type_check
    check (business_type in ('doctor', 'lawyer', 'salon', 'restaurant', 'other'))
);

comment on column tenant.tenants.business_type is
  'Generic tenant category. Doctors first; extend enum as new verticals are onboarded.';

comment on column tenant.tenants.specialty is
  'Optional vertical-specific label, e.g. Neurología for doctors.';

-- ---------------------------------------------------------------------------
-- Basic business profile (non-schedule fields only for this stage)
-- ---------------------------------------------------------------------------
create table if not exists tenant.business_profiles (
  tenant_id uuid primary key references tenant.tenants(id) on delete cascade,
  service_fee numeric(10, 2),
  service_currency text not null default 'BOB',
  address text,
  timezone text not null default 'America/La_Paz',
  maps_url text,
  metadata jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

comment on column tenant.business_profiles.metadata is
  'Flexible JSON for business-type-specific fields without schema changes.';

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

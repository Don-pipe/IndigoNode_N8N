-- White Node / IndigoNode
-- Run order: 14
-- Purpose: Tenant schema v2 — new tables, POC columns, migrate business_profiles data
-- Prerequisites: 001–012 applied (production)
-- Next: 015_messaging_channels_schema.sql
--
-- STATUS: APPLIED in production — 2026-08-24 (steps 0–9, no errors)
-- Note: step 8 first attempt failed (PL/pgSQL phone/name); fixed with table alias ten.*
--       014b not needed if step 8 completed successfully from this file.
--
-- BEFORE RUNNING: deactivate n8n workflow (see docs/resources/migration_plan_v2.md)

-- ---------------------------------------------------------------------------
-- 0) Drop old automation view (depends on business_profiles) | Complete no errors
-- ---------------------------------------------------------------------------
drop view if exists public.v_automation_config cascade;
drop view if exists tenant.v_automation_config cascade;

-- ---------------------------------------------------------------------------
-- 1) Extend tenants with POC fields (keep legacy columns until 018 cleanup) | Complete no errors
-- ---------------------------------------------------------------------------
alter table tenant.tenants
  add column if not exists name text,
  add column if not exists last_name text,
  add column if not exists professional_title text,
  add column if not exists phone text,
  add column if not exists email text;

comment on column tenant.tenants.name is
  'POC first name(s). Public bot name lives on tenant_businesses.name.';
comment on column tenant.tenants.email is
  'Future Gmail / subscription login email. Nullable until auth is built.';

-- ---------------------------------------------------------------------------
-- 2) tenant_settings | Complete no errors
-- ---------------------------------------------------------------------------
create table if not exists tenant.tenant_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null unique references tenant.tenants(id) on delete cascade,
  account_status boolean not null default true,
  automation_plan text not null default 'basic',
  max_business integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint tenant_settings_automation_plan_check
    check (automation_plan in ('basic', 'enterprise', 'custom'))
);

comment on column tenant.tenant_settings.automation_plan is
  'Billing tier (basic/enterprise/custom). NOT tied to 24h message cap.';

-- ---------------------------------------------------------------------------
-- 3) tenant_businesses | Complete no errors
-- ---------------------------------------------------------------------------
create table if not exists tenant.tenant_businesses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  name text not null,
  category text not null,
  subcategory text,
  address text,
  maps_url text,
  currency text not null default 'BOB',
  timezone text not null default 'America/La_Paz',
  phone_1 text,
  phone_2 text,
  phone_3 text,
  hours_start time,
  hours_end time,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_tenant_businesses_tenant
  on tenant.tenant_businesses (tenant_id)
  where is_active = true;

-- ---------------------------------------------------------------------------
-- 4) business_pricing | Complete no errors
-- ---------------------------------------------------------------------------
create table if not exists tenant.business_pricing (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  business_id uuid not null references tenant.tenant_businesses(id) on delete cascade,
  name text not null,
  amount numeric(10, 2) not null,
  currency text,
  is_default boolean not null default false,
  description text,
  is_active boolean not null default true,
  sort_order integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_business_pricing_one_default
  on tenant.business_pricing (business_id)
  where is_default = true and is_active = true;

-- ---------------------------------------------------------------------------
-- 5) business_knowledge | Complete with no errors
-- ---------------------------------------------------------------------------
create table if not exists tenant.business_knowledge (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  business_id uuid not null references tenant.tenant_businesses(id) on delete cascade,
  type text not null,
  title text not null,
  content text not null,
  metadata jsonb not null default '{}',
  is_active boolean not null default true,
  sort_order integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint business_knowledge_type_check
    check (type in ('faq', 'policy', 'about'))
);

-- ---------------------------------------------------------------------------
-- 6) whatsapp_accounts.business_id | Complete with no errors
-- ---------------------------------------------------------------------------
alter table tenant.whatsapp_accounts
  add column if not exists business_id uuid references tenant.tenant_businesses(id) on delete restrict;

create index if not exists idx_whatsapp_accounts_business
  on tenant.whatsapp_accounts (business_id)
  where is_active = true;

-- ---------------------------------------------------------------------------
-- 7) updated_at triggers for new tables | Complete with no errors
-- ---------------------------------------------------------------------------
drop trigger if exists trg_tenant_settings_updated_at on tenant.tenant_settings;
create trigger trg_tenant_settings_updated_at
before update on tenant.tenant_settings
for each row execute function tenant.set_updated_at();

drop trigger if exists trg_tenant_businesses_updated_at on tenant.tenant_businesses;
create trigger trg_tenant_businesses_updated_at
before update on tenant.tenant_businesses
for each row execute function tenant.set_updated_at();

drop trigger if exists trg_business_pricing_updated_at on tenant.business_pricing;
create trigger trg_business_pricing_updated_at
before update on tenant.business_pricing
for each row execute function tenant.set_updated_at();

drop trigger if exists trg_business_knowledge_updated_at on tenant.business_knowledge;
create trigger trg_business_knowledge_updated_at
before update on tenant.business_knowledge
for each row execute function tenant.set_updated_at();

-- ---------------------------------------------------------------------------
-- 8) Data migration: business_profiles → v2 tables (idempotent) | Completed with no errors
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_business_id uuid;
  v_category text;
  v_subcategory text;
  v_hours_start time;
  v_hours_end time;
begin
  for r in
    select
      t.id as tenant_id,
      t.slug,
      t.display_name,
      t.business_type,
      t.specialty,
      t.is_active,
      bp.service_fee,
      bp.service_currency,
      bp.address,
      bp.timezone,
      bp.maps_url,
      bp.metadata,
      wa.whatsapp_business_number
    from tenant.tenants t
    left join tenant.business_profiles bp on bp.tenant_id = t.id
    left join lateral (
      select whatsapp_business_number
      from tenant.whatsapp_accounts wa
      where wa.tenant_id = t.id
        and wa.is_active = true
      order by wa.is_primary desc, wa.created_at
      limit 1
    ) wa on true
  loop
    -- POC fields (Murillo slug gets structured split; others keep display_name as name)
    -- Table alias required: in PL/pgSQL, bare "phone"/"name" resolve as variables, not columns.
    if r.slug = 'dr-luis-murillo' then
      update tenant.tenants ten
      set professional_title = 'Dr',
          name = 'Luis Felipe',
          last_name = 'Murillo',
          phone = coalesce(r.whatsapp_business_number, ten.phone),
          updated_at = now()
      where ten.id = r.tenant_id;
    else
      update tenant.tenants ten
      set name = coalesce(ten.name, r.display_name),
          phone = coalesce(r.whatsapp_business_number, ten.phone),
          updated_at = now()
      where ten.id = r.tenant_id;
    end if;

    -- tenant_settings (skip if already migrated)
    insert into tenant.tenant_settings (tenant_id, account_status, automation_plan, max_business)
    values (r.tenant_id, coalesce(r.is_active, true), 'basic', 1)
    on conflict (tenant_id) do update
      set account_status = excluded.account_status,
          updated_at = now();

    -- category / subcategory from legacy enums
    v_category := case r.business_type
      when 'doctor' then 'medicine'
      when 'lawyer' then 'legal'
      when 'salon' then 'beauty wellness'
      when 'restaurant' then 'restaurant'
      else coalesce(r.business_type, 'other')
    end;

    v_subcategory := case
      when lower(coalesce(r.specialty, '')) in ('neurología', 'neurologia', 'neurology') then 'neurology'
      when r.specialty is not null then lower(r.specialty)
      else null
    end;

    v_hours_start := nullif(r.metadata->>'office_hours_start', '')::time;
    v_hours_end := nullif(r.metadata->>'office_hours_end', '')::time;

    -- tenant_businesses (one primary business per tenant for POC)
    select tb.id into v_business_id
    from tenant.tenant_businesses tb
    where tb.tenant_id = r.tenant_id
    order by tb.created_at
    limit 1;

    if v_business_id is null then
      insert into tenant.tenant_businesses (
        tenant_id,
        name,
        category,
        subcategory,
        address,
        maps_url,
        currency,
        timezone,
        phone_1,
        hours_start,
        hours_end,
        is_active
      ) values (
        r.tenant_id,
        coalesce(r.display_name, 'Business'),
        v_category,
        v_subcategory,
        r.address,
        r.maps_url,
        coalesce(r.service_currency, 'BOB'),
        coalesce(r.timezone, 'America/La_Paz'),
        r.whatsapp_business_number,
        v_hours_start,
        v_hours_end,
        coalesce(r.is_active, true)
      )
      returning id into v_business_id;
    end if;

    -- business_pricing default row
    if r.service_fee is not null and not exists (
      select 1 from tenant.business_pricing p
      where p.business_id = v_business_id and p.is_default = true
    ) then
      insert into tenant.business_pricing (
        tenant_id,
        business_id,
        name,
        amount,
        currency,
        is_default,
        is_active,
        sort_order
      ) values (
        r.tenant_id,
        v_business_id,
        'Consulta',
        r.service_fee,
        coalesce(r.service_currency, 'BOB'),
        true,
        true,
        0
      );
    end if;

    -- Link WhatsApp accounts to business
    update tenant.whatsapp_accounts
    set business_id = v_business_id,
        updated_at = now()
    where tenant_id = r.tenant_id
      and business_id is null;
  end loop;
end $$;

-- Require business_id on active WhatsApp lines after migration | Complete — no errors
alter table tenant.whatsapp_accounts
  drop constraint if exists whatsapp_accounts_business_required;

alter table tenant.whatsapp_accounts
  add constraint whatsapp_accounts_business_required
  check (business_id is not null or is_active = false);

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- select t.slug, t.professional_title, t.name, t.last_name, tb.name, tb.category, ts.automation_plan
-- from tenant.tenants t
-- join tenant.tenant_settings ts on ts.tenant_id = t.id
-- join tenant.tenant_businesses tb on tb.tenant_id = t.id;
--
-- select whatsapp_phone_number_id, business_id from tenant.whatsapp_accounts;


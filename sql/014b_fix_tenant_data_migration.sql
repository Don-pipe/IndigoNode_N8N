-- White Node / IndigoNode
-- STATUS: NOT NEEDED — 014 step 8 completed successfully 2026-08-24 (fixed in 014_tenant_v2_migration.sql)
-- Run only if: 014 section 8 failed with ERROR 42703 column "phone" does not exist
-- Cause: PL/pgSQL resolves bare "phone"/"name" as variables, not table columns.
-- Safe to re-run (idempotent).

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

    insert into tenant.tenant_settings (tenant_id, account_status, automation_plan, max_business)
    values (r.tenant_id, coalesce(r.is_active, true), 'basic', 1)
    on conflict (tenant_id) do update
      set account_status = excluded.account_status,
          updated_at = now();

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

    update tenant.whatsapp_accounts
    set business_id = v_business_id,
        updated_at = now()
    where tenant_id = r.tenant_id
      and business_id is null;
  end loop;
end $$;

alter table tenant.whatsapp_accounts
  drop constraint if exists whatsapp_accounts_business_required;

alter table tenant.whatsapp_accounts
  add constraint whatsapp_accounts_business_required
  check (business_id is not null or is_active = false);

-- Verify:
-- select t.slug, t.professional_title, t.name, tb.name, wa.business_id
-- from tenant.tenants t
-- join tenant.tenant_businesses tb on tb.tenant_id = t.id
-- join tenant.whatsapp_accounts wa on wa.tenant_id = t.id;

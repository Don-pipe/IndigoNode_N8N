-- White Node / IndigoNode
-- Run order: 19 (test data — run manually in Supabase SQL Editor)
-- Purpose: Add a second Murillo business (same WhatsApp line, different office/price/hours)
--
-- v1 bot routes ONE business per phone_number_id via whatsapp_accounts.business_id.
-- After this script, use the SWITCH queries at the bottom to test each office.

do $$
declare
  v_tenant_id uuid;
  v_business_primary uuid;
  v_business_second uuid;
begin
  select id into v_tenant_id
  from tenant.tenants
  where slug = 'dr-luis-murillo';

  if v_tenant_id is null then
    raise exception 'Tenant dr-luis-murillo not found — run v2 migration first.';
  end if;

  -- Allow two businesses on this tenant plan (test)
  update tenant.tenant_settings
  set max_business = 2,
      updated_at = now()
  where tenant_id = v_tenant_id;

  -- Primary office (ensure known values)
  select tb.id into v_business_primary
  from tenant.tenant_businesses tb
  where tb.tenant_id = v_tenant_id
  order by tb.created_at
  limit 1;

  if v_business_primary is null then
    raise exception 'No existing business for Murillo — run 014 migration first.';
  end if;

  update tenant.tenant_businesses
  set name = 'Dr. Luis Felipe Murillo',
      category = 'medicine',
      subcategory = 'neurology',
      address = 'Calle Papa León XIII, La Paz',
      maps_url = 'https://maps.app.goo.gl/LqGRvjm85YP29LGr9',
      currency = 'BOB',
      timezone = 'America/La_Paz',
      phone_1 = '+59176268600',
      hours_start = '09:00'::time,
      hours_end = '12:00'::time,
      is_active = true,
      updated_at = now()
  where id = v_business_primary;

  -- Default price 300 BOB on primary
  if not exists (
    select 1 from tenant.business_pricing p
    where p.business_id = v_business_primary and p.is_default = true
  ) then
    insert into tenant.business_pricing (
      tenant_id, business_id, name, amount, currency, is_default, is_active, sort_order
    ) values (
      v_tenant_id, v_business_primary, 'Consulta', 300, 'BOB', true, true, 0
    );
  else
    update tenant.business_pricing
    set amount = 300,
        currency = 'BOB',
        is_active = true,
        updated_at = now()
    where business_id = v_business_primary
      and is_default = true;
  end if;

  -- Second office — afternoon / Sopocachi
  select tb.id into v_business_second
  from tenant.tenant_businesses tb
  where tb.tenant_id = v_tenant_id
    and tb.name = 'Consultorio Neurológico Murillo — Sopocachi';

  if v_business_second is null then
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
      v_tenant_id,
      'Consultorio Neurológico Murillo — Sopocachi',
      'medicine',
      'neurology',
      'Av. Sánchez Lima #2235, Sopocachi, La Paz',
      'https://www.google.com/maps?q=-16.5074,-68.1290',
      'BOB',
      'America/La_Paz',
      '+59176268600',
      '14:00'::time,
      '20:00'::time,
      true
    )
    returning id into v_business_second;
  else
    update tenant.tenant_businesses
    set address = 'Av. Sánchez Lima #2235, Sopocachi, La Paz',
        maps_url = 'https://www.google.com/maps?q=-16.5074,-68.1290',
        phone_1 = '+59176268600',
        hours_start = '14:00'::time,
        hours_end = '20:00'::time,
        is_active = true,
        updated_at = now()
    where id = v_business_second;
  end if;

  if not exists (
    select 1 from tenant.business_pricing p
    where p.business_id = v_business_second and p.is_default = true
  ) then
    insert into tenant.business_pricing (
      tenant_id, business_id, name, amount, currency, is_default, is_active, sort_order
    ) values (
      v_tenant_id, v_business_second, 'Consulta', 250, 'BOB', true, true, 0
    );
  else
    update tenant.business_pricing
    set amount = 250,
        currency = 'BOB',
        is_active = true,
        updated_at = now()
    where business_id = v_business_second
      and is_default = true;
  end if;

  -- Default routing: primary office (300 BOB, morning). Switch for Sopocachi test.
  update tenant.whatsapp_accounts
  set business_id = v_business_primary,
      updated_at = now()
  where tenant_id = v_tenant_id
    and whatsapp_phone_number_id = '1248499035016959';

  raise notice 'Primary business_id: %', v_business_primary;
  raise notice 'Second business_id: %', v_business_second;
end $$;

-- ---------------------------------------------------------------------------
-- Verify both businesses
-- ---------------------------------------------------------------------------
select
  tb.name,
  tb.address,
  tb.maps_url,
  tb.hours_start,
  tb.hours_end,
  bp.amount as consult_price_bob,
  (wa.business_id = tb.id) as is_active_for_whatsapp
from tenant.tenants t
join tenant.tenant_businesses tb on tb.tenant_id = t.id
left join tenant.business_pricing bp on bp.business_id = tb.id and bp.is_default = true
left join tenant.whatsapp_accounts wa on wa.tenant_id = t.id and wa.is_active = true
where t.slug = 'dr-luis-murillo'
order by tb.created_at;

-- ---------------------------------------------------------------------------
-- SWITCH active business for v1 bot testing (same WhatsApp number)
-- ---------------------------------------------------------------------------
-- Primary — Calle Papa León XIII, 09:00–12:00, 300 BOB:
-- update tenant.whatsapp_accounts wa
-- set business_id = (
--   select tb.id from tenant.tenant_businesses tb
--   join tenant.tenants t on t.id = tb.tenant_id
--   where t.slug = 'dr-luis-murillo'
--     and tb.name = 'Dr. Luis Felipe Murillo'
-- ),
-- updated_at = now()
-- where whatsapp_phone_number_id = '1248499035016959';
--
-- Second — Sopocachi, 14:00–20:00, 250 BOB:
-- update tenant.whatsapp_accounts wa
-- set business_id = (
--   select tb.id from tenant.tenant_businesses tb
--   join tenant.tenants t on t.id = tb.tenant_id
--   where t.slug = 'dr-luis-murillo'
--     and tb.name = 'Consultorio Neurológico Murillo — Sopocachi'
-- ),
-- updated_at = now()
-- where whatsapp_phone_number_id = '1248499035016959';
--
-- Confirm what the bot will load:
-- select tenant_name, service_fee, address, business_metadata
-- from tenant.v_automation_config
-- where whatsapp_phone_number_id = '1248499035016959';

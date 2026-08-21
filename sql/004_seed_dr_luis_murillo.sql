-- White Node / IndigoNode
-- Run order: 4
-- Purpose: Seed first tenant (Dr. Luis Felipe Murillo)
--
-- BEFORE RUNNING:
-- 1. Replace YOUR_META_PHONE_NUMBER_ID_HERE with metadata.phone_number_id from n8n
-- 2. Replace +591XXXXXXXX with the doctor's WhatsApp business number

do $$
declare
  v_tenant_id uuid;
begin
  insert into tenant.tenants (slug, display_name, specialty)
  values ('dr-luis-murillo', 'Dr. Luis Felipe Murillo', 'Neurología')
  on conflict (slug) do update
    set display_name = excluded.display_name,
        specialty = excluded.specialty,
        is_active = true,
        updated_at = now()
  returning id into v_tenant_id;

  if v_tenant_id is null then
    select id into v_tenant_id
    from tenant.tenants
    where slug = 'dr-luis-murillo';
  end if;

  insert into tenant.business_profiles (
    tenant_id,
    consultation_fee,
    consultation_currency,
    address,
    office_hours_start,
    office_hours_end,
    timezone,
    maps_url
  ) values (
    v_tenant_id,
    300,
    'BOB',
    'Calle Papa León XIII',
    '09:00',
    '12:00',
    'America/La_Paz',
    'https://maps.app.goo.gl/LqGRvjm85YP29LGr9'
  )
  on conflict (tenant_id) do update
    set consultation_fee = excluded.consultation_fee,
        consultation_currency = excluded.consultation_currency,
        address = excluded.address,
        office_hours_start = excluded.office_hours_start,
        office_hours_end = excluded.office_hours_end,
        timezone = excluded.timezone,
        maps_url = excluded.maps_url,
        updated_at = now();

  insert into tenant.whatsapp_accounts (
    tenant_id,
    whatsapp_phone_number_id,
    whatsapp_business_number,
    is_primary,
    is_active
  ) values (
    v_tenant_id,
    'YOUR_META_PHONE_NUMBER_ID_HERE',
    '+591XXXXXXXX',
    true,
    true
  )
  on conflict (whatsapp_phone_number_id) do update
    set tenant_id = excluded.tenant_id,
        whatsapp_business_number = excluded.whatsapp_business_number,
        is_primary = excluded.is_primary,
        is_active = excluded.is_active,
        updated_at = now();

  insert into tenant.integrations (tenant_id, provider, external_id, is_active)
  values (
    v_tenant_id,
    'google_calendar',
    '37ebcac507f299c1de41e49af7883046b274aa93c1538705f70ce243ae1c340d@group.calendar.google.com',
    true
  )
  on conflict (tenant_id, provider) do update
    set external_id = excluded.external_id,
        is_active = excluded.is_active,
        updated_at = now();
end $$;

-- Verify seed:
-- select * from tenant.v_automation_config where slug = 'dr-luis-murillo';

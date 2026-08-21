-- White Node / IndigoNode
-- Run order: 5
-- Purpose: Seed first tenant (Dr. Luis Felipe Murillo)
--
-- BEFORE RUNNING:
-- 1. Replace YOUR_META_PHONE_NUMBER_ID_HERE with metadata.phone_number_id from n8n
-- 2. Replace +591XXXXXXXX with the tenant WhatsApp business number

do $$
declare
  v_tenant_id uuid;
begin
  insert into tenant.tenants (slug, display_name, business_type, specialty)
  values ('dr-luis-murillo', 'Dr. Luis Felipe Murillo', 'doctor', 'Neurología')
  on conflict (slug) do update
    set display_name = excluded.display_name,
        business_type = excluded.business_type,
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
    service_fee,
    service_currency,
    address,
    timezone,
    maps_url,
    metadata
  ) values (
    v_tenant_id,
    300,
    'BOB',
    'Calle Papa León XIII',
    'America/La_Paz',
    'https://maps.app.goo.gl/LqGRvjm85YP29LGr9',
    '{"office_hours_start":"09:00","office_hours_end":"12:00"}'::jsonb
  )
  on conflict (tenant_id) do update
    set service_fee = excluded.service_fee,
        service_currency = excluded.service_currency,
        address = excluded.address,
        timezone = excluded.timezone,
        maps_url = excluded.maps_url,
        metadata = excluded.metadata,
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
end $$;

-- Verify seed:
-- select * from tenant.v_automation_config where slug = 'dr-luis-murillo';

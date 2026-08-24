-- White Node / IndigoNode
-- Run order: 21
-- Purpose: When a tenant_businesses row is deactivated, cascade is_active = false
--          to pricing, knowledge, contacts; reassign or pause WhatsApp line.
--
-- Does NOT auto-reactivate children when business is turned back on (explicit opt-in).

-- ---------------------------------------------------------------------------
-- 1) cascade function
-- ---------------------------------------------------------------------------
create or replace function tenant.cascade_business_deactivation()
returns trigger
language plpgsql
as $$
declare
  v_fallback_business_id uuid;
begin
  if not (
    (TG_OP = 'UPDATE' and OLD.is_active = true and NEW.is_active = false)
    or (TG_OP = 'INSERT' and NEW.is_active = false)
  ) then
    return NEW;
  end if;

  update tenant.business_pricing
  set is_active = false,
      updated_at = now()
  where business_id = NEW.id
    and is_active = true;

  update tenant.business_knowledge
  set is_active = false,
      updated_at = now()
  where business_id = NEW.id
    and is_active = true;

  update messaging_channels.contacts
  set is_active = false,
      updated_at = now()
  where business_id = NEW.id
    and is_active = true;

  update messaging_channels.routing_sessions
  set selected_business_id = null,
      updated_at = now()
  where selected_business_id = NEW.id;

  select tb.id
  into v_fallback_business_id
  from tenant.tenant_businesses tb
  where tb.tenant_id = NEW.tenant_id
    and tb.is_active = true
    and tb.id <> NEW.id
  order by tb.created_at
  limit 1;

  if v_fallback_business_id is not null then
    update tenant.whatsapp_accounts wa
    set business_id = v_fallback_business_id,
        is_active = true,
        updated_at = now()
    where wa.tenant_id = NEW.tenant_id
      and wa.business_id = NEW.id;
  else
    update tenant.whatsapp_accounts wa
    set is_active = false,
        updated_at = now()
    where wa.tenant_id = NEW.tenant_id
      and wa.business_id = NEW.id;
  end if;

  return NEW;
end;
$$;

comment on function tenant.cascade_business_deactivation() is
  'AFTER INSERT/UPDATE on tenant_businesses: deactivate pricing, knowledge, contacts; clear routing; reassign WhatsApp default business.';

-- ---------------------------------------------------------------------------
-- 2) trigger
-- ---------------------------------------------------------------------------
drop trigger if exists trg_tenant_businesses_deactivation_cascade on tenant.tenant_businesses;

create trigger trg_tenant_businesses_deactivation_cascade
after insert or update of is_active on tenant.tenant_businesses
for each row
execute function tenant.cascade_business_deactivation();

-- ---------------------------------------------------------------------------
-- 3) backfill — touch is_active to fire trigger for rows already inactive
-- ---------------------------------------------------------------------------
update tenant.tenant_businesses tb
set is_active = false
where tb.is_active = false;

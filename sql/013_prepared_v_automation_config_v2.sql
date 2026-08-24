-- White Node / IndigoNode
-- Run order: 13 (after 014–016)
-- Purpose: Replace tenant.v_automation_config for the new schema (see docs/resources/supabase_db_design.md)
--
-- STATUS: APPLIED in production — 2026-08-24 (section 1 only, no errors)
-- Skipped: public.v_automation_config proxy (n8n uses Postgres node)
-- Grants: sql/017_grants_rls_v2.sql
--
-- n8n usage (unchanged entry point):
--   select * from tenant.v_automation_config
--   where whatsapp_phone_number_id = '{{ $json.phone_number_id }}'
--   limit 1;
--
-- COLUMN MAP (v1.3 → v2) — backward-compatible aliases included:
--   tenant_id              ← tenants.id
--   tenant_name            ← tenant_businesses.name (display name for AI)
--   specialty              ← tenant_businesses.subcategory (alias)
--   tenant_active          ← tenant_settings.account_status (+ business/whatsapp active)
--   service_fee            ← default business_pricing.amount
--   service_currency       ← tenant_businesses.currency
--   address, maps_url      ← tenant_businesses
--   business_metadata      ← json { office_hours_start, office_hours_end }
--   knowledge_blocks       ← NEW json array of faq/policy/about
--   pricing_blocks         ← NEW json array of all active prices
--   knowledge_text         ← NEW single text block for AI prompt

-- ---------------------------------------------------------------------------
-- 1) Main automation config view (webhook lookup)
-- ---------------------------------------------------------------------------
create or replace view tenant.v_automation_config as
select
  t.id as tenant_id,
  t.name as tenant_account_name,
  tb.id as business_id,
  tb.name as tenant_name,
  tb.category,
  tb.subcategory,
  tb.subcategory as specialty,

  (
    ts.account_status
    and tb.is_active
    and wa.is_active
  ) as tenant_active,

  ts.automation_plan,
  ts.max_business,

  tb.address,
  tb.maps_url,
  tb.currency as service_currency,
  tb.timezone,
  tb.hours_start,
  tb.hours_end,

  jsonb_build_object(
    'office_hours_start', to_char(tb.hours_start, 'HH24:MI'),
    'office_hours_end', to_char(tb.hours_end, 'HH24:MI')
  ) as business_metadata,

  default_price.amount as service_fee,
  coalesce(default_price.currency, tb.currency) as default_price_currency,
  default_price.name as default_price_name,

  wa.id as whatsapp_account_id,
  wa.whatsapp_phone_number_id,
  wa.whatsapp_business_number,
  wa.waba_id,
  wa.is_primary as whatsapp_is_primary,

  coalesce(knowledge.knowledge_blocks, '[]'::jsonb) as knowledge_blocks,
  coalesce(knowledge.knowledge_text, '') as knowledge_text,
  coalesce(pricing.pricing_blocks, '[]'::jsonb) as pricing_blocks

from tenant.whatsapp_accounts wa
join tenant.tenants t
  on t.id = wa.tenant_id
join tenant.tenant_settings ts
  on ts.tenant_id = t.id
join tenant.tenant_businesses tb
  on tb.id = wa.business_id
 and tb.tenant_id = t.id

left join lateral (
  select
    p.amount,
    p.currency,
    p.name
  from tenant.business_pricing p
  where p.business_id = tb.id
    and p.is_active = true
    and p.is_default = true
  order by p.sort_order nulls last, p.created_at
  limit 1
) default_price on true

left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'type', bk.type,
        'title', bk.title,
        'content', bk.content
      )
      order by bk.sort_order nulls last, bk.type, bk.title
    ) as knowledge_blocks,
    string_agg(
      initcap(bk.type) || ' — ' || bk.title || E':\n' || bk.content,
      E'\n\n'
      order by bk.sort_order nulls last, bk.type, bk.title
    ) as knowledge_text
  from tenant.business_knowledge bk
  where bk.business_id = tb.id
    and bk.is_active = true
) knowledge on true

left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'name', bp.name,
        'amount', bp.amount,
        'currency', coalesce(bp.currency, tb.currency),
        'is_default', bp.is_default,
        'description', bp.description
      )
      order by bp.sort_order nulls last, bp.name
    ) as pricing_blocks
  from tenant.business_pricing bp
  where bp.business_id = tb.id
    and bp.is_active = true
) pricing on true

where wa.is_active = true
  and tb.is_active = true;

comment on view tenant.v_automation_config is
  'n8n webhook lookup: whatsapp_phone_number_id → tenant + business + default price + knowledge/pricing aggregates (supabase_db_design v2).';

-- ---------------------------------------------------------------------------
-- 2) public proxy — SKIPPED (IndigoNode uses n8n Postgres node, not REST)
-- ---------------------------------------------------------------------------
-- Decision: do NOT create public.v_automation_config. Get tenant configuration
-- queries tenant.v_automation_config directly via Postgres credential (see v1.4 flow).
-- Grants for tenant.v_automation_config are in sql/017_grants_rls_v2.sql.
--
-- create or replace view public.v_automation_config as
-- select * from tenant.v_automation_config;
--
-- grant select on public.v_automation_config to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Grants — applied in sql/017_grants_rls_v2.sql (not here)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Verify (after tables + seed data exist)
-- ---------------------------------------------------------------------------
-- select
--   tenant_id,
--   business_id,
--   tenant_name,
--   category,
--   subcategory,
--   tenant_active,
--   service_fee,
--   service_currency,
--   knowledge_text,
--   pricing_blocks
-- from tenant.v_automation_config
-- where whatsapp_phone_number_id = 'YOUR_PHONE_NUMBER_ID';

-- ---------------------------------------------------------------------------
-- n8n AI prompt hints (Phase 2 — not applied yet)
-- ---------------------------------------------------------------------------
-- RESUMEN PREVIO:     {{ $('Get Message Summary').item.json.summary }}
-- Business context:   {{ $('Get tenant configuration').item.json.knowledge_text }}
-- Default price:      {{ $('Get tenant configuration').item.json.service_fee }} {{ $('Get tenant configuration').item.json.service_currency }}
-- All prices (JSON):  {{ $('Get tenant configuration').item.json.pricing_blocks }}

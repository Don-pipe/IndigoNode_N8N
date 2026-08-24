-- White Node / IndigoNode
-- Run order: 18 (after 013 view + 017 grants)
-- Purpose: Drop legacy messaging schema, business_profiles, and obsolete tenant columns
-- WARNING: irreversible. Take a Supabase backup before running.
--
-- STATUS: APPLIED in production — 2026-08-24 (all sections, no errors)
-- Phase 2 SQL migration complete → proceed to Phase 4 n8n (migration_plan_v2.md)

-- ---------------------------------------------------------------------------
-- 1) Drop legacy messaging schema (contacts, conversations, messages, functions)
-- ---------------------------------------------------------------------------
drop schema if exists messaging cascade;

-- ---------------------------------------------------------------------------
-- 2) Drop business_profiles (replaced by tenant_businesses + business_pricing)
-- ---------------------------------------------------------------------------
drop table if exists tenant.business_profiles cascade;

-- ---------------------------------------------------------------------------
-- 3) Drop legacy tenant columns (replaced by tenant_settings + POC fields)
-- ---------------------------------------------------------------------------
alter table tenant.tenants
  drop column if exists display_name,
  drop column if exists business_type,
  drop column if exists specialty,
  drop column if exists is_active;

-- slug kept — still useful for admin URLs and seed scripts

-- ---------------------------------------------------------------------------
-- 4) Tighten whatsapp_accounts.business_id (all active rows must have business)
-- ---------------------------------------------------------------------------
alter table tenant.whatsapp_accounts
  drop constraint if exists whatsapp_accounts_business_required;

alter table tenant.whatsapp_accounts
  alter column business_id set not null;

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- select column_name from information_schema.columns
-- where table_schema = 'tenant' and table_name = 'tenants';
--
-- select schema_name from information_schema.schemata where schema_name = 'messaging';
-- should return 0 rows

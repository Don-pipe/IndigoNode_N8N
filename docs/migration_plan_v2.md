# Migration Plan — Database v2 (tenant + messaging_channels)

**Project:** IndigoNode WhatsApp Agent  
**Date:** 2026-08-24  
**Design reference:** [task_1.md](./task_1.md)  
**Production workflow:** `flows/IndigoNode_Whatsapp_bot_v1.4_v2.json` (post-migration)

---

## Migration status (live)

**Last updated:** 2026-08-24 — **migration complete**

| Step | File | Status |
|------|------|--------|
| Phase 1 | n8n backup + deactivate | In progress — confirm locally |
| **1** | `sql/014_tenant_v2_migration.sql` | **Done** — steps 0–9, no errors |
| 1b | `sql/014b_fix_tenant_data_migration.sql` | **Skipped** — not needed (014 step 8 succeeded) |
| **2** | `sql/015_messaging_channels_schema.sql` | **Done** — verify: contacts 0, conversations 0 |
| **3** | `sql/016_messaging_channels_functions.sql` | **Done** |
| **4** | `sql/013_prepared_v_automation_config_v2.sql` | **Done** — section 1 only; public proxy skipped |
| **5** | `sql/017_grants_rls_v2.sql` | **Done** — grants + RLS |
| **6** | `sql/018_cleanup_legacy.sql` | **Done** — legacy `messaging` dropped |
| Phase 2 | Supabase SQL | **Complete** |
| Phase 3 | SQL verify gate | **Complete** |
| Phase 4 | n8n cutover | **Done** |
| Phase 5 | Test + activate | **Done** — end-to-end working |

### 014 applied — step checklist

| Step | Section | Status |
|------|---------|--------|
| 0 | Drop old `v_automation_config` view | Done |
| 1 | Extend `tenants` POC columns | Done |
| 2 | `tenant_settings` table | Done |
| 3 | `tenant_businesses` table | Done |
| 4 | `business_pricing` table | Done |
| 5 | `business_knowledge` table | Done |
| 6 | `whatsapp_accounts.business_id` column | Done |
| 7 | `updated_at` triggers | Done |
| 8 | Data migration (`business_profiles` → v2) | Done |
| 9 | `whatsapp_accounts_business_required` constraint | Done |

---

## Goals

1. Restructure **`tenant`** schema (POC fields, businesses, pricing, settings).
2. Replace **`messaging`** with **`messaging_channels`** (multi-channel ready, summary-only memory).
3. Replace **`tenant.v_automation_config`** with v2 view ([`sql/013`](../sql/013_prepared_v_automation_config_v2.sql)).
4. **Reset** test conversations (1 contact / 1 conversation — OK to discard).
5. Update **n8n** Postgres queries and AI prompt (Phase 4 in task_1.md).

---

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Conversation data | **Reset** — do not migrate `messaging.contacts/conversations` |
| `messaging.messages` | **0 rows** — drop with old schema |
| WhatsApp line | `1248499035016959` / `+59176268600` |
| Murillo businesses | **1** `tenant_businesses` row now; model allows many |
| Tenant POC | `Dr` + `Luis Felipe` + `Murillo` |
| Public business name | `Dr. Luis Felipe Murillo` |
| `business_knowledge` | **Empty** at launch |
| `tenants.phone` / `email` | Nullable until filled; phone may equal business line |
| Rate limit | 24h window, cap 30 — **not** tied to `automation_plan` |
| Downtime | OK — deactivate n8n during cutover |
| n8n DB access | **Postgres node** on `tenant.*` / `messaging_channels.*` — no `public.v_automation_config` proxy |

---

## Execution overview

| Phase | When | What |
|-------|------|------|
| **1** | First | Backup + deactivate n8n |
| **2** | Second | Run SQL `014` → `018` in Supabase |
| **3** | After SQL succeeds | Verify DB — **gate before n8n** |
| **4** | After Phase 3 passes | Edit n8n workflow (v1.4) |
| **5** | After Phase 4 | Test, then re-activate |

> **Do not edit n8n until Phase 2 is complete and Phase 3 passes.**

---

## Phase 1 — Before SQL (manual)

- [x] Confirm baseline in repo: [`flows/IndigoNode_Whatsapp_bot_v1.4.json`](../flows/IndigoNode_Whatsapp_bot_v1.4.json)
- [x] **Deactivate** workflow in n8n (`active: false` — already off in v1.4 export)
- [ ] Export / duplicate live workflow in n8n (backup) — confirm if done
- [ ] Optional: Supabase point-in-time backup / snapshot

---

## Phase 2 — Supabase SQL migration

Run **one file at a time** in Supabase SQL Editor. Confirm success before the next.

| Step | File | Status | What it does |
|------|------|--------|----------------|
| 1 | [`sql/014_tenant_v2_migration.sql`](../sql/014_tenant_v2_migration.sql) | **Done** | New tenant tables, POC columns, migrate `business_profiles`, link `whatsapp_accounts.business_id` |
| 2 | [`sql/015_messaging_channels_schema.sql`](../sql/015_messaging_channels_schema.sql) | **Done** | Create `messaging_channels` schema — verify: contacts 0, conversations 0 |
| 3 | [`sql/016_messaging_channels_functions.sql`](../sql/016_messaging_channels_functions.sql) | **Done** | `get_conversation_summary` (24h window) + `update_conversation_summary` |
| 4 | [`sql/013_prepared_v_automation_config_v2.sql`](../sql/013_prepared_v_automation_config_v2.sql) | **Done** | `tenant.v_automation_config` v2 view (no public proxy) |
| 5 | [`sql/017_grants_rls_v2.sql`](../sql/017_grants_rls_v2.sql) | **Done** | Grants + RLS for new tables, view, and functions |
| 6 | [`sql/018_cleanup_legacy.sql`](../sql/018_cleanup_legacy.sql) | **Done** | Drop `messaging` schema, `business_profiles`, legacy `tenants` columns |

**Do not run:** [`sql/006_n8n_queries.sql`](../sql/006_n8n_queries.sql) (reference only).

**Murillo data** is migrated automatically in step 1 — no manual seed inserts needed.

### Data migration map (Murillo)

### `tenant.tenants`

| Old column | New column | Value |
|------------|------------|-------|
| `display_name` | split → | `professional_title` = `Dr`, `name` = `Luis Felipe`, `last_name` = `Murillo` |
| — | `phone` | `+59176268600` or null |
| — | `email` | null (Gmail subscription later) |
| `slug`, `business_type`, `specialty`, `is_active` | *(dropped in step 6)* | Migrated to other tables first |

### New rows

| Table | Source |
|-------|--------|
| `tenant_settings` | `is_active` → `account_status`; `automation_plan` = `basic`; `max_business` = 1 |
| `tenant_businesses` | `business_profiles` + `display_name` + category `medicine` / subcategory `neurology` |
| `business_pricing` | `service_fee` 300 BOB, `is_default` = true |
| `business_knowledge` | *(empty)* |
| `whatsapp_accounts.business_id` | → new business UUID |

### `messaging` → `messaging_channels`

| Action |
|--------|
| **No row migration** — fresh start on first WhatsApp message after cutover |

---

## Phase 3 — Verify SQL success (gate before n8n)

**Stop here if any check fails. Do not open n8n until all pass.**

> **`tenant.v_automation_config` does not exist until step 013.** It was dropped in 014 step 0. Use `tenant.tenants` for tests before 013.

### 3A. After 014 — tenant tables (no view yet)

```sql
select t.professional_title, t.name, t.last_name, tb.name, tb.category, ts.automation_plan
from tenant.tenants t
join tenant.tenant_settings ts on ts.tenant_id = t.id
join tenant.tenant_businesses tb on tb.tenant_id = t.id;

select whatsapp_phone_number_id, business_id
from tenant.whatsapp_accounts;
```

- [x] Tenant v2 query returns expected Murillo row
- [x] `whatsapp_accounts.business_id` is set

### 3B. After 016 — messaging_channels functions (before 013)

```sql
select *
from messaging_channels.get_conversation_summary(
  p_tenant_id := (select id from tenant.tenants where slug = 'dr-luis-murillo'),
  p_channel := 'whatsapp',
  p_external_id := '59177944041',
  p_channel_endpoint_id := '1248499035016959',
  p_display_name := 'Test User'
);
```

Expected: `conversation_id`, `summary`, `message_count = 1`, `message_window_started_at` set.

```sql
select count(*) from messaging_channels.contacts;      -- should be 1 after test above
select count(*) from messaging_channels.conversations;
```

- [ ] Function runs without error
- [ ] Counts become 1 after smoke test

### 3C. After 013 — automation view (n8n lookup)

```sql
select tenant_id, tenant_name, specialty, tenant_active, service_fee, service_currency, knowledge_text
from tenant.v_automation_config
where whatsapp_phone_number_id = '1248499035016959';
```

Expected: one row; `tenant_active = true`; `service_fee = 300`; `tenant_name = Dr. Luis Felipe Murillo`.

- [x] `v_automation_config` lookup by phone_number_id works

### 3D. After 018 — legacy cleanup

- [x] Old `messaging.get_conversation_summary` fails
- [x] `messaging` schema dropped
- [x] `business_profiles` table gone

**Phase 3 complete → proceed to Phase 4 (n8n).**

---

## Phase 4 — n8n cutover (after Phase 3 passes)

**Workflow:** `IndigoNode_Whatsapp_bot_v1.4` in n8n · **Postgres credential:** Supabase session pooler.

Open the workflow in n8n. Work through each node. **Do not re-activate until Phase 5 tests pass.**

### 4.1 Whatsapp fields (Set node) — no change

- [ ] Confirm fields: `phone_number_id`, `wa_id`, `message`, `Name`, `image`, `sticker`, `user_id`, `date`
- [ ] v1.4 already references `Whatsapp fields` correctly (fixed from v1.3)

### 4.2 Messages Type (IF) — no change

- [ ] **TRUE** (no image) → Get tenant configuration
- [ ] **FALSE** → Image Message Handler

### 4.3 Get tenant configuration (Postgres) — no query change

View name is the same; v2 view replaces internals. Keep:

```sql
select *
from tenant.v_automation_config
where whatsapp_phone_number_id = '{{ $json.phone_number_id }}'
limit 1;
```

- [ ] Run node once in n8n (manual test) — returns Murillo row with `tenant_id`, `tenant_active`, `service_fee`

### 4.4 Get Message Summary (Postgres) — **change required**

Replace entire query:

```sql
select
  contact_id,
  conversation_id,
  summary,
  summary_updated_at,
  message_count,
  message_window_started_at
from messaging_channels.get_conversation_summary(
  p_tenant_id := '{{ $('Get tenant configuration').item.json.tenant_id }}'::uuid,
  p_channel := 'whatsapp',
  p_external_id := '{{ $('Whatsapp fields').item.json.wa_id }}',
  p_channel_endpoint_id := '{{ $('Whatsapp fields').item.json.phone_number_id }}',
  p_display_name := '{{ $('Whatsapp fields').item.json.Name }}'
);
```

- [ ] Schema: `messaging.` → `messaging_channels.`
- [ ] Params: `p_wa_id` / `p_phone_number_id` → `p_external_id` / `p_channel_endpoint_id` + `p_channel := 'whatsapp'`
- [ ] Node refs use `Whatsapp fields` (not `Important WPP message fields`)

### 4.5 Active verification (IF) — no change

Runs after Get Message Summary; uses `$json.message_count`.

- [ ] `tenant_id` is not empty
- [ ] `tenant_active` equals `true`
- [ ] `message_count` **lt** `30`
- [ ] TRUE → AI Agent · FALSE → To many messages handler

### 4.6 AI Agent — **change required**

- [ ] **Disconnect and delete Simple Memory** sub-node (Postgres summary replaces LangChain memory)
- [ ] OpenAI Chat Model stays connected
- [ ] Optional — add to prompt after `RESUMEN PREVIO`:

```text
CONTEXTO DEL NEGOCIO:
{{ $('Get tenant configuration').item.json.knowledge_text }}
```

(empty at launch — safe to add now for when FAQ rows exist)

- [ ] Keep JSON output format: `{"reply":"...","summary":"..."}`

### 4.7 Code in JavaScript — no change

- [ ] Parses `$json.output` → `{ reply, summary }`
- [ ] Fallback summary from `$('Get Message Summary')`

### 4.8 Send message (WhatsApp) — no change

- [ ] Text body: `={{ $json.reply }}`

### 4.9 Update Conversation Summary (Postgres) — **change required**

Replace query:

```sql
select messaging_channels.update_conversation_summary(
  '{{ $('Get Message Summary').item.json.conversation_id }}'::uuid,
  '{{ $('Code in JavaScript').item.json.summary }}'
) as summary_updated_at;
```

- [ ] Schema: `messaging.` → `messaging_channels.`

### 4.10 To many messages handler — no change

- [ ] Fixed message only — no AI, no Update Conversation Summary on this branch

### 4.11 Image Message Handler — no change

- [ ] Fixed message for image/sticker path

### 4.12 Wiring confirm

```text
WhatsApp Trigger → If → Whatsapp fields → Messages Type
  TRUE  → Get tenant configuration → Get Message Summary → Active verification
    TRUE  → AI Agent → Code in JavaScript → Send message → Update Conversation Summary
    FALSE → To many messages handler
  FALSE → Image Message Handler
```

- [ ] Simple Memory **not** connected to AI Agent

---

## Phase 5 — Test before re-activate

- [ ] Manual execute: Get tenant configuration → Get Message Summary (no errors)
- [ ] **Text “hola”** → AI reply on WhatsApp; row in `messaging_channels.conversations`; `message_count = 1`
- [ ] **Second message** → bot uses prior `summary`; count increments
- [ ] **Send image** → Image Message Handler only; no AI call
- [ ] Supabase: `summary_updated_at` updates after each AI reply
- [ ] No “Referenced node doesn't exist” in execution log

Then:

- [ ] Save workflow
- [ ] **Activate** workflow in n8n
- [ ] Export post-migration JSON to repo as `flows/IndigoNode_Whatsapp_bot_v1.4_v2.json`

---

## Rollback (if needed)

1. Deactivate n8n.
2. Restore from Supabase **backup / point-in-time recovery** (recommended before step 1).
3. Re-import previous workflow JSON from repo if n8n was changed.
4. Re-activate workflow.

There is no automatic down-migration script — take a backup before step 1.

---

## Timeline estimate

| Phase | Duration |
|-------|----------|
| Phase 1 — backup + deactivate | 5 min |
| Phase 2 — SQL steps 1–6 | 10–15 min |
| Phase 3 — verify SQL gate | 5 min |
| Phase 4 — n8n edits | 15–20 min |
| Phase 5 — test + activate | 10–15 min |

**Total:** ~45–60 minutes

---

## After go-live

- [x] Export workflow as `flows/IndigoNode_Whatsapp_bot_v1.4_v2.json`
- [ ] Update [Supabase.md](./Supabase.md) to v2 design
- [ ] Commit SQL + docs to git
- [ ] Add `business_knowledge` rows when content is ready

---

## Detailed n8n reference

Extended checklist with prompt notes: [task_1.md Phase 4](./task_1.md#phase-4--manual-rollout-checklist-your-hands-on-steps)

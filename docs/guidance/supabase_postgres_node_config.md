# Supabase Postgres Node Config — n8n Setup

**Purpose:** Connect n8n to Supabase Postgres for tenant lookup, conversation memory, and rate limiting.  
**Audience:** IndigoNode ops / onboarding.  
**Prerequisite:** Complete [whatsapp_trigger_config.md](./whatsapp_trigger_config.md) **Step 2** first.  
**Next:** Import and configure the full bot workflow — see [whatsapp_bot.md](../whatsapp_bot.md)  
**Related:** [Supabase.md](../Supabase.md) · [supabase_db_design.md](../resources/supabase_db_design.md)

---

> After Meta and WhatsApp trigger setup, configure the n8n **Postgres** credential and wire the database nodes in the bot workflow.  
> **Follow the steps below in order.**

---

## Pre-requirements

- [ ] [WhatsApp trigger setup](./whatsapp_trigger_config.md) complete through **Step 2.3**
- [ ] Supabase project provisioned with v2 schema (`tenant` + `messaging_channels`)
- [ ] Tenant + `whatsapp_accounts` row exists for the business line (see [meta_business_setup.md — Appendix C](./meta_business_setup.md#appendix-c--supabase-after-meta--n8n))

---

## Step 3 — Supabase Postgres node setup

### 3.1 Supabase | Get connection details

**Go to:** Supabase Dashboard → **Project Settings** → **Database**

- [ ] Open **Connection string** → select **Session pooler** (not Direct connection)
- [ ] Copy:
  - [ ] **Host**
  - [ ] **Port** (session pooler — typically `5432`)
  - [ ] **Database** (`postgres`)
  - [ ] **User** (`postgres.[project-ref]`)
  - [ ] **Password** (database password — reset in same screen if needed)
- [ ] Enable **SSL** (required)

> **Important:** Use the **Postgres node** in n8n — **not** the Supabase REST node. n8n queries `tenant.*` and `messaging_channels.*` schemas directly.

---

### 3.2 n8n | Create Postgres credential

- [ ] Go to **Credentials** → **Add credential** → **Postgres**
- [ ] **Name:** `Postgres account whatsapp bot project` (match workflow export)
- [ ] Paste connection values from **Step 3.1**
- [ ] **SSL:** ON
- [ ] Click **Test connection** → must succeed
- [ ] **Save**

---

### 3.3 n8n | Wire Postgres nodes in the workflow

Import [`IndigoNode_Whatsapp_bot_v1.4.json`](../../flows/IndigoNode_Whatsapp_bot_v1.4.json) or add three **Postgres** nodes manually. Link each to the credential from **Step 3.2**.

| Node name | Purpose |
|-----------|---------|
| **Get tenant configuration** | Resolve `phone_number_id` → tenant + business config |
| **Get Message Summary** | Upsert contact/conversation; return summary + 24h counter |
| **Update Conversation Summary** | Persist AI rolling summary after reply |

#### 3.3.1 Get tenant configuration

```sql
select *
from tenant.v_automation_config
where whatsapp_phone_number_id = '{{ $json.phone_number_id }}'
limit 1;
```

- [ ] **Input:** `phone_number_id` from **Whatsapp fields** node
- [ ] Must return **one row** with `tenant_active = true` for a live tenant

#### 3.3.2 Get Message Summary

```sql
select
  contact_id,
  conversation_id,
  summary,
  summary_updated_at,
  message_count,
  message_window_started_at
from messaging_channels.get_conversation_summary(
  p_tenant_id := '{{ $json.tenant_id }}'::uuid,
  p_channel := 'whatsapp',
  p_external_id := '{{ $('Whatsapp fields').item.json.wa_id }}',
  p_channel_endpoint_id := '{{ $('Whatsapp fields').item.json.phone_number_id }}',
  p_display_name := '{{ $('Whatsapp fields').item.json.Name }}'
);
```

- [ ] **Input:** `tenant_id` from **Get tenant configuration**
- [ ] Node name references (`Whatsapp fields`, `Get tenant configuration`) must match the canvas **exactly**

#### 3.3.3 Update Conversation Summary

Runs **after** **Send message** (AI path only).

```sql
select messaging_channels.update_conversation_summary(
  '{{ $('Get Message Summary').item.json.conversation_id }}'::uuid,
  '{{ $('Code in JavaScript').item.json.summary }}'
) as summary_updated_at;
```

- [ ] Updates `messaging_channels.conversations.summary` — does **not** store the WhatsApp reply body

---

### 3.4 n8n | Verify end-to-end

- [ ] Send a **test WhatsApp text message** to the connected business line
- [ ] Workflow executes without Postgres errors on all three nodes
- [ ] In Supabase SQL Editor:

```sql
select c.summary, c.summary_updated_at, c.message_count, ct.external_id
from messaging_channels.conversations c
join messaging_channels.contacts ct on ct.id = c.contact_id
order by c.summary_updated_at desc nulls last
limit 5;
```

- [ ] Row appears/updates for the sender's `wa_id`
- [ ] **Activate** workflow when verified

---

## Quick reference — step map

| Step | Where | Action |
|------|--------|--------|
| **3.1** | Supabase Dashboard | Session pooler connection string |
| **3.2** | n8n Credentials | Postgres credential + test connection |
| **3.3** | n8n Workflow | Three Postgres nodes + SQL queries |
| **3.4** | n8n + Supabase | Test message + verify conversation row |

---

## What Postgres does in the bot

```text
WhatsApp Trigger
    → Whatsapp fields (phone_number_id, wa_id)
        → Get tenant configuration     ← tenant.v_automation_config
        → Get Message Summary          ← messaging_channels.get_conversation_summary
        → Active verification          ← message_count < 30
        → AI Agent → Send message
        → Update Conversation Summary  ← messaging_channels.update_conversation_summary
```

| Stored in DB | Not stored |
|--------------|------------|
| Rolling `summary` (2–4 sentences) | Inbound/outbound message bodies |
| `message_count` (24h window) | Raw webhook payloads |
| Contact `external_id`, display name | |

Full node reference: [whatsapp_bot.md](../whatsapp_bot.md).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Connection test fails | Wrong pooler host/port or password | Re-copy **Session pooler** string from Supabase; reset DB password if needed |
| SSL error | SSL disabled in n8n | Enable SSL on Postgres credential |
| Get tenant configuration returns 0 rows | Missing/wrong `whatsapp_accounts` row | Match Meta **Phone number ID** to `tenant.whatsapp_accounts.whatsapp_phone_number_id` |
| Permission denied on schema | Grants not applied | Confirm migrations `017_grants_rls_v2.sql` ran in Supabase |
| Function does not exist | v2 migration incomplete | Run SQL `014`–`018`; see [migration_plan_v2.md](../resources/migration_plan_v2.md) |
| Node reference error in SQL | Canvas node renamed | Keep names exactly: `Whatsapp fields`, `Get tenant configuration`, `Get Message Summary`, `Code in JavaScript` |

---

## Bibliography

- [Supabase — Connect to your database](https://supabase.com/docs/guides/database/connecting-to-postgres)
- [Supabase — Connection pooler](https://supabase.com/docs/guides/database/connecting-to-postgres#connection-pooler)
- [n8n Postgres node](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.postgres/)
- [IndigoNode schema reference](../Supabase.md)

---

## Backlog

- [ ] Document Supabase `whatsapp_accounts` INSERT template for new tenants
- [ ] Credential rotation runbook (pooler password change without downtime)

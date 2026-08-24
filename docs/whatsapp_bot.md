# WhatsApp Bot — n8n Workflow

**Workflow file:** [`flows/IndigoNode_Whatsapp_bot_v1.4.json`](../flows/IndigoNode_Whatsapp_bot_v1.4.json)  
**Also exported as:** [`flows/IndigoNode_Whatsapp_bot_v1.4_v2.json`](../flows/IndigoNode_Whatsapp_bot_v1.4_v2.json) (same content)  
**Internal n8n name:** `IndigoNode_Whatsapp_bot_v1.4_v2`  
**Prerequisite:** [whatsapp_trigger_config.md](./guidance/whatsapp_trigger_config.md) — OAuth, webhook, Send Message credentials  
**Database:** Supabase Postgres — see [Supabase.md](./Supabase.md)  
**Timezone:** `America/La_Paz`

---

## What this workflow does

IndigoNode's production WhatsApp assistant for tenant businesses (currently **Dr. Luis Felipe Murillo**). When a patient sends a WhatsApp message to a connected business line:

1. **Identifies** which tenant/business owns the WhatsApp number
2. **Loads or creates** a conversation record with rolling AI memory (Postgres summary)
3. **Checks** tenant is active and the sender has not exceeded 30 messages in 24 hours
4. **Generates** a short, professional reply using OpenAI
5. **Sends** the reply on WhatsApp
6. **Saves** an updated conversation summary back to Postgres

**Non-text messages** (images) get a fixed reply asking the user to describe the content — no AI call.  
**Rate-limited users** (>30 messages in 24h) get a fixed handoff message — no AI call.

**Memory:** Postgres rolling summary only. **No** LangChain Simple Memory. **No** raw message storage in the database.

---

## High-level flow

```text
WhatsApp Trigger
    │
    ▼
If (has messages?)
    │ TRUE
    ▼
Whatsapp fields          ← normalize webhook payload
    │
    ▼
Messages Type            ← text vs image?
    │
    ├─ FALSE (image) ──► Image Message Handler ──► END
    │
    └─ TRUE (text)
           │
           ▼
       Get tenant configuration     ← tenant.v_automation_config
           │
           ▼
       Get Message Summary          ← messaging_channels.get_conversation_summary
           │
           ▼
       Active verification           ← tenant active + message_count < 30
           │
           ├─ FALSE ──► To many messages handler ──► END
           │
           └─ TRUE
                  │
                  ▼
              AI Agent (+ OpenAI Chat Model)
                  │
                  ▼
              Code in JavaScript      ← parse { reply, summary } JSON
                  │
                  ▼
              Send message            ← WhatsApp reply to patient
                  │
                  ▼
              Update Conversation Summary  ← messaging_channels.update_conversation_summary
                  │
                  ▼
                 END
```

---

## Credentials

| Credential | Used by |
|------------|---------|
| WhatsApp OAuth account | WhatsApp Trigger |
| WhatsApp account | Send message, Image Message Handler, To many messages handler |
| Postgres account whatsapp bot project | Get tenant configuration, Get Message Summary, Update Conversation Summary |
| OpenAI account | OpenAI Chat Model |

Postgres connects to Supabase via **session pooler** (not Supabase REST node).

---

## Nodes (detailed)

### 1. WhatsApp Trigger

| Setting | Value |
|---------|-------|
| Type | `n8n-nodes-base.whatsAppTrigger` |
| Updates | `messages` only |

Listens for inbound WhatsApp Cloud API webhooks. Starts the workflow when Meta delivers a message event.

---

### 2. If

| Condition | `$json.messages && $json.messages.length > 0` is **true** |

Filters out empty or non-message webhook payloads. Only continues when at least one message exists.

---

### 3. Whatsapp fields (Set node)

Normalizes webhook data into fields used by downstream nodes.

| Field | Source | Purpose |
|-------|--------|---------|
| `phone_number_id` | `metadata.phone_number_id` | **Business line ID** — tenant lookup key |
| `wa_id` | `contacts[0].wa_id` | **Patient WhatsApp ID** — contact lookup key |
| `message` | `messages[0].text.body` | Inbound text for AI |
| `Timestamp` | `messages[0].timestamp` | Meta timestamp |
| `Name` | `contacts[0].profile.name` | Display name for contact record |
| `user_id` | `contacts[0].wa_id` | Same as `wa_id` (legacy field name) |
| `date` | `$now.toISO()` | Current datetime for AI prompt (year context) |
| `image` | `messages[0].image` | Image object if present — triggers image branch |
| `sticker` | `messages[0].sticker` | Sticker object if present |

> **Important:** `phone_number_id` = tenant's business line. `wa_id` = person messaging the business.

---

### 4. Messages Type (IF)

| Condition | `!$json.image` is **true** |
|-----------|----------------------------|

| Branch | Path |
|--------|------|
| **TRUE** | Text path → Get tenant configuration → AI flow |
| **FALSE** | Image Message Handler (fixed reply, no AI) |

Currently checks **image only** — stickers follow the text path if `image` is empty.

---

### 5. Get tenant configuration (Postgres)

Loads tenant + business config for the WhatsApp line that received the message.

```sql
select *
from tenant.v_automation_config
where whatsapp_phone_number_id = '{{ $json.phone_number_id }}'
limit 1;
```

**Input:** `phone_number_id` from Whatsapp fields  
**Output (key fields used downstream):**

| Field | Used for |
|-------|----------|
| `tenant_id` | Get Message Summary |
| `tenant_name` | AI prompt — public business name |
| `specialty` | AI prompt — subcategory alias |
| `tenant_active` | Active verification |
| `service_fee`, `service_currency` | AI prompt — pricing |
| `address`, `maps_url` | AI prompt — location |
| `business_metadata.office_hours_start/end` | AI prompt — hours |

See [Supabase.md — v_automation_config](./Supabase.md#view-tenantv_automation_config) for full column list.

---

### 6. Get Message Summary (Postgres)

Upserts contact + conversation and returns rolling memory + 24h message counter.

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

**Input:** `tenant_id` from Get tenant configuration  
**Side effects in DB:**

- Creates/updates `messaging_channels.contacts`
- Creates/updates `messaging_channels.conversations`
- Increments `message_count` (resets after 24h window expires)

**Output used downstream:**

| Field | Used for |
|-------|----------|
| `summary` | AI prompt — RESUMEN PREVIO |
| `conversation_id` | Update Conversation Summary |
| `message_count` | Active verification (< 30) |

---

### 7. Active verification (IF)

All three conditions must pass (**AND**):

| # | Condition | Purpose |
|---|-----------|---------|
| 1 | `Get tenant configuration.tenant_id` is not empty | Tenant found for this WhatsApp line |
| 2 | `Get tenant configuration.tenant_active` equals `true` | Account + business + WhatsApp line active |
| 3 | `$json.message_count` **lt** `30` | 24h rate limit — cost/abuse protection |

| Branch | Path |
|--------|------|
| **TRUE** | AI Agent |
| **FALSE** | To many messages handler |

Rate limit is **per conversation**, rolling **24 hours** — not tied to billing plan.

---

### 8. AI Agent

| Setting | Value |
|---------|-------|
| Type | LangChain Agent v3.1 |
| Model | **OpenAI Chat Model** → `gpt-5.6-luna` |
| Memory | **None** — Postgres summary replaces LangChain memory |
| Output | Single `output` string (JSON inside) |

**Prompt structure (Spanish):**

| Section | Source |
|---------|--------|
| Role | `tenant_name`, `specialty` from tenant config |
| RESUMEN PREVIO | `Get Message Summary.summary` |
| MENSAJE ACTUAL | `Whatsapp fields.message` |
| Doctor data | name, specialty, fee, address, hours, maps from tenant config |
| Client data | Name, message from Whatsapp fields |
| Rules | No medical advice, no invented data, short WhatsApp-style replies |
| Booking rules | Collect name + date + time before confirming appointment |
| Required output | JSON: `{"reply":"...", "summary":"..."}` |

**`reply`** = text sent to WhatsApp  
**`summary`** = 2–4 sentence memory saved to Postgres for next message

---

### 9. Code in JavaScript

Parses AI output into structured fields for Send message and Update Conversation Summary.

```javascript
// Reads $json.output from AI Agent
// Strips markdown code fences if present
// Parses JSON { reply, summary }
// Falls back to raw output + previous summary on parse error
// Returns { reply, summary }
```

| Output field | Used by |
|--------------|---------|
| `reply` | Send message → `textBody` |
| `summary` | Update Conversation Summary |

---

### 10. Send message (WhatsApp)

| Field | Expression |
|-------|------------|
| `phoneNumberId` | `$('Whatsapp fields').item.json.phone_number_id` |
| `recipientPhoneNumber` | `$('Whatsapp fields').item.json.wa_id` |
| `textBody` | `$json.reply` (from Code in JavaScript) |

Sends the AI-generated reply to the patient. **Reply text is not stored in the database.**

---

### 11. Update Conversation Summary (Postgres)

Persists the updated rolling summary after a successful AI reply.

```sql
select messaging_channels.update_conversation_summary(
  '{{ $('Get Message Summary').item.json.conversation_id }}'::uuid,
  '{{ $('Code in JavaScript').item.json.summary }}'
) as summary_updated_at;
```

Updates `messaging_channels.conversations.summary` and `summary_updated_at`. Does **not** store the WhatsApp reply body.

---

## Branch handlers (no AI)

### Image Message Handler

**Trigger:** Messages Type → FALSE (message contains image)

**Fixed reply (Spanish):**  
*"Ahora no podemos ver la imagen, por favor podria describir que es lo que contiene para que pueda ayudarlo"*

No Postgres summary update. No AI token usage.

---

### To many messages handler

**Trigger:** Active verification → FALSE (`message_count >= 30` in current 24h window)

**Fixed reply (Spanish):**  
*"Muchas Gracias por comunicarse con nosotros en seguida atenderemos su solicitud"*

No AI Agent. No Update Conversation Summary. Prevents unnecessary token spend on heavy senders.

---

## Database touchpoints per text message

| Step | Schema | Object | Read / Write |
|------|--------|--------|--------------|
| Get tenant configuration | `tenant` | `v_automation_config` | Read |
| Get Message Summary | `messaging_channels` | `get_conversation_summary()` | Write contacts + conversations, Read summary |
| Update Conversation Summary | `messaging_channels` | `update_conversation_summary()` | Write summary |

**Not stored:** inbound message body, outbound reply text, raw webhook payloads.

---

## WhatsApp ID reference

| ID | Where | Example role |
|----|-------|----------------|
| `phone_number_id` | `metadata.phone_number_id` | Identifies **which business line** received the message → tenant lookup |
| `wa_id` | `contacts[0].wa_id` | Identifies **who sent** the message → contact record |

Same patient (`wa_id`) talking to the same business line always maps to one `messaging_channels.conversations` row.

---

## Production tenant (Murillo)

| Item | Value |
|------|-------|
| `whatsapp_phone_number_id` | `1248499035016959` |
| Business number | `+59176268600` |
| Public name (`tenant_name`) | `Dr. Luis Felipe Murillo` |
| Specialty | `neurology` |
| Default consult fee | 300 BOB |

---

## What is intentionally not in this workflow

| Feature | Status |
|---------|--------|
| LangChain Simple Memory | Removed — Postgres summary used |
| Image understanding / vision AI | Not implemented — fixed text reply |
| Sticker-specific branch | Not implemented — may hit text path |
| Appointment booking / calendar | Prompt collects info only — no calendar integration |
| Outbound message logging | Reply not stored in DB |
| `knowledge_text` in AI prompt | Available in view — not wired yet (empty at launch) |

---

## Related documentation

| Document | Contents |
|----------|----------|
| [Supabase.md](./Supabase.md) | Full schema, tables, functions |
| [resources/supabase_db_design.md](./resources/supabase_db_design.md) | Design rationale and n8n Phase 4 checklist |
| [resources/migration_plan_v2.md](./resources/migration_plan_v2.md) | v2 migration runbook (complete) |
| [`sql/006_n8n_queries.sql`](../sql/006_n8n_queries.sql) | SQL query reference |

---

## Import / activate

1. Import [`flows/IndigoNode_Whatsapp_bot_v1.4.json`](../flows/IndigoNode_Whatsapp_bot_v1.4.json) into n8n
2. Re-link credentials (WhatsApp OAuth, WhatsApp account, Postgres, OpenAI)
3. Confirm Postgres credential uses Supabase session pooler
4. Test with a text message → verify row in `messaging_channels.conversations`
5. Activate workflow

# WhatsApp Bot — n8n Workflow

**Workflow file:** [`flows/IndigoNode_Whatsapp_bot_v1.5.json`](../flows/IndigoNode_Whatsapp_bot_v1.5.json)  
**Previous:** [`flows/older version/IndigoNode_Whatsapp_bot_v1.4_v2.json`](../flows/older%20version/IndigoNode_Whatsapp_bot_v1.4_v2.json) (single-location only)  
**Internal n8n name:** `IndigoNode_Whatsapp_bot_v1.5`  
**Prerequisite:** [whatsapp_trigger_config.md](./guidance/whatsapp_trigger_config.md) → [supabase_postgres_node_config.md](./guidance/supabase_postgres_node_config.md)  
**Database:** Supabase Postgres — see [Supabase.md](./Supabase.md)  
**Timezone:** `America/La_Paz`

---

## What this workflow does

IndigoNode's production WhatsApp assistant for tenant businesses (currently **Dr. Luis Felipe Murillo**). When a patient sends a WhatsApp message to a connected business line:

1. **Identifies** which tenant owns the WhatsApp number
2. **Routes** the patient to a location when the tenant has multiple businesses (numbered menu)
3. **Loads or creates** a conversation record with rolling AI memory (Postgres summary)
4. **Checks** tenant is active and the sender has not exceeded 30 messages in 24 hours
5. **Generates** a short, professional reply using OpenAI (for the **selected** location)
6. **Sends** the reply on WhatsApp
7. **Saves** an updated conversation summary back to Postgres

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
       Process routing              ← messaging_channels.process_inbound_routing
           │
           ▼
       Needs location menu?
           │
           ├─ TRUE ──► Location menu ──► Send location menu ──► END
           │
           └─ FALSE (location already chosen)
                  │
                  ▼
              Get tenant configuration     ← tenant.v_automation_config_all + selected_business_id
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
| WhatsApp account | Send message, Send location menu, Image Message Handler, To many messages handler |
| Postgres account whatsapp bot project | Process routing, Get tenant configuration, Update Conversation Summary |
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
| **TRUE** | Text path → Process routing → location menu or AI flow |
| **FALSE** | Image Message Handler (fixed reply, no AI) |

Currently checks **image only** — stickers follow the text path if `image` is empty.

---

### 5. Process routing (Postgres)

Resolves tenant, location choice, and conversation memory in one call. Entry point for multi-location routing (SQL `020`).

```sql
select *
from messaging_channels.process_inbound_routing(
  p_channel := 'whatsapp',
  p_channel_endpoint_id := '{{ $('Whatsapp fields').item.json.phone_number_id }}',
  p_external_id := '{{ $('Whatsapp fields').item.json.wa_id }}',
  p_display_name := '{{ $('Whatsapp fields').item.json.Name }}',
  p_message := '{{ $('Whatsapp fields').item.json.message }}'
);
```

**Output (key fields):**

| Field | Used for |
|-------|----------|
| `tenant_id`, `tenant_active` | Active verification |
| `welcome_brand_name` | Location menu greeting |
| `needs_location_menu` | Branch — show menu vs continue to AI |
| `business_menu` | JSON array of locations (index, name, address, …) |
| `selected_business_id` | Get tenant configuration filter |
| `summary`, `conversation_id`, `message_count` | AI path (when location already chosen) |

**Behavior:**

- **One business** on the line → auto-selects; no menu.
- **Multiple businesses** → first message shows brand welcome + numbered list; patient replies `1`, `2`, or a keyword.
- Choice persists in `messaging_channels.routing_sessions`.

---

### 6. Needs location menu? (IF)

| Condition | `$json.needs_location_menu` equals **true** |

| Branch | Path |
|--------|------|
| **TRUE** | Location menu → Send location menu → END (no AI) |
| **FALSE** | Get tenant configuration → AI flow |

---

### 7. Location menu (Code)

Builds the Spanish welcome message from `welcome_brand_name` and `business_menu`:

```text
¡Hola! Bienvenido a {brand}. ¿En qué sede desea ser atendido?

1. {location name} — {address}
2. …

Responda con el número de la sede.
```

**Send location menu** sends `$json.reply` on WhatsApp.

---

### 8. Get tenant configuration (Postgres)

Loads config for the **selected** business on this WhatsApp line.

```sql
select *
from tenant.v_automation_config_all
where whatsapp_phone_number_id = '{{ $('Whatsapp fields').item.json.phone_number_id }}'
  and business_id = '{{ $('Process routing').item.json.selected_business_id }}'::uuid
limit 1;
```

**Output (key fields used downstream):**

| Field | Used for |
|-------|----------|
| `tenant_name` | AI prompt — public business name (location-specific) |
| `specialty` | AI prompt — subcategory alias |
| `service_fee`, `service_currency` | AI prompt — pricing |
| `address`, `maps_url` | AI prompt — location |
| `business_metadata.office_hours_start/end` | AI prompt — hours |

See [Supabase.md — v_automation_config_all](./Supabase.md) for full column list.

---

### 9. Active verification (IF)

All three conditions must pass (**AND**):

| # | Condition | Purpose |
|---|-----------|---------|
| 1 | `Process routing.tenant_id` is not empty | Tenant found for this WhatsApp line |
| 2 | `Process routing.tenant_active` equals `true` | Account + business + WhatsApp line active |
| 3 | `Process routing.message_count` **lt** `30` | 24h rate limit — cost/abuse protection |

| Branch | Path |
|--------|------|
| **TRUE** | AI Agent |
| **FALSE** | To many messages handler |

Rate limit is **per conversation** (or routing session before a location is chosen), rolling **24 hours**.

---

### 10. AI Agent

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
| RESUMEN PREVIO | `Process routing.summary` |
| MENSAJE ACTUAL | `Whatsapp fields.message` |
| Doctor data | name, specialty, fee, address, hours, maps from tenant config |
| Client data | Name, message from Whatsapp fields |
| Rules | No medical advice, no invented data, short WhatsApp-style replies |
| Booking rules | Collect name + date + time before confirming appointment |
| Required output | JSON: `{"reply":"...", "summary":"..."}` |

**`reply`** = text sent to WhatsApp  
**`summary`** = 2–4 sentence memory saved to Postgres for next message

---

### 11. Code in JavaScript

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

### 12. Send message (WhatsApp)

| Field | Expression |
|-------|------------|
| `phoneNumberId` | `$('Whatsapp fields').item.json.phone_number_id` |
| `recipientPhoneNumber` | `$('Whatsapp fields').item.json.wa_id` |
| `textBody` | `$json.reply` (from Code in JavaScript) |

Sends the AI-generated reply to the patient. **Reply text is not stored in the database.**

---

### 13. Update Conversation Summary (Postgres)

Persists the updated rolling summary after a successful AI reply.

```sql
select messaging_channels.update_conversation_summary(
  '{{ $('Process routing').item.json.conversation_id }}'::uuid,
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
| Process routing | `messaging_channels` | `process_inbound_routing()` | Routing session + contacts/conversations when location chosen |
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
| Brand (`welcome_brand_name`) | Dr. Luis Felipe Murillo |
| Locations | 1 — Papa León XIII (300 BOB, 09:00–12:00) · 2 — Sopocachi (250 BOB, 14:00–20:00) |

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

1. Import [`flows/IndigoNode_Whatsapp_bot_v1.5.json`](../flows/IndigoNode_Whatsapp_bot_v1.5.json) into n8n
2. Deactivate v1.4 if still active
3. Re-link credentials (WhatsApp OAuth, WhatsApp account, Postgres, OpenAI)
4. Confirm Postgres credential uses Supabase session pooler
5. Test: send **Hola** → location menu; reply **1** or **2** → AI uses that office's price/hours
6. Activate workflow

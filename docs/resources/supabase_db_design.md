# IndigoNode Database Design

**Canonical reference:** [Supabase.md](../Supabase.md) — production schema field reference  
**Companion:** [migration_plan_v2.md](./migration_plan_v2.md) · [meta_business_setup.md](../guidance/meta_business_setup.md) · [whatsapp_trigger_config.md](../guidance/whatsapp_trigger_config.md) · [supabase_postgres_node_config.md](../guidance/supabase_postgres_node_config.md)

Date: 24/08/2026

Good morning lets get top work, i've had time to think about the data base and i want to discuss the changes i want to make

At this point in time we will focus on modifying two schemas: **tenant** and **messaging_channels**.

**Decision:** Channel runtime schema is `**messaging_channels`** — not `whatsapp`, not plain `messaging`.  
WhatsApp is the **first channel**; same schema will support Instagram, Facebook, SMS, Email, etc.

**Decision:** Schema name stays `**tenant`** — not renaming to `core`.

**Decision:** All `**id`** and `***_id`** link columns use `**uuid**` (never text). Foreign keys reference parent table `id` columns.

# Tenant schema

This schema should contain all information regarding the client and should be reusable for all types of profesionlas so the idea i came up with is the followin 

Tables 

## 1.1 Tenants

Account holder — the IndigoNode client (person or org). **Main point of contact** for billing and platform access. **No profession/category here** — that lives on each business.

- id — uuid PK
- name — text — first name(s)
- last_name — text
- professional_title — text — short prefix, e.g. `Dr`, `Lic`, `Eng` (nullable if none)
- phone — text — **tenant direct / personal line** (POC; may match business line in solo practices)
- email — text — **login / subscription email** (future: Gmail OAuth sign-up for IndigoNode)
- created_at — timestamptz
- updated_at — timestamptz

**Decision — tenant phone vs business phones:**


| Field                                        | Role                                           | Can match?                                |
| -------------------------------------------- | ---------------------------------------------- | ----------------------------------------- |
| `tenants.phone`                              | Direct line for the **person in charge** (POC) | Sometimes same as business                |
| `tenant_businesses.phone_1/2/3`              | **Business** lines patients call               | Often the **automated WhatsApp** line too |
| `whatsapp_accounts.whatsapp_business_number` | Meta WhatsApp Business number                  | Usually = primary business line           |


Same pattern as names: **separate fields**, but **allowed to be the same value** when the doctor runs everything from one number.

**Decision — `tenants.email`:** Email used to **register and subscribe** on IndigoNode (planned: **Gmail** sign-in). Not the public clinic email unless they choose to use the same address.

**Decision — structured POC (not one blob field):**


| Field                | Example (Murillo) |
| -------------------- | ----------------- |
| `professional_title` | `Dr`              |
| `name`               | `Luis Felipe`     |
| `last_name`          | `Murillo`         |


Display/formal contact name (if needed): `Dr Luis Felipe Murillo` — built from parts in views or n8n, not stored as a duplicate column.

**Decision — `tenants` vs `tenant_businesses.name`:** POC fields live on `**tenants`**. Public / bot name lives on `**tenant_businesses.name`** — may match the formatted doctor name or a custom brand (e.g. `Neuro Consultorio Murillo`).


| Example              | Tenant POC                 | `tenant_businesses.name` (public / bot) |
| -------------------- | -------------------------- | --------------------------------------- |
| Doctor uses own name | Dr + Luis Felipe + Murillo | Dr. Luis Felipe Murillo                 |
| Custom clinic brand  | Dr + Luis Felipe + Murillo | Neuro Consultorio Murillo               |


The WhatsApp bot and AI use `**tenant_businesses.name**`, not the raw tenant name fields.

## 1.2 tenant_settings

Platform / billing settings for the IndigoNode client. **Not** the same as per-conversation message rate limits.

- id — uuid PK
- tenant_id — uuid FK → tenants.id
- account_status — bool
- automation_plan — text (`basic`, `enterprise`, `custom`) — **pricing tier for cart / subscription**
- max_business — integer (how many businesses allowed on this plan)
- created_at — timestamptz
- updated_at — timestamptz

**Decision — `automation_plan`:** Commercial tier the client chooses at checkout (different prices, features later). Examples: `basic`, `enterprise`, `custom`. Used for billing and feature gates — **not** for the 24h message cap on end-users.

## 1.3 tenant_businesses

- id — uuid PK
- tenant_id — uuid FK → tenants.id
- name — text — **public business name** (what patients see; bot says “asistente de …”)
- category — text (macro vertical — broad industry)
- subcategory — text (macro specialty — niche within category)
- address — text
- maps_url — text
- currency — text (default currency for this business, eg. BOB)
- timezone — text (eg. America/La_Paz)
- phone_1 — text
- phone_2 — text
- phone_3 — text
- hours_start — time
- hours_end — time
- is_active — bool
- created_at — timestamptz
- updated_at — timestamptz

**Decision:** `maps_url`, `currency`, and `timezone` live here — structured fields the bot needs on every reply, not in `business_knowledge`.

**Decision:** `**category` + `subcategory`** replace `tenants.profession`. Macro data at the **business** level (a tenant can run different business types).


| category        | subcategory       | Example business name   |
| --------------- | ----------------- | ----------------------- |
| medicine        | neurology         | Dr. Luis Felipe Murillo |
| restaurant      | french cuisine    | Bistro Paris            |
| beauty wellness | hair & nail salon | Studio Nails            |


Use for: AI tone, prompt templates, future vertical modules, reporting — not for storing clinical/restaurant-specific data (that stays in `business_knowledge` / `business_pricing`).

**Later (not Phase 1):** Controlled vocabulary + indexes — lookup tables (eg. `tenant.categories`, `tenant.subcategories`) and index on `tenant_businesses (category, subcategory)` when the catalog grows. Free text on businesses is fine until then.

## 1.4 business_pricing

One business can have **one default price** or **several** (consultation, follow-up, procedure, etc.).  
Use a dedicated table so pricing stays queryable and `business_knowledge` does not bloat.

- id — uuid PK
- tenant_id — uuid FK → tenants.id
- business_id — uuid FK → tenant_businesses.id
- name — text (eg. Consulta neurológica, Control, EEG)
- amount — numeric(10, 2)
- currency — text (defaults to business currency if null)
- is_default — bool (one default price per business for simple “how much?” questions)
- description — text (optional short note for AI)
- is_active — bool
- sort_order — integer
- created_at — timestamptz
- updated_at — timestamptz

**Examples:**


| business    | name                  | amount | currency | is_default |
| ----------- | --------------------- | ------ | -------- | ---------- |
| Dr. Murillo | Consulta neurológica  | 300    | BOB      | true       |
| Dr. Murillo | Control / seguimiento | 200    | BOB      | false      |
| Dr. Murillo | Electroencefalograma  | 450    | BOB      | false      |


**n8n / AI:** Load all active rows for the business, or filter `is_default = true` for a short answer.

## 1.5 business_knowledge

**Purpose:** Long-form text the AI reads — FAQs, policies, about.  
**Not for:** prices, maps, hours, currency (those are structured columns/tables above).

- id — uuid PK
- tenant_id — uuid FK → tenants.id
- business_id — uuid FK → tenant_businesses.id
- type — text (`faq`, `policy`, `about` — see allowed types below)
- title — text
- content — text
- metadata — jsonb (optional extras)
- is_active — bool
- sort_order — integer
- created_at — timestamptz
- updated_at — timestamptz

**Allowed `type` values (keep the list small):**


| type     | Use for                                |
| -------- | -------------------------------------- |
| `faq`    | Common questions and answers           |
| `policy` | Cancellation, emergencies, rules       |
| `about`  | Bio, approach, who the professional is |


**Do NOT store here:** `pricing`, `location`, `hours` — avoids bloat and duplicate data.

business_knowledge (example)


| business_id | type   | title           | content                     |
| ----------- | ------ | --------------- | --------------------------- |
| uuid...     | faq    | Cancelación     | Puede cancelar con 24h...   |
| uuid...     | policy | Emergencias     | En urgencia acuda a...      |
| uuid...     | about  | Sobre el doctor | Dr. Murillo es neurólogo... |


---

## Data placement — avoid bloating `business_knowledge`


| Data                | Where                               | Why                            |
| ------------------- | ----------------------------------- | ------------------------------ |
| maps_url            | `tenant_businesses.maps_url`        | Single link, always needed     |
| currency (default)  | `tenant_businesses.currency`        | One default per business       |
| timezone            | `tenant_businesses.timezone`        | Scheduling / prompts           |
| hours               | `tenant_businesses.hours_start/end` | Structured, one row            |
| Prices (1 or many)  | `business_pricing` rows             | Structured amounts, filterable |
| FAQs, policies, bio | `business_knowledge`                | Narrative text for AI only     |


**Rule:** If it has a **fixed shape** (number, URL, time) → column or `business_pricing`.  
If it is **free text** for the AI → `business_knowledge`.

---

## 1.6 whatsapp_accounts *(todo — design next)*

Maps Meta `phone_number_id` → tenant + business for n8n webhook lookup.

- id — uuid PK
- tenant_id — uuid FK → tenants.id
- business_id — uuid FK → tenant_businesses.id
- whatsapp_phone_number_id — text UNIQUE
- whatsapp_business_number — text
- is_primary — bool
- is_active — bool
- created_at — timestamptz
- updated_at — timestamptz

---

# messaging_channels schema

**Purpose:** Runtime data for **all messaging channels** (WhatsApp today; IG, FB, SMS, Email later). Links back to **tenant** — especially `tenant_businesses` and `whatsapp_accounts` (WhatsApp channel config for now).

**Privacy / cost rule:** We do **NOT** store every message. We only store:

- who is messaging (contact)
- one conversation row per contact + business line
- a **rolling AI summary** (memory)
- a **message counter** (usage limits)

No `messages` table in this design.

**Channel values (examples):** `whatsapp`, `instagram`, `facebook`, `sms`, `email`

---

## Design principles


| Do store                            | Do NOT store                    |
| ----------------------------------- | ------------------------------- |
| Contact `external_id`, display name | Full chat history               |
| Rolling `summary` (2–4 sentences)   | Inbound/outbound message bodies |
| `message_count` per conversation    | Raw webhook payloads            |
| Last activity timestamps            |                                 |


---

## Tables

### 2.1 contacts

People who message a tenant business (patients, customers, leads).


| Column        | Type                           | Notes                                                  |
| ------------- | ------------------------------ | ------------------------------------------------------ |
| id            | uuid PK                        |                                                        |
| tenant_id     | uuid FK → tenants.id           | Isolation                                              |
| business_id   | uuid FK → tenant_businesses.id | Which business they talk to                            |
| channel       | text                           | `whatsapp`, `instagram`, `facebook`, `sms`, `email`, … |
| external_id   | text                           | Channel user ID (WhatsApp `wa_id` today)               |
| display_name  | text                           | Profile name from channel                              |
| first_seen_at | timestamptz                    |                                                        |
| last_seen_at  | timestamptz                    | Updated each inbound message                           |
| is_active     | bool                           | default true                                           |
| created_at    | timestamptz                    |                                                        |
| updated_at    | timestamptz                    |                                                        |


**Unique:** `(tenant_id, business_id, channel, external_id)`

**WhatsApp v1.3 today:** `channel = 'whatsapp'`, `external_id` = webhook `wa_id`.

---

### 2.2 conversations

One row = one chat thread between a **contact** and a **channel endpoint** (business WhatsApp line, IG page, etc.).  
This is where **summary memory** lives.


| Column                    | Type                           | Notes                                                  |
| ------------------------- | ------------------------------ | ------------------------------------------------------ |
| id                        | uuid PK                        | Used by n8n to update summary                          |
| tenant_id                 | uuid FK → tenants.id           |                                                        |
| business_id               | uuid FK → tenant_businesses.id |                                                        |
| contact_id                | uuid FK → contacts.id          |                                                        |
| channel                   | text                           | Same as contact — `whatsapp` for current bot           |
| channel_endpoint_id       | text                           | Channel routing ID (WhatsApp `phone_number_id` today)  |
| status                    | text                           | `open`, `closed`, `archived` — default `open`          |
| summary                   | text                           | Rolling AI summary — **only memory we keep**           |
| summary_updated_at        | timestamptz                    | Last time AI updated summary                           |
| message_count             | integer                        | Inbound messages in **current 24h window** — default 0 |
| message_window_started_at | timestamptz                    | Start of 24h window; counter resets when expired       |
| last_message_at           | timestamptz                    |                                                        |
| created_at                | timestamptz                    |                                                        |
| updated_at                | timestamptz                    |                                                        |


**Unique:** `(tenant_id, contact_id, channel, channel_endpoint_id)`

**WhatsApp v1.3 today:** `channel = 'whatsapp'`, `channel_endpoint_id` = `whatsapp_phone_number_id`.

**Decision — rate limit (end-user abuse / cost protection):**

- **Not** tied to `automation_plan`.
- Count inbound messages per **conversation** in a **rolling 24-hour window**.
- If `message_count` > **30** (configurable constant in n8n or DB later) → exit AI flow → human handoff message (your **To many messages handler** node).
- On each inbound message, `get_conversation_summary` logic:
  1. If `now - message_window_started_at` ≥ 24 hours → reset `message_count = 1`, set `message_window_started_at = now()`
  2. Else → increment `message_count`
  3. Return `message_count` so n8n IF can branch before AI Agent

**Example row:**


| contact     | summary                                              | message_count |
| ----------- | ---------------------------------------------------- | ------------- |
| Luis Felipe | "Solicitó cita 22/08 10:15. Pendiente confirmación." | 5             |


---

## Functions (n8n uses these)

### 2.3 get_conversation_summary

Called on **every inbound message** (Get Message Summary node).

**Input:** `tenant_id`, `channel`, `external_id`, `channel_endpoint_id`, `display_name`

**WhatsApp v1.3 params (unchanged in n8n until Phase 2):** `p_wa_id`, `p_phone_number_id` map to `external_id` + `channel_endpoint_id` with `channel = 'whatsapp'`.

**Does:**

1. Upsert `contacts`
2. Upsert `conversations` — increments `message_count` by 1
3. Returns current `summary`, `conversation_id`, `message_count`

**Output for AI prompt:** `summary` → RESUMEN PREVIO

---

### 2.4 update_conversation_summary

Called **after AI replies** (Update Conversation Summary node).

**Input:** `conversation_id`, new `summary` (from Code in JavaScript)

**Does:** Saves updated summary + `summary_updated_at`

**Does NOT:** Store the WhatsApp reply text as a message row

---

## How messaging_channels links to tenant

```text
Channel webhook (WhatsApp today)
      │
      ▼
whatsapp_accounts (tenant schema)     ← WhatsApp channel config; phone_number_id
      │
      ├── tenant_id
      └── business_id
      │
      ▼
get_conversation_summary (messaging_channels)
      │
      ├── contacts        ← channel + external_id
      └── conversations   ← summary + message_count
      │
      ▼
AI Agent reads:
  • business_knowledge (tenant)  ← FAQs, pricing, policies
  • conversations.summary        ← conversation memory
      │
      ▼
update_conversation_summary      ← save new summary only
```

**Later:** Add `instagram_accounts`, `sms_accounts`, etc. under tenant (or `channel_accounts` table) — same pattern, different channel.

---

## n8n flow (unchanged logic)

```text
Whatsapp fields
  → Get tenant config (+ business + knowledge)
  → Get Message Summary          ← messaging_channels.get_conversation_summary
  → AI Agent                     ← prompt uses summary + business_knowledge
  → Code in JavaScript           ← split reply + summary
  → Send message                 ← reply to WhatsApp (not stored in DB)
  → Update Conversation Summary  ← messaging_channels.update_conversation_summary
```

---

## What we are removing / not adding

- ~~messaging_channels.messages~~ — no per-message storage
- ~~Simple Memory (n8n)~~ — replaced by `conversations.summary`
- ~~LangChain memory~~ — replaced by Postgres

---

# TODOs — align before writing code

**Status:** Phase 1 tenant design **complete** (prepared SQL ready). No migrations run yet.

**Prepared view:** `sql/013_prepared_v_automation_config_v2.sql` — run after v2 tables are created in Phase 3.

---

## Phase 1 — Review & decide (this document)

### Tenant — open questions

- [x] Schema name: `**tenant**` (confirmed — no rename to `core`)
- [x] All ids and link columns: `**uuid**` with FKs (not text)
- [x] Add **1.6 whatsapp_accounts** table (phone_number_id routing for n8n webhook) — draft in doc
- [x] `**tenants.profession` removed** — use `tenant_businesses.category` + `subcategory` instead
- [x] **pricing, maps_url, timezone, currency** — decided (see Data placement table)
- [x] `**business_knowledge.type**` — `faq`, `policy`, `about` only (no pricing/location rows)
- [x] Add `tenant_id` FK on `tenant_businesses` and `business_knowledge` (uuid — in table design above)
- [x] Design new view: `**v_automation_config**` — see `sql/013_prepared_v_automation_config_v2.sql`

### messaging_channels — open questions

- [x] Schema name: `**messaging_channels**` (not `whatsapp`, not plain `messaging`)
- [x] `**business_id**` on `contacts` and `conversations`
- [x] **No messages table** — summary-only memory
- [x] **Channel-agnostic columns:** `channel`, `external_id`, `channel_endpoint_id`
- [x] **Rate limit:** 24h rolling window on `conversations.message_count` — cap ~30 → human handoff; **not** tied to `automation_plan`
- [x] `**automation_plan`:** `basic` / `enterprise` / `custom` — subscription tier for cart/pricing (separate concern)
- [x] Map current production (`messaging.*`) → new schema — see **Migration map** below
- [x] Prepared SQL for `get_conversation_summary` / `update_conversation_summary` under `messaging_channels` — see `sql/016_messaging_channels_functions.sql`

---

## Migration map — production → v2

### Tenant schema (old → new)


| Production today                                                           | New v2                                                               | Migration action                                                                        |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `tenant.tenants` (slug, display_name, business_type, specialty, is_active) | `tenant.tenants` (name, last_name, professional_title, phone, email) | Split POC; drop slug/specialty from tenant row                                          |
| *(none)*                                                                   | `tenant.tenant_settings`                                             | **Create** from `tenants.is_active` → `account_status`; set `automation_plan = 'basic'` |
| `tenant.business_profiles` (1 row/tenant)                                  | `tenant.tenant_businesses`                                           | **Move** address, maps_url, timezone, currency, hours from metadata                     |
| `business_profiles.service_fee`                                            | `tenant.business_pricing`                                            | **Move** to pricing row with `is_default = true`                                        |
| `business_profiles.metadata` (office hours)                                | `tenant_businesses.hours_start/end`                                  | **Parse** JSON → time columns                                                           |
| *(none)*                                                                   | `tenant.business_knowledge`                                          | **Create** manually or leave empty at first                                             |
| `tenant.whatsapp_accounts` (tenant_id only)                                | `tenant.whatsapp_accounts` (+ `business_id`)                         | **Add** FK to the new business row                                                      |
| `tenant.v_automation_config`                                               | `tenant.v_automation_config` (v2)                                    | **Replace** with `sql/013_prepared_v_automation_config_v2.sql`                          |


### messaging → messaging_channels


| Production today                          | New v2                                                       | Migration action                                         |
| ----------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------- |
| schema `messaging`                        | schema `messaging_channels`                                  | Rename / create new + migrate data                       |
| `contacts.wa_id`                          | `contacts.external_id` + `channel = 'whatsapp'`              | Copy `wa_id` → `external_id`                             |
| *(none)*                                  | `contacts.business_id`                                       | Set from `whatsapp_accounts.business_id` for that tenant |
| `contacts` unique `(tenant_id, wa_id)`    | unique `(tenant_id, business_id, channel, external_id)`      | Widen unique key                                         |
| `conversations.whatsapp_phone_number_id`  | `conversations.channel_endpoint_id` + `channel = 'whatsapp'` | Copy column value                                        |
| *(none)*                                  | `conversations.business_id`                                  | Same as contact business                                 |
| `conversations.summary`                   | same                                                         | **Copy as-is**                                           |
| `conversations.summary_updated_at`        | same                                                         | **Copy as-is**                                           |
| `conversations.message_count`             | same                                                         | **Copy as-is**                                           |
| *(none)*                                  | `conversations.message_window_started_at`                    | Set to `coalesce(last_message_at, now())` on migrate     |
| `messaging.messages`                      | *(removed)*                                                  | **Do not migrate** — drop if any rows exist              |
| `messaging.get_conversation_summary()`    | `messaging_channels.get_conversation_summary()`              | **Rewrite** (+ 24h window logic)                         |
| `messaging.update_conversation_summary()` | `messaging_channels.update_conversation_summary()`           | **Rewrite** (schema prefix only)                         |


### What you can run now (paste results to help migration SQL)

```sql
-- Row counts
select 'contacts' as tbl, count(*) from messaging.contacts
union all
select 'conversations', count(*) from messaging.conversations
union all
select 'messages', count(*) from messaging.messages;

-- Current tenant + config
select * from tenant.v_automation_config;

-- Conversation state to preserve
select c.id, c.summary, c.message_count, c.summary_updated_at, ct.wa_id, ct.display_name
from messaging.conversations c
join messaging.contacts ct on ct.id = c.contact_id;

-- WhatsApp line in production
select tenant_id, whatsapp_phone_number_id, whatsapp_business_number, is_active
from tenant.whatsapp_accounts;
```

### Questions we need answered before writing `014+`

1. **Preserve conversation data?** ~~Keep existing~~ → **Reset OK** (only 1 test conversation)
2. **Any rows in `messaging.messages`?** **0** — confirmed
3. **Real `whatsapp_phone_number_id`** → `**1248499035016959**` — assume same as Meta unless they change
4. **Dr. Murillo = 1 tenant, 1 business (for now)?** **Yes for this example** — model supports **multiple** `tenant_businesses` later
5. `**tenants**` → `**name` + `last_name` + `professional_title**` (POC) · `**tenant_businesses.name**` → public / bot name
6. `**business_knowledge` at launch?** **Skip for now** — add later, keep clean
7. **Cutover downtime?** **OK** — only a test user on the line

**How you can help:** ~~Run diagnostic queries~~ **Done** — see production snapshot below.

### Production snapshot (2026-08-24)

**Row counts**


| Table                     | Count |
| ------------------------- | ----- |
| `messaging.contacts`      | 1     |
| `messaging.conversations` | 1     |
| `messaging.messages`      | 0     |


`**tenant.v_automation_config` (current)**


| Field                   | Value                                       |
| ----------------------- | ------------------------------------------- |
| tenant_id               | `79bf89b7-7726-4032-9591-de87b533a592`      |
| slug                    | `dr-luis-murillo`                           |
| tenant_name             | Dr. Luis Felipe Murillo                     |
| business_type           | doctor                                      |
| specialty               | Neurología                                  |
| tenant_active           | true                                        |
| service_fee             | 300.00 BOB                                  |
| address                 | Calle Papa León XIII                        |
| timezone                | America/La_Paz                              |
| maps_url                | `https://maps.app.goo.gl/LqGRvjm85YP29LGr9` |
| office hours (metadata) | 09:00 – 12:00                               |


`**tenant.whatsapp_accounts**`


| whatsapp_phone_number_id | whatsapp_business_number | is_active |
| ------------------------ | ------------------------ | --------- |
| `1248499035016959`       | +59176268600             | true      |


**Test conversation (will reset on migrate — reference only)**


| Field           | Value                                  |
| --------------- | -------------------------------------- |
| conversation_id | `af3ede29-2046-483c-bc74-0dd17f01c4d6` |
| wa_id           | `59177944041`                          |
| message_count   | 12                                     |
| summary         | (appointment neurology — test data)    |


### v2 seed mapping for Dr. Murillo (from snapshot)


| New table                                          | Source / value                                                                                          |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `tenants.name`                                     | `Luis Felipe`                                                                                           |
| `tenants.last_name`                                | `Murillo`                                                                                               |
| `tenants.professional_title`                       | `Dr`                                                                                                    |
| `tenants.phone`                                    | Direct POC line — **nullable at launch**; can equal business phone                                      |
| `tenants.email`                                    | Gmail / subscription email — **set when auth is built**; nullable until then                            |
| `tenant_settings`                                  | `account_status = true`, `automation_plan = 'basic'`, `max_business = 1`                                |
| `tenant_businesses.name`                           | Public name — **Murillo today:** `Dr. Luis Felipe Murillo` (or custom e.g. `Neuro Consultorio Murillo`) |
| `tenant_businesses.category`                       | `medicine`                                                                                              |
| `tenant_businesses.subcategory`                    | `neurology` (from `Neurología`)                                                                         |
| `tenant_businesses` address, maps, timezone, hours | From `business_profiles`                                                                                |
| `business_pricing`                                 | 300 BOB consulta, `is_default = true`                                                                   |
| `business_knowledge`                               | **Empty at launch**                                                                                     |
| `whatsapp_accounts.business_id`                    | FK → new business row; keep `1248499035016959`                                                          |
| `messaging_channels.*`                             | **Fresh start** — no row migration                                                                      |


**Murillo POC (confirmed structure):** `Dr` + `Luis Felipe` + `Murillo` · business name `Dr. Luis Felipe Murillo`.

**Phone / email at migration:** Can seed `tenants.phone` = `+59176268600` (same as WhatsApp business line) or leave **null**. `**tenants.email`** = null until Gmail subscription flow exists.

**Later:** Gmail OAuth on sign-up → write verified email to `tenants.email`.

---

## Phase 2 — n8n (after schema agreed)

- [ ] Remove **Simple Memory** from `IndigoNode_Whatsapp_bot_v1.3`
- [ ] Update **Get tenant configuration** query to use new view (business + knowledge)
- [ ] Confirm **Get Message Summary** returns `summary`, `conversation_id`, `message_count`
- [ ] Update AI prompt: RESUMEN PREVIO from summary + business context from `business_knowledge`
- [ ] End-to-end test: 2+ messages → summary continuity in `conversations`
- [ ] Verify `To many messages handler` branch uses `message_count`

---

## Phase 3 — migration (after Phase 1 + 2 signed off)

- [ ] Create tenant v2 tables (`tenants`, `tenant_settings`, `tenant_businesses`, `business_pricing`, `business_knowledge`, `whatsapp_accounts`)
- [ ] Run `sql/013_prepared_v_automation_config_v2.sql`
- [ ] Seed Dr. Murillo into `tenant_businesses`, `business_pricing`, and `business_knowledge`
- [ ] Update `docs/Supabase.md` to match final design
- [ ] Inventory all references: SQL `001`–`012`, n8n v1.3, RLS, grants
- [ ] Plan downtime / cutover for live WhatsApp bot

---

## Backlog (later)

- [ ] **Category index** — lookup tables for `category` / `subcategory` + DB indexes for filtering/reporting (eg. all `medicine` tenants)
- [ ] **Gmail subscription** — sign-up writes to `tenants.email`; link to `automation_plan` cart
- [ ] Google Calendar / appointments
- [ ] Move **Active verification** before **Get Message Summary**
- [ ] Safe SQL for summaries with apostrophes (parameterized queries)
- [ ] Project/module schemas for bespoke clients (e.g. toxic waste contract)
- [ ] `tenant.projects` registry — tenant → active project → schema(s)

---

## Notes

- Production flow today: `flows/IndigoNode_Whatsapp_bot_v1.3.json`
- Memory today: `messaging.conversations.summary` → migrates to `**messaging_channels.conversations**`
- **Do not run `013` in Supabase until v2 tables exist and data is migrated**

## Phase 1 complete — both schemas decided

**tenant** and **messaging_channels** designs are agreed. Migration SQL is in `sql/014`–`018` — see **[migration_plan_v2.md](./migration_plan_v2.md)**.

---

# Phase 4 — Manual rollout checklist (your hands-on steps)

Use this as the **final execution guide**. Check boxes as you go.  
**Workflow:** `IndigoNode_Whatsapp_bot_v1.4` in n8n · **Postgres credential:** Supabase session pooler.

> **Sections 1–3 = Supabase only.** **Sections 4–7 = n8n — run only after SQL migration succeeds and Phase 3 verify passes** (see [migration_plan_v2.md](./migration_plan_v2.md)).

---

## 0. Before you start

- [ ] Export / duplicate the live n8n workflow (backup)
- [ ] Note current Supabase project ref and Postgres credential in n8n
- [ ] **Deactivate** the workflow in n8n (stop webhooks during DB cutover)
- [ ] In Supabase Dashboard → Database → confirm you can open SQL Editor
- [ ] Optional: screenshot current `messaging.conversations` row(s) for Dr. Murillo

---

## 1. Supabase — run SQL (in order)

Run each file in **Supabase → SQL Editor → Run**. Wait for success before the next.

### 1A. New schema (in repo — run in this order)


| Order | File                                          | Status  | What it does                                                                                      |
| ----- | --------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------- |
| 1     | `sql/014_tenant_v2_migration.sql`             | **Done** | New tenant tables, POC columns, migrate `business_profiles`, link `whatsapp_accounts.business_id` |
| 1b    | `sql/014b_fix_tenant_data_migration.sql`      | Skipped | Only if 014 step 8 failed — not needed                                                            |
| 2     | `sql/015_messaging_channels_schema.sql`       | **Done** | Schema `messaging_channels` + `contacts` / `conversations` tables (verify: count 0)              |
| 3     | `sql/016_messaging_channels_functions.sql`    | **Done** | `get_conversation_summary` (24h window) + `update_conversation_summary`                           |
| 4     | `sql/013_prepared_v_automation_config_v2.sql` | **Done** | `tenant.v_automation_config` v2 (Postgres node; no public proxy)                                  |
| 5     | `sql/017_grants_rls_v2.sql`                   | **Done** | Grants + RLS                                                                                      |
| 6     | `sql/018_cleanup_legacy.sql`                  | **Done** | Drop `messaging`, `business_profiles`, legacy tenant columns                                     |


Full checklist: **[migration_plan_v2.md](./migration_plan_v2.md)**

### 1B. Already in repo (only if not run before)


| File                                     | Run only if…                                                               |
| ---------------------------------------- | -------------------------------------------------------------------------- |
| `sql/012_conversation_message_count.sql` | Still on **old** `messaging` schema and need `message_count` until cutover |


### 1C. Do **NOT** run in Supabase


| File                      | Reason                            |
| ------------------------- | --------------------------------- |
| `sql/006_n8n_queries.sql` | Reference for n8n copy-paste only |


---

## 2. Supabase — verify migration (automatic seed in 014)

Murillo data is migrated by `sql/014_tenant_v2_migration.sql`. **Skip manual inserts** unless you are adding a new tenant.

**Verify tenant lookup:**

```sql
select * from tenant.v_automation_config
where whatsapp_phone_number_id = 'YOUR_PHONE_NUMBER_ID';
```

Expected: one row with `tenant_name`, `service_fee`, `knowledge_text`, `tenant_active = true`.

**Verify conversation function:**

```sql
select * from messaging_channels.get_conversation_summary(
  p_tenant_id := 'TENANT_UUID'::uuid,
  p_channel := 'whatsapp',
  p_external_id := '59177944841',
  p_channel_endpoint_id := 'YOUR_PHONE_NUMBER_ID',
  p_display_name := 'Test User'
);
```

Expected: `summary`, `conversation_id`, `message_count`, `message_window_started_at`.

---

## 3. Supabase — post-migration verify queries

- [ ] Contacts created on test message:

```sql
select * from messaging_channels.contacts
order by last_seen_at desc limit 5;
```

- [ ] Summary + 24h counter:

```sql
select id, message_count, message_window_started_at, summary, summary_updated_at
from messaging_channels.conversations
order by last_message_at desc nulls last;
```

- [ ] Rate-limit test: after 30+ messages in 24h, `message_count` should stay > 30 until window resets

---

## 4. n8n — nodes to edit (v1.4) — **after SQL migration succeeds**

> **Do not start this section until Phase 3 in [migration_plan_v2.md](./migration_plan_v2.md) passes.**

Open **`IndigoNode_Whatsapp_bot_v1.4`**. Baseline export: [`flows/IndigoNode_Whatsapp_bot_v1.4.json`](../../flows/IndigoNode_Whatsapp_bot_v1.4.json).

### 4.1 Whatsapp fields (Set node)

- [ ] Confirm fields: `phone_number_id`, `wa_id`, `message`, `Name`, `image`, `sticker`
- [ ] `image` = `{{ $('WhatsApp Trigger').item.json.messages[0].image ?? null }}`
- [ ] `sticker` = `{{ $('WhatsApp Trigger').item.json.messages[0].sticker ?? null }}`

### 4.2 If1 — text vs media

- [ ] **TRUE** → Get tenant configuration (text path)
- [ ] **FALSE** → Image Message Handler
- [ ] Condition: `{{ !$json.image && !$json.sticker }}` → boolean **is true**

### 4.3 Get tenant configuration (Postgres)

Replace query with (after v2 view exists):

```sql
select *
from tenant.v_automation_config
where whatsapp_phone_number_id = '{{ $json.phone_number_id }}'
limit 1;
```

- [ ] Node name references in other nodes must match exactly: `**Get tenant configuration**`

### 4.4 Get Message Summary (Postgres)

Replace query (after v2 functions exist):

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

- [ ] Fix any old references to `Important WPP message fields` → `**Whatsapp fields**`
- [ ] Schema changes from `messaging.` → `**messaging_channels.**`

### 4.5 Active verification (IF)

Current flow: runs **after** Get Message Summary (needs `$json.message_count`).

- [ ] Condition 1: `$('Get tenant configuration').item.json.tenant_id` **is not empty**
- [ ] Condition 2: `$('Get tenant configuration').item.json.tenant_active` **equals** `true`
- [ ] Condition 3: `$json.message_count` **lt** `30` (24h cap — not tied to `automation_plan`)
- [ ] **TRUE** → AI Agent path
- [ ] **FALSE** (rate limit) → **To many messages handler**

### 4.6 AI Agent

- [ ] **Disconnect / delete Simple Memory** sub-node (Postgres summary replaces it)
- [ ] Turn **OFF** “Require Specific Output Format” (unless you add Output Parser)
- [ ] Update prompt — use new view fields, e.g.:
  - `tenant_name`, `subcategory` (or `specialty` alias)
  - `{{ $('Get Message Summary').item.json.summary }}` → RESUMEN PREVIO
  - `{{ $('Get tenant configuration').item.json.knowledge_text }}` → business FAQs/policies
  - `service_fee`, `service_currency`, `address`, `maps_url`
  - `business_metadata.office_hours_start` / `office_hours_end`
- [ ] Require JSON output: `{"reply":"...","summary":"..."}`

### 4.7 Code in JavaScript

- [ ] Parses `$json.output` → `{ reply, summary }`
- [ ] `$('Get Message Summary')` for fallback summary (node name exact)

### 4.8 Send message (WhatsApp)

- [ ] Text body: `={{ $json.reply }}` (from Code node, **not** raw AI output)

### 4.9 Update Conversation Summary (Postgres)

```sql
select messaging_channels.update_conversation_summary(
  '{{ $('Get Message Summary').item.json.conversation_id }}'::uuid,
  '{{ $('Code in JavaScript').item.json.summary }}'
) as summary_updated_at;
```

### 4.10 To many messages handler (WhatsApp)

- [ ] Fixed message, e.g. “Has enviado muchos mensajes. Un agente humano te contactará pronto.”
- [ ] **No** AI Agent, **no** Update Conversation Summary on this branch

### 4.11 Image Message Handler (WhatsApp)

- [ ] Fixed message: text-only for now

---

## 5. n8n — wiring order (confirm)

```text
WhatsApp Trigger → If (has messages)
  → Whatsapp fields → If1 (text vs image/sticker)
    TRUE → Get tenant configuration → Get Message Summary → Active verification
      TRUE  → AI Agent → Code in JavaScript → Send message → Update Conversation Summary
      FALSE → To many messages handler
    FALSE → Image Message Handler
```

- [ ] Simple Memory **not** connected to AI Agent
- [ ] OpenAI Chat Model **is** connected to AI Agent

---

## 6. Testing checklist (before re-activate)

- [ ] **Text hi** → AI reply on WhatsApp; row in `messaging_channels.conversations`; `message_count = 1`
- [ ] **Second message** → bot uses prior `summary`; count increments
- [ ] **Send image** → Image Message Handler only; no AI charge
- [ ] **31+ messages in 24h** (test carefully) → To many messages handler; no AI call
- [ ] Supabase: `summary_updated_at` updates after each AI reply
- [ ] No “Referenced node doesn't exist” errors (node names match expressions)

---

## 7. Go live

- [ ] Save workflow
- [ ] **Activate** workflow in n8n
- [ ] Send real WhatsApp message to production number
- [ ] Monitor n8n Executions for errors
- [ ] Export updated workflow JSON to repo (`flows/IndigoNode_Whatsapp_bot_v1.4_v2.json`)

---

## 8. Optional cleanup (after stable)

- [ ] Update `docs/Supabase.md` to v2 design
- [ ] Commit + push repo changes
- [ ] Drop legacy `messaging` schema/tables when confident (keep backup)
- [ ] Deactivate old flow exports (v1.0–v1.2) in repo docs only

---

## Quick reference — what runs where


| Step                         | Supabase                                         | n8n                           |
| ---------------------------- | ------------------------------------------------ | ----------------------------- |
| Who owns this WhatsApp line? | `tenant.v_automation_config`                     | Get tenant configuration      |
| Conversation memory + count  | `messaging_channels.get_conversation_summary`    | Get Message Summary           |
| Block if >30 msgs / 24h      | function returns `message_count`                 | Active verification IF        |
| AI reply                     | —                                                | AI Agent + Code in JavaScript |
| Save summary                 | `messaging_channels.update_conversation_summary` | Update Conversation Summary   |
| Billing tier (later)         | `tenant_settings.automation_plan`                | not used in bot flow yet      |



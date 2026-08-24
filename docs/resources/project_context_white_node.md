# WHITE NODE — PROJECT CONTEXT

## PHASE 0 — PROJECT CONTEXT

**Status:** Living reference — updated as the platform ships  
**Last updated:** 2026-08-24  
**Company:** IndigoNode — Automation Services  
**Project:** White Node (IndigoNode WhatsApp automation)  
**Project Type:** WhatsApp Business automation platform for businesses  
**Initial Target Market:** Doctors / medical practices  

**Canonical docs (repo):**

| Area | Document |
|------|----------|
| Database (v2) | [Supabase.md](../Supabase.md) |
| n8n workflow | [whatsapp_bot.md](../whatsapp_bot.md) |
| Onboarding Step 1 — Meta | [meta_business_setup.md](../guidance/meta_business_setup.md) |
| Onboarding Step 2 — WhatsApp trigger | [whatsapp_trigger_config.md](../guidance/whatsapp_trigger_config.md) |
| Onboarding Step 3 — Postgres | [supabase_postgres_node_config.md](../guidance/supabase_postgres_node_config.md) |
| DB design rationale | [supabase_db_design.md](./supabase_db_design.md) |
| v2 migration runbook | [migration_plan_v2.md](./migration_plan_v2.md) |

---

# 1. PROJECT OVERVIEW

White Node is an automation platform developed by **IndigoNode** that combines:

* WhatsApp Business Coexistence
* WhatsApp Business Platform / API
* Self-hosted n8n
* AI agents
* Supabase / PostgreSQL

The initial target customer is a **doctor or medical practice**.

The core value proposition is:

> Allow a doctor to continue using the WhatsApp Business application normally while simultaneously connecting the same business presence to the WhatsApp Business Platform, allowing White Node to automate conversations and operational tasks using n8n and AI.

The doctor should not need to abandon the WhatsApp Business application to benefit from automation.

---

# 2. BUSINESS CONTEXT

White Node is a product in active delivery — **v1 WhatsApp conversation automation is live** for the first production POC (Murillo, 2026-08-24). Broader MVP features (reminders, summaries, coexistence) remain on the roadmap.

**Important business fact:**

Three units have already been sold even though the product is not yet fully implemented.

This means the project is not purely experimental. The MVP must prioritize:

1. Reliability
2. WhatsApp connectivity
3. Correct message handling
4. Data isolation between customers
5. Basic AI automation
6. Easy onboarding
7. Operational maintainability

The initial implementation will focus on doctors, but the architecture must allow White Node to eventually support other business types.

Potential future customers may include:

* Restaurants
* Salons
* Lawyers
* Real estate agents
* Small businesses
* Professional services
* Other appointment-based businesses

Therefore, **medical-specific functionality should not be hardcoded into the core platform whenever avoidable.**

---

# 3. CORE PROBLEM

Many businesses already use WhatsApp Business as their primary communication channel.

They want automation, but they also want to continue using the WhatsApp Business application manually.

White Node solves this by connecting the business's WhatsApp presence to an automation layer.

The desired architecture is:

```text
CUSTOMER / PATIENT
        │
        ▼
   WhatsApp
        │
        ▼
WhatsApp Business
   Coexistence
        │
        ▼
WhatsApp Business Platform
        │
        ▼
      n8n
        │
   ┌────┴─────┐
   ▼          ▼
 AI Agent   Business Logic
   │          │
   └────┬─────┘
        ▼
    Supabase
    PostgreSQL
```

The exact Meta architecture may evolve as the product implementation progresses.

---

# 4. ACTORS

## 4.1 Patient / Customer

The person communicating with the doctor through WhatsApp.

They may:

* Send questions
* Receive automated responses
* Ask about schedules
* Ask about locations
* Receive reminders
* Receive other informational messages

---

## 4.2 Doctor / Business User

The customer purchasing White Node.

The doctor should be able to:

* Continue using WhatsApp Business
* Configure business information
* Configure locations
* Configure schedules
* Define frequently asked questions
* Receive and respond to conversations
* Use AI automation
* Review summaries
* Eventually manage appointments

---

## 4.3 White Node

White Node is the automation layer between WhatsApp, business data, and AI.

White Node is responsible for:

* Receiving WhatsApp events
* Processing incoming messages
* Determining whether automation should occur
* Retrieving relevant business information
* Calling AI agents
* Sending automated responses
* Persisting relevant data
* Generating summaries
* Executing scheduled workflows

---

## 4.4 IndigoNode Administrator

The IndigoNode team operates the platform.

Administrators may need to:

* Onboard businesses
* Configure integrations
* Monitor workflows
* Troubleshoot WhatsApp connectivity
* Review automation failures
* Manage tenants
* Manage system configuration
* Monitor system health

---

# 5. MVP OBJECTIVES

The MVP must prove that White Node can reliably automate common WhatsApp interactions for a doctor while allowing the doctor to continue using WhatsApp Business.

The MVP should prioritize the following:

### Objective 1 — WhatsApp Connectivity

Connect a doctor's WhatsApp Business account to the WhatsApp Business Platform using the supported coexistence architecture.

### Objective 2 — Message Processing

Receive incoming WhatsApp messages and process them through n8n.

### Objective 3 — AI Responses

Allow an AI agent to respond to predefined classes of patient questions.

### Objective 4 — Business Knowledge

Allow the AI agent to access the doctor's configured business information.

### Objective 5 — Scheduled Automation

Allow White Node to send scheduled messages such as reminders.

### Objective 6 — Operational Summaries

Generate daily summaries for the doctor.

---

# 6. MVP USER STORIES

## Conversation Automation

* As a doctor, I want my agent to greet new patients automatically.
* As a doctor, I want my agent to answer frequently asked questions.
* As a doctor, I want my agent to know my working hours.
* As a doctor, I want my agent to know all of my business locations.
* As a doctor, I want my agent to provide patients with accurate information about my services.

## Patient Communication

* As a doctor, I want my agent to answer common patient questions.
* As a doctor, I want my agent to recognize when a question cannot be answered.
* As a doctor, I want the conversation to be escalated to me when human intervention is required.

## Reminders

* As a doctor, I want my agent to send appointment reminders.
* As a doctor, I want reminders to be generated automatically based on appointment data.

## Daily Summaries

* As a doctor, I want to receive a daily summary of my appointments.
* As a doctor, I want to receive a daily summary of what patients asked during the day.

---

# 7. MVP OUT OF SCOPE

The following functionality is intentionally excluded from the first MVP unless explicitly added later.

## Appointment Rescheduling

Automated appointment rescheduling is currently out of scope.

The system may eventually support:

* Creating appointments
* Cancelling appointments
* Rescheduling appointments
* Checking availability

However, these should not be implemented as part of the initial MVP.

---

# 8. HUMAN HANDOFF

AI automation must not assume that every conversation should be handled automatically.

The architecture should support a future human-handoff mechanism.

Examples:

* Patient explicitly requests a human.
* AI confidence is too low.
* Patient asks a question outside the configured knowledge.
* Sensitive or complex requests require human intervention.

The MVP does not necessarily need a complete human-handoff UI, but the architecture should not prevent it.

---

# 9. TECHNOLOGY STACK

## n8n

n8n is the primary workflow automation engine.

Responsibilities include:

* Receiving webhook events
* Processing messages
* Executing business logic
* Calling AI services
* Querying Supabase
* Sending WhatsApp messages
* Executing scheduled workflows
* Generating summaries

n8n should contain orchestration logic rather than becoming the permanent source of truth for business data.

---

## Supabase

Supabase provides the backend infrastructure.

Primary responsibilities:

* PostgreSQL database
* Authentication
* Storage when required
* Database APIs
* Row Level Security
* Persistent application data

Supabase/PostgreSQL should be considered the primary source of truth for structured White Node data.

---

# 10. THIRD-PARTY SERVICES

The initial system depends on:

### Meta

* Meta Developer Platform
* Meta Business
* WhatsApp Business Platform
* WhatsApp Business Coexistence

Meta configuration and approval requirements are external dependencies and may affect project timelines.

### AI Provider

White Node will require an AI model/provider for AI agents.

The AI provider should remain abstracted where practical so that the platform is not unnecessarily coupled to one provider.

---

# 11. MULTI-TENANCY

White Node must eventually support multiple businesses.

Each customer is considered a **tenant**.

Example:

```text
White Node
│
├── Tenant A — Doctor 1
│   ├── WhatsApp
│   ├── Patients
│   ├── Messages
│   └── Appointments
│
├── Tenant B — Doctor 2
│   ├── WhatsApp
│   ├── Patients
│   ├── Messages
│   └── Appointments
│
└── Tenant C — Business 3
    ├── WhatsApp
    ├── Customers
    ├── Messages
    └── Appointments
```

Tenant isolation is a fundamental architectural requirement.

One tenant must never be able to access another tenant's data.

---

# 12. DATABASE ARCHITECTURE

**Status (2026-08-24):** v2 schema **live in production Supabase**. Legacy `messaging` schema removed.

PostgreSQL uses **schemas to organize domains**. The implemented v2 structure:

```text
PostgreSQL Database (Supabase)
│
├── tenant                          ← customers, businesses, WhatsApp routing
│   ├── tenants
│   ├── tenant_settings
│   ├── tenant_businesses
│   ├── business_pricing
│   ├── business_knowledge
│   ├── whatsapp_accounts           ← phone_number_id → business (n8n webhook key)
│   └── v_automation_config         ← view: tenant + business + pricing + knowledge
│
├── messaging_channels              ← runtime messaging (WhatsApp today; multi-channel later)
│   ├── contacts
│   ├── conversations               ← rolling AI summary + 24h message_count only
│   ├── get_conversation_summary()
│   └── update_conversation_summary()
│
├── appointments                    ← planned, not in v1
├── ai                              ← planned, not in v1 (prompt lives in n8n today)
└── system                          ← planned
```

**Privacy rule (v1):** Store rolling conversation **summaries** and counters — **not** inbound/outbound message bodies or raw webhook payloads.

**n8n access:** Postgres node via Supabase **session pooler** — queries `tenant.*` and `messaging_channels.*` directly. No `public.v_automation_config` proxy.

Source of truth for DDL: [`sql/`](../sql/) (migrations `013`–`018`).

---

# 13. INITIAL DATABASE DOMAINS

## Tenant — **implemented (v2)**

Stores each White Node customer and their business configuration.

Live entities:

* `tenants` — POC identity (name, title, slug)
* `tenant_settings` — activation, automation plan
* `tenant_businesses` — public business name, category, address, metadata (hours, maps)
* `business_pricing` — service fees (e.g. consulta price in BOB)
* `business_knowledge` — FAQ / policy blocks for AI (aggregate via view)
* `whatsapp_accounts` — Meta `phone_number_id` routing to a business

---

## Messaging — **implemented as `messaging_channels` (v2)**

Channel-agnostic messaging runtime. WhatsApp is the first channel.

Live entities:

* `contacts` — channel user ID (`wa_id` for WhatsApp)
* `conversations` — rolling `summary`, `message_count` (24h window), timestamps

**Not stored:** message bodies, chat history, raw webhooks.

Legacy `messaging` schema was dropped after v2 cutover (2026-08-24).

---

## Appointments

Stores appointment-related information.

Potential entities:

* Appointments
* Appointment status
* Appointment participants
* Reminder configuration

---

## AI

Stores configuration required by AI agents.

Potential entities:

* Agents
* Agent configuration
* System prompts
* Knowledge sources
* FAQ entries
* AI execution logs

---

## System

Stores platform-level information.

Potential entities:

* Third-party integrations
* Workflow executions
* Error logs
* Audit logs
* System configuration

---

# 14. DATA OWNERSHIP PRINCIPLE

Every tenant-owned record should have a clear relationship to its tenant.

Example:

```text
tenant_id
    │
    ├── business profile
    ├── locations
    ├── contacts
    ├── conversations
    ├── appointments (future)
    └── AI configuration (partial — knowledge in DB, prompt in n8n)
```

The system should favor explicit tenant relationships instead of relying exclusively on application-level filtering.

Supabase Row Level Security should be considered an important part of the tenant-isolation strategy.

---

# 15. SECURITY PRINCIPLES

White Node may process sensitive business and patient communication data.

Therefore:

* Tenant data must be isolated.
* Database access must follow least-privilege principles.
* Secrets must never be hardcoded.
* API tokens must be stored securely.
* Webhook endpoints must validate incoming requests.
* Logs should avoid unnecessarily exposing sensitive message content.
* AI providers should only receive the minimum information required.
* Administrative access should be restricted.
* Production credentials must never be used in development unnecessarily.

Security requirements will become more detailed before production deployment.

---

# 16. ENVIRONMENTS

The project should eventually maintain separate environments for:

```text
Development
     │
     ▼
Testing / QA
     │
     ▼
Production
```

Development and testing should avoid using real patient data whenever possible.

Production credentials and production WhatsApp numbers should not be casually used for development testing.

---

# 17. N8N ARCHITECTURE PRINCIPLE

n8n is the **orchestration layer**, not the database.

**Production workflow (v1.4):** `IndigoNode_Whatsapp_bot_v1.4_v2` — see [whatsapp_bot.md](../whatsapp_bot.md).

Implemented flow:

```text
WhatsApp Trigger (Meta webhook)
      │
      ▼
Whatsapp fields          ← normalize phone_number_id, wa_id, message, type
      │
      ▼
Messages Type (IF)       ← text vs image
      │
      ├─ image  → fixed reply (no AI)
      │
      └─ text
            │
            ▼
      Get tenant configuration     ← tenant.v_automation_config
            │
            ▼
      Get Message Summary          ← messaging_channels.get_conversation_summary
            │
            ▼
      Active verification          ← tenant active + message_count < 30
            │
            ├─ over limit → fixed handoff message
            │
            └─ OK
                  │
                  ▼
              AI Agent (OpenAI)      ← no LangChain Simple Memory
                  │
                  ▼
              Code in JavaScript     ← parse { reply, summary }
                  │
                  ▼
              Send message (WhatsApp)
                  │
                  ▼
              Update Conversation Summary  ← messaging_channels.update_conversation_summary
```

Business data persists in PostgreSQL. n8n holds credentials (WhatsApp OAuth, WhatsApp API token, Postgres pooler, OpenAI) — never commit tokens to git.

---

# 18. AI AGENT PRINCIPLES

The AI agent should not invent business information.

The agent should primarily use information configured for the tenant.

For example:

```text
Patient Question
       │
       ▼
AI Agent
       │
       ├── Business Information
       ├── FAQs
       ├── Schedule
       ├── Locations
       └── Other approved knowledge
       │
       ▼
Response
```

If the required information is unavailable, the preferred behavior should be to acknowledge the limitation or escalate rather than hallucinate an answer.

---

# 19. INITIAL DOCTOR CONFIGURATION

Each doctor should eventually have a configurable profile containing:

### Business Information

* Doctor name
* Specialty
* Description
* Services

### Locations

* Location name
* Address
* Working days
* Working hours

### FAQs

* Question
* Approved answer

### WhatsApp

* WhatsApp Business information
* Meta integration information
* Connection status

### AI

* Agent enabled/disabled
* Agent instructions
* Approved knowledge

---

# 20. CURRENT PROJECT STATUS

**Last updated:** 2026-08-24

## v1 WhatsApp bot — **live (POC)**

End-to-end WhatsApp automation is **working in production** for the first tenant:

| Item | Status |
|------|--------|
| Database v2 (`tenant` + `messaging_channels`) | **Complete** — SQL `014`–`018` applied |
| n8n workflow cutover | **Complete** — v1.4 on v2 functions/view |
| Meta + n8n onboarding runbooks | **Documented** in `docs/guidance/` |
| Production POC tenant | **Dr. Luis Felipe Murillo** |

**Production POC values (Murillo):**

| Field | Value |
|-------|-------|
| Public name | Dr. Luis Felipe Murillo |
| WhatsApp business number | `+59176268600` |
| Meta `phone_number_id` | `1248499035016959` |
| Default consult price | 300 BOB |

## What v1 delivers today

* Inbound WhatsApp text → AI reply in Spanish (professional, no medical advice)
* Tenant lookup by Meta `phone_number_id`
* Postgres rolling conversation summary (replaces LangChain memory)
* 30 messages / 24h per conversation rate limit
* Image messages → fixed “describe the content” reply (no AI)
* Business config from DB: name, specialty, fee, address, hours, maps URL

## v1 known limitations

* **One WhatsApp line → one active business** — `whatsapp_phone_number_id` maps to a single `business_id` via `whatsapp_accounts`. Two offices on the same number with different prices requires a product decision (not supported in v1).
* **`knowledge_text`** exists in the view but is not yet wired into the AI prompt.
* **Stickers** follow the text path (only images are branched).
* **WhatsApp Business Coexistence** (doctor keeps using the mobile app on the same number) remains a **future** goal — current onboarding uses Meta Business Suite + Cloud API (do **not** register the number in the standalone WhatsApp Business app during setup).
* **Appointments, reminders, daily summaries** — out of scope for v1 (see §7).

## v1.1 polish backlog (optional)

* Wire `knowledge_text` into AI Agent prompt
* Sticker branch on Messages Type
* Parameterize summary SQL expressions
* Move Active verification before Get Message Summary (ordering cleanup)

## Still planned (post-v1)

* Multi-tenant self-service onboarding
* Admin UI / tenant management
* Appointments module
* Permanent System User token (replace short-lived dev tokens)
* Client-owned vs IndigoNode-owned Meta Business Portfolio playbook

---

# 21. CURRENT BLOCKERS

## Resolved (2026-08-24)

* Database schema design → **v2 implemented and migrated**
* n8n ↔ Supabase integration → **Postgres node + v2 functions working**
* Meta onboarding procedure → **documented** ([Step 1](../guidance/meta_business_setup.md) → [Step 2](../guidance/whatsapp_trigger_config.md) → [Step 3](../guidance/supabase_postgres_node_config.md))

## Active / external dependencies

* **Meta ecosystem** — app review, billing, token lifetime (System User permanent token for production)
* **WhatsApp Business Coexistence** — still a strategic dependency for the full product vision; not required for current Cloud API POC
* **Sold units (3)** — onboarding playbooks and multi-tenant ops still manual

When Meta blocks progress, continue on: tenant data model, prompt quality, admin tooling, appointments design, and test infrastructure.

---

# 22. DEVELOPMENT PRINCIPLES

The project should follow these principles:

1. **Build the smallest useful MVP.**
2. **Do not over-engineer future functionality.**
3. **Keep business logic separate from infrastructure logic.**
4. **Keep tenant data isolated.**
5. **Use PostgreSQL as the source of truth.**
6. **Use n8n primarily for orchestration.**
7. **Keep third-party integrations replaceable where practical.**
8. **Design the core platform to be business-agnostic.**
9. **Keep medical-specific functionality inside the appropriate domain/configuration layer.**
10. **Prioritize reliability over cleverness.**
11. **Every production workflow should have logging and error handling.**
12. **Never assume an external API will behave perfectly.**

---

# 23. DEFINITION OF MVP SUCCESS

### v1 achieved (2026-08-24)

The following are **proven** with the Murillo POC:

1. Connect a business WhatsApp line via Meta Cloud API + n8n webhooks.
2. Receive patient messages and process them through n8n.
3. AI agent answers common questions using configured business data (name, specialty, fee, address, hours).
4. Conversation memory via Postgres summary (no raw message storage).
5. Rate limiting and inactive-tenant guards.
6. Tenant data isolated by schema + RLS (n8n uses service-role pooler).

### Full MVP (still outstanding)

The broader MVP definition from §5–§6 still includes items **not yet built**:

* Continue using WhatsApp Business app on the same number (coexistence)
* Automated greeting flows (beyond implicit AI behavior)
* Scheduled appointment reminders
* Daily appointment + patient-question summaries
* Structured human-handoff UI
* Appointment create/cancel/reschedule

Treat v1 as the **conversation automation foundation**; schedule/reminder/summary features remain on the roadmap (§24).

---

# 24. FUTURE ROADMAP

Potential future functionality includes:

* Appointment creation
* Appointment cancellation
* Appointment rescheduling
* Calendar integration
* CRM functionality
* Multiple AI agents
* Voice messages
* Document processing
* Automated follow-ups
* Analytics
* Customer dashboards
* Additional communication channels
* Additional business verticals
* White-label deployments
* Multi-business administration

These features are **not part of the current MVP unless explicitly added to scope.**

---

# 25. IMPORTANT TERMINOLOGY

### Tenant

A customer/business using White Node.

Example:

```text
Tenant = Dr. Carlos Medical Practice
```

### Schema

A PostgreSQL namespace used to organize related database objects.

Example:

```text
messaging_channels.conversations
```

Here:

* `messaging_channels` = schema
* `conversations` = table

### Phone number ID

Meta's identifier for the **business WhatsApp line** (webhook `metadata.phone_number_id`). Used by n8n to look up the tenant — not the patient's number.

### WA ID

The patient's WhatsApp user ID (webhook `contacts[].wa_id`). Stored as `messaging_channels.contacts.external_id`.

### Workflow

An n8n automation that performs a defined process.

### Agent

An AI-powered component responsible for interpreting and responding to messages according to configured rules and business knowledge.

### Coexistence

The WhatsApp capability that allows the supported WhatsApp Business application and WhatsApp Business Platform/API functionality to work together.

### Source of Truth

The system that should contain the authoritative version of persistent business data.

For White Node, PostgreSQL should generally serve as the source of truth.

---

# 26. PROJECT NORTH STAR

White Node should evolve from a collection of n8n automations into a **multi-tenant WhatsApp automation platform**.

The initial implementation is intentionally narrow:

> **Automate WhatsApp communication for doctors without forcing them to abandon the WhatsApp Business experience they already use.**

The architecture should be simple enough to ship quickly, but structured enough that the same platform can later support other businesses without rebuilding the entire system.

---

# 27. REPOSITORY LAYOUT (DOCS)

```text
docs/
├── Supabase.md              ← v2 schema reference (canonical DB doc)
├── whatsapp_bot.md          ← n8n workflow node-by-node reference
├── guidance/                ← step-by-step onboarding runbooks
│   ├── meta_business_setup.md           Step 1 — Meta suite
│   ├── whatsapp_trigger_config.md       Step 2 — OAuth + webhook + send
│   └── supabase_postgres_node_config.md Step 3 — Postgres credential + nodes
└── resources/
    ├── project_context_white_node.md    ← this file
    ├── supabase_db_design.md            ← design rationale + Phase 4 checklist
    └── migration_plan_v2.md             ← v2 migration runbook (complete)

flows/                       ← n8n JSON exports
sql/                         ← DDL source of truth (014–018 = v2)
```

**Onboarding order for a new tenant:** Step 1 → Step 2 → Step 3 → import workflow → verify Supabase row → activate.

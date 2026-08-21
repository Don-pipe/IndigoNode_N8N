# WHITE NODE — PROJECT CONTEXT

## PHASE 0 — PROJECT CONTEXT

**Status:** Read-only reference
**Company:** IndigoNode — Automation Services
**Project:** White Node
**Project Type:** WhatsApp Business automation platform for businesses
**Initial Target Market:** Doctors / medical practices

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

White Node is currently a product under development.

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

The database will use PostgreSQL.

The system will use PostgreSQL **schemas to organize domains**, rather than treating every individual data type as a schema.

A schema is a namespace used to logically organize related database objects such as tables, views, functions, and other objects.

Example:

```text
PostgreSQL Database
│
├── tenant
│   ├── tenants
│   ├── users
│   └── business_profiles
│
├── messaging
│   ├── conversations
│   ├── messages
│   └── contacts
│
├── appointments
│   └── appointments
│
├── ai
│   ├── agents
│   ├── prompts
│   └── knowledge
│
└── system
    ├── integrations
    ├── workflow_logs
    └── audit_logs
```

This is a proposed logical structure and should be validated before implementation.

---

# 13. INITIAL DATABASE DOMAINS

## Tenant

Stores information about each White Node customer.

Potential entities:

* Tenant
* Business profile
* Tenant users
* Business locations
* Business schedules

---

## Messaging

Stores communication-related information.

Potential entities:

* Contacts
* Conversations
* Messages
* Message events
* Message status

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
    ├── messages
    ├── appointments
    └── AI configuration
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

n8n should be treated as the **orchestration layer**, not the database.

Example:

```text
WhatsApp Event
      │
      ▼
    n8n
      │
      ├── Identify Tenant
      │
      ├── Identify Contact
      │
      ├── Store Message
      │
      ├── Retrieve Business Context
      │
      ├── Determine Automation
      │
      ├── Call AI
      │
      └── Send Response
```

Business data should persist in PostgreSQL rather than only inside n8n workflow state.

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

Current status:

* White Node concept defined.
* Initial target market identified: doctors.
* Three units have already been sold.
* WhatsApp Business Coexistence is a critical dependency.
* Meta Developer / Meta Business configuration is required.
* n8n automation architecture has been selected.
* Supabase/PostgreSQL has been selected as the backend.
* MVP functionality has been defined at a high level.
* Database architecture still needs to be designed.
* Production architecture still needs to be validated.

---

# 21. CURRENT BLOCKERS

The project currently depends on the Meta ecosystem for WhatsApp Business Coexistence and related capabilities.

Any Meta verification, app configuration, permissions, or provider requirements should be treated as **external project dependencies**.

When a Meta dependency blocks implementation, development should continue on components that can be built independently, such as:

* Database architecture
* Tenant model
* n8n workflows
* AI agent logic
* Business configuration
* Mock webhook payloads
* Testing infrastructure
* Logging
* Error handling
* Admin functionality

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

The MVP can be considered successful when a real doctor can:

1. Connect their supported WhatsApp Business setup.
2. Continue using WhatsApp Business normally.
3. Receive patient messages.
4. Have White Node process those messages.
5. Automatically greet patients.
6. Automatically answer configured FAQs.
7. Provide configured locations and schedules.
8. Send configured reminders.
9. Receive a daily appointment summary.
10. Receive a daily summary of patient questions.
11. Escalate conversations that require human intervention.
12. Have all data securely isolated from other White Node customers.

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
messaging.messages
```

Here:

* `messaging` = schema
* `messages` = table

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

# WhatsApp Trigger Config — n8n Setup

**Purpose:** Connect n8n to Meta WhatsApp Cloud API (OAuth, webhook, send credentials).  
**Audience:** IndigoNode ops / onboarding.  
**Prerequisite:** Complete [meta_business_setup.md](./meta_business_setup.md) **Step 1** first.  
**Next:** Import and configure the full bot workflow — see [supabase_postgres_node_config.md](./supabase_postgres_node_config.md) (Step 3) · [whatsapp_bot.md](../whatsapp_bot.md)  
**Related:** [Supabase.md](../Supabase.md) · [supabase_db_design.md](../resources/supabase_db_design.md)

---

> After Meta suite setup (Step 1), configure the n8n WhatsApp trigger and webhook.  
> **Follow the steps below in order.**

---

## Pre-requirements

- [ ] [Meta suite setup](./meta_business_setup.md) complete through **Step 1.6**
- [ ] n8n instance running and accessible from the internet (webhook URL must be reachable by Meta)

---

## Step 2 — n8n WhatsApp trigger setup

### 2.1 n8n | Create a new workflow

- [ ] Create a **new workflow**
- [ ] Add a **WhatsApp Trigger** node
- [ ] Add **WhatsApp OAuth account** credentials:
  - [ ] Go to **App Settings** on Meta Developer (app from [Step 1.2](./meta_business_setup.md#12-meta-developer--create-a-developer-account))
    - [ ] **App ID** → paste as **Client ID** in n8n
    - [ ] **Generate App Secret** → paste as **Client Secret** in n8n
  - [ ] Copy those values into n8n and **Save**

---

### 2.2 Meta Developers | Create webhook

**Go to:** [developers.facebook.com](https://developers.facebook.com) → select the application

- [ ] Go to **Use cases** → **Production setup** → **Configure Webhooks**
- [ ] Copy the **POST callback URL** from the n8n WhatsApp Trigger node
- [ ] Create a **verification token** (example: `Orwellian_2026_Bo`)
- [ ] Paste the same verification token in n8n and Meta

> **Very important:** To detect the webhook you must **activate the workflow in n8n first**, and **only then** click **Save and Subscribe** in Meta Developers.

- [ ] **Activate** the n8n workflow
- [ ] Click **Save and Subscribe** in Meta Developers
- [ ] Once the webhook is accepted, click **Subscribe to webhook** and **activate** that as well

---

### 2.3 n8n | Create a Send Message node

- [ ] Add a **Send Message** node (WhatsApp)
- [ ] Add **WhatsApp account** credentials:
  - [ ] Go to [Step 1.6](./meta_business_setup.md#16-meta-developer--configure-whatsapp) on Meta for Business / Developer
    - [ ] Copy the **Business ID**
    - [ ] **Generate an access token**
  - [ ] Add those values in n8n
  - [ ] **Save**

---

## Quick reference — step map

| Step | Where | Action |
|------|--------|--------|
| **2.1** | n8n + Meta App Settings | WhatsApp Trigger + OAuth (Client ID / Secret) |
| **2.2** | Meta Developers + n8n | Webhook URL, verify token, activate workflow, Save and Subscribe |
| **2.3** | n8n + Meta | Send Message node + Business ID + access token |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Webhook verification fails | Workflow not active in n8n | Activate workflow **before** Save and Subscribe in Meta |
| Meta never delivers events | Subscribe to webhook not enabled | After verification, click **Subscribe to webhook** and activate |
| OAuth errors in n8n | Wrong App ID / Secret | Re-copy from Meta App Settings → Basic |
| Send Message fails | Token expired or wrong Business ID | Regenerate token in Step 1.6; update n8n credential |

---

## Bibliography

- [How to Build a WhatsApp Agent with n8n (credential tutorial)](https://www.youtube.com/watch?v=A0OwvNOLNlw)
- [How to Configure WhatsApp API Manually Step-By-Step — Manual Meta WhatsApp API Setup For Business](https://www.youtube.com/watch?v=-E8GlZ5C3Lc)
- [Meta for Developers — Webhooks](https://developers.facebook.com/docs/graph-api/webhooks)
- [WhatsApp Cloud API documentation](https://developers.facebook.com/docs/whatsapp/cloud-api)
- [n8n WhatsApp Trigger node](https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.whatsapptrigger/)

---

## Backlog

- [ ] Supabase `whatsapp_accounts` insert after trigger is live
- [ ] System User + permanent token for production (replace short-lived dev token)
- [ ] Full workflow import checklist in [whatsapp_bot.md](../whatsapp_bot.md) — continue with [supabase_postgres_node_config.md](./supabase_postgres_node_config.md)

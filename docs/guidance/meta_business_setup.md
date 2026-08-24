# Meta for Business — WhatsApp Setup

**Purpose:** Official IndigoNode procedure to set up Meta **before** the WhatsApp bot can go live.  
**Audience:** IndigoNode ops / onboarding.  
**Next step after 1.7:** [whatsapp_trigger_config.md](./whatsapp_trigger_config.md) (Step 2)  
**Related:** [Supabase.md](../Supabase.md) · [supabase_db_design.md](../resources/supabase_db_design.md) · [whatsapp_bot.md](../whatsapp_bot.md)

---

> In order for us to be able to create the bot, we first need to set up the Meta suite.  
> **Follow the steps below in order.**

---

## Pre-requirements

- [ ] Have a **Facebook account**

---

## Step 1 — Meta suite setup

### 1.1 Meta Business | Create Business Portfolio

**Go to:** [business.facebook.com](https://business.facebook.com)

- [ ] Sidebar → **Create Business portfolio**
- [ ] **Name:** `[Business Name]`
- [ ] **First Name** | **Last Name** | **Business Email**
- [ ] Click **Create**

---

### 1.2 Meta Developer | Create a developer account

**Go to:** [developers.facebook.com](https://developers.facebook.com)

- [ ] Log in with your Facebook account
- [ ] Create new project → **My Apps** page
  - [ ] **Name:** `IndigoNode Automation`
  - [ ] **Email:** `lmurillo.dev@gmail.com`
  - [ ] **Use case:** Connect with customers through WhatsApp
  - [ ] **Business:** Add Business portfolio → **Step 1.1**

---

### 1.3 WhatsApp Business | Application

> **Important:** **DO NOT** create a WhatsApp Business account with the phone number in this step.

- [ ] Skip standalone WhatsApp Business app setup — number is added in **Step 1.4** via Meta Business Suite

---

### 1.4 Meta Business | Add phone number

**Go to:** Meta Business Suite → **Accounts** → **WhatsApp Accounts**

- [ ] **Add phone number**
- [ ] Verify by **SMS**

---

### 1.5 Meta Business | Add payment method

**Go to:** **Billing and payments**

- [ ] **Payment methods** → **Add**

---

### 1.6 Meta Developer | Configure WhatsApp

**Go to:** [developers.facebook.com](https://developers.facebook.com) → select the app created in **Step 1.2**

- [ ] Click **Use cases**
- [ ] Click **Connect with customers through WhatsApp**
- [ ] Click **Basic setup**

#### Step 1 | Try it out

- [ ] Claim a WhatsApp **test number**
- [ ] **Generate a token**
- [ ] **Send a test message**

#### Step 2 | Production setup

- [ ] **Configure Webhooks** → leave for now (created in **n8n Step 2**)
- [ ] **Register WhatsApp number** → use number from **Step 1.4**
- [ ] **Add payment method** → use **Step 1.5**

---

### 1.7 n8n | Continue setup

- [ ] Go to **n8n setup → Step 2**

See [whatsapp_trigger_config.md](./whatsapp_trigger_config.md) for OAuth, webhook, and Send Message credentials.  
Full workflow reference: [whatsapp_bot.md](../whatsapp_bot.md).

---

## Quick reference — step map

| Step | Where | Action |
|------|--------|--------|
| **1.1** | [business.facebook.com](https://business.facebook.com) | Create Business portfolio |
| **1.2** | [developers.facebook.com](https://developers.facebook.com) | Create app `IndigoNode Automation` |
| **1.3** | WhatsApp Business app | **Do not** register number here |
| **1.4** | Meta Business → WhatsApp Accounts | Add + verify phone (SMS) |
| **1.5** | Meta Business → Billing | Add payment method |
| **1.6** | Meta Developer → WhatsApp | Test number + token, then production setup |
| **1.7** | n8n | [whatsapp_trigger_config.md](./whatsapp_trigger_config.md) (**Step 2**) |

---

## Appendix A — Architecture (Meta → n8n → Supabase)

```text
Patient WhatsApp  →  Meta Cloud API  →  n8n (WhatsApp Trigger)
                                              │
                                              ▼
                                        Supabase lookup
                                        (phone_number_id → tenant)
                                              │
                                              ▼
                                        AI reply  →  Meta  →  Patient
```

IndigoNode does **not** host WhatsApp. Meta sends webhooks to n8n; Supabase stores tenant routing and conversation memory.

---

## Appendix B — IDs to save after setup

Collect from **Meta Developer → WhatsApp → API Setup** after **Step 1.6**:

| Meta label | Supabase column |
|------------|-----------------|
| **Phone number ID** | `tenant.whatsapp_accounts.whatsapp_phone_number_id` |
| **WhatsApp Business Account ID** | `tenant.whatsapp_accounts.waba_id` |
| **Business phone number** (E.164) | `tenant.whatsapp_accounts.whatsapp_business_number` |
| **Access token** | n8n WhatsApp credential only — **never in git** |

### Webhook IDs (do not confuse)

| Webhook field | Who it identifies |
|---------------|-------------------|
| `metadata.phone_number_id` | **Business line** → tenant lookup |
| `contacts[0].wa_id` | **Patient / sender** → contact record |

---

## Appendix C — Supabase (after Meta + n8n)

Insert or update `tenant.whatsapp_accounts` with the **Phone number ID** from Meta:

```sql
select tenant_id, business_id, tenant_name, tenant_active, service_fee, address
from tenant.v_automation_config
where whatsapp_phone_number_id = 'YOUR_PHONE_NUMBER_ID';
```

Must return one row with `tenant_active = true`. Full schema: [Supabase.md](../Supabase.md).

**Production POC (Murillo):**

| Field | Value |
|-------|-------|
| Phone number ID | `1248499035016959` |
| Business number | `+59176268600` |

---

## Appendix D — Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| n8n never triggers | Webhook not configured | Complete n8n Step 2; verify webhook in Meta app |
| Trigger fires, no tenant | Wrong `phone_number_id` in DB | Match Meta API Setup ID to `whatsapp_accounts` |
| Send fails | Token expired | Regenerate token in Step 1.6; refresh n8n credential |
| Payment errors | Step 1.5 missing | Add payment method in Meta Business billing |

---

## Bibliography

- [Cómo obtener el Token Permanente de WhatsApp para n8n (Guía Definitiva)](https://www.youtube.com/watch?v=aerQRoAJkWg)
- [How to Configure WhatsApp API Manually Step-By-Step — Manual Meta WhatsApp API Setup For Business](https://www.youtube.com/watch?v=-E8GlZ5C3Lc)
- [Meta Business Suite](https://business.facebook.com)
- [Meta for Developers](https://developers.facebook.com)
- [WhatsApp Cloud API documentation](https://developers.facebook.com/docs/whatsapp/cloud-api)
- [WhatsApp Manager](https://business.facebook.com/wa/manage/home/)
- [WhatsApp Business Platform](https://business.whatsapp.com/products/business-platform)

---

## Backlog

- [ ] System User + permanent token for production
- [ ] Client-owned vs IndigoNode-owned Business Portfolio playbook

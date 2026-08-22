# IndigoNode — TODOs

**Last updated:** Saturday, Aug 22, 2026  
**Next session:** Monday

---

## Monday — Priority

### 1. Replace n8n Simple Memory with Supabase

- [ ] Remove **Simple Memory** sub-node from AI Agent in `IndigoNode_Whatsapp_bot_v1.3`
- [ ] Confirm **Get Message Summary** returns `summary`, `conversation_id`, `message_count`
- [ ] Confirm AI prompt uses `{{ $('Get Message Summary').item.json.summary }}` as **RESUMEN PREVIO**
- [ ] Confirm **Code in JavaScript** parses `reply` + `summary` from AI output
- [ ] Confirm **Update Conversation Summary** saves new summary after each reply
- [ ] End-to-end test: send 2+ messages → verify summary continuity in `messaging.conversations`
- [ ] Verify `message_count` increments and rate-limit branch (`To many messages handler`) works if wired
- [ ] Document final flow in `sql/006_n8n_queries.sql` if node names changed

**Goal:** Postgres rolling summary is the only conversation memory — no LangChain memory.

---

### 2. Schema rename analysis (plan before migrating)

**Target model (one Supabase project, many projects inside):**

| Layer | Purpose | Current name | Proposed direction |
|-------|---------|--------------|-------------------|
| Core | IndigoNode clients (generic) | `tenant` | Keep or rename → `core` |
| Channel | WhatsApp bot / n8n runtime | `messaging` | Keep or rename → `messaging` / `channels` |
| Project / module | Custom automation per contract or vertical | *(none yet)* | `medical`, `project_<slug>`, etc. |

- [ ] Inventory everything that references schema names today:
  - [ ] All SQL migrations (`sql/001`–`012`)
  - [ ] n8n Postgres queries in v1.3 flow
  - [ ] `docs/Supabase.md`
  - [ ] Supabase RLS policies and grants (`004`, `007`)
  - [ ] Functions: `get_conversation_summary`, `update_conversation_summary`, etc.
- [ ] Decide final schema names (document decision — do not rename until agreed):
  - [ ] `tenant` vs `core`
  - [ ] `messaging` vs `whatsapp_bot` vs `channels`
  - [ ] Bespoke projects: `project_<slug>` vs reusable modules (`medical`, `waste_management`)
- [ ] Design `core.projects` (or equivalent) registry:
  - [ ] Links `tenant_id` → active project(s) → schema(s) enabled
  - [ ] How n8n resolves “which schema to query” on webhook
- [ ] Write migration plan: rename order, `DROP`/`CREATE` functions, n8n update checklist
- [ ] Estimate risk: downtime, breaking n8n live workflow, Supabase pooler credentials

**Goal:** Written plan ready so we rename once — not twice.

---

## Later (backlog)

- [ ] Google Calendar integration for appointment booking
- [ ] Move **Active verification** before **Get Message Summary** (skip DB for inactive tenants)
- [ ] Safe SQL for summaries with apostrophes (parameterized query vs string interpolation)
- [ ] Remove Simple Memory references from older flow exports (v1.0, v1.1, v1.2)
- [ ] Push / align `docs/Supabase.md` with any schema rename decisions

---

## Notes

- Production flow: `flows/IndigoNode_Whatsapp_bot_v1.3.json`
- Memory lives on: `messaging.conversations.summary` + `message_count`
- Raw messages: intentionally **not** stored in production flow

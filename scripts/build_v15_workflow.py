import json
import uuid
import copy

src = json.load(open("flows/older version/IndigoNode_Whatsapp_bot_v1.4_v2.json", encoding="utf-8"))
wf = copy.deepcopy(src)
wf["name"] = "IndigoNode_Whatsapp_bot_v1.5"
wf["active"] = False
wf["versionId"] = str(uuid.uuid4())

wf["nodes"] = [n for n in wf["nodes"] if n["name"] != "Get Message Summary"]

for n in wf["nodes"]:
    if n["name"] == "Get tenant configuration":
        n["parameters"]["query"] = (
            "select *\n"
            "from tenant.v_automation_config_all\n"
            "where whatsapp_phone_number_id = '{{ $('Whatsapp fields').item.json.phone_number_id }}'\n"
            "  and business_id = '{{ $('Process routing').item.json.selected_business_id }}'::uuid\n"
            "limit 1;"
        )
        n["position"] = [-16, -560]
        n["notes"] = "Business config for selected location"
    elif n["name"] == "Active verification":
        n["parameters"]["conditions"]["conditions"] = [
            {
                "id": "tenant-found-check",
                "leftValue": "={{ $('Process routing').item.json.tenant_id }}",
                "rightValue": "",
                "operator": {"type": "string", "operation": "notEmpty", "singleValue": True},
            },
            {
                "id": "47d725c5-e29a-4eb9-b99c-eacf097fdc52",
                "leftValue": "={{ $('Process routing').item.json.tenant_active }}",
                "rightValue": True,
                "operator": {"type": "boolean", "operation": "equals"},
            },
            {
                "id": "772a758e-4520-4790-9c5b-29c2307a3d9d",
                "leftValue": "={{ $('Process routing').item.json.message_count }}",
                "rightValue": 30,
                "operator": {"type": "number", "operation": "lt"},
            },
        ]
        n["position"] = [224, -560]
    elif n["name"] == "Update Conversation Summary":
        n["parameters"]["query"] = (
            "select messaging_channels.update_conversation_summary(\n"
            "  '{{ $('Process routing').item.json.conversation_id }}'::uuid,\n"
            "  '{{ $('Code in JavaScript').item.json.summary }}'\n"
            ") as summary_updated_at;"
        )
    elif n["name"] == "Code in JavaScript":
        n["parameters"]["jsCode"] = (
            "const raw = $input.first().json.output ?? '';\n"
            "const previousSummary = $('Process routing').first().json.summary ?? '';\n"
            "\n"
            "let reply = raw;\n"
            "let summary = previousSummary;\n"
            "\n"
            "try {\n"
            "  const cleaned = raw.replace(/```json\\n?|```/g, '').trim();\n"
            "  const parsed = JSON.parse(cleaned);\n"
            "  reply = parsed.reply ?? raw;\n"
            "  summary = parsed.summary ?? previousSummary;\n"
            "} catch (error) {\n"
            "  reply = raw;\n"
            "  summary = previousSummary;\n"
            "}\n"
            "\n"
            "return [{ json: { reply, summary } }];"
        )
    elif n["name"] == "AI Agent":
        n["parameters"]["text"] = n["parameters"]["text"].replace(
            "Get Message Summary", "Process routing"
        )

new_nodes = [
    {
        "parameters": {
            "operation": "executeQuery",
            "query": (
                "select *\n"
                "from messaging_channels.process_inbound_routing(\n"
                "  p_channel := 'whatsapp',\n"
                "  p_channel_endpoint_id := '{{ $('Whatsapp fields').item.json.phone_number_id }}',\n"
                "  p_external_id := '{{ $('Whatsapp fields').item.json.wa_id }}',\n"
                "  p_display_name := '{{ $('Whatsapp fields').item.json.Name }}',\n"
                "  p_message := '{{ $('Whatsapp fields').item.json.message }}'\n"
                ");"
            ),
            "options": {},
        },
        "type": "n8n-nodes-base.postgres",
        "typeVersion": 2.7,
        "position": [-288, -560],
        "id": str(uuid.uuid4()),
        "name": "Process routing",
        "credentials": {
            "postgres": {"id": "3qTU0DmGmB7nGAAC", "name": "Postgres account whatsapp bot project"}
        },
        "notes": "Multi-location routing: menu or selected business",
    },
    {
        "parameters": {
            "conditions": {
                "options": {
                    "caseSensitive": True,
                    "leftValue": "",
                    "typeValidation": "strict",
                    "version": 3,
                },
                "conditions": [
                    {
                        "id": "needs-location-menu",
                        "leftValue": "={{ $json.needs_location_menu }}",
                        "rightValue": True,
                        "operator": {"type": "boolean", "operation": "equals"},
                    }
                ],
                "combinator": "and",
            },
            "options": {},
        },
        "type": "n8n-nodes-base.if",
        "typeVersion": 2.3,
        "position": [-48, -720],
        "id": str(uuid.uuid4()),
        "name": "Needs location menu?",
    },
    {
        "parameters": {
            "jsCode": (
                "const routing = $('Process routing').first().json;\n"
                "const brand = routing.welcome_brand_name || 'nuestro consultorio';\n"
                "const menu = Array.isArray(routing.business_menu) ? routing.business_menu : [];\n"
                "\n"
                "const lines = menu.map((item) => {\n"
                "  const addr = item.address ? ' — ' + item.address : '';\n"
                "  return item.index + '. ' + item.name + addr;\n"
                "});\n"
                "\n"
                "const reply = '¡Hola! Bienvenido a ' + brand + '. ¿En qué sede desea ser atendido?\\n\\n'\n"
                "  + lines.join('\\n')\n"
                "  + '\\n\\nResponda con el número de la sede.';\n"
                "\n"
                "return [{ json: { reply } }];"
            )
        },
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": [224, -720],
        "id": str(uuid.uuid4()),
        "name": "Location menu",
    },
    {
        "parameters": {
            "operation": "send",
            "phoneNumberId": "={{ $('Whatsapp fields').item.json.phone_number_id }}",
            "recipientPhoneNumber": "={{ $('Whatsapp fields').item.json.wa_id }}",
            "textBody": "={{ $json.reply }}",
            "additionalFields": {},
        },
        "type": "n8n-nodes-base.whatsApp",
        "typeVersion": 1.1,
        "position": [496, -720],
        "id": str(uuid.uuid4()),
        "name": "Send location menu",
        "webhookId": "fd017b13-0e51-4025-8030-d4289a8a019a",
        "executeOnce": False,
        "credentials": {"whatsAppApi": {"id": "MKK8kfFDJVZVP9b4", "name": "WhatsApp account"}},
    },
    {
        "parameters": {
            "content": "## Multi-location routing (v1.5)\nPatient picks a location before AI. process_inbound_routing returns needs_location_menu + business_menu.",
            "height": 320,
            "width": 400,
        },
        "type": "n8n-nodes-base.stickyNote",
        "position": [-320, -880],
        "typeVersion": 1,
        "id": str(uuid.uuid4()),
        "name": "Sticky Note routing",
    },
]
wf["nodes"].extend(new_nodes)

wf["connections"] = {
    "WhatsApp Trigger": {"main": [[{"node": "If", "type": "main", "index": 0}]]},
    "If": {"main": [[{"node": "Whatsapp fields", "type": "main", "index": 0}]]},
    "Send message": {"main": [[{"node": "Update Conversation Summary", "type": "main", "index": 0}]]},
    "AI Agent": {"main": [[{"node": "Code in JavaScript", "type": "main", "index": 0}]]},
    "OpenAI Chat Model": {
        "ai_languageModel": [[{"node": "AI Agent", "type": "ai_languageModel", "index": 0}]]
    },
    "Get tenant configuration": {"main": [[{"node": "Active verification", "type": "main", "index": 0}]]},
    "Active verification": {
        "main": [
            [{"node": "AI Agent", "type": "main", "index": 0}],
            [{"node": "To many messages handler", "type": "main", "index": 0}],
        ]
    },
    "Code in JavaScript": {"main": [[{"node": "Send message", "type": "main", "index": 0}]]},
    "Whatsapp fields": {"main": [[{"node": "Messages Type", "type": "main", "index": 0}]]},
    "Messages Type": {
        "main": [
            [{"node": "Process routing", "type": "main", "index": 0}],
            [{"node": "Image Message Handler", "type": "main", "index": 0}],
        ]
    },
    "Process routing": {"main": [[{"node": "Needs location menu?", "type": "main", "index": 0}]]},
    "Needs location menu?": {
        "main": [
            [{"node": "Location menu", "type": "main", "index": 0}],
            [{"node": "Get tenant configuration", "type": "main", "index": 0}],
        ]
    },
    "Location menu": {"main": [[{"node": "Send location menu", "type": "main", "index": 0}]]},
}

with open("flows/IndigoNode_Whatsapp_bot_v1.5.json", "w", encoding="utf-8") as f:
    json.dump(wf, f, indent=2, ensure_ascii=False)

print("Created flows/IndigoNode_Whatsapp_bot_v1.5.json")

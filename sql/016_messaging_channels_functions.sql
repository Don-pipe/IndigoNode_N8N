-- White Node / IndigoNode
-- Run order: 16
-- Purpose: messaging_channels conversation functions (24h rolling window)
-- Prerequisites: 015_messaging_channels_schema.sql
-- Next: 013_prepared_v_automation_config_v2.sql

-- ---------------------------------------------------------------------------
-- get_conversation_summary — upsert contact + conversation, apply 24h window
-- ---------------------------------------------------------------------------
create or replace function messaging_channels.get_conversation_summary(
  p_tenant_id uuid,
  p_channel text,
  p_external_id text,
  p_channel_endpoint_id text,
  p_display_name text default null
)
returns table (
  contact_id uuid,
  conversation_id uuid,
  summary text,
  summary_updated_at timestamptz,
  message_count integer,
  message_window_started_at timestamptz
)
language plpgsql
as $$
#variable_conflict use_column
declare
  v_business_id uuid;
  v_contact_id uuid;
  v_conversation_id uuid;
  v_summary text;
  v_summary_updated_at timestamptz;
  v_message_count integer;
  v_window_started timestamptz;
  v_now timestamptz := now();
begin
  select wa.business_id
  into v_business_id
  from tenant.whatsapp_accounts wa
  join tenant.tenant_settings ts on ts.tenant_id = wa.tenant_id
  join tenant.tenant_businesses tb on tb.id = wa.business_id and tb.tenant_id = wa.tenant_id
  where wa.tenant_id = p_tenant_id
    and wa.whatsapp_phone_number_id = p_channel_endpoint_id
    and wa.is_active = true
    and ts.account_status = true
    and tb.is_active = true
  limit 1;

  if v_business_id is null then
    raise exception
      'No active business/WhatsApp endpoint for tenant % channel_endpoint_id %',
      p_tenant_id, p_channel_endpoint_id;
  end if;

  insert into messaging_channels.contacts (
    tenant_id,
    business_id,
    channel,
    external_id,
    display_name,
    last_seen_at
  ) values (
    p_tenant_id,
    v_business_id,
    p_channel,
    p_external_id,
    p_display_name,
    v_now
  )
  on conflict (tenant_id, business_id, channel, external_id) do update
    set display_name = coalesce(excluded.display_name, messaging_channels.contacts.display_name),
        last_seen_at = v_now,
        updated_at = v_now
  returning id into v_contact_id;

  if v_contact_id is null then
    select c.id into v_contact_id
    from messaging_channels.contacts c
    where c.tenant_id = p_tenant_id
      and c.business_id = v_business_id
      and c.channel = p_channel
      and c.external_id = p_external_id;
  end if;

  insert into messaging_channels.conversations as conv (
    tenant_id,
    business_id,
    contact_id,
    channel,
    channel_endpoint_id,
    last_message_at,
    message_count,
    message_window_started_at
  ) values (
    p_tenant_id,
    v_business_id,
    v_contact_id,
    p_channel,
    p_channel_endpoint_id,
    v_now,
    1,
    v_now
  )
  on conflict (tenant_id, contact_id, channel, channel_endpoint_id) do update
    set last_message_at = v_now,
        updated_at = v_now,
        message_count = case
          when conv.message_window_started_at is null
            or v_now - conv.message_window_started_at >= interval '24 hours'
          then 1
          else conv.message_count + 1
        end,
        message_window_started_at = case
          when conv.message_window_started_at is null
            or v_now - conv.message_window_started_at >= interval '24 hours'
          then v_now
          else conv.message_window_started_at
        end
  returning
    conv.id,
    conv.summary,
    conv.summary_updated_at,
    conv.message_count,
    conv.message_window_started_at
  into
    v_conversation_id,
    v_summary,
    v_summary_updated_at,
    v_message_count,
    v_window_started;

  if v_conversation_id is null then
    select
      c.id,
      c.summary,
      c.summary_updated_at,
      c.message_count,
      c.message_window_started_at
    into
      v_conversation_id,
      v_summary,
      v_summary_updated_at,
      v_message_count,
      v_window_started
    from messaging_channels.conversations c
    where c.tenant_id = p_tenant_id
      and c.contact_id = v_contact_id
      and c.channel = p_channel
      and c.channel_endpoint_id = p_channel_endpoint_id;
  end if;

  contact_id := v_contact_id;
  conversation_id := v_conversation_id;
  summary := coalesce(v_summary, 'Sin conversación previa.');
  summary_updated_at := v_summary_updated_at;
  message_count := v_message_count;
  message_window_started_at := v_window_started;
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- update_conversation_summary — save rolling summary after AI reply
-- ---------------------------------------------------------------------------
create or replace function messaging_channels.update_conversation_summary(
  p_conversation_id uuid,
  p_summary text
)
returns timestamptz
language plpgsql
as $$
declare
  v_updated_at timestamptz := now();
begin
  update messaging_channels.conversations
  set summary = p_summary,
      summary_updated_at = v_updated_at,
      last_message_at = v_updated_at,
      updated_at = v_updated_at
  where id = p_conversation_id;

  if not found then
    raise exception 'Conversation not found: %', p_conversation_id;
  end if;

  return v_updated_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Verify (use tenants.slug — v_automation_config does not exist until 013)
-- select *
-- from messaging_channels.get_conversation_summary(
--   p_tenant_id := (select id from tenant.tenants where slug = 'dr-luis-murillo'),
--   p_channel := 'whatsapp',
--   p_external_id := '59177944041',
--   p_channel_endpoint_id := '1248499035016959',
--   p_display_name := 'Test User'
-- );

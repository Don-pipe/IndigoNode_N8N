-- White Node / IndigoNode
-- Run order: 20
-- Purpose: Multi-location routing — one WhatsApp line, patient picks a business/location
--
-- Flow: process_inbound_routing → needs_location_menu?
--   YES → n8n sends welcome + numbered location menu (no AI)
--   NO  → get_conversation_summary uses selected business → normal AI path

-- ---------------------------------------------------------------------------
-- 1) welcome brand on tenant_settings (used in location menu greeting)
-- ---------------------------------------------------------------------------
alter table tenant.tenant_settings
  add column if not exists welcome_brand_name text;

comment on column tenant.tenant_settings.welcome_brand_name is
  'Brand name for multi-location welcome, e.g. Dr. Luis Felipe Murillo. Falls back to tenant POC name.';

update tenant.tenant_settings ts
set welcome_brand_name = coalesce(
  ts.welcome_brand_name,
  trim(concat_ws(' ', t.professional_title, t.name, t.last_name))
)
from tenant.tenants t
where t.id = ts.tenant_id
  and ts.welcome_brand_name is null;

-- ---------------------------------------------------------------------------
-- 2) routing_sessions — tenant-level session before / after location pick
-- ---------------------------------------------------------------------------
create table if not exists messaging_channels.routing_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant.tenants(id) on delete cascade,
  channel text not null,
  external_id text not null,
  channel_endpoint_id text not null,
  selected_business_id uuid references tenant.tenant_businesses(id) on delete set null,
  display_name text,
  message_count integer not null default 0,
  message_window_started_at timestamptz,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (tenant_id, channel, external_id, channel_endpoint_id),

  constraint routing_sessions_channel_check
    check (channel in ('whatsapp', 'instagram', 'facebook', 'sms', 'email', 'other'))
);

create index if not exists idx_routing_sessions_lookup
  on messaging_channels.routing_sessions (tenant_id, channel, external_id, channel_endpoint_id);

drop trigger if exists trg_routing_sessions_updated_at on messaging_channels.routing_sessions;
create trigger trg_routing_sessions_updated_at
before update on messaging_channels.routing_sessions
for each row execute function messaging_channels.set_updated_at();

comment on table messaging_channels.routing_sessions is
  'Per-user routing on a channel endpoint. Holds selected_business_id once patient picks a location.';

-- ---------------------------------------------------------------------------
-- 3) v_automation_config_all — one row per active business on a WhatsApp line
-- ---------------------------------------------------------------------------
create or replace view tenant.v_automation_config_all as
select
  t.id as tenant_id,
  t.name as tenant_account_name,
  tb.id as business_id,
  tb.name as tenant_name,
  tb.category,
  tb.subcategory,
  tb.subcategory as specialty,

  (
    ts.account_status
    and tb.is_active
    and wa.is_active
  ) as tenant_active,

  ts.automation_plan,
  ts.max_business,
  coalesce(
    nullif(trim(ts.welcome_brand_name), ''),
    trim(concat_ws(' ', t.professional_title, t.name, t.last_name))
  ) as welcome_brand_name,

  tb.address,
  tb.maps_url,
  tb.currency as service_currency,
  tb.timezone,
  tb.hours_start,
  tb.hours_end,

  jsonb_build_object(
    'office_hours_start', to_char(tb.hours_start, 'HH24:MI'),
    'office_hours_end', to_char(tb.hours_end, 'HH24:MI')
  ) as business_metadata,

  default_price.amount as service_fee,
  coalesce(default_price.currency, tb.currency) as default_price_currency,
  default_price.name as default_price_name,

  wa.id as whatsapp_account_id,
  wa.whatsapp_phone_number_id,
  wa.whatsapp_business_number,
  wa.waba_id,
  wa.is_primary as whatsapp_is_primary,

  coalesce(knowledge.knowledge_blocks, '[]'::jsonb) as knowledge_blocks,
  coalesce(knowledge.knowledge_text, '') as knowledge_text,
  coalesce(pricing.pricing_blocks, '[]'::jsonb) as pricing_blocks,

  tb.created_at as business_sort_at

from tenant.whatsapp_accounts wa
join tenant.tenants t on t.id = wa.tenant_id
join tenant.tenant_settings ts on ts.tenant_id = t.id
join tenant.tenant_businesses tb on tb.tenant_id = t.id and tb.is_active = true

left join lateral (
  select p.amount, p.currency, p.name
  from tenant.business_pricing p
  where p.business_id = tb.id and p.is_active = true and p.is_default = true
  order by p.sort_order nulls last, p.created_at
  limit 1
) default_price on true

left join lateral (
  select
    jsonb_agg(jsonb_build_object('type', bk.type, 'title', bk.title, 'content', bk.content)
      order by bk.sort_order nulls last, bk.type, bk.title) as knowledge_blocks,
    string_agg(initcap(bk.type) || ' — ' || bk.title || E':\n' || bk.content, E'\n\n'
      order by bk.sort_order nulls last, bk.type, bk.title) as knowledge_text
  from tenant.business_knowledge bk
  where bk.business_id = tb.id and bk.is_active = true
) knowledge on true

left join lateral (
  select jsonb_agg(jsonb_build_object(
      'name', bp.name, 'amount', bp.amount,
      'currency', coalesce(bp.currency, tb.currency),
      'is_default', bp.is_default, 'description', bp.description
    ) order by bp.sort_order nulls last, bp.name) as pricing_blocks
  from tenant.business_pricing bp
  where bp.business_id = tb.id and bp.is_active = true
) pricing on true

where wa.is_active = true;

comment on view tenant.v_automation_config_all is
  'All active businesses for each WhatsApp line — use business_id filter after location selection.';

-- ---------------------------------------------------------------------------
-- 4) try_match_business — parse 1/2/3, phrase, or keyword tokens from message
-- ---------------------------------------------------------------------------
create or replace function messaging_channels.try_match_business(
  p_tenant_id uuid,
  p_message text
)
returns uuid
language plpgsql
stable
as $$
declare
  v_msg text := lower(trim(coalesce(p_message, '')));
  v_pick integer;
  v_business_id uuid;
  v_count integer;
  v_tokens text[];
  v_stopwords text[] := array[
    'en', 'la', 'el', 'de', 'del', 'los', 'las', 'un', 'una', 'y', 'a', 'al',
    'por', 'para', 'que', 'con', 'se', 'es', 'lo', 'su', 'mi', 'me', 'sede',
    'quiero', 'atendido', 'ser', 'desea', 'donde', 'cual', 'cuál', 'numero',
    'número', 'una', 'uno', 'dos', 'tres'
  ];
begin
  if v_msg = '' then
    return null;
  end if;

  select count(*) into v_count
  from tenant.tenant_businesses tb
  where tb.tenant_id = p_tenant_id and tb.is_active = true;

  -- Numeric pick: "1", "2", …
  if v_msg ~ '^\d+$' then
    v_pick := v_msg::integer;
    if v_pick >= 1 and v_pick <= v_count then
      select tb.id into v_business_id
      from tenant.tenant_businesses tb
      where tb.tenant_id = p_tenant_id and tb.is_active = true
      order by tb.created_at
      offset (v_pick - 1) limit 1;
      return v_business_id;
    end if;
  end if;

  -- Full phrase substring (e.g. "sopocachi", "papa león xiii")
  select tb.id into v_business_id
  from tenant.tenant_businesses tb
  where tb.tenant_id = p_tenant_id
    and tb.is_active = true
    and (
      lower(tb.name) like '%' || v_msg || '%'
      or lower(coalesce(tb.address, '')) like '%' || v_msg || '%'
    )
  order by tb.created_at
  limit 1;

  if v_business_id is not null then
    return v_business_id;
  end if;

  -- Token match: "en la de sopocachi" → sopocachi; ambiguous tokens → null
  v_tokens := array(
    select tok
    from unnest(
      regexp_split_to_array(
        regexp_replace(v_msg, '[^a-z0-9áéíóúñü ]', ' ', 'g'),
        '\s+'
      )
    ) as tok
    where length(tok) >= 3
      and not (tok = any (v_stopwords))
  );

  if coalesce(array_length(v_tokens, 1), 0) = 0 then
    return null;
  end if;

  with candidates as (
    select tb.id, count(distinct tok) as score
    from tenant.tenant_businesses tb
    cross join unnest(v_tokens) as tok
    where tb.tenant_id = p_tenant_id
      and tb.is_active = true
      and (
        lower(tb.name) like '%' || tok || '%'
        or lower(coalesce(tb.address, '')) like '%' || tok || '%'
      )
    group by tb.id
  ),
  top_matches as (
    select c.id
    from candidates c
    where c.score = (select max(score) from candidates)
  )
  select tm.id
  into v_business_id
  from top_matches tm
  where (select count(*) from top_matches) = 1
  limit 1;

  return v_business_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) get_conversation_summary — optional p_business_id (multi-location)
-- ---------------------------------------------------------------------------
create or replace function messaging_channels.get_conversation_summary(
  p_tenant_id uuid,
  p_channel text,
  p_external_id text,
  p_channel_endpoint_id text,
  p_display_name text default null,
  p_business_id uuid default null
)
returns table (
  contact_id uuid,
  conversation_id uuid,
  summary text,
  summary_updated_at timestamptz,
  message_count integer,
  message_window_started_at timestamptz,
  business_id uuid
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
  v_business_id := p_business_id;

  if v_business_id is null then
    select rs.selected_business_id into v_business_id
    from messaging_channels.routing_sessions rs
    where rs.tenant_id = p_tenant_id
      and rs.channel = p_channel
      and rs.external_id = p_external_id
      and rs.channel_endpoint_id = p_channel_endpoint_id;
  end if;

  if v_business_id is null then
    select wa.business_id into v_business_id
    from tenant.whatsapp_accounts wa
    join tenant.tenant_settings ts on ts.tenant_id = wa.tenant_id
    join tenant.tenant_businesses tb on tb.id = wa.business_id and tb.tenant_id = wa.tenant_id
    where wa.tenant_id = p_tenant_id
      and wa.whatsapp_phone_number_id = p_channel_endpoint_id
      and wa.is_active = true
      and ts.account_status = true
      and tb.is_active = true
    limit 1;
  end if;

  if v_business_id is null then
    raise exception 'No business resolved for tenant % endpoint %', p_tenant_id, p_channel_endpoint_id;
  end if;

  insert into messaging_channels.contacts (
    tenant_id, business_id, channel, external_id, display_name, last_seen_at
  ) values (
    p_tenant_id, v_business_id, p_channel, p_external_id, p_display_name, v_now
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
    tenant_id, business_id, contact_id, channel, channel_endpoint_id,
    last_message_at, message_count, message_window_started_at
  ) values (
    p_tenant_id, v_business_id, v_contact_id, p_channel, p_channel_endpoint_id,
    v_now, 1, v_now
  )
  on conflict (tenant_id, contact_id, channel, channel_endpoint_id) do update
    set last_message_at = v_now,
        updated_at = v_now,
        message_count = case
          when conv.message_window_started_at is null
            or v_now - conv.message_window_started_at >= interval '24 hours'
          then 1 else conv.message_count + 1 end,
        message_window_started_at = case
          when conv.message_window_started_at is null
            or v_now - conv.message_window_started_at >= interval '24 hours'
          then v_now else conv.message_window_started_at end
  returning conv.id, conv.summary, conv.summary_updated_at, conv.message_count, conv.message_window_started_at
  into v_conversation_id, v_summary, v_summary_updated_at, v_message_count, v_window_started;

  if v_conversation_id is null then
    select c.id, c.summary, c.summary_updated_at, c.message_count, c.message_window_started_at
    into v_conversation_id, v_summary, v_summary_updated_at, v_message_count, v_window_started
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
  business_id := v_business_id;
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) process_inbound_routing — main entry for n8n after Whatsapp fields
-- ---------------------------------------------------------------------------
create or replace function messaging_channels.process_inbound_routing(
  p_channel text,
  p_channel_endpoint_id text,
  p_external_id text,
  p_display_name text default null,
  p_message text default null
)
returns table (
  tenant_id uuid,
  tenant_active boolean,
  welcome_brand_name text,
  business_count integer,
  selected_business_id uuid,
  needs_location_menu boolean,
  business_menu jsonb,
  message_count integer,
  contact_id uuid,
  conversation_id uuid,
  summary text,
  summary_updated_at timestamptz,
  message_window_started_at timestamptz
)
language plpgsql
as $$
#variable_conflict use_column
declare
  v_tenant_id uuid;
  v_tenant_active boolean;
  v_welcome text;
  v_business_count integer;
  v_selected uuid;
  v_matched uuid;
  v_now timestamptz := now();
  v_routing_count integer;
  v_routing_window timestamptz;
  v_contact_id uuid;
  v_conversation_id uuid;
  v_summary text;
  v_summary_updated timestamptz;
  v_conv_count integer;
  v_conv_window timestamptz;
begin
  select wa.tenant_id,
         (ts.account_status and wa.is_active),
         coalesce(nullif(trim(ts.welcome_brand_name), ''),
           trim(concat_ws(' ', t.professional_title, t.name, t.last_name)))
  into v_tenant_id, v_tenant_active, v_welcome
  from tenant.whatsapp_accounts wa
  join tenant.tenants t on t.id = wa.tenant_id
  join tenant.tenant_settings ts on ts.tenant_id = t.id
  where wa.whatsapp_phone_number_id = p_channel_endpoint_id
    and wa.is_active = true
  limit 1;

  if v_tenant_id is null then
    raise exception 'No tenant for channel_endpoint_id %', p_channel_endpoint_id;
  end if;

  select count(*) into v_business_count
  from tenant.tenant_businesses tb
  where tb.tenant_id = v_tenant_id and tb.is_active = true;

  insert into messaging_channels.routing_sessions as rs (
    tenant_id, channel, external_id, channel_endpoint_id, display_name,
    last_message_at, message_count, message_window_started_at
  ) values (
    v_tenant_id, p_channel, p_external_id, p_channel_endpoint_id, p_display_name,
    v_now, 1, v_now
  )
  on conflict (tenant_id, channel, external_id, channel_endpoint_id) do update
    set display_name = coalesce(excluded.display_name, rs.display_name),
        last_message_at = v_now,
        updated_at = v_now,
        message_count = case
          when rs.message_window_started_at is null
            or v_now - rs.message_window_started_at >= interval '24 hours'
          then 1 else rs.message_count + 1 end,
        message_window_started_at = case
          when rs.message_window_started_at is null
            or v_now - rs.message_window_started_at >= interval '24 hours'
          then v_now else rs.message_window_started_at end
  returning rs.selected_business_id, rs.message_count, rs.message_window_started_at
  into v_selected, v_routing_count, v_routing_window;

  if v_selected is null then
    select rs.selected_business_id into v_selected
    from messaging_channels.routing_sessions rs
    where rs.tenant_id = v_tenant_id
      and rs.channel = p_channel
      and rs.external_id = p_external_id
      and rs.channel_endpoint_id = p_channel_endpoint_id;
  end if;

  if v_business_count = 1 then
    select tb.id into v_selected
    from tenant.tenant_businesses tb
    where tb.tenant_id = v_tenant_id and tb.is_active = true
    order by tb.created_at limit 1;

    update messaging_channels.routing_sessions
    set selected_business_id = v_selected, updated_at = v_now
    where tenant_id = v_tenant_id
      and channel = p_channel
      and external_id = p_external_id
      and channel_endpoint_id = p_channel_endpoint_id;
  elsif v_selected is null then
    v_matched := messaging_channels.try_match_business(v_tenant_id, p_message);
    if v_matched is not null then
      v_selected := v_matched;
      update messaging_channels.routing_sessions
      set selected_business_id = v_selected, updated_at = v_now
      where tenant_id = v_tenant_id
        and channel = p_channel
        and external_id = p_external_id
        and channel_endpoint_id = p_channel_endpoint_id;
    end if;
  end if;

  tenant_id := v_tenant_id;
  tenant_active := v_tenant_active;
  welcome_brand_name := v_welcome;
  business_count := v_business_count;
  selected_business_id := v_selected;
  needs_location_menu := (v_selected is null and v_business_count > 1);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'index', row_number,
      'business_id', tb.id,
      'name', tb.name,
      'address', tb.address,
      'hours_start', to_char(tb.hours_start, 'HH24:MI'),
      'hours_end', to_char(tb.hours_end, 'HH24:MI'),
      'service_fee', bp.amount,
      'currency', coalesce(bp.currency, tb.currency)
    ) order by tb.created_at
  ), '[]'::jsonb)
  into business_menu
  from (
    select tb.*, row_number() over (order by tb.created_at) as row_number
    from tenant.tenant_businesses tb
    where tb.tenant_id = v_tenant_id and tb.is_active = true
  ) tb
  left join lateral (
    select p.amount, p.currency
    from tenant.business_pricing p
    where p.business_id = tb.id and p.is_active = true and p.is_default = true
    limit 1
  ) bp on true;

  if v_selected is not null then
    select g.contact_id, g.conversation_id, g.summary, g.summary_updated_at,
           g.message_count, g.message_window_started_at
    into v_contact_id, v_conversation_id, v_summary, v_summary_updated,
         v_conv_count, v_conv_window
    from messaging_channels.get_conversation_summary(
      v_tenant_id, p_channel, p_external_id, p_channel_endpoint_id,
      p_display_name, v_selected
    ) g;

    contact_id := v_contact_id;
    conversation_id := v_conversation_id;
    summary := v_summary;
    summary_updated_at := v_summary_updated;
    message_count := v_conv_count;
    message_window_started_at := v_conv_window;
  else
    contact_id := null;
    conversation_id := null;
    summary := 'Sin conversación previa.';
    summary_updated_at := null;
    message_count := v_routing_count;
    message_window_started_at := v_routing_window;
  end if;

  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants (service_role / postgres for n8n)
-- ---------------------------------------------------------------------------
grant select on tenant.v_automation_config_all to anon, authenticated, service_role;
grant select, insert, update on messaging_channels.routing_sessions to service_role;
grant execute on function messaging_channels.try_match_business(uuid, text) to postgres, service_role;
grant execute on function messaging_channels.get_conversation_summary(uuid, text, text, text, text, uuid) to postgres, service_role;
grant execute on function messaging_channels.process_inbound_routing(text, text, text, text, text) to postgres, service_role;

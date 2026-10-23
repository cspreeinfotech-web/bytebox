-- =====================================================================
-- Bytebox · Stage 8 · Website forms + Meta Conversions API pipeline.
-- =====================================================================

create extension if not exists pg_net;

alter table public.site_settings add column organic_apk_path text;
alter table public.site_settings add column organic_apk_version text;
alter table public.site_settings add column site_url text not null default 'https://bytebox.vercel.app'
  check (site_url ~ '^https://');

-- ---------------------------------------------------------------------
-- Public website helpers (anon)
-- ---------------------------------------------------------------------
create table public.deletion_requests (
  id          bigint generated always as identity primary key,
  email       text not null check (char_length(email) between 3 and 200),
  scope       text not null check (scope in ('account', 'some_data')),
  details     text check (char_length(details) <= 2000),
  status      text not null default 'open' check (status in ('open', 'done', 'rejected')),
  ip          inet,
  created_at  timestamptz not null default now(),
  handled_at  timestamptz
);
alter table public.deletion_requests enable row level security;
create policy deletion_requests_owner on public.deletion_requests for select to authenticated using ((select public.is_owner()));
create policy deletion_requests_owner_update on public.deletion_requests for update to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));
revoke insert, delete, truncate on public.deletion_requests from anon, authenticated;

create or replace function public.submit_deletion_request(p_email text, p_scope text, p_details text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_ip inet := private.request_ip();
begin
  if btrim(coalesce(p_email, '')) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Please enter a valid email'; end if;
  if (select count(*) from public.deletion_requests
      where (ip = v_ip or lower(email) = lower(btrim(p_email))) and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many requests. Please try again later.';
  end if;
  insert into public.deletion_requests (email, scope, details, ip)
  values (lower(btrim(p_email)), p_scope, left(p_details, 2000), v_ip);
end;
$$;

create or replace function public.submit_web_report(
  p_reason text, p_link text, p_details text, p_contact text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_post uuid;
begin
  if char_length(btrim(coalesce(p_details, ''))) < 5 then raise exception 'Please describe the problem'; end if;
  begin
    v_post := substring(p_link from '/p/([0-9a-fA-F-]{36})')::uuid;
  exception when others then v_post := null;
  end;
  if (select count(*) from public.reports where source = 'web' and created_at > now() - interval '1 hour') >= 200 then
    raise exception 'Too many reports right now. Please email us instead.';
  end if;
  insert into public.reports (post_id, channel_id, reason, details, contact, source)
  values (case when exists (select 1 from public.posts where id = v_post) then v_post end,
          (select channel_id from public.posts where id = v_post),
          p_reason, left(btrim(p_link) || E'\n' || p_details, 2000), left(p_contact, 200), 'web');
end;
$$;

-- Share page preview: only published, everyone-audience posts in live channels.
create or replace function public.public_post_preview(p_post_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('title', p.title, 'channel', c.name, 'is_premium', p.is_premium, 'kind', p.kind)
  from public.posts p join public.channels c on c.id = p.channel_id
  where p.id = p_post_id and p.status = 'published' and p.audience = 'all'
    and c.review_status = 'approved' and c.publish_state = 'active' and c.audience = 'all';
$$;

-- ---------------------------------------------------------------------
-- Ad clicks (called from the /d page in the visitor's browser, so the
-- request IP / UA are the visitor's).
-- ---------------------------------------------------------------------
create table public.ad_clicks (
  id           bigint generated always as identity primary key,
  fbclid       text,
  fbc          text,
  fbp          text,
  ip           inet,
  user_agent   text,
  landing_url  text,
  utm_source   text,
  utm_campaign text,
  created_at   timestamptz not null default now()
);
alter table public.ad_clicks enable row level security;
create index ad_clicks_ip_idx on public.ad_clicks (ip, created_at desc);
create policy ad_clicks_owner on public.ad_clicks for select to authenticated using ((select public.is_owner()));
revoke insert, update, delete, truncate on public.ad_clicks from anon, authenticated;

create or replace function public.record_ad_click(p_fbclid text, p_fbp text, p_landing_url text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_ip inet := private.request_ip();
begin
  if v_ip is null then return; end if;
  if (select count(*) from public.ad_clicks where ip = v_ip and created_at > now() - interval '10 minutes') >= 20 then
    return;
  end if;
  insert into public.ad_clicks (fbclid, fbc, fbp, ip, user_agent, landing_url, utm_source, utm_campaign)
  values (left(p_fbclid, 500),
          case when nullif(p_fbclid, '') is not null
               then 'fb.1.' || (extract(epoch from now()) * 1000)::bigint || '.' || left(p_fbclid, 500) end,
          left(p_fbp, 200), v_ip, private.request_user_agent(), left(p_landing_url, 1000),
          private.referrer_param(split_part(p_landing_url, '?', 2), 'utm_source'),
          private.referrer_param(split_part(p_landing_url, '?', 2), 'utm_campaign'));
end;
$$;

alter table public.installs add column ad_click_id bigint references public.ad_clicks (id) on delete set null;

-- ---------------------------------------------------------------------
-- Meta Conversions API
-- ---------------------------------------------------------------------
create table private.meta_config (
  id              int primary key default 1 check (id = 1),
  capi_token      text,
  test_event_code text,
  graph_version   text not null default 'v23.0',
  enabled         boolean not null default true
);
insert into private.meta_config (id) values (1);

create table public.meta_events (
  id                 bigint generated always as identity primary key,
  event_name         text not null,
  event_id           text not null unique,
  event_time         timestamptz not null default now(),
  user_id            uuid,
  install_id         uuid,
  order_id           uuid,
  value              numeric(12, 2),
  currency           text,
  fbc                text,
  fbp                text,
  ip                 inet,
  user_agent         text,
  email_sha256       text,
  external_id_sha256 text,
  is_test            boolean not null default false,
  status             text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed', 'skipped')),
  attempts           int not null default 0,
  request_id         bigint,
  last_error         text,
  sent_at            timestamptz,
  created_at         timestamptz not null default now()
);
alter table public.meta_events enable row level security;
create index meta_events_pending_idx on public.meta_events (created_at) where status in ('pending', 'sending');
create policy meta_events_owner on public.meta_events for select to authenticated using ((select public.is_owner()));
revoke insert, update, delete, truncate on public.meta_events from anon, authenticated;

create or replace function private.sha256(p text)
returns text language sql immutable set search_path = ''
as $$ select case when nullif(btrim(p), '') is null then null
                  else encode(extensions.digest(lower(btrim(p)), 'sha256'), 'hex') end; $$;

-- Install: match an ad click from the same IP within 48 h, queue an AppInstall event for ads installs.
create or replace function private.on_install_created()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_click public.ad_clicks%rowtype;
begin
  if new.ip is not null then
    select * into v_click from public.ad_clicks
     where ip = new.ip and created_at > new.created_at - interval '48 hours' and created_at <= new.created_at
     order by created_at desc limit 1;
    if found then
      update public.installs set ad_click_id = v_click.id where install_id = new.install_id;
    end if;
  end if;
  if new.source = 'ads' or v_click.id is not null then
    insert into public.meta_events (event_name, event_id, install_id, user_id, fbc, fbp, ip, user_agent, external_id_sha256)
    values ('AppInstall', 'install-' || new.install_id, new.install_id, new.first_user_id, v_click.fbc, v_click.fbp,
            new.ip, coalesce(new.user_agent, v_click.user_agent),
            private.sha256(new.install_id::text))
    on conflict (event_id) do nothing;
  end if;
  return null;
end;
$$;
create trigger installs_meta after insert on public.installs
  for each row execute function private.on_install_created();

create or replace function private.user_click(p_uid uuid)
returns public.ad_clicks
language sql stable security definer set search_path = ''
as $$
  select c.* from public.install_users iu
  join public.installs i on i.install_id = iu.install_id
  join public.ad_clicks c on c.id = i.ad_click_id
  where iu.user_id = p_uid order by iu.first_seen limit 1;
$$;

-- Guest → real account.
create or replace function private.on_user_registered()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_click public.ad_clicks; v_src text;
begin
  if new.email is not null and not coalesce(new.is_anonymous, false)
     and (coalesce(old.is_anonymous, false) or old.email is null) then
    select source into v_src from public.profiles where id = new.id;
    v_click := private.user_click(new.id);
    insert into public.meta_events (event_name, event_id, user_id, fbc, fbp, ip, user_agent, email_sha256, external_id_sha256)
    values ('CompleteRegistration', 'reg-' || new.id, new.id, v_click.fbc, v_click.fbp, v_click.ip, v_click.user_agent,
            private.sha256(new.email), private.sha256(new.id::text))
    on conflict (event_id) do nothing;
  end if;
  return null;
end;
$$;
create trigger on_auth_user_registered after update of email, is_anonymous on auth.users
  for each row execute function private.on_user_registered();

-- Successful payment → Purchase (value INR, event_id = order id).
create or replace function private.on_payment_success()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_click public.ad_clicks; v_email text;
begin
  if new.status = 'success' and old.status is distinct from 'success' and new.user_id is not null then
    v_click := private.user_click(new.user_id);
    select email into v_email from auth.users where id = new.user_id;
    insert into public.meta_events (event_name, event_id, user_id, order_id, value, currency, fbc, fbp, ip, user_agent,
                                    email_sha256, external_id_sha256)
    values ('Purchase', new.id::text, new.user_id, new.id, round(new.amount_paise / 100.0, 2), 'INR',
            v_click.fbc, v_click.fbp, v_click.ip, v_click.user_agent, private.sha256(v_email), private.sha256(new.user_id::text))
    on conflict (event_id) do nothing;
  end if;
  return null;
end;
$$;
create trigger payment_orders_meta after update of status on public.payment_orders
  for each row execute function private.on_payment_success();

-- Dispatcher (pg_cron every minute): collect pg_net responses, then send pending events in batches.
create or replace function private.meta_dispatch()
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  cfg     private.meta_config%rowtype;
  v_pixel text;
  v_batch bigint[];
  v_data  jsonb;
  v_req   bigint;
  r       record;
begin
  -- 1) Settle earlier requests.
  for r in
    select e.id, h.status_code, h.content, h.error_msg
    from public.meta_events e join net._http_response h on h.id = e.request_id
    where e.status = 'sending'
  loop
    if r.status_code between 200 and 299 then
      update public.meta_events set status = 'sent', sent_at = now(), last_error = null where id = r.id;
    else
      update public.meta_events
         set status = case when attempts >= 5 then 'failed' else 'pending' end,
             last_error = left(coalesce(r.error_msg, r.content::text, 'HTTP ' || r.status_code), 1000)
       where id = r.id;
    end if;
  end loop;
  -- Requests with no response after 10 minutes are retried.
  update public.meta_events set status = 'pending', last_error = 'No response from Meta'
   where status = 'sending' and created_at < now() - interval '10 minutes'
     and not exists (select 1 from net._http_response h where h.id = request_id);

  select * into cfg from private.meta_config where id = 1;
  select meta_pixel_id into v_pixel from public.site_settings where id = 1;
  if not coalesce(cfg.enabled, false) or cfg.capi_token is null or v_pixel is null then return 0; end if;

  select array_agg(id) into v_batch from (
    select id from public.meta_events where status = 'pending' and attempts < 6 order by created_at limit 50
  ) s;
  if v_batch is null then return 0; end if;

  -- Test events and live events go in separate requests.
  for r in select distinct is_test from public.meta_events where id = any (v_batch) loop
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'event_name', e.event_name,
             'event_time', extract(epoch from e.event_time)::bigint,
             'event_id', e.event_id,
             'action_source', 'website',
             'event_source_url', (select rtrim(site_url, '/') || '/d' from public.site_settings where id = 1),
             'user_data', jsonb_strip_nulls(jsonb_build_object(
               'em', case when e.email_sha256 is not null then jsonb_build_array(e.email_sha256) end,
               'external_id', case when e.external_id_sha256 is not null then jsonb_build_array(e.external_id_sha256) end,
               'fbc', e.fbc, 'fbp', e.fbp,
               'client_ip_address', host(e.ip), 'client_user_agent', e.user_agent)),
             'custom_data', case when e.value is not null
                                 then jsonb_build_object('value', e.value, 'currency', e.currency, 'order_id', e.order_id) end
           )))
      into v_data
      from public.meta_events e where e.id = any (v_batch) and e.is_test = r.is_test;

    select net.http_post(
             url := 'https://graph.facebook.com/' || cfg.graph_version || '/' || v_pixel || '/events',
             body := jsonb_strip_nulls(jsonb_build_object(
                       'data', v_data, 'access_token', cfg.capi_token,
                       'test_event_code', case when r.is_test then cfg.test_event_code end)),
             headers := '{"Content-Type": "application/json"}'::jsonb,
             timeout_milliseconds := 15000)
      into v_req;

    update public.meta_events set status = 'sending', request_id = v_req, attempts = attempts + 1
     where id = any (v_batch) and is_test = r.is_test;
  end loop;
  return cardinality(v_batch);
end;
$$;

select cron.schedule('bytebox-meta-dispatch', '* * * * *', 'select private.meta_dispatch()');

-- ---------------------------------------------------------------------
-- Owner tools for the Meta page
-- ---------------------------------------------------------------------
create or replace function public.admin_meta_status()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare cfg private.meta_config%rowtype;
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  select * into cfg from private.meta_config where id = 1;
  return jsonb_build_object(
    'pixel_id', (select meta_pixel_id from public.site_settings where id = 1),
    'token_set', cfg.capi_token is not null,
    'token_hint', case when cfg.capi_token is not null then '…' || right(cfg.capi_token, 4) end,
    'test_event_code', cfg.test_event_code,
    'graph_version', cfg.graph_version,
    'enabled', cfg.enabled,
    'counts_24h', (select coalesce(jsonb_object_agg(status, n), '{}') from (
        select status, count(*) n from public.meta_events where created_at > now() - interval '24 hours' group by status) s),
    'by_event_7d', (select coalesce(jsonb_object_agg(event_name, n), '{}') from (
        select event_name, count(*) n from public.meta_events
        where status = 'sent' and created_at > now() - interval '7 days' and not is_test group by event_name) s),
    'last_sent_at', (select max(sent_at) from public.meta_events where status = 'sent'),
    'last_error', (select last_error from public.meta_events where last_error is not null order by created_at desc limit 1),
    'clicks_24h', (select count(*) from public.ad_clicks where created_at > now() - interval '24 hours'),
    'matched_installs_7d', (select count(*) from public.installs where ad_click_id is not null and created_at > now() - interval '7 days')
  );
end;
$$;

create or replace function public.admin_meta_configure(
  p_pixel_id text, p_token text, p_test_event_code text, p_graph_version text, p_enabled boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  update public.site_settings set meta_pixel_id = nullif(btrim(p_pixel_id), ''), updated_at = now() where id = 1;
  update private.meta_config
     set capi_token = coalesce(nullif(btrim(p_token), ''), capi_token),
         test_event_code = nullif(btrim(p_test_event_code), ''),
         graph_version = coalesce(nullif(btrim(p_graph_version), ''), graph_version),
         enabled = coalesce(p_enabled, enabled)
   where id = 1;
end;
$$;

create or replace function public.admin_meta_test_event()
returns text
language plpgsql security definer set search_path = ''
as $$
declare v_id text := 'test-' || extract(epoch from now())::bigint;
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  if (select test_event_code from private.meta_config where id = 1) is null then
    raise exception 'Add the Test Event Code from Events Manager first';
  end if;
  insert into public.meta_events (event_name, event_id, is_test, value, currency, external_id_sha256, ip, user_agent)
  values ('Purchase', v_id, true, 49, 'INR', private.sha256(auth.uid()::text), private.request_ip(), private.request_user_agent());
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Grants: website helpers are callable without signing in.
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.webhook_payment(text, text, bigint) from authenticated;
grant execute on function public.is_admin(), public.is_owner(),
  public.submit_deletion_request(text, text, text), public.submit_web_report(text, text, text, text),
  public.public_post_preview(uuid), public.record_ad_click(text, text, text) to anon;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on public.ad_clicks, public.meta_events, public.deletion_requests from anon;
revoke execute on all functions in schema private from public, anon, authenticated;

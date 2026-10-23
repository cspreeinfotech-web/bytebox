-- =====================================================================
-- Bytebox · Stage 9 · Google Play: User Choice Billing (India), prepared
-- but OFF (app_mode.play_billing_enabled = false).
-- =====================================================================

alter table public.plans add column play_product_id text unique;
update public.plans set play_product_id = 'bytebox_' || code;

create table public.play_purchases (
  purchase_token  text primary key,
  user_id         uuid references auth.users (id) on delete set null,
  order_id        uuid references public.payment_orders (id) on delete set null,
  product_id      text not null,
  google_order_id text,
  state           text not null check (state in ('purchased', 'pending', 'cancelled')),
  raw             jsonb,
  created_at      timestamptz not null default now()
);
alter table public.play_purchases enable row level security;
create policy play_purchases_owner on public.play_purchases for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_owner()));
revoke insert, update, delete, truncate on public.play_purchases from anon, authenticated;

create table public.play_external_reports (
  order_id                 uuid primary key references public.payment_orders (id) on delete cascade,
  external_transaction_id  text not null unique,
  external_transaction_token text,
  status                   text not null default 'pending' check (status in ('pending', 'reported', 'failed')),
  last_error               text,
  reported_at              timestamptz,
  created_at               timestamptz not null default now()
);
alter table public.play_external_reports enable row level security;
create policy play_external_reports_owner on public.play_external_reports for select to authenticated
  using ((select public.is_owner()));
revoke insert, update, delete, truncate on public.play_external_reports from anon, authenticated;

create or replace function public.is_play_billing_enabled()
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce((select play_billing_enabled from public.app_mode where id = 1), false); $$;

-- Called only by Edge Function play-verify (service role) after Google confirms the purchase.
create or replace function public.play_activate(
  p_user_id uuid, p_product_id text, p_purchase_token text, p_google_order_id text, p_raw jsonb)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_plan public.plans%rowtype;
  v_order uuid;
begin
  if not public.is_play_billing_enabled() then raise exception 'Google Play billing is off'; end if;
  select * into v_plan from public.plans where play_product_id = p_product_id;
  if not found then raise exception 'Unknown product'; end if;
  if exists (select 1 from public.play_purchases where purchase_token = p_purchase_token and order_id is not null) then
    return 'success'; -- idempotent
  end if;
  insert into public.payment_orders (user_id, plan_code, plan_name, duration_days, amount_paise, reference, channel, status)
  values (p_user_id, v_plan.code, v_plan.name, v_plan.duration_days, v_plan.price_inr::bigint * 100,
          'BB' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD') || upper(encode(extensions.gen_random_bytes(6), 'hex')),
          'play', 'initiated')
  returning id into v_order;
  insert into public.play_purchases (purchase_token, user_id, order_id, product_id, google_order_id, state, raw)
  values (p_purchase_token, p_user_id, v_order, p_product_id, p_google_order_id, 'purchased', p_raw)
  on conflict (purchase_token) do update set order_id = excluded.order_id, state = 'purchased', raw = excluded.raw;
  -- Google order ids are like GPA.1234-5678-9012-34567 → use as the unique UTR without punctuation.
  return private.activate_payment(v_order, upper(regexp_replace(coalesce(p_google_order_id, p_purchase_token), '[^A-Za-z0-9]', '', 'g')) , 'webhook');
end;
$$;

-- UPI payments made from the Play build under User Choice Billing must be reported to Google.
create or replace function public.play_queue_external_report(p_order_id uuid, p_token text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_play_billing_enabled() then return; end if;
  if not exists (select 1 from public.payment_orders where id = p_order_id and user_id = auth.uid()) then
    raise exception 'Order not found';
  end if;
  insert into public.play_external_reports (order_id, external_transaction_id, external_transaction_token)
  values (p_order_id, replace(p_order_id::text, '-', ''), left(p_token, 2000))
  on conflict (order_id) do update set external_transaction_token = coalesce(excluded.external_transaction_token,
                                                                             public.play_external_reports.external_transaction_token);
end;
$$;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.webhook_payment(text, text, bigint), public.play_activate(uuid, text, text, text, jsonb)
  from authenticated;
grant execute on function public.webhook_payment(text, text, bigint), public.play_activate(uuid, text, text, text, jsonb)
  to service_role;
grant execute on function public.is_admin(), public.is_owner(),
  public.submit_deletion_request(text, text, text), public.submit_web_report(text, text, text, text),
  public.public_post_preview(uuid), public.record_ad_click(text, text, text) to anon;

-- =====================================================================
-- Bytebox · Admin live controls: plans, UPI and free access.
-- The app only shows what these functions return; nothing is hard-coded.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Data model
-- ---------------------------------------------------------------------
alter table public.plans add column free_eligible boolean not null default true;

-- code is read-only after create
create or replace function private.plans_code_immutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.code is distinct from old.code then raise exception 'Plan code cannot be changed'; end if;
  return new;
end;
$$;
create trigger plans_code_immutable before update on public.plans
  for each row execute function private.plans_code_immutable();

alter table public.payment_settings add column updated_by uuid references auth.users (id) on delete set null;

alter table public.app_mode drop column if exists updated_by;
alter table public.app_mode add column free_plans_for text not null default 'none'
  check (free_plans_for in ('none', 'organic', 'ads', 'everyone'));
alter table public.app_mode add column promo_id uuid;

alter table public.payment_orders drop constraint if exists payment_orders_amount_paise_check;
alter table public.payment_orders add constraint payment_orders_amount_paise_check check (amount_paise >= 0);
alter table public.payment_orders drop constraint if exists payment_orders_activated_by_check;
alter table public.payment_orders add constraint payment_orders_activated_by_check
  check (activated_by in ('auto', 'owner', 'webhook', 'free'));
alter table public.payment_orders
  add column plan_id bigint references public.plans (id),
  add column upi_id_used text,
  add column payee_used text,
  add column price_inr_at_order int,
  add column duration_days_at_order int,
  add column promo_id uuid,
  add column source text not null default 'upi_app'
    check (source in ('upi_app', 'admin', 'provider_api', 'free_promo'));

update public.payment_orders o
   set price_inr_at_order = o.amount_paise / 100,
       duration_days_at_order = o.duration_days,
       plan_id = (select p.id from public.plans p where p.code = o.plan_code),
       upi_id_used = (select upi_id from public.payment_settings where id = 1),
       payee_used = (select payee_name from public.payment_settings where id = 1),
       source = case o.activated_by when 'owner' then 'admin' when 'webhook' then 'provider_api' else 'upi_app' end;

-- One free claim per user per plan per promotion.
create unique index payment_orders_one_free_claim on public.payment_orders (user_id, plan_id, promo_id)
  where source = 'free_promo';
create index payment_orders_source_idx on public.payment_orders (source, created_at desc);

-- Keep `source` truthful when an order is activated by the owner or a provider.
create or replace function private.order_source_from_activation()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'success' and old.status is distinct from 'success' and new.source <> 'free_promo' then
    new.source := case new.activated_by when 'owner' then 'admin' when 'webhook' then 'provider_api' else new.source end;
  end if;
  return new;
end;
$$;
create trigger payment_orders_source before update of status on public.payment_orders
  for each row execute function private.order_source_from_activation();

-- ---------------------------------------------------------------------
-- Audit: one row per changed field on plans, payment_settings, app_mode
-- ---------------------------------------------------------------------
create table public.settings_audit (
  id         bigint generated always as identity primary key,
  table_name text not null,
  record     text,
  field      text not null,
  old_value  text,
  new_value  text,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now()
);
alter table public.settings_audit enable row level security;
create index settings_audit_changed_idx on public.settings_audit (changed_at desc);
create policy settings_audit_owner on public.settings_audit for select to authenticated using ((select public.is_owner()));
revoke insert, update, delete, truncate on public.settings_audit from anon, authenticated;

create or replace function private.audit_settings()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  o jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else to_jsonb(old) end;
  n jsonb := to_jsonb(new);
  k text;
  rec text := case tg_table_name when 'plans' then n ->> 'code' else tg_table_name end;
begin
  for k in select jsonb_object_keys(n) loop
    continue when k in ('updated_at', 'updated_by', 'created_at', 'id');
    if (o -> k) is distinct from (n -> k) then
      insert into public.settings_audit (table_name, record, field, old_value, new_value, changed_by)
      values (tg_table_name, rec, k,
              case when o ? k then o ->> k end, n ->> k, auth.uid());
    end if;
  end loop;
  return null;
end;
$$;
create trigger plans_audit after insert or update on public.plans
  for each row execute function private.audit_settings();
create trigger payment_settings_audit after update on public.payment_settings
  for each row execute function private.audit_settings();
create trigger app_mode_audit after update on public.app_mode
  for each row execute function private.audit_settings();

-- Public "something changed" signal for Realtime (the app cannot read payment_settings).
create table public.settings_version (
  id         int primary key default 1 check (id = 1),
  version    bigint not null default 1,
  changed_at timestamptz not null default now()
);
insert into public.settings_version (id) values (1);
alter table public.settings_version enable row level security;
create policy settings_version_read on public.settings_version for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.settings_version from anon, authenticated;

create or replace function private.bump_settings_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.settings_version set version = version + 1, changed_at = now() where id = 1;
  return null;
end;
$$;
create trigger plans_bump after insert or update on public.plans
  for each statement execute function private.bump_settings_version();
create trigger payment_settings_bump after update on public.payment_settings
  for each statement execute function private.bump_settings_version();
create trigger app_mode_bump after update on public.app_mode
  for each statement execute function private.bump_settings_version();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.settings_version;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Server functions
-- ---------------------------------------------------------------------
create or replace function public.source_of(p_uid uuid default auth.uid())
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select source from public.profiles where id = p_uid), 'organic');
$$;

create or replace function public.payments_available()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select s.enabled and s.upi_id is not null and nullif(btrim(s.payee_name), '') is not null
                   from public.payment_settings s where s.id = 1), false)
     and not public.is_free_mode();
$$;

create or replace function public.free_plans_for()
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select free_plans_for from public.app_mode where id = 1), 'none');
$$;

create or replace function public.is_plan_free_for(p_plan public.plans, p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select p_plan.free_eligible and case public.free_plans_for()
    when 'everyone' then true
    when 'organic'  then public.source_of(p_uid) = 'organic'
    when 'ads'      then public.source_of(p_uid) = 'ads'
    else false end;
$$;

create or replace function private.duration_label(p_days int)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_days % 365 = 0 then case when p_days = 365 then '1 year' else (p_days / 365) || ' years' end
    when p_days = 180 then '6 months'
    when p_days % 30 = 0 then case when p_days = 30 then '1 month' else (p_days / 30) || ' months' end
    when p_days % 7 = 0 then case when p_days = 7 then '1 week' else (p_days / 7) || ' weeks' end
    else p_days || ' days' end;
$$;

create or replace function public.plans_for_me()
returns table (id bigint, code text, name text, price_inr int, duration_days int, duration_label text, perks text[],
               badge text, "position" int, free_for_me boolean, pay_mode text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.code, p.name, p.price_inr, p.duration_days, private.duration_label(p.duration_days), p.perks,
         p.badge, p.position, public.is_plan_free_for(p),
         case when public.is_plan_free_for(p) then 'free'
              when public.payments_available() then 'upi'
              else 'unavailable' end
  from public.plans p
  where p.active
  order by p.position, p.id;
$$;

-- my_status v3: + free_plans_for, payments_available, plan source
create or replace function public.my_status()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'user_id', p.id,
    'display_name', p.display_name,
    'is_guest', not public.is_logged_in(),
    'email', (select u.email from auth.users u where u.id = p.id),
    'source', p.source,
    'ads_access_status', p.ads_access_status,
    'has_ads_access', public.has_ads_access(p.id),
    'admin_role', public.admin_role(p.id),
    'free_mode', public.is_free_mode(),
    'free_plans_for', public.free_plans_for(),
    'payments_available', public.payments_available(),
    'is_premium', public.is_premium_user(p.id),
    'plan', (select jsonb_build_object('code', s.plan_code, 'name', s.plan_name, 'ends_at', s.ends_at,
                                       'source', (select o.source from public.payment_orders o where o.id = s.last_order_id))
             from public.subscriptions s where s.user_id = p.id and s.ends_at > now()),
    'open_order', (select private.order_json(o.id) from public.payment_orders o
                   where o.user_id = p.id and o.status in ('initiated', 'pending')
                     and o.created_at > now() - interval '24 hours'
                   order by o.created_at desc limit 1),
    'quota_bytes', public.quota_bytes(p.id),
    'used_bytes', public.cloud_used_bytes(p.id),
    'owns_approved_channel', exists (select 1 from public.channels c where c.owner_id = p.id
                                     and c.review_status = 'approved' and c.publish_state = 'active')
  )
  from public.profiles p where p.id = (select auth.uid());
$$;

create or replace function private.order_json(p_order_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('order_id', o.id, 'reference', o.reference, 'status', o.status,
    'plan_id', o.plan_id, 'plan_code', o.plan_code, 'plan_name', o.plan_name,
    'amount', to_char(o.amount_paise / 100.0, 'FM999999990.00'),
    'duration_days', o.duration_days, 'source', o.source,
    'reason', o.reason, 'paid_at', o.paid_at, 'created_at', o.created_at)
  from public.payment_orders o where o.id = p_order_id;
$$;

-- Orders snapshot price, duration and the UPI account at order time.
create or replace function public.create_payment_order(p_plan_id bigint)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_plan public.plans%rowtype;
  v_set  public.payment_settings%rowtype;
  v_ord  public.payment_orders%rowtype;
  v_reused boolean := false;
begin
  if not public.is_logged_in() then raise exception 'Please log in to buy a plan'; end if;
  if public.is_free_mode() then raise exception 'Plans are free right now'; end if;
  select * into v_plan from public.plans where id = p_plan_id and active;
  if not found then raise exception 'This plan is not available'; end if;
  if public.is_plan_free_for(v_plan, v_uid) then
    raise exception 'This plan is free for you — tap Activate for free';
  end if;
  if not public.payments_available() then raise exception 'Payments are not available right now'; end if;
  select * into v_set from public.payment_settings where id = 1;

  perform pg_advisory_xact_lock(hashtext('bytebox-order-' || v_uid::text));

  select * into v_ord from public.payment_orders
   where user_id = v_uid and plan_id = v_plan.id and status in ('initiated', 'pending') and source = 'upi_app'
     and created_at > now() - interval '24 hours'
   order by created_at desc limit 1;

  if found and v_ord.amount_paise = v_plan.price_inr::bigint * 100 and v_ord.duration_days = v_plan.duration_days
     and v_ord.upi_id_used is not distinct from v_set.upi_id then
    v_reused := true;
  else
    if found and v_ord.status = 'initiated' then
      update public.payment_orders set status = 'cancelled', reason = 'Plan or UPI details changed', updated_at = now()
       where id = v_ord.id;
    end if;
    insert into public.payment_orders (user_id, plan_id, plan_code, plan_name, duration_days, amount_paise, reference,
                                       upi_id_used, payee_used, price_inr_at_order, duration_days_at_order, source)
    values (v_uid, v_plan.id, v_plan.code, v_plan.name, v_plan.duration_days, v_plan.price_inr::bigint * 100,
            'BB' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD') || upper(encode(extensions.gen_random_bytes(6), 'hex')),
            v_set.upi_id, v_set.payee_name, v_plan.price_inr, v_plan.duration_days, 'upi_app')
    returning * into v_ord;
  end if;

  update public.payment_orders set status = 'cancelled', reason = 'Replaced by a newer order', updated_at = now()
   where user_id = v_uid and id <> v_ord.id and status = 'initiated';

  return jsonb_build_object(
    'order_id', v_ord.id, 'reference', v_ord.reference, 'status', v_ord.status, 'reused', v_reused,
    'plan_id', v_plan.id, 'plan_code', v_ord.plan_code, 'plan_name', v_ord.plan_name,
    'amount', to_char(v_ord.amount_paise / 100.0, 'FM999999990.00'),
    'amount_paise', v_ord.amount_paise, 'price_inr', v_ord.price_inr_at_order,
    'duration_days', v_ord.duration_days,
    'upi_id', v_ord.upi_id_used, 'payee_name', v_ord.payee_used);
end;
$$;

-- Older app builds call create_payment_order(code).
create or replace function public.create_payment_order(p_plan_code text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_id bigint;
begin
  select id into v_id from public.plans where code = p_plan_code;
  if v_id is null then raise exception 'This plan is not available'; end if;
  return public.create_payment_order(v_id);
end;
$$;

-- Free plan claim (promotion).
create or replace function public.claim_free_plan(p_plan_id bigint)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_plan  public.plans%rowtype;
  v_promo uuid;
  v_ord   uuid;
  v_ends  timestamptz;
begin
  if not public.is_logged_in() then raise exception 'Please log in to activate a plan'; end if;
  select * into v_plan from public.plans where id = p_plan_id and active;
  if not found then raise exception 'This plan is not available'; end if;
  if not public.is_plan_free_for(v_plan, v_uid) then raise exception 'This plan is not free for you'; end if;
  if public.has_active_plan(v_uid) then raise exception 'You already have an active plan'; end if;
  select promo_id into v_promo from public.app_mode where id = 1;

  perform pg_advisory_xact_lock(hashtext('bytebox-claim-' || v_uid::text));
  if exists (select 1 from public.payment_orders where user_id = v_uid and plan_id = v_plan.id
             and promo_id is not distinct from v_promo and source = 'free_promo') then
    raise exception 'You already claimed this free plan';
  end if;

  insert into public.payment_orders (user_id, plan_id, plan_code, plan_name, duration_days, amount_paise, reference, status,
                                     activated_by, paid_at, price_inr_at_order, duration_days_at_order, promo_id, source)
  values (v_uid, v_plan.id, v_plan.code, v_plan.name, v_plan.duration_days, 0,
          'BB' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD') || upper(encode(extensions.gen_random_bytes(6), 'hex')),
          'success', 'free', now(), v_plan.price_inr, v_plan.duration_days, v_promo, 'free_promo')
  returning id into v_ord;

  insert into public.subscriptions as s (user_id, plan_code, plan_name, started_at, ends_at, last_order_id)
  values (v_uid, v_plan.code, v_plan.name, now(), now() + make_interval(days => v_plan.duration_days), v_ord)
  on conflict (user_id) do update
     set plan_code = excluded.plan_code, plan_name = excluded.plan_name, last_order_id = excluded.last_order_id,
         started_at = case when s.ends_at > now() then s.started_at else now() end,
         ends_at = greatest(now(), s.ends_at) + make_interval(days => v_plan.duration_days),
         updated_at = now()
  returning ends_at into v_ends;

  -- Same approval rule as a paid purchase: organic users are queued, ads users need none.
  update public.profiles
     set ads_access_status = 'pending', ads_access_requested_at = now(), updated_at = now()
   where id = v_uid and coalesce(source, 'organic') = 'organic' and ads_access_status = 'none';

  return jsonb_build_object('order_id', v_ord, 'plan_name', v_plan.name, 'ends_at', v_ends, 'status', 'success');
end;
$$;

-- ---------------------------------------------------------------------
-- Owner functions (validated; audit rows come from the triggers)
-- ---------------------------------------------------------------------
create or replace function private.require_owner()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
end;
$$;

create or replace function private.validate_plan(p_name text, p_price int, p_days int)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if char_length(btrim(coalesce(p_name, ''))) < 2 then raise exception 'Plan name is required'; end if;
  if coalesce(p_price, 0) < 1 then raise exception 'Price must be at least ₹1'; end if;
  if coalesce(p_days, 0) < 1 then raise exception 'Duration must be at least 1 day'; end if;
end;
$$;

create or replace function public.admin_update_plan(
  p_plan_id bigint, p_name text, p_price_inr int, p_duration_days int, p_perks text[], p_badge text,
  p_position int, p_active boolean, p_free_eligible boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  perform private.validate_plan(p_name, p_price_inr, p_duration_days);
  update public.plans
     set name = btrim(p_name), price_inr = p_price_inr, duration_days = p_duration_days,
         perks = coalesce(array_remove(p_perks, ''), '{}'), badge = nullif(btrim(p_badge), ''),
         position = coalesce(p_position, 0), active = coalesce(p_active, true),
         free_eligible = coalesce(p_free_eligible, true), updated_at = now()
   where id = p_plan_id;
  if not found then raise exception 'Plan not found'; end if;
end;
$$;

create or replace function public.admin_create_plan(
  p_code text, p_name text, p_price_inr int, p_duration_days int, p_perks text[], p_badge text,
  p_position int, p_active boolean, p_free_eligible boolean)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform private.require_owner();
  perform private.validate_plan(p_name, p_price_inr, p_duration_days);
  if lower(btrim(coalesce(p_code, ''))) !~ '^[a-z0-9_-]{2,30}$' then
    raise exception 'Code: 2–30 lowercase letters, numbers, - or _';
  end if;
  insert into public.plans (code, name, price_inr, duration_days, perks, badge, position, active, free_eligible, play_product_id)
  values (lower(btrim(p_code)), btrim(p_name), p_price_inr, p_duration_days, coalesce(array_remove(p_perks, ''), '{}'),
          nullif(btrim(p_badge), ''), coalesce(p_position, 0), coalesce(p_active, true), coalesce(p_free_eligible, true),
          'bytebox_' || lower(btrim(p_code)))
  returning id into v_id;
  return v_id;
exception when unique_violation then raise exception 'A plan with this code already exists';
end;
$$;

create or replace function public.admin_set_upi(p_upi_id text, p_payee_name text, p_enabled boolean, p_activation_mode text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  if btrim(coalesce(p_upi_id, '')) !~ '^[A-Za-z0-9._-]{2,200}@[A-Za-z0-9.-]{2,64}$' then
    raise exception 'UPI ID must look like name@bank';
  end if;
  if char_length(btrim(coalesce(p_payee_name, ''))) < 2 then raise exception 'Payee name is required'; end if;
  if p_activation_mode not in ('instant', 'manual') then raise exception 'Activation mode must be instant or manual'; end if;
  update public.payment_settings
     set upi_id = btrim(p_upi_id), payee_name = btrim(p_payee_name), enabled = coalesce(p_enabled, true),
         activation_mode = p_activation_mode, updated_by = auth.uid(), updated_at = now()
   where id = 1;
end;
$$;

create or replace function public.admin_clear_upi()
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  update public.payment_settings set upi_id = null, payee_name = null, updated_by = auth.uid(), updated_at = now()
   where id = 1;
end;
$$;

create or replace function public.admin_set_free_mode(p_on boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  update public.app_mode set free_mode = coalesce(p_on, false), updated_at = now() where id = 1;
end;
$$;

-- Switching free plans on (from Off) starts a new promotion: everyone may claim once again.
create or replace function public.admin_set_free_plans(p_for text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old text;
begin
  perform private.require_owner();
  if p_for not in ('none', 'organic', 'ads', 'everyone') then raise exception 'Invalid free plans setting'; end if;
  select free_plans_for into v_old from public.app_mode where id = 1;
  update public.app_mode
     set free_plans_for = p_for,
         promo_id = case when p_for <> 'none' and v_old = 'none' then gen_random_uuid() else promo_id end,
         updated_at = now()
   where id = 1;
end;
$$;

create or replace function public.admin_payment_settings()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s public.payment_settings%rowtype;
begin
  perform private.require_owner();
  select * into s from public.payment_settings where id = 1;
  return jsonb_build_object('upi_id', s.upi_id, 'payee_name', s.payee_name, 'enabled', s.enabled,
    'activation_mode', s.activation_mode, 'updated_at', s.updated_at,
    'updated_by_email', (select email from auth.users where id = s.updated_by),
    'live', public.payments_available());
end;
$$;

create or replace function public.admin_free_claims()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_promo uuid;
begin
  perform private.require_owner();
  select promo_id into v_promo from public.app_mode where id = 1;
  return jsonb_build_object(
    'promo_id', v_promo,
    'organic', (select count(*) from public.payment_orders o join public.profiles p on p.id = o.user_id
                where o.source = 'free_promo' and o.promo_id is not distinct from v_promo and coalesce(p.source, 'organic') = 'organic'),
    'ads', (select count(*) from public.payment_orders o join public.profiles p on p.id = o.user_id
            where o.source = 'free_promo' and o.promo_id is not distinct from v_promo and p.source = 'ads'));
end;
$$;

create or replace function public.admin_settings_history(p_limit int default 100)
returns table (table_name text, record text, field text, old_value text, new_value text, changed_by_email text,
               changed_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_owner();
  return query
    select a.table_name, a.record, a.field, a.old_value, a.new_value, u.email::text, a.changed_at
    from public.settings_audit a left join auth.users u on u.id = a.changed_by
    order by a.changed_at desc, a.id desc
    limit least(greatest(p_limit, 1), 500);
end;
$$;

-- Admin listings, extended
drop function if exists public.admin_payments(text, text, int, int);
create or replace function public.admin_payments(
  p_filter text default 'all', p_search text default null, p_limit int default 50, p_offset int default 0,
  p_source text default null, p_user_type text default null)
returns table (id uuid, reference text, user_id uuid, email text, user_source text, plan_name text, amount_paise bigint,
               price_inr_at_order int, duration_days_at_order int, upi_id_used text, source text, status text,
               utr text, client_status text, reason text, activated_by text, created_at timestamptz,
               paid_at timestamptz, total bigint)
language plpgsql stable security definer set search_path = ''
as $$
declare v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  perform private.require_owner();
  return query
    select o.id, o.reference, o.user_id, u.email::text, coalesce(p.source, 'organic'), o.plan_name, o.amount_paise,
           o.price_inr_at_order, o.duration_days_at_order, o.upi_id_used, o.source, o.status, o.utr,
           o.client_status, o.reason, o.activated_by, o.created_at, o.paid_at, count(*) over ()
    from public.payment_orders o
    left join auth.users u on u.id = o.user_id
    left join public.profiles p on p.id = o.user_id
    where case p_filter
            when 'activated_today' then o.status = 'success' and o.paid_at >= v_today and o.source <> 'free_promo'
            when 'pending' then o.status = 'pending'
            when 'open'    then o.status in ('initiated', 'pending')
            when 'success' then o.status = 'success'
            when 'revoked' then o.status = 'revoked'
            else true end
      and (p_source is null or o.source = p_source)
      and (p_user_type is null or coalesce(p.source, 'organic') = p_user_type)
      and (nullif(btrim(p_search), '') is null
           or o.reference ilike '%' || btrim(p_search) || '%'
           or o.utr ilike '%' || btrim(p_search) || '%'
           or u.email ilike '%' || btrim(p_search) || '%')
    order by coalesce(o.paid_at, o.created_at) desc
    limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0);
end;
$$;

drop function if exists public.admin_users(text, text, int, int);
create or replace function public.admin_users(
  p_search text default null, p_filter text default 'all', p_limit int default 50, p_offset int default 0)
returns table (id uuid, email text, display_name text, source text, ads_access_status text, is_guest boolean,
               plan_name text, plan_ends_at timestamptz, plan_source text, admin_role text, created_at timestamptz,
               total bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform private.require_owner();
  return query
    with base as (
      select p.id, u.email::text as email, p.display_name, coalesce(p.source, 'organic') as source,
             p.ads_access_status, coalesce(u.is_anonymous, false) as is_guest,
             s.plan_name, s.ends_at, (select o.source from public.payment_orders o where o.id = s.last_order_id) as plan_source,
             a.role, p.created_at
      from public.profiles p
      join auth.users u on u.id = p.id
      left join public.subscriptions s on s.user_id = p.id and s.ends_at > now()
      left join public.admins a on a.user_id = p.id
      where (nullif(btrim(p_search), '') is null
             or u.email ilike '%' || btrim(p_search) || '%'
             or p.display_name ilike '%' || btrim(p_search) || '%'
             or p.id::text = btrim(p_search))
        and case p_filter
              when 'members' then coalesce(u.is_anonymous, false) = false
              when 'guests'  then coalesce(u.is_anonymous, false)
              when 'ads'     then p.source = 'ads'
              when 'organic' then coalesce(p.source, 'organic') = 'organic'
              when 'premium' then s.user_id is not null
              else true end
    )
    select b.*, count(*) over () from base b
    order by b.created_at desc
    limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0);
end;
$$;

-- Dashboard: + month revenue, free claims, mode badges
create or replace function public.admin_dashboard()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v jsonb;
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v_month timestamptz := date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  v := jsonb_build_object(
    'pending_channels', (select count(*) from public.channels where review_status = 'pending'),
    'open_reports',     (select count(*) from public.reports where status = 'open'),
    'channels',         (select count(*) from public.channels where review_status = 'approved'),
    'posts',            (select count(*) from public.posts where status = 'published'),
    'free_mode',        public.is_free_mode(),
    'free_plans_for',   public.free_plans_for(),
    'payments_live',    public.payments_available()
  );
  if public.is_owner() then
    v := v || jsonb_build_object(
      'users',            (select count(*) from auth.users where coalesce(is_anonymous, false) = false),
      'guests',           (select count(*) from auth.users where coalesce(is_anonymous, false)),
      'ads_users',        (select count(*) from public.profiles where source = 'ads'),
      'organic_users',    (select count(*) from public.profiles where coalesce(source, 'organic') = 'organic'),
      'installs_today',   (select count(*) from public.installs where created_at >= v_today),
      'active_premium',   (select count(*) from public.subscriptions where ends_at > now()),
      'pending_requests', (select count(*) from public.profiles where ads_access_status = 'pending'),
      'pending_payments', (select count(*) from public.payment_orders where status = 'pending'),
      'activated_today',  (select count(*) from public.payment_orders
                           where status = 'success' and paid_at >= v_today and source <> 'free_promo'),
      'revenue_today_paise', (select coalesce(sum(amount_paise), 0) from public.payment_orders
                              where status = 'success' and paid_at >= v_today),
      'revenue_month_paise', (select coalesce(sum(amount_paise), 0) from public.payment_orders
                              where status = 'success' and paid_at >= v_month),
      'revenue_30d_paise',   (select coalesce(sum(amount_paise), 0) from public.payment_orders
                              where status = 'success' and paid_at >= now() - interval '30 days')
    ) || jsonb_build_object('free_claims', public.admin_free_claims());
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.webhook_payment(text, text, bigint), public.play_activate(uuid, text, text, text, jsonb)
  from authenticated;
grant execute on function public.webhook_payment(text, text, bigint), public.play_activate(uuid, text, text, text, jsonb)
  to service_role;
grant execute on function public.is_admin(), public.is_owner(),
  public.submit_deletion_request(text, text, text), public.submit_web_report(text, text, text, text),
  public.public_post_preview(uuid), public.record_ad_click(text, text, text) to anon;
revoke execute on all functions in schema private from public, anon, authenticated;

-- =====================================================================
-- Bytebox · Stage 3 · App mode (free mode), plans, UPI payments with
-- instant activation + owner safeguards, subscriptions, cloud storage.
-- =====================================================================

create extension if not exists pg_cron;

-- ---------------------------------------------------------------------
-- App mode (singleton). Readable by everyone, owner writes. Realtime.
-- ---------------------------------------------------------------------
create table public.app_mode (
  id                   int primary key default 1 check (id = 1),
  free_mode            boolean not null default false,   -- START_MODE = PAID
  play_billing_enabled boolean not null default false,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references auth.users (id) on delete set null
);
insert into public.app_mode (id, free_mode) values (1, false);
alter table public.app_mode enable row level security;
create policy app_mode_read on public.app_mode for select to anon, authenticated using (true);
create policy app_mode_owner_update on public.app_mode for update to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));
revoke insert, delete, truncate on public.app_mode from anon, authenticated;

create or replace function public.is_free_mode()
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce((select free_mode from public.app_mode where id = 1), false); $$;

-- ---------------------------------------------------------------------
-- Plans
-- ---------------------------------------------------------------------
create table public.plans (
  id            bigint generated always as identity primary key,
  code          text not null unique check (code ~ '^[a-z0-9_-]{2,30}$'),
  name          text not null check (char_length(name) between 2 and 40),
  price_inr     int not null check (price_inr between 1 and 100000),
  duration_days int not null check (duration_days between 1 and 3650),
  perks         text[] not null default '{}',
  active        boolean not null default true,
  position      int not null default 0,
  badge         text check (char_length(badge) <= 30),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table public.plans enable row level security;
create policy plans_read on public.plans for select to anon, authenticated
  using (active or (select public.is_admin()));
create policy plans_owner_insert on public.plans for insert to authenticated with check ((select public.is_owner()));
create policy plans_owner_update on public.plans for update to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));
revoke delete, truncate on public.plans from anon, authenticated;   -- never delete; deactivate instead

insert into public.plans (code, name, price_inr, duration_days, position, badge, perks) values
  ('trial',    'Trial',     49,   7, 1, null,         array['Full premium videos', '2 TB cloud storage', 'Downloads']),
  ('silver',   'Silver',   129,   7, 2, null,         array['Full premium videos', '2 TB cloud storage', 'Downloads']),
  ('gold',     'Gold',     259,  30, 3, 'Best value', array['Full premium videos', '2 TB cloud storage', 'Downloads']),
  ('platinum', 'Platinum', 599, 180, 4, null,         array['Full premium videos', '2 TB cloud storage', 'Downloads']),
  ('diamond',  'Diamond',  999, 365, 5, null,         array['Full premium videos', '2 TB cloud storage', 'Downloads']);

-- ---------------------------------------------------------------------
-- Subscriptions (one row per user; ends_at extends on every purchase)
-- ---------------------------------------------------------------------
create table public.subscriptions (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  plan_code     text not null,
  plan_name     text not null,
  started_at    timestamptz not null default now(),
  ends_at       timestamptz not null,
  last_order_id uuid,
  updated_at    timestamptz not null default now()
);
alter table public.subscriptions enable row level security;
create index subscriptions_active_idx on public.subscriptions (ends_at);
create policy subscriptions_select on public.subscriptions for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
revoke insert, update, delete, truncate on public.subscriptions from anon, authenticated;

create or replace function public.has_active_plan(p_uid uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.subscriptions s where s.user_id = p_uid and s.ends_at > now()); $$;

create or replace function private.is_real_user(p_uid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from auth.users u where u.id = p_uid and coalesce(u.is_anonymous, false) = false); $$;

-- Premium = active plan, OR free mode + logged in + ads access.
create or replace function public.is_premium_user(p_uid uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.has_active_plan(p_uid)
      or (public.is_free_mode() and private.is_real_user(p_uid) and public.has_ads_access(p_uid));
$$;

-- ---------------------------------------------------------------------
-- Full-access requests (organic users)
-- ---------------------------------------------------------------------
alter table public.profiles add column play_free_cloud boolean not null default false;

create or replace function public.request_full_access()
returns text
language plpgsql security definer set search_path = ''
as $$
declare v text;
begin
  if not public.is_logged_in() then raise exception 'Please log in first'; end if;
  update public.profiles
     set ads_access_status = 'pending', ads_access_requested_at = now(), updated_at = now()
   where id = auth.uid() and coalesce(source, 'organic') = 'organic' and ads_access_status in ('none', 'rejected')
  returning ads_access_status into v;
  return coalesce(v, (select ads_access_status from public.profiles where id = auth.uid()));
end;
$$;

create or replace function public.admin_set_access(p_user_id uuid, p_status text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  if p_status not in ('none', 'pending', 'approved', 'rejected') then raise exception 'Invalid status'; end if;
  update public.profiles set ads_access_status = p_status, ads_access_decided_at = now(), updated_at = now()
  where id = p_user_id;
end;
$$;

-- Play build: logged-in users get 15 GB free cloud.
create or replace function public.enable_play_free_cloud()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if public.is_logged_in() then
    update public.profiles set play_free_cloud = true, updated_at = now() where id = auth.uid() and not play_free_cloud;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Quota: 2 TB with plan; 15 GB in free mode or Play build; else 0.
-- ---------------------------------------------------------------------
create or replace function public.quota_bytes(p_uid uuid default auth.uid())
returns bigint
language sql stable security definer set search_path = ''
as $$
  select case
    when public.has_active_plan(p_uid) then 2199023255552
    when private.is_real_user(p_uid)
         and (public.is_free_mode() or coalesce((select play_free_cloud from public.profiles where id = p_uid), false))
      then 16106127360
    else 0
  end::bigint;
$$;

-- ---------------------------------------------------------------------
-- Payment settings (owner only)
-- ---------------------------------------------------------------------
create table public.payment_settings (
  id              int primary key default 1 check (id = 1),
  upi_id          text check (upi_id ~ '^[A-Za-z0-9._-]{2,200}@[A-Za-z0-9.-]{2,64}$'),
  payee_name      text check (char_length(payee_name) <= 100),
  enabled         boolean not null default true,
  activation_mode text not null default 'instant' check (activation_mode in ('instant', 'manual')),
  updated_at      timestamptz not null default now()
);
insert into public.payment_settings (id, upi_id, payee_name, enabled, activation_mode)
values (1, '2728412a@bandhan', 'Bytebox', true, 'instant');
alter table public.payment_settings enable row level security;
create policy payment_settings_owner_read on public.payment_settings for select to authenticated using ((select public.is_owner()));
create policy payment_settings_owner_update on public.payment_settings for update to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));
revoke insert, delete, truncate on public.payment_settings from anon, authenticated;

-- ---------------------------------------------------------------------
-- Payment orders
-- ---------------------------------------------------------------------
create table public.payment_orders (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users (id) on delete set null,   -- kept after account deletion
  plan_code       text not null,
  plan_name       text not null,
  duration_days   int not null,
  amount_paise    bigint not null check (amount_paise > 0),
  reference       text not null unique,
  status          text not null default 'initiated'
                  check (status in ('initiated', 'pending', 'success', 'failed', 'cancelled', 'revoked')),
  utr             text unique,
  client_status   text,
  raw_response    text,
  reason          text,
  activated_by    text check (activated_by in ('auto', 'owner', 'webhook')),
  channel         text not null default 'upi' check (channel in ('upi', 'play')),
  paid_at         timestamptz,
  revoked_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
alter table public.payment_orders enable row level security;
create index payment_orders_user_idx on public.payment_orders (user_id, created_at desc);
create index payment_orders_open_idx on public.payment_orders (created_at) where status in ('initiated', 'pending');
create index payment_orders_paid_idx on public.payment_orders (paid_at) where status = 'success';
create policy payment_orders_select on public.payment_orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_owner()));
revoke insert, update, delete, truncate on public.payment_orders from anon, authenticated;

create table public.blocked_txn_ids (
  utr        text primary key,
  reason     text,
  created_at timestamptz not null default now()
);
alter table public.blocked_txn_ids enable row level security;
create policy blocked_txn_owner on public.blocked_txn_ids for select to authenticated using ((select public.is_owner()));
revoke all on public.blocked_txn_ids from anon, authenticated;

create or replace function public.create_payment_order(p_plan_code text)
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
  if public.is_free_mode() then raise exception 'Plans are not needed right now'; end if;
  select * into v_set from public.payment_settings where id = 1;
  if not coalesce(v_set.enabled, false) or v_set.upi_id is null or v_set.payee_name is null then
    raise exception 'Payments are not available right now';
  end if;
  select * into v_plan from public.plans where code = p_plan_code and active;
  if not found then raise exception 'This plan is not available'; end if;

  perform pg_advisory_xact_lock(hashtext('bytebox-order-' || v_uid::text));

  select * into v_ord from public.payment_orders
   where user_id = v_uid and plan_code = v_plan.code and status in ('initiated', 'pending')
     and created_at > now() - interval '24 hours'
   order by created_at desc limit 1;

  if found then
    v_reused := true;
  else
    insert into public.payment_orders (user_id, plan_code, plan_name, duration_days, amount_paise, reference)
    values (v_uid, v_plan.code, v_plan.name, v_plan.duration_days, v_plan.price_inr::bigint * 100,
            'BB' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD')
                 || upper(encode(extensions.gen_random_bytes(6), 'hex')))
    returning * into v_ord;
  end if;

  update public.payment_orders set status = 'cancelled', reason = 'Replaced by a newer order', updated_at = now()
   where user_id = v_uid and id <> v_ord.id and status = 'initiated';

  return jsonb_build_object(
    'order_id', v_ord.id, 'reference', v_ord.reference, 'status', v_ord.status, 'reused', v_reused,
    'plan_code', v_ord.plan_code, 'plan_name', v_ord.plan_name,
    'amount', to_char(v_ord.amount_paise / 100.0, 'FM999999990.00'),
    'amount_paise', v_ord.amount_paise,
    'upi_id', v_set.upi_id, 'payee_name', v_set.payee_name);
end;
$$;

-- Activation core: lock, idempotent, amount check, UTR unique/not blocked, extend plan.
create or replace function private.activate_payment(
  p_order_id uuid, p_utr text, p_activated_by text, p_amount_paise bigint default null)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v public.payment_orders%rowtype;
  v_utr text := upper(btrim(p_utr));
begin
  select * into v from public.payment_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v.status = 'success' then return 'success'; end if;               -- idempotent
  if v.status not in ('initiated', 'pending', 'failed', 'cancelled') then
    raise exception 'Order cannot be activated from status %', v.status;
  end if;
  if p_amount_paise is not null and p_amount_paise <> v.amount_paise then
    raise exception 'Amount does not match the order';
  end if;
  if v_utr is null or v_utr !~ '^[A-Z0-9]{6,40}$' then raise exception 'Invalid transaction id'; end if;
  if exists (select 1 from public.blocked_txn_ids b where b.utr = v_utr) then
    raise exception 'This transaction id is blocked';
  end if;
  if exists (select 1 from public.payment_orders o where o.utr = v_utr and o.id <> v.id) then
    raise exception 'This transaction id was already used';
  end if;

  update public.payment_orders
     set status = 'success', utr = v_utr, activated_by = p_activated_by, paid_at = now(),
         reason = null, updated_at = now()
   where id = v.id;

  insert into public.subscriptions as s (user_id, plan_code, plan_name, started_at, ends_at, last_order_id)
  values (v.user_id, v.plan_code, v.plan_name, now(), now() + make_interval(days => v.duration_days), v.id)
  on conflict (user_id) do update
     set plan_code = excluded.plan_code, plan_name = excluded.plan_name, last_order_id = excluded.last_order_id,
         started_at = case when s.ends_at > now() then s.started_at else now() end,
         ends_at = greatest(now(), s.ends_at) + make_interval(days => v.duration_days),
         updated_at = now();

  -- Organic buyers are queued for ads-content approval; ads buyers need none.
  update public.profiles
     set ads_access_status = 'pending', ads_access_requested_at = now(), updated_at = now()
   where id = v.user_id and coalesce(source, 'organic') = 'organic' and ads_access_status = 'none';

  return 'success';
end;
$$;

create or replace function private.upi_param(p_raw text, p_key text)
returns text
language sql immutable set search_path = ''
as $$
  select nullif(btrim(split_part(kv, '=', 2)), '')
  from unnest(string_to_array(replace(coalesce(p_raw, ''), '?', '&'), '&')) kv
  where lower(btrim(split_part(kv, '=', 1))) = lower(p_key)
  limit 1;
$$;

create or replace function private.order_json(p_order_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('order_id', o.id, 'reference', o.reference, 'status', o.status,
    'plan_code', o.plan_code, 'plan_name', o.plan_name,
    'amount', to_char(o.amount_paise / 100.0, 'FM999999990.00'),
    'reason', o.reason, 'paid_at', o.paid_at, 'created_at', o.created_at)
  from public.payment_orders o where o.id = p_order_id;
$$;

-- Called by the app with the raw UPI intent response (also retried on next start).
create or replace function public.report_payment_result(p_order_id uuid, p_raw_response text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v       public.payment_orders%rowtype;
  v_mode  text;
  v_st    text := upper(coalesce(private.upi_param(p_raw_response, 'Status'), ''));
  v_ref   text := private.upi_param(p_raw_response, 'txnRef');
  v_txn   text := upper(coalesce(private.upi_param(p_raw_response, 'ApprovalRefNo'),
                                 private.upi_param(p_raw_response, 'txnId')));
  v_reason text;
begin
  select * into v from public.payment_orders where id = p_order_id and user_id = auth.uid() for update;
  if not found then raise exception 'Order not found'; end if;
  if v.status not in ('initiated', 'pending') then return private.order_json(v.id); end if;

  update public.payment_orders set client_status = nullif(v_st, ''), raw_response = left(p_raw_response, 2000),
         updated_at = now() where id = v.id;

  if v_st in ('SUCCESS', 'SUBMITTED') then
    select activation_mode into v_mode from public.payment_settings where id = 1;
    if v_st = 'SUBMITTED' then v_reason := 'Bank marked the payment as submitted';
    elsif coalesce(v_mode, 'manual') <> 'instant' then v_reason := 'Manual verification mode';
    elsif v_ref is distinct from v.reference then v_reason := 'Reference mismatch';
    elsif v_txn is null or v_txn !~ '^[A-Z0-9]{6,40}$' then v_reason := 'Missing or invalid transaction id';
    elsif exists (select 1 from public.blocked_txn_ids where utr = v_txn)
       or exists (select 1 from public.payment_orders where utr = v_txn and id <> v.id) then
      v_reason := 'Transaction id already used';
    elsif v.created_at < now() - interval '2 hours' then v_reason := 'Order older than 2 hours';
    elsif (select count(*) from public.payment_orders
            where user_id = v.user_id and activated_by = 'auto' and paid_at > now() - interval '24 hours') >= 3 then
      v_reason := 'Daily auto-activation limit reached';
    end if;

    if v_reason is null then
      perform private.activate_payment(v.id, v_txn, 'auto');
    else
      update public.payment_orders
         set status = 'pending', reason = v_reason,
             utr = case when v_txn ~ '^[A-Z0-9]{6,40}$'
                         and not exists (select 1 from public.payment_orders x where x.utr = v_txn and x.id <> v.id)
                        then v_txn else utr end,
             updated_at = now()
       where id = v.id;
    end if;
  elsif v_st = 'FAILURE' or v_st = 'FAILED' then
    update public.payment_orders set status = 'failed', reason = 'UPI app reported failure', updated_at = now()
    where id = v.id;
  end if;
  -- Empty response / back button: stays 'initiated' (app shows "Payment not completed").
  return private.order_json(v.id);
end;
$$;

create or replace function public.get_payment_order(p_order_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select private.order_json(o.id) from public.payment_orders o
  where o.id = p_order_id and (o.user_id = auth.uid() or public.is_owner());
$$;

-- Owner tools ----------------------------------------------------------
create or replace function public.admin_mark_paid(p_order_id uuid, p_utr text)
returns text
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  update public.payment_orders set utr = null where id = p_order_id and status <> 'success'
    and utr is distinct from upper(btrim(p_utr));
  return private.activate_payment(p_order_id, p_utr, 'owner');
end;
$$;

create or replace function public.admin_revoke_payment(p_order_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v public.payment_orders%rowtype;
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Please give a reason'; end if;
  select * into v from public.payment_orders where id = p_order_id for update;
  if not found or v.status <> 'success' then raise exception 'Only successful payments can be revoked'; end if;
  update public.payment_orders set status = 'revoked', reason = btrim(p_reason), revoked_at = now(), updated_at = now()
  where id = v.id;
  if v.utr is not null then
    insert into public.blocked_txn_ids (utr, reason) values (v.utr, btrim(p_reason)) on conflict do nothing;
  end if;
  update public.subscriptions set ends_at = least(ends_at, now()), updated_at = now() where user_id = v.user_id;
end;
$$;

-- Bank / provider alert (Edge Function upi-webhook, service role only).
create or replace function public.webhook_payment(p_reference text, p_utr text, p_amount_paise bigint)
returns text
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  select id into v_id from public.payment_orders where reference = p_reference;
  if v_id is null then raise exception 'Unknown reference'; end if;
  return private.activate_payment(v_id, p_utr, 'webhook', p_amount_paise);
end;
$$;

-- Cancel open orders older than 24 h (pg_cron every 30 min).
create or replace function private.cancel_stale_orders()
returns int
language sql security definer set search_path = ''
as $$
  with c as (
    update public.payment_orders set status = 'cancelled', reason = coalesce(reason, 'Expired after 24 hours'),
           updated_at = now()
    where status in ('initiated', 'pending') and created_at < now() - interval '24 hours' and utr is null
    returning 1)
  select count(*)::int from c;
$$;

select cron.schedule('bytebox-cancel-stale-orders', '*/30 * * * *', 'select private.cancel_stale_orders()');

-- ---------------------------------------------------------------------
-- Cloud storage: bucket "cloud", keys <user_id>/<file_id>
-- ---------------------------------------------------------------------
create table public.cloud_files (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  parent_id   uuid references public.cloud_files (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 200 and name !~ '[/\\]'),
  is_folder   boolean not null default false,
  storage_key text unique,
  size_bytes  bigint not null default 0 check (size_bytes >= 0 and size_bytes <= 52428800),
  mime_type   text,
  uploaded    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique nulls not distinct (user_id, parent_id, name)
);
alter table public.cloud_files enable row level security;
create index cloud_files_parent_idx on public.cloud_files (user_id, parent_id);
create index cloud_files_parent_fk_idx on public.cloud_files (parent_id);
create policy cloud_files_own on public.cloud_files for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.cloud_files from anon, authenticated;

create or replace function public.cloud_used_bytes(p_uid uuid default auth.uid())
returns bigint
language sql stable security definer set search_path = ''
as $$ select coalesce(sum(size_bytes), 0)::bigint from public.cloud_files where user_id = p_uid and not is_folder; $$;

create or replace function private.cloud_quota_guard()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.is_folder then return new; end if;
  if public.cloud_used_bytes(new.user_id) - coalesce(case when tg_op = 'UPDATE' then old.size_bytes end, 0)
     + new.size_bytes > public.quota_bytes(new.user_id) then
    raise exception 'storage quota exceeded' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger cloud_files_quota before insert or update of size_bytes on public.cloud_files
  for each row execute function private.cloud_quota_guard();

create or replace function private.cloud_check_parent(p_parent uuid)
returns void
language plpgsql stable security definer set search_path = ''
as $$
begin
  if p_parent is not null and not exists (select 1 from public.cloud_files
      where id = p_parent and user_id = auth.uid() and is_folder) then
    raise exception 'Folder not found';
  end if;
end;
$$;

create or replace function public.cloud_create_folder(p_parent_id uuid, p_name text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.is_logged_in() then raise exception 'Please log in to use cloud storage'; end if;
  perform private.cloud_check_parent(p_parent_id);
  insert into public.cloud_files (user_id, parent_id, name, is_folder)
  values (auth.uid(), p_parent_id, btrim(p_name), true) returning id into v_id;
  return v_id;
exception when unique_violation then raise exception 'A file or folder with this name already exists';
end;
$$;

-- Step 1 of upload: reserve the row (quota checked here), returns the storage key.
create or replace function public.cloud_begin_upload(p_parent_id uuid, p_name text, p_size_bytes bigint, p_mime text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid := gen_random_uuid(); v_key text;
begin
  if not public.is_logged_in() then raise exception 'Please log in to use cloud storage'; end if;
  if public.quota_bytes() = 0 then raise exception 'Cloud storage needs a Premium plan'; end if;
  if p_size_bytes > 52428800 then raise exception 'Files must be 50 MB or smaller'; end if;
  perform private.cloud_check_parent(p_parent_id);
  v_key := auth.uid() || '/' || v_id;
  insert into public.cloud_files (id, user_id, parent_id, name, storage_key, size_bytes, mime_type)
  values (v_id, auth.uid(), p_parent_id, btrim(p_name), v_key, coalesce(p_size_bytes, 0), left(p_mime, 120));
  return jsonb_build_object('file_id', v_id, 'storage_key', v_key);
exception when unique_violation then raise exception 'A file or folder with this name already exists';
end;
$$;

-- Step 2: after the bytes are in storage.
create or replace function public.cloud_finish_upload(p_file_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_size bigint;
begin
  select coalesce((o.metadata ->> 'size')::bigint, f.size_bytes) into v_size
  from public.cloud_files f
  join storage.objects o on o.bucket_id = 'cloud' and o.name = f.storage_key
  where f.id = p_file_id and f.user_id = auth.uid();
  if v_size is null then raise exception 'Upload not found'; end if;
  update public.cloud_files set uploaded = true, size_bytes = v_size, updated_at = now() where id = p_file_id;
end;
$$;

create or replace function public.cloud_rename(p_id uuid, p_name text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.cloud_files set name = btrim(p_name), updated_at = now() where id = p_id and user_id = auth.uid();
  if not found then raise exception 'Not found'; end if;
exception when unique_violation then raise exception 'A file or folder with this name already exists';
end;
$$;

create or replace function public.cloud_move(p_id uuid, p_new_parent_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform private.cloud_check_parent(p_new_parent_id);
  -- Prevent moving a folder into itself or its descendants.
  if p_new_parent_id is not null and exists (
       with recursive up as (
         select id, parent_id from public.cloud_files where id = p_new_parent_id
         union all
         select f.id, f.parent_id from public.cloud_files f join up on f.id = up.parent_id)
       select 1 from up where id = p_id) then
    raise exception 'Cannot move a folder into itself';
  end if;
  update public.cloud_files set parent_id = p_new_parent_id, updated_at = now() where id = p_id and user_id = auth.uid();
  if not found then raise exception 'Not found'; end if;
exception when unique_violation then raise exception 'A file or folder with this name already exists there';
end;
$$;

-- Deletes the row (and nested rows); returns storage keys the app must remove.
create or replace function public.cloud_delete(p_id uuid)
returns text[]
language plpgsql security definer set search_path = ''
as $$
declare v_keys text[];
begin
  with recursive tree as (
    select id, storage_key from public.cloud_files where id = p_id and user_id = auth.uid()
    union all
    select f.id, f.storage_key from public.cloud_files f join tree t on f.parent_id = t.id)
  select coalesce(array_agg(storage_key) filter (where storage_key is not null), '{}') into v_keys from tree;
  delete from public.cloud_files where id = p_id and user_id = auth.uid();
  if not found then raise exception 'Not found'; end if;
  return v_keys;
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit)
values ('cloud', 'cloud', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

-- Upload allowed only to a key reserved by cloud_begin_upload (quota enforced there).
create policy cloud_read on storage.objects for select to authenticated
  using (bucket_id = 'cloud' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy cloud_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'cloud' and exists (
    select 1 from public.cloud_files f where f.storage_key = objects.name and f.user_id = (select auth.uid()) and not f.uploaded));
create policy cloud_delete on storage.objects for delete to authenticated
  using (bucket_id = 'cloud' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------------
-- my_status v2
-- ---------------------------------------------------------------------
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
    'is_premium', public.is_premium_user(p.id),
    'plan', (select jsonb_build_object('code', s.plan_code, 'name', s.plan_name, 'ends_at', s.ends_at)
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

-- ---------------------------------------------------------------------
-- Realtime: app updates live when the owner edits plans or free mode.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.plans, public.app_mode;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.webhook_payment(text, text, bigint) from authenticated;
grant execute on function public.webhook_payment(text, text, bigint) to service_role;
revoke execute on all functions in schema private from public, anon, authenticated;
-- Policies readable by anon (plans, categories, app_mode) reference these; they return false for anon.
grant execute on function public.is_admin(), public.is_owner() to anon;

-- =====================================================================
-- Bytebox · Stage 7 · Admin panel functions, site settings, downloads.
-- Every function checks the caller's admin role itself.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Site settings (public read): ads APK for /d, Meta Pixel id.
-- ---------------------------------------------------------------------
create table public.site_settings (
  id                   int primary key default 1 check (id = 1),
  ads_apk_path         text,
  ads_apk_version      text,
  ads_apk_uploaded_at  timestamptz,
  meta_pixel_id        text check (meta_pixel_id ~ '^[0-9]{5,20}$'),
  updated_at           timestamptz not null default now()
);
insert into public.site_settings (id) values (1);
alter table public.site_settings enable row level security;
create policy site_settings_read on public.site_settings for select to anon, authenticated using (true);
create policy site_settings_owner_update on public.site_settings for update to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));
revoke insert, delete, truncate on public.site_settings from anon, authenticated;

-- Public bucket for the ads APK download page; only the owner uploads.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('downloads', 'downloads', true, 209715200,
        array['application/vnd.android.package-archive', 'application/octet-stream'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy downloads_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'downloads' and public.is_owner());
create policy downloads_owner_update on storage.objects for update to authenticated
  using (bucket_id = 'downloads' and public.is_owner()) with check (bucket_id = 'downloads' and public.is_owner());
create policy downloads_owner_delete on storage.objects for delete to authenticated
  using (bucket_id = 'downloads' and public.is_owner());

-- ---------------------------------------------------------------------
-- Dashboard
-- ---------------------------------------------------------------------
create or replace function public.admin_dashboard()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v jsonb;
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  v := jsonb_build_object(
    'pending_channels', (select count(*) from public.channels where review_status = 'pending'),
    'open_reports',     (select count(*) from public.reports where status = 'open'),
    'channels',         (select count(*) from public.channels where review_status = 'approved'),
    'posts',            (select count(*) from public.posts where status = 'published'),
    'free_mode',        public.is_free_mode()
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
      'activated_today',  (select count(*) from public.payment_orders where status = 'success' and paid_at >= v_today),
      'auto_activated_today', (select count(*) from public.payment_orders
                               where status = 'success' and activated_by = 'auto' and paid_at >= v_today),
      'revenue_today_paise', (select coalesce(sum(amount_paise), 0) from public.payment_orders
                              where status = 'success' and paid_at >= v_today),
      'revenue_30d_paise',   (select coalesce(sum(amount_paise), 0) from public.payment_orders
                              where status = 'success' and paid_at >= now() - interval '30 days')
    );
  end if;
  return v;
end;
$$;

-- Sidebar counters (cheap).
create or replace function public.admin_counters()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select case when not public.is_admin() then null else jsonb_build_object(
    'approvals', (select count(*) from public.channels where review_status = 'pending'),
    'requests',  case when public.is_owner() then (select count(*) from public.profiles where ads_access_status = 'pending') end,
    'payments',  case when public.is_owner() then (select count(*) from public.payment_orders where status = 'pending') end,
    'reports',   (select count(*) from public.reports where status = 'open'),
    'role',      public.admin_role()
  ) end;
$$;

-- ---------------------------------------------------------------------
-- Approvals
-- ---------------------------------------------------------------------
create or replace function public.admin_pending_channels()
returns table (id uuid, name text, description text, category text, tags text[], icon_key text,
               created_at timestamptz, owner_id uuid, owner_name text, owner_email text, owner_source text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  return query
    select c.id, c.name, c.description, c.category, c.tags, c.icon_key, c.created_at, c.owner_id,
           p.display_name, u.email::text, coalesce(p.source, 'organic')
    from public.channels c
    left join public.profiles p on p.id = c.owner_id
    left join auth.users u on u.id = c.owner_id
    where c.review_status = 'pending'
    order by c.created_at;
end;
$$;

-- ---------------------------------------------------------------------
-- Users + full-access requests
-- ---------------------------------------------------------------------
create or replace function public.admin_users(
  p_search text default null, p_filter text default 'all', p_limit int default 50, p_offset int default 0)
returns table (id uuid, email text, display_name text, source text, ads_access_status text, is_guest boolean,
               plan_name text, plan_ends_at timestamptz, admin_role text, created_at timestamptz, total bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  return query
    with base as (
      select p.id, u.email::text as email, p.display_name, coalesce(p.source, 'organic') as source,
             p.ads_access_status, coalesce(u.is_anonymous, false) as is_guest,
             s.plan_name, s.ends_at, a.role, p.created_at
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

create or replace function public.admin_access_requests()
returns table (id uuid, email text, display_name text, source text, requested_at timestamptz,
               plan_name text, paid boolean)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  return query
    select p.id, u.email::text, p.display_name, coalesce(p.source, 'organic'), p.ads_access_requested_at,
           s.plan_name, exists (select 1 from public.payment_orders o where o.user_id = p.id and o.status = 'success')
    from public.profiles p
    join auth.users u on u.id = p.id
    left join public.subscriptions s on s.user_id = p.id and s.ends_at > now()
    where p.ads_access_status = 'pending'
    order by p.ads_access_requested_at nulls last;
end;
$$;

-- ---------------------------------------------------------------------
-- Payments
-- ---------------------------------------------------------------------
create or replace function public.admin_payments(
  p_filter text default 'all', p_search text default null, p_limit int default 50, p_offset int default 0)
returns table (id uuid, reference text, user_id uuid, email text, plan_name text, amount_paise bigint, status text,
               utr text, client_status text, reason text, activated_by text, created_at timestamptz,
               paid_at timestamptz, total bigint)
language plpgsql stable security definer set search_path = ''
as $$
declare v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  return query
    select o.id, o.reference, o.user_id, u.email::text, o.plan_name, o.amount_paise, o.status, o.utr,
           o.client_status, o.reason, o.activated_by, o.created_at, o.paid_at, count(*) over ()
    from public.payment_orders o
    left join auth.users u on u.id = o.user_id
    where case p_filter
            when 'activated_today' then o.status = 'success' and o.paid_at >= v_today
            when 'pending' then o.status = 'pending'
            when 'open'    then o.status in ('initiated', 'pending')
            when 'success' then o.status = 'success'
            when 'revoked' then o.status = 'revoked'
            else true end
      and (nullif(btrim(p_search), '') is null
           or o.reference ilike '%' || btrim(p_search) || '%'
           or o.utr ilike '%' || btrim(p_search) || '%'
           or u.email ilike '%' || btrim(p_search) || '%')
    order by coalesce(o.paid_at, o.created_at) desc
    limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0);
end;
$$;

create or replace function public.admin_plan_subscribers()
returns table (plan_code text, active bigint, total_paid bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  return query
    select pl.code,
           (select count(*) from public.subscriptions s where s.plan_code = pl.code and s.ends_at > now()),
           (select count(*) from public.payment_orders o where o.plan_code = pl.code and o.status = 'success')
    from public.plans pl;
end;
$$;

-- ---------------------------------------------------------------------
-- Admins
-- ---------------------------------------------------------------------
create or replace function public.admin_list_admins()
returns table (user_id uuid, email text, display_name text, role text, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  return query
    select a.user_id, u.email::text, p.display_name, a.role, a.created_at
    from public.admins a join auth.users u on u.id = a.user_id left join public.profiles p on p.id = a.user_id
    order by a.created_at;
end;
$$;

create or replace function public.admin_add_admin(p_email text, p_role text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid;
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  if p_role not in ('owner', 'content') then raise exception 'Invalid role'; end if;
  select id into v_uid from auth.users where lower(email) = lower(btrim(p_email)) and coalesce(is_anonymous, false) = false;
  if v_uid is null then raise exception 'No account with this email. Ask them to create an account in the app first.'; end if;
  insert into public.admins (user_id, role) values (v_uid, p_role)
  on conflict (user_id) do update set role = excluded.role;
end;
$$;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.webhook_payment(text, text, bigint) from authenticated;
grant execute on function public.is_admin(), public.is_owner() to anon;

-- =====================================================================
-- Bytebox · Stage 1 · Foundation: profiles, installs, attribution,
-- consents, admins.  Every rule lives here, not in the app.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Admins (owner | content)
-- ---------------------------------------------------------------------
create table public.admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text not null check (role in ('owner', 'content')),
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;

create or replace function public.admin_role(p_uid uuid default auth.uid())
returns text
language sql stable security definer set search_path = ''
as $$
  select a.role from public.admins a where a.user_id = p_uid;
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.admins a where a.user_id = (select auth.uid()));
$$;

create or replace function public.is_owner()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.admins a
                 where a.user_id = (select auth.uid()) and a.role = 'owner');
$$;

create policy admins_select on public.admins
  for select to authenticated
  using ((select public.is_admin()));

create policy admins_owner_insert on public.admins
  for insert to authenticated
  with check ((select public.is_owner()));

create policy admins_owner_update on public.admins
  for update to authenticated
  using ((select public.is_owner()))
  with check ((select public.is_owner()));

create policy admins_owner_delete on public.admins
  for delete to authenticated
  using ((select public.is_owner()));

-- Never leave the app without an owner.
create or replace function private.guard_last_owner()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.role = 'owner'
     and (tg_op = 'DELETE' or new.role <> 'owner')
     and not exists (select 1 from public.admins a
                     where a.role = 'owner' and a.user_id <> old.user_id) then
    raise exception 'Cannot remove the last owner' using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger admins_guard_last_owner
  before update or delete on public.admins
  for each row execute function private.guard_last_owner();

-- ---------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------
create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  display_name       text not null check (char_length(display_name) between 1 and 40),
  source             text check (source in ('ads', 'organic')),   -- first touch, never changes once set
  ads_access_status  text not null default 'none'
                     check (ads_access_status in ('none', 'pending', 'approved', 'rejected')),
  ads_access_requested_at timestamptz,
  ads_access_decided_at   timestamptz,
  attributed_install_id   uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
alter table public.profiles enable row level security;
create index profiles_ads_access_pending_idx on public.profiles (ads_access_requested_at)
  where ads_access_status = 'pending';

create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));
-- No insert/update/delete policies: all writes go through functions below.

create or replace function private.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, 'User-' || left(new.id::text, 8))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Is the caller a real (non-guest) account?
create or replace function public.is_logged_in()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from auth.users u
                 where u.id = (select auth.uid()) and coalesce(u.is_anonymous, false) = false);
$$;

create or replace function public.has_ads_access(p_uid uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce((select p.source = 'ads' or p.ads_access_status = 'approved'
                   from public.profiles p where p.id = p_uid), false);
$$;

create or replace function public.set_display_name(p_name text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_name text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 40 then
    raise exception 'Name must be 2–40 characters';
  end if;
  update public.profiles set display_name = v_name, updated_at = now()
  where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
-- Installs + attribution (first touch wins)
-- ---------------------------------------------------------------------
create table public.installs (
  install_id     uuid primary key,
  secret_hash    text not null,
  referrer       text,
  utm_source     text,
  utm_medium     text,
  utm_campaign   text,
  source         text not null check (source in ('ads', 'organic')),
  device         jsonb not null default '{}'::jsonb,
  first_user_id  uuid references auth.users (id) on delete set null,
  ip             inet,
  user_agent     text,
  created_at     timestamptz not null default now(),
  last_seen_at   timestamptz not null default now()
);
alter table public.installs enable row level security;
create index installs_created_at_idx on public.installs (created_at);

create policy installs_admin_select on public.installs
  for select to authenticated using ((select public.is_admin()));

create table public.install_users (
  install_id  uuid not null references public.installs (install_id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  primary key (install_id, user_id)
);
alter table public.install_users enable row level security;
create index install_users_user_idx on public.install_users (user_id);

create policy install_users_admin_select on public.install_users
  for select to authenticated using ((select public.is_admin()));

-- Pull one query-string value out of a referrer like "utm_source=meta&utm_medium=..."
create or replace function private.referrer_param(p_referrer text, p_key text)
returns text
language sql immutable set search_path = ''
as $$
  select nullif(lower(btrim(split_part(kv, '=', 2))), '')
  from unnest(string_to_array(coalesce(p_referrer, ''), '&')) as kv
  where lower(btrim(split_part(kv, '=', 1))) = lower(p_key)
  limit 1;
$$;

create or replace function public.source_from_referrer(p_referrer text)
returns text
language sql immutable set search_path = ''
as $$
  select case when private.referrer_param(p_referrer, 'utm_source')
                   in ('meta', 'facebook', 'instagram', 'fb', 'ig')
              then 'ads' else 'organic' end;
$$;

create or replace function private.request_ip()
returns inet
language plpgsql stable set search_path = ''
as $$
declare v text;
begin
  v := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1);
  return nullif(btrim(v), '')::inet;
exception when others then
  return null;
end;
$$;

create or replace function private.request_user_agent()
returns text
language plpgsql stable set search_path = ''
as $$
begin
  return left(current_setting('request.headers', true)::json ->> 'user-agent', 500);
exception when others then
  return null;
end;
$$;

-- Link the signed-in user to this install. Sets profile.source only if it
-- has never been set (first touch wins).  Call after every login.
create or replace function public.attribute_user(p_install_id uuid, p_install_secret text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_inst public.installs%rowtype;
  v_src  text;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;

  select * into v_inst from public.installs where install_id = p_install_id;
  if not found then raise exception 'Unknown install'; end if;
  if v_inst.secret_hash <> encode(extensions.digest(coalesce(p_install_secret, ''), 'sha256'), 'hex') then
    raise exception 'Install secret mismatch';
  end if;

  insert into public.install_users (install_id, user_id) values (p_install_id, v_uid)
  on conflict (install_id, user_id) do update set last_seen = now();

  update public.installs set last_seen_at = now(),
         first_user_id = coalesce(first_user_id, v_uid)
  where install_id = p_install_id;

  update public.profiles
     set source = v_inst.source,
         attributed_install_id = p_install_id,
         updated_at = now()
   where id = v_uid and source is null;

  select source into v_src from public.profiles where id = v_uid;
  return v_src;
end;
$$;

-- First open: register the install (idempotent; referrer of a known install is never changed).
create or replace function public.record_install(
  p_install_id     uuid,
  p_install_secret text,
  p_referrer       text default null,
  p_device         jsonb default '{}'::jsonb
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_hash text := encode(extensions.digest(coalesce(p_install_secret, ''), 'sha256'), 'hex');
  v_existing text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_install_id is null or char_length(coalesce(p_install_secret, '')) < 16 then
    raise exception 'Invalid install';
  end if;

  select secret_hash into v_existing from public.installs where install_id = p_install_id;
  if v_existing is null then
    insert into public.installs (install_id, secret_hash, referrer, utm_source, utm_medium, utm_campaign,
                                 source, device, ip, user_agent)
    values (p_install_id, v_hash, left(p_referrer, 1000),
            private.referrer_param(p_referrer, 'utm_source'),
            private.referrer_param(p_referrer, 'utm_medium'),
            private.referrer_param(p_referrer, 'utm_campaign'),
            public.source_from_referrer(p_referrer),
            coalesce(p_device, '{}'::jsonb),
            private.request_ip(), private.request_user_agent())
    on conflict (install_id) do nothing;
  elsif v_existing <> v_hash then
    raise exception 'Install secret mismatch';
  end if;

  return public.attribute_user(p_install_id, p_install_secret);
end;
$$;

-- ---------------------------------------------------------------------
-- Consents
-- ---------------------------------------------------------------------
create table public.consents (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  install_id  uuid references public.installs (install_id) on delete set null,
  version     text not null,
  documents   text[] not null,
  device      jsonb not null default '{}'::jsonb,
  accepted_at timestamptz not null default now(),
  unique (user_id, version)
);
alter table public.consents enable row level security;
create index consents_install_idx on public.consents (install_id);

create policy consents_select_own on public.consents
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create or replace function public.record_consent(
  p_version text, p_documents text[], p_install_id uuid default null, p_device jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_version is null or coalesce(array_length(p_documents, 1), 0) = 0 then
    raise exception 'Consent version and documents are required';
  end if;
  insert into public.consents (user_id, install_id, version, documents, device)
  values (auth.uid(), p_install_id, p_version, p_documents, coalesce(p_device, '{}'::jsonb))
  on conflict (user_id, version) do nothing;
end;
$$;

-- ---------------------------------------------------------------------
-- my_status(): one call the app makes on start / resume.
-- Later stages replace this with plan + quota fields.
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
    'admin_role', public.admin_role(p.id)
  )
  from public.profiles p where p.id = (select auth.uid());
$$;

-- ---------------------------------------------------------------------
-- Grants: functions are callable only by signed-in sessions
-- (anonymous guests are role "authenticated" too).
-- ---------------------------------------------------------------------
-- Tables whose writes go only through security-definer functions:
revoke insert, update, delete, truncate on public.profiles, public.installs,
  public.install_users, public.consents from anon, authenticated;
revoke all on public.admins from anon;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;

-- =====================================================================
-- Bytebox · Stage 2 · Channels, posts, audience rules, private media,
-- views, search, reports.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Placeholder; Stage 3 replaces with plans + free mode.
-- ---------------------------------------------------------------------
create or replace function public.is_premium_user(p_uid uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = ''
as $$ select false; $$;

-- ---------------------------------------------------------------------
-- Audience rule: all → everyone; organic → organic users; ads → has_ads_access()
-- ---------------------------------------------------------------------
create or replace function public.can_see(p_audience text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when public.is_admin() then true
    when p_audience = 'all' then true
    when p_audience = 'organic' then coalesce(
      (select coalesce(p.source, 'organic') = 'organic' from public.profiles p where p.id = (select auth.uid())), false)
    when p_audience = 'ads' then public.has_ads_access()
    else false
  end;
$$;

-- ---------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------
create table public.categories (
  slug      text primary key check (slug ~ '^[a-z0-9-]{2,30}$'),
  name      text not null,
  position  int not null default 0,
  active    boolean not null default true
);
alter table public.categories enable row level security;
create policy categories_read on public.categories for select to anon, authenticated using (active or (select public.is_admin()));
create policy categories_admin_write on public.categories for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

insert into public.categories (slug, name, position) values
  ('entertainment', 'Entertainment', 1), ('education', 'Education', 2), ('music', 'Music', 3),
  ('comedy', 'Comedy', 4), ('lifestyle', 'Lifestyle', 5), ('gaming', 'Gaming', 6),
  ('tech', 'Tech', 7), ('news', 'News', 8), ('sports', 'Sports', 9), ('other', 'Other', 10);

-- ---------------------------------------------------------------------
-- Channels
-- ---------------------------------------------------------------------
create table public.channels (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid references auth.users (id) on delete set null,
  name            text not null check (char_length(btrim(name)) between 3 and 60),
  description     text not null default '' check (char_length(description) <= 1000),
  category        text not null references public.categories (slug),
  tags            text[] not null default '{}' check (cardinality(tags) <= 10),
  icon_key        text,
  review_status   text not null default 'pending' check (review_status in ('pending', 'approved', 'rejected')),
  publish_state   text not null default 'draft'   check (publish_state in ('draft', 'active', 'disabled')),
  audience        text not null default 'all'     check (audience in ('all', 'organic', 'ads')),
  created_via     text not null default 'app'     check (created_via in ('app', 'admin')),
  review_reason   text,
  reviewed_by     uuid references auth.users (id) on delete set null,
  reviewed_at     timestamptz,
  member_count    int not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
alter table public.channels enable row level security;
create index channels_owner_idx on public.channels (owner_id);
create index channels_pending_idx on public.channels (created_at) where review_status = 'pending';
create index channels_live_idx on public.channels (category) where review_status = 'approved' and publish_state = 'active';

create or replace function public.channel_visible(p_channel_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.channels c
    where c.id = p_channel_id
      and (public.is_admin()
           or (c.review_status = 'approved' and c.publish_state = 'active' and public.can_see(c.audience)))
  );
$$;

create policy channels_select on public.channels for select to authenticated
  using (owner_id = (select auth.uid())
         or (select public.is_admin())
         or (review_status = 'approved' and publish_state = 'active' and public.can_see(audience)));
-- All writes go through functions.
revoke insert, update, delete, truncate on public.channels from anon, authenticated;

create table public.channel_members (
  channel_id uuid not null references public.channels (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (channel_id, user_id)
);
alter table public.channel_members enable row level security;
create index channel_members_user_idx on public.channel_members (user_id);
create policy channel_members_select on public.channel_members for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
revoke insert, update, delete, truncate on public.channel_members from anon, authenticated;

create or replace function private.channel_member_count()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.channels set member_count = member_count + 1 where id = new.channel_id;
  else
    update public.channels set member_count = greatest(member_count - 1, 0) where id = old.channel_id;
  end if;
  return null;
end;
$$;
create trigger channel_members_count after insert or delete on public.channel_members
  for each row execute function private.channel_member_count();

-- ---------------------------------------------------------------------
-- Posts
-- ---------------------------------------------------------------------
create table public.posts (
  id               uuid primary key default gen_random_uuid(),
  channel_id       uuid not null references public.channels (id) on delete cascade,
  author_id        uuid references auth.users (id) on delete set null,
  kind             text not null default 'video' check (kind in ('video', 'photo')),
  title            text not null check (char_length(btrim(title)) between 1 and 160),
  description      text not null default '' check (char_length(description) <= 2000),
  is_premium       boolean not null default false,
  audience         text not null default 'all' check (audience in ('all', 'organic', 'ads')),
  status           text not null default 'draft' check (status in ('draft', 'published', 'removed')),
  media_key        text,
  trailer_key      text,
  thumbnail_key    text,
  duration_seconds int check (duration_seconds >= 0),
  size_bytes       bigint check (size_bytes >= 0),
  view_count       bigint not null default 0,
  published_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
alter table public.posts enable row level security;
create index posts_channel_idx on public.posts (channel_id, published_at desc);
create index posts_latest_idx on public.posts (published_at desc) where status = 'published';
create index posts_author_idx on public.posts (author_id);
create index posts_title_trgm_idx on public.posts using gin (title extensions.gin_trgm_ops);
create index posts_desc_trgm_idx on public.posts using gin (description extensions.gin_trgm_ops);

create or replace function public.post_visible(p_post_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.posts p
    where p.id = p_post_id
      and (public.is_admin()
           or (p.status = 'published' and public.can_see(p.audience) and public.channel_visible(p.channel_id)))
  );
$$;

create policy posts_select on public.posts for select to authenticated
  using (author_id = (select auth.uid())
         or (select public.is_admin())
         or (status = 'published' and public.can_see(audience) and public.channel_visible(channel_id)));
revoke insert, update, delete, truncate on public.posts from anon, authenticated;

-- Is the caller the owner of the channel (creator), or an admin?
create or replace function private.is_channel_owner(p_channel_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.channels c where c.id = p_channel_id and c.owner_id = (select auth.uid()));
$$;

-- ---------------------------------------------------------------------
-- Media access.  Keys inside private bucket "media":
--   channels/<channel_id>/icon.<ext>
--   posts/<post_id>/main.<ext> | trailer.<ext> | thumb.<ext>
-- ---------------------------------------------------------------------
create or replace function public.can_read_media(p_key text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(coalesce(p_key, ''), '/');
  v_id    uuid;
  v_file  text;
  v_post  public.posts%rowtype;
  v_owner uuid;
begin
  if (select auth.uid()) is null or cardinality(v_parts) <> 3 then return false; end if;
  begin
    v_id := v_parts[2]::uuid;
  exception when others then return false;
  end;
  v_file := split_part(v_parts[3], '.', 1);

  if public.is_admin() then return true; end if;

  if v_parts[1] = 'channels' and v_file = 'icon' then
    select owner_id into v_owner from public.channels where id = v_id;
    return v_owner = auth.uid() or public.channel_visible(v_id);
  end if;

  if v_parts[1] <> 'posts' then return false; end if;
  select * into v_post from public.posts where id = v_id;
  if not found then return false; end if;
  if v_post.author_id = auth.uid() or private.is_channel_owner(v_post.channel_id) then return true; end if;
  if not public.post_visible(v_id) then return false; end if;

  return case v_file
    when 'thumb'   then true
    when 'trailer' then public.has_ads_access()
    when 'main'    then case when v_post.is_premium then public.is_premium_user() else public.is_logged_in() end
    else false
  end;
end;
$$;

-- Who may upload/replace/delete an object at this key?
create or replace function public.can_write_media(p_key text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(coalesce(p_key, ''), '/');
  v_id    uuid;
  v_file  text;
  v_post  public.posts%rowtype;
begin
  if not public.is_logged_in() or cardinality(v_parts) <> 3 then return false; end if;
  begin
    v_id := v_parts[2]::uuid;
  exception when others then return false;
  end;
  v_file := split_part(v_parts[3], '.', 1);
  if public.is_admin() then return v_parts[1] in ('channels', 'posts'); end if;

  if v_parts[1] = 'channels' and v_file = 'icon' then
    return private.is_channel_owner(v_id);
  end if;
  if v_parts[1] = 'posts' and v_file in ('main', 'trailer', 'thumb') then
    select * into v_post from public.posts where id = v_id;
    return found and v_post.author_id = auth.uid()
       and exists (select 1 from public.channels c where c.id = v_post.channel_id
                   and c.owner_id = auth.uid() and c.review_status = 'approved' and c.publish_state = 'active');
  end if;
  return false;
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', false, 52428800,
        array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime',
              'video/webm', 'video/x-matroska', 'video/3gpp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy media_read on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.can_read_media(name));
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.can_write_media(name));
create policy media_update on storage.objects for update to authenticated
  using (bucket_id = 'media' and public.can_write_media(name))
  with check (bucket_id = 'media' and public.can_write_media(name));
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.can_write_media(name));

-- ---------------------------------------------------------------------
-- Channel functions
-- ---------------------------------------------------------------------
create or replace function private.clean_tags(p_tags text[])
returns text[]
language sql immutable set search_path = ''
as $$
  select coalesce(array_agg(distinct t) filter (where t <> ''), '{}')
  from (select left(lower(btrim(x)), 30) as t from unnest(coalesce(p_tags, '{}')) x) s;
$$;

-- App: every new channel is pending/draft/audience all — even when an admin creates it from the app.
create or replace function public.create_channel(
  p_name text, p_category text, p_description text default '', p_tags text[] default '{}')
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.is_logged_in() then raise exception 'Please log in to create a channel'; end if;
  if char_length(btrim(coalesce(p_name, ''))) < 3 then raise exception 'Channel name must be at least 3 characters'; end if;
  if (select count(*) from public.channels where owner_id = auth.uid() and review_status = 'pending') >= 3 then
    raise exception 'You already have 3 channels waiting for approval';
  end if;
  insert into public.channels (owner_id, name, description, category, tags,
                               review_status, publish_state, audience, created_via)
  values (auth.uid(), btrim(p_name), coalesce(btrim(p_description), ''), p_category,
          private.clean_tags(p_tags), 'pending', 'draft', 'all', 'app')
  returning id into v_id;
  return v_id;
end;
$$;

-- Creator edits: name/description/category/tags/icon only.
create or replace function public.update_channel(
  p_channel_id uuid, p_name text, p_category text, p_description text, p_tags text[], p_icon_key text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not (private.is_channel_owner(p_channel_id) or public.is_admin()) then
    raise exception 'Not allowed';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) < 3 then raise exception 'Channel name must be at least 3 characters'; end if;
  if p_icon_key is not null and p_icon_key not like 'channels/' || p_channel_id || '/icon.%' then
    raise exception 'Invalid icon';
  end if;
  update public.channels
     set name = btrim(p_name), category = p_category, description = coalesce(btrim(p_description), ''),
         tags = private.clean_tags(p_tags), icon_key = coalesce(p_icon_key, icon_key), updated_at = now()
   where id = p_channel_id;
end;
$$;

-- Creators may delete only while not approved; admins any time.
create or replace function public.delete_channel(p_channel_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v public.channels%rowtype;
begin
  select * into v from public.channels where id = p_channel_id for update;
  if not found then raise exception 'Channel not found'; end if;
  if not public.is_admin() then
    if v.owner_id is distinct from auth.uid() then raise exception 'Not allowed'; end if;
    if v.review_status = 'approved' then raise exception 'Approved channels can only be removed by support'; end if;
  end if;
  delete from public.channels where id = p_channel_id;
end;
$$;

-- Admin panel: channels created here are approved immediately.
create or replace function public.admin_create_channel(
  p_name text, p_category text, p_description text default '', p_tags text[] default '{}',
  p_audience text default 'all', p_owner_id uuid default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  insert into public.channels (owner_id, name, description, category, tags, review_status, publish_state,
                               audience, created_via, reviewed_by, reviewed_at)
  values (coalesce(p_owner_id, auth.uid()), btrim(p_name), coalesce(p_description, ''), p_category,
          private.clean_tags(p_tags), 'approved', 'active', p_audience, 'admin', auth.uid(), now())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.admin_review_channel(
  p_channel_id uuid, p_approve boolean, p_audience text default 'all', p_reason text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_owner uuid;
begin
  if not public.is_owner() then raise exception 'Owner only'; end if;
  if p_audience not in ('all', 'organic', 'ads') then raise exception 'Invalid audience'; end if;
  update public.channels
     set review_status = case when p_approve then 'approved' else 'rejected' end,
         publish_state = case when p_approve then 'active' else 'draft' end,
         audience = case when p_approve then p_audience else audience end,
         review_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
   where id = p_channel_id
  returning owner_id into v_owner;
  if not found then raise exception 'Channel not found'; end if;
  if p_approve and v_owner is not null then
    insert into public.channel_members (channel_id, user_id) values (p_channel_id, v_owner)
    on conflict do nothing;
  end if;
end;
$$;

create or replace function public.admin_update_channel(
  p_channel_id uuid, p_audience text, p_publish_state text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  update public.channels set audience = p_audience, publish_state = p_publish_state, updated_at = now()
  where id = p_channel_id;
end;
$$;

create or replace function public.join_channel(p_channel_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not public.channel_visible(p_channel_id) then raise exception 'Channel not available'; end if;
  insert into public.channel_members (channel_id, user_id) values (p_channel_id, auth.uid()) on conflict do nothing;
end;
$$;

create or replace function public.leave_channel(p_channel_id uuid)
returns void
language sql security definer set search_path = ''
as $$
  delete from public.channel_members where channel_id = p_channel_id and user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- Post functions: draft → upload → publish (approved + active channel only)
-- ---------------------------------------------------------------------
create or replace function public.create_post_draft(
  p_channel_id uuid, p_title text, p_description text default '', p_kind text default 'video',
  p_is_premium boolean default false)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.is_logged_in() then raise exception 'Please log in'; end if;
  if not exists (select 1 from public.channels c where c.id = p_channel_id
                 and (c.owner_id = auth.uid() or public.is_admin())
                 and c.review_status = 'approved' and c.publish_state = 'active') then
    raise exception 'You can post only in your approved channels';
  end if;
  insert into public.posts (channel_id, author_id, kind, title, description, is_premium, status)
  values (p_channel_id, auth.uid(), p_kind, btrim(p_title), coalesce(p_description, ''), coalesce(p_is_premium, false), 'draft')
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.publish_post(
  p_post_id uuid, p_media_key text, p_trailer_key text default null, p_thumbnail_key text default null,
  p_duration_seconds int default null, p_size_bytes bigint default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v public.posts%rowtype;
begin
  select * into v from public.posts where id = p_post_id for update;
  if not found or (v.author_id is distinct from auth.uid() and not public.is_admin()) then
    raise exception 'Not allowed';
  end if;
  if not exists (select 1 from public.channels c where c.id = v.channel_id
                 and c.review_status = 'approved' and c.publish_state = 'active') then
    raise exception 'Channel is not approved';
  end if;
  if p_media_key is null or p_media_key not like 'posts/' || p_post_id || '/main.%'
     or (p_trailer_key is not null and p_trailer_key not like 'posts/' || p_post_id || '/trailer.%')
     or (p_thumbnail_key is not null and p_thumbnail_key not like 'posts/' || p_post_id || '/thumb.%') then
    raise exception 'Invalid media keys';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'media' and o.name = p_media_key) then
    raise exception 'Upload the file before publishing';
  end if;
  if p_size_bytes > 52428800 then raise exception 'Files must be 50 MB or smaller'; end if;
  update public.posts
     set media_key = p_media_key, trailer_key = p_trailer_key, thumbnail_key = p_thumbnail_key,
         duration_seconds = p_duration_seconds, size_bytes = p_size_bytes,
         status = 'published', published_at = coalesce(published_at, now()), updated_at = now()
   where id = p_post_id;
end;
$$;

-- Removes the row; the caller deletes storage objects first (storage API).
create or replace function public.delete_post(p_post_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.posts
  where id = p_post_id
    and (author_id = auth.uid() or private.is_channel_owner(channel_id) or public.is_admin());
  if not found then raise exception 'Not allowed'; end if;
end;
$$;

create or replace function public.admin_set_post(p_post_id uuid, p_status text, p_audience text, p_is_premium boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  update public.posts set status = p_status, audience = p_audience, is_premium = p_is_premium, updated_at = now()
  where id = p_post_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Views: counted once per user/post per 30 minutes
-- ---------------------------------------------------------------------
create table public.post_views (
  post_id   uuid not null references public.posts (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_views enable row level security;
revoke all on public.post_views from anon, authenticated;

create or replace function public.record_view(p_post_id uuid)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_counted boolean := false; v_count bigint;
begin
  if auth.uid() is null or not public.post_visible(p_post_id) then return null; end if;
  insert into public.post_views (post_id, user_id) values (p_post_id, auth.uid())
  on conflict (post_id, user_id) do update set viewed_at = now()
    where public.post_views.viewed_at < now() - interval '30 minutes'
  returning true into v_counted;
  if v_counted then
    update public.posts set view_count = view_count + 1 where id = p_post_id returning view_count into v_count;
  else
    select view_count into v_count from public.posts where id = p_post_id;
  end if;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------
-- Listing / search (server side; RLS still applies because SECURITY INVOKER)
-- ---------------------------------------------------------------------
create or replace function public.search_posts(
  p_query text default null, p_category text default null, p_channel_id uuid default null,
  p_feed boolean default false, p_limit int default 20, p_offset int default 0)
returns table (
  id uuid, channel_id uuid, channel_name text, channel_icon_key text, kind text, title text,
  description text, is_premium boolean, has_trailer boolean, thumbnail_key text,
  duration_seconds int, view_count bigint, published_at timestamptz)
language sql stable security invoker set search_path = ''
as $$
  select p.id, p.channel_id, c.name, c.icon_key, p.kind, p.title, p.description, p.is_premium,
         p.trailer_key is not null, p.thumbnail_key, p.duration_seconds, p.view_count, p.published_at
  from public.posts p
  join public.channels c on c.id = p.channel_id
  where p.status = 'published'
    and c.review_status = 'approved' and c.publish_state = 'active'
    and (p_category is null or c.category = p_category)
    and (p_channel_id is null or p.channel_id = p_channel_id)
    and (not p_feed or exists (select 1 from public.channel_members m
                               where m.channel_id = p.channel_id and m.user_id = (select auth.uid())))
    and (nullif(btrim(p_query), '') is null
         or p.title ilike '%' || btrim(p_query) || '%'
         or p.description ilike '%' || btrim(p_query) || '%'
         or c.name ilike '%' || btrim(p_query) || '%')
  order by p.published_at desc nulls last
  limit least(greatest(p_limit, 1), 50) offset greatest(p_offset, 0);
$$;

-- ---------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------
create table public.reports (
  id          bigint generated always as identity primary key,
  reporter_id uuid references auth.users (id) on delete set null,
  post_id     uuid references public.posts (id) on delete set null,
  channel_id  uuid references public.channels (id) on delete set null,
  reason      text not null check (reason in ('sexual', 'violence', 'hate', 'copyright', 'spam', 'other')),
  details     text check (char_length(details) <= 2000),
  contact     text check (char_length(contact) <= 200),
  source      text not null default 'app' check (source in ('app', 'web')),
  status      text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  created_at  timestamptz not null default now(),
  handled_by  uuid references auth.users (id) on delete set null,
  handled_at  timestamptz
);
alter table public.reports enable row level security;
create index reports_open_idx on public.reports (created_at) where status = 'open';
create policy reports_admin_select on public.reports for select to authenticated using ((select public.is_admin()));
revoke insert, update, delete, truncate on public.reports from anon, authenticated;

create or replace function public.submit_report(
  p_reason text, p_post_id uuid default null, p_channel_id uuid default null, p_details text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_post_id is null and p_channel_id is null then raise exception 'Nothing to report'; end if;
  if p_reason = 'other' and char_length(btrim(coalesce(p_details, ''))) < 3 then
    raise exception 'Please add some details';
  end if;
  if (select count(*) from public.reports where reporter_id = auth.uid() and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Too many reports. Please try later.';
  end if;
  insert into public.reports (reporter_id, post_id, channel_id, reason, details)
  values (auth.uid(), p_post_id,
          coalesce(p_channel_id, (select channel_id from public.posts where id = p_post_id)),
          p_reason, left(p_details, 2000));
end;
$$;

create or replace function public.admin_handle_report(p_report_id bigint, p_status text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  update public.reports set status = p_status, handled_by = auth.uid(), handled_at = now() where id = p_report_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;

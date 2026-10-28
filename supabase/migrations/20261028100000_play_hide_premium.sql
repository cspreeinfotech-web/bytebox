-- Google Play Payments policy: the Play build (without Play billing) must not list premium
-- content that can't be unlocked in the app. search_posts gains p_hide_premium (default false,
-- so existing callers and the website APK are unchanged).
drop function if exists public.search_posts(text, text, uuid, boolean, int, int);

create function public.search_posts(
  p_query text default null, p_category text default null, p_channel_id uuid default null,
  p_feed boolean default false, p_limit int default 20, p_offset int default 0,
  p_hide_premium boolean default false)
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
    and (not coalesce(p_hide_premium, false) or not p.is_premium)
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

revoke execute on function public.search_posts(text, text, uuid, boolean, int, int, boolean) from public, anon;
grant execute on function public.search_posts(text, text, uuid, boolean, int, int, boolean) to authenticated;

-- Stage 2: channels review, audience rules, media access, posting, views, search, reports.
begin;

select tests.new_user('owner2@test.dev')   as owner_id   \gset
select tests.new_user('creator@test.dev')  as creator    \gset
select tests.new_user(null, true)          as ads_guest  \gset
select tests.new_user(null, true)          as org_guest  \gset
select tests.new_user('org@test.dev')      as org_member \gset
select tests.new_user('ads@test.dev')      as ads_member \gset
insert into public.admins (user_id, role) values (:'owner_id', 'owner');
update public.profiles set source = 'ads'     where id in (:'ads_guest', :'ads_member');
update public.profiles set source = 'organic' where id in (:'org_guest', :'org_member', :'creator');

-- ---- guests cannot create channels
select tests.login(:'ads_guest');
set role authenticated;
select tests.throws($q$select public.create_channel('Guest Channel','music')$q$, 'log in to create a channel');
reset role;

-- ---- creator: pending/draft/all is forced; max 3 pending
select tests.login(:'creator');
set role authenticated;
select public.create_channel('Cooking Daily', 'lifestyle', 'Recipes', array[' Food ','food','']) as ch \gset
select tests.ok((review_status, publish_state, audience, created_via) = ('pending','draft','all','app'), 'forced pending')
  from public.channels where id = :'ch';
select tests.ok(tags = array['food'], 'tags cleaned') from public.channels where id = :'ch';
select public.create_channel('Second One', 'music');
select public.create_channel('Third One', 'music');
select tests.throws($q$select public.create_channel('Fourth One','music')$q$, '3 channels waiting');
select tests.throws($q$select public.create_channel('ab','music')$q$, 'at least 3');
select tests.throws($q$insert into public.channels(name, category, review_status) values ('Direct','music','approved')$q$, 'permission denied');
select tests.throws(format($q$select public.create_post_draft(%L,'t')$q$, :'ch'), 'approved channels');
reset role;

-- other users don't see pending channels
select tests.login(:'ads_member');
set role authenticated;
select tests.ok(count(*) = 0, 'pending hidden') from public.channels where id = :'ch';
select tests.throws(format($q$select public.admin_review_channel(%L, true, 'ads')$q$, :'ch'), 'owner only');
reset role;

-- ---- owner approves with audience "ads" → creator auto-joined
select tests.login(:'owner_id');
set role authenticated;
select public.admin_review_channel(:'ch', true, 'ads');
select tests.ok((review_status, publish_state, audience, member_count) = ('approved','active','ads',1), 'approved+joined')
  from public.channels where id = :'ch';
select public.admin_create_channel('Admin Picks', 'entertainment', '', '{}', 'all') as ch_all \gset
select tests.ok(review_status = 'approved', 'admin-panel channel approved') from public.channels where id = :'ch_all';
reset role;

-- ---- creator posts: draft → upload → publish
select tests.login(:'creator');
set role authenticated;
select tests.throws(format($q$select public.delete_channel(%L)$q$, :'ch'), 'only be removed by support');
select public.create_post_draft(:'ch', 'Premium Biryani', 'Full recipe', 'video', true) as p_prem \gset
select tests.throws(format($q$select public.publish_post(%L, 'posts/%s/main.mp4')$q$, :'p_prem', :'p_prem'), 'Upload the file');
insert into storage.objects (bucket_id, name) values ('media', 'posts/' || :'p_prem' || '/main.mp4'),
                                                     ('media', 'posts/' || :'p_prem' || '/trailer.mp4'),
                                                     ('media', 'posts/' || :'p_prem' || '/thumb.jpg');
select public.publish_post(:'p_prem', 'posts/' || :'p_prem' || '/main.mp4', 'posts/' || :'p_prem' || '/trailer.mp4',
                           'posts/' || :'p_prem' || '/thumb.jpg', 120, 1000000);
select public.create_post_draft(:'ch', 'Free Chai', 'Quick chai', 'video', false) as p_free \gset
insert into storage.objects (bucket_id, name) values ('media', 'posts/' || :'p_free' || '/main.mp4');
select public.publish_post(:'p_free', 'posts/' || :'p_free' || '/main.mp4');
reset role;

-- a different user cannot upload into the creator's post
select tests.login(:'ads_member');
set role authenticated;
select tests.throws(format($q$insert into storage.objects (bucket_id, name) values ('media','posts/%s/main.mp4')$q$, :'p_free'), 'row-level security');
reset role;

-- ---- ads guest: sees channel, trailer + thumb yes, premium main no, free main no (guest)
select tests.login(:'ads_guest');
set role authenticated;
select tests.ok(count(*) = 2, 'ads guest sees both posts') from public.posts;
select tests.ok(public.can_read_media('posts/' || :'p_prem' || '/trailer.mp4'), 'trailer for ads guest');
select tests.ok(public.can_read_media('posts/' || :'p_prem' || '/thumb.jpg'), 'thumb');
select tests.ok(not public.can_read_media('posts/' || :'p_prem' || '/main.mp4'), 'no premium main without plan');
select tests.ok(not public.can_read_media('posts/' || :'p_free' || '/main.mp4'), 'free main needs login');
select tests.ok(count(*) = 1, 'storage RLS: trailer readable') from storage.objects where name = 'posts/' || :'p_prem' || '/trailer.mp4';
select tests.ok(count(*) = 0, 'storage RLS: main hidden') from storage.objects where name = 'posts/' || :'p_prem' || '/main.mp4';
select tests.ok(public.record_view(:'p_free') = 1, 'first view counted');
select tests.ok(public.record_view(:'p_free') = 1, 'repeat view within 30 min not counted');
reset role;

-- ---- logged-in ads member: free main yes, premium main still no
select tests.login(:'ads_member');
set role authenticated;
select tests.ok(public.can_read_media('posts/' || :'p_free' || '/main.mp4'), 'free main for logged-in');
select tests.ok(not public.can_read_media('posts/' || :'p_prem' || '/main.mp4'), 'premium needs plan');
select tests.ok(count(*) = 1, 'search by title') from public.search_posts('biryani');
select tests.ok(count(*) = 1, 'search by category + query') from public.search_posts('chai', 'lifestyle');
select tests.ok(count(*) = 0, 'category filter') from public.search_posts(null, 'music');
select tests.ok(count(*) = 0, 'feed empty before join') from public.search_posts(p_feed => true);
select public.join_channel(:'ch');
select tests.ok(count(*) = 2, 'feed after join') from public.search_posts(p_feed => true);
select tests.ok(count(*) = 1 and bool_and(not is_premium), 'Play build: premium hidden') from public.search_posts(p_feed => true, p_hide_premium => true);
select tests.throws($q$select public.submit_report('other', p_post_id => null, p_channel_id => null)$q$, 'Nothing to report');
select tests.throws(format($q$select public.submit_report('other', %L)$q$, :'p_free'), 'add some details');
select public.submit_report('spam', :'p_free');
select tests.ok(count(*) = 0, 'reports not readable by users') from public.reports;
reset role;

-- ---- organic users never see 'ads' content until approved
select tests.login(:'org_member');
set role authenticated;
select tests.ok(count(*) = 0, 'organic: ads channel hidden') from public.channels where id = :'ch';
select tests.ok(count(*) = 0, 'organic: ads posts hidden') from public.posts;
select tests.ok(not public.can_read_media('posts/' || :'p_prem' || '/thumb.jpg'), 'organic: no thumb');
select tests.ok(not public.can_read_media('posts/' || :'p_prem' || '/trailer.mp4'), 'organic: no trailer');
select tests.ok(count(*) = 1, 'organic sees all-audience channel') from public.channels where id = :'ch_all';
reset role;
update public.profiles set ads_access_status = 'approved' where id = :'org_member';
select tests.login(:'org_member');
set role authenticated;
select tests.ok(count(*) = 2, 'approved organic sees ads posts') from public.posts;
select tests.ok(public.can_read_media('posts/' || :'p_prem' || '/trailer.mp4'), 'approved organic gets trailer');
reset role;

-- ---- audience "organic": ads users don't see it
select tests.login(:'owner_id');
set role authenticated;
select public.admin_update_channel(:'ch_all', 'organic', 'active');
reset role;
select tests.login(:'ads_member');
set role authenticated;
select tests.ok(count(*) = 0, 'ads user: organic channel hidden') from public.channels where id = :'ch_all';
reset role;

-- reports reached the admin
select tests.ok(count(*) = 1, 'report stored') from public.reports;

\echo 'content_access: ok'
rollback;

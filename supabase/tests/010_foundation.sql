-- Stage 1: profiles, attribution (first touch wins), consents, admins.
begin;

select tests.new_user(null, true)             as guest_ads   \gset
select tests.new_user(null, true)             as guest_org   \gset
select tests.new_user('owner@test.dev')       as owner_id    \gset
select tests.new_user('member@test.dev')      as member_id   \gset

-- signup trigger: display_name = 'User-' || first 8 chars
do $$
begin
  assert (select count(*) from public.profiles) = 4, 'profile per user';
  assert (select bool_and(display_name = 'User-' || left(id::text, 8)) from public.profiles), 'display name format';
end $$;

-- referrer parsing
do $$
begin
  assert public.source_from_referrer('utm_source=meta&utm_medium=paid_social') = 'ads';
  assert public.source_from_referrer('utm_medium=x&UTM_SOURCE=Instagram') = 'ads';
  assert public.source_from_referrer('utm_source=ig') = 'ads';
  assert public.source_from_referrer('utm_source=google-play') = 'organic';
  assert public.source_from_referrer(null) = 'organic';
end $$;

-- ---- ads guest installs from the ads APK
select tests.login(:'guest_ads');
set role authenticated;
select public.record_install('11111111-1111-1111-1111-111111111111', 'secret-ads-0123456789',
       'utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download', '{"model":"Pixel"}');
select tests.ok((public.my_status() ->> 'source') = 'ads', 'ads guest source');
select tests.ok(public.has_ads_access(), 'ads guest has_ads_access');
select tests.ok((public.my_status() ->> 'is_guest')::boolean, 'guest flag');

-- wrong secret is rejected; same install re-recorded with a different referrer keeps 'ads'
select tests.throws($q$select public.record_install('11111111-1111-1111-1111-111111111111','wrong-secret-0123456789',null)$q$, 'secret mismatch');
select public.record_install('11111111-1111-1111-1111-111111111111', 'secret-ads-0123456789', 'utm_source=google');
reset role;
do $$ begin
  assert (select source from public.installs where install_id = '11111111-1111-1111-1111-111111111111') = 'ads', 'install source is first touch';
end $$;

-- ---- organic guest; then logs into the ads install device: their own source must NOT change
select tests.login(:'guest_org');
set role authenticated;
select public.record_install('22222222-2222-2222-2222-222222222222', 'secret-org-0123456789', null);
select tests.ok(public.has_ads_access() = false, 'organic has no ads access');
select tests.ok(public.attribute_user('11111111-1111-1111-1111-111111111111', 'secret-ads-0123456789') = 'organic', 'first touch must win for user');

-- guests cannot write profiles directly or escalate
select tests.throws($q$update public.profiles set source='ads', ads_access_status='approved'$q$, 'permission denied');
select tests.throws($q$insert into public.admins(user_id, role) values (auth.uid(), 'owner')$q$, 'row-level security');
-- only own profile visible
select tests.ok((count(*) = 1), 'profile isolation') from public.profiles;
-- consent
select public.record_consent('v1', array['privacy','terms','refund','community'], '22222222-2222-2222-2222-222222222222', '{}');
select public.record_consent('v1', array['privacy','terms','refund','community']);
select tests.ok((count(*) = 1), 'consent idempotent') from public.consents;
select public.set_display_name('  Riya  ');
select tests.ok((display_name = 'Riya'), 'set_display_name') from public.profiles;
select tests.throws($q$select public.set_display_name('x')$q$, '2–40');
reset role;

-- ---- admins: owner seeded by SQL; last owner cannot be removed
insert into public.admins (user_id, role) values (:'owner_id', 'owner');
select tests.login(:'owner_id');
set role authenticated;
select tests.ok(public.is_owner(), 'is_owner');
select tests.ok((count(*) = 4), 'admin sees all profiles') from public.profiles;
insert into public.admins (user_id, role) values (:'member_id', 'content');
select tests.throws(format($q$delete from public.admins where user_id = %L$q$, :'owner_id'), 'last owner');
reset role;

select tests.login(:'member_id');
set role authenticated;
select tests.ok(public.is_admin() and not public.is_owner(), 'content admin role');
select tests.throws(format($q$insert into public.admins(user_id, role) values (%L,'owner')$q$, :'guest_org'), 'row-level security');
reset role;

\echo 'foundation: ok'
rollback;

-- Stage 8: website forms, ad click → install match, Meta events, dispatcher.
begin;
select tests.new_user('owner8@test.dev') as owner_id \gset
insert into public.admins (user_id, role) values (:'owner_id', 'owner');

-- anon website helpers
select set_config('request.headers', '{"x-forwarded-for": "203.0.113.7", "user-agent": "Mozilla/5.0 test"}', false);
set role anon;
select public.record_ad_click('IwAR123abc', 'fb.1.1700000000.123', 'https://bytebox.vercel.app/d?utm_source=meta&utm_campaign=launch');
select public.submit_deletion_request('someone@example.com', 'some_data', 'Remove my cloud files only');
select tests.throws($q$select public.submit_deletion_request('bad', 'account')$q$, 'valid email');
select public.submit_web_report('copyright', 'https://bytebox.vercel.app/p/00000000-0000-0000-0000-000000000000', 'This video is mine');
select tests.ok(public.public_post_preview('00000000-0000-0000-0000-000000000000') is null, 'no preview for missing post');
select tests.throws($q$select * from public.ad_clicks$q$, 'permission denied');
reset role;
select tests.ok((select fbc from public.ad_clicks) like 'fb.1.%.IwAR123abc', 'fbc built from fbclid');
select tests.ok((select utm_campaign from public.ad_clicks) = 'launch', 'utm parsed');

-- ads install from same IP → matched + AppInstall event
select tests.new_user(null, true) as guest \gset
select tests.login(:'guest');
set role authenticated;
select public.record_install('33333333-3333-3333-3333-333333333333', 'secret-ads-abcdefghijk', 'utm_source=meta');
reset role;
select tests.ok(ad_click_id is not null, 'install matched to click') from public.installs where install_id = '33333333-3333-3333-3333-333333333333';
select tests.ok(count(*) = 1 and min(fbc) like 'fb.1.%', 'AppInstall queued with fbc')
  from public.meta_events where event_name = 'AppInstall';

-- guest → account: CompleteRegistration with hashed email
update auth.users set is_anonymous = false, email = 'Buyer@Example.com' where id = :'guest';
select tests.ok(email_sha256 = encode(extensions.digest('buyer@example.com', 'sha256'), 'hex'), 'CompleteRegistration hashed email')
  from public.meta_events where event_name = 'CompleteRegistration';

-- purchase → Purchase event with value INR + event_id = order id
select tests.login(:'guest');
set role authenticated;
select public.create_payment_order('trial') ->> 'order_id' as oid \gset
reset role;
update public.payment_orders set status = 'success', paid_at = now(), utr = 'META000000001' where id = :'oid';
select tests.ok(value = 49 and currency = 'INR' and event_id = :'oid', 'Purchase event')
  from public.meta_events where event_name = 'Purchase';

-- dispatcher: not configured → nothing sent
select tests.ok(private.meta_dispatch() = 0, 'no dispatch without config');
select tests.login(:'owner_id');
set role authenticated;
select public.admin_meta_configure('1234567890', 'EAAtesttoken', 'TEST123', 'v23.0', true);
select tests.ok((public.admin_meta_status() ->> 'token_hint') = '…oken', 'token masked');
select public.admin_meta_test_event();
reset role;
select tests.ok(private.meta_dispatch() = 4, 'batch dispatched');
select tests.ok(count(*) = 4, 'all sending') from public.meta_events where status = 'sending';
-- simulate Meta answering 200 for live request and 400 for test request
insert into net._http_response (id, status_code, content)
select distinct request_id, case when is_test then 400 else 200 end, '{}' from public.meta_events;
select private.meta_dispatch();
select tests.ok(count(*) = 3, 'live events sent') from public.meta_events where status = 'sent';
select tests.ok(count(*) = 1, 'test event back to pending') from public.meta_events where is_test and status in ('pending', 'sending');

-- non-owner cannot read config or events
select tests.login(:'guest');
set role authenticated;
select tests.throws($q$select public.admin_meta_status()$q$, 'Owner only');
select tests.ok(count(*) = 0, 'events hidden') from public.meta_events;
select tests.throws($q$select * from private.meta_config$q$, 'permission denied');
reset role;

\echo 'website_meta: ok'
rollback;

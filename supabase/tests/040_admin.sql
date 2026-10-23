-- Stage 7: admin functions are role-gated.
begin;
select tests.new_user('owner7@test.dev')   as owner_id   \gset
select tests.new_user('content7@test.dev') as content_id \gset
select tests.new_user('user7@test.dev')    as user_id    \gset
insert into public.admins (user_id, role) values (:'owner_id', 'owner'), (:'content_id', 'content');
update public.profiles set source = 'organic', ads_access_status = 'pending', ads_access_requested_at = now()
 where id = :'user_id';

-- normal user: everything refused
select tests.login(:'user_id');
set role authenticated;
select tests.throws($q$select public.admin_dashboard()$q$, 'Admins only');
select tests.throws($q$select * from public.admin_users()$q$, 'Owner only');
select tests.throws($q$select public.admin_add_admin('user7@test.dev','owner')$q$, 'Owner only');
select tests.ok(public.admin_counters() is null, 'no counters for users');
update public.site_settings set meta_pixel_id = '123456';
reset role;
select tests.ok(meta_pixel_id is null, 'users cannot edit site settings') from public.site_settings;

-- content admin: dashboard without money, no owner pages
select tests.login(:'content_id');
set role authenticated;
select tests.ok(public.admin_dashboard() ? 'pending_channels' and not (public.admin_dashboard() ? 'revenue_today_paise'), 'content dashboard');
select tests.throws($q$select * from public.admin_payments()$q$, 'Owner only');
select tests.throws($q$select * from public.admin_pending_channels()$q$, 'Owner only');
reset role;

-- owner
select tests.login(:'owner_id');
set role authenticated;
select tests.ok((public.admin_dashboard() ->> 'pending_requests')::int = 1, 'owner dashboard');
select tests.ok(count(*) = 1, 'access requests') from public.admin_access_requests();
select tests.ok(count(*) = 1, 'user search') from public.admin_users('user7@');
select tests.ok(count(*) = 5, 'plan subscriber rows') from public.admin_plan_subscribers();
select public.admin_add_admin('USER7@test.dev', 'content');
select tests.ok(count(*) = 3, 'admin added by email') from public.admin_list_admins();
select tests.throws($q$select public.admin_add_admin('nobody@test.dev','content')$q$, 'No account');
update public.site_settings set meta_pixel_id = '1234567890';
select tests.ok(meta_pixel_id = '1234567890', 'owner edits site settings') from public.site_settings;
update public.app_mode set free_mode = true;
select tests.ok(public.is_free_mode(), 'owner toggles free mode');
reset role;

\echo 'admin: ok'
rollback;

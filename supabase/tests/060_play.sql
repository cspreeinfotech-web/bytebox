-- Stage 9: Play billing is OFF by default and service-role only.
begin;
select tests.new_user('play@test.dev') as uid \gset
select tests.ok(not public.is_play_billing_enabled(), 'play billing off by default');
select tests.throws(format($q$select public.play_activate(%L, 'bytebox_gold', 'tok-1', 'GPA.1111-2222-3333-44444', '{}')$q$, :'uid'), 'billing is off');
update public.app_mode set play_billing_enabled = true;
select tests.ok(public.play_activate(:'uid', 'bytebox_gold', 'tok-1', 'GPA.1111-2222-3333-44444', '{}') = 'success', 'activated');
select tests.ok(public.play_activate(:'uid', 'bytebox_gold', 'tok-1', 'GPA.1111-2222-3333-44444', '{}') = 'success', 'idempotent');
select tests.ok(count(*) = 1 and min(channel) = 'play', 'one play order') from public.payment_orders where user_id = :'uid';
select tests.ok(public.has_active_plan(:'uid'), 'plan active');
select tests.login(:'uid');
set role authenticated;
select tests.throws(format($q$select public.play_activate(%L, 'bytebox_gold', 'tok-2', 'x', '{}')$q$, :'uid'), 'permission denied');
reset role;
\echo 'play: ok'
rollback;

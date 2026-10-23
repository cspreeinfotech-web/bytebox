-- Admin live controls: plan changes, UPI changes, free plans, audit, permissions.
begin;
select tests.new_user('owner9@test.dev') as owner_id \gset
select tests.new_user('org9@test.dev')   as org     \gset
select tests.new_user('ads9@test.dev')   as ads     \gset
select tests.new_user(null, true)        as guest   \gset
insert into public.admins (user_id, role) values (:'owner_id', 'owner');
update public.profiles set source = 'organic' where id in (:'org', :'guest');
update public.profiles set source = 'ads' where id = :'ads';
select id as gold from public.plans where code = 'gold' \gset
select id as trial from public.plans where code = 'trial' \gset

-- ---- plans_for_me: paid by default
select tests.login(:'org');
set role authenticated;
select tests.ok(count(*) = 5 and bool_and(pay_mode = 'upi') and not bool_or(free_for_me), 'all upi by default') from public.plans_for_me();
select tests.ok((select duration_label from public.plans_for_me() where id = :gold) = '1 month', 'duration label');
select tests.ok((public.my_status() ->> 'payments_available')::boolean, 'payments available');
-- order snapshots price, duration, UPI
select public.create_payment_order(:gold) as o1 \gset
select tests.ok((:'o1')::jsonb ->> 'upi_id' = '2728412a@bandhan' and ((:'o1')::jsonb ->> 'price_inr')::int = 259, 'order snapshot');
reset role;
-- complete the first order so a subscription exists at the old price/duration
update public.payment_orders set status = 'success', paid_at = now(), utr = 'LIVE00000001' where id = ((:'o1')::jsonb ->> 'order_id')::uuid;
insert into public.subscriptions (user_id, plan_code, plan_name, ends_at, last_order_id)
values (:'org', 'gold', 'Gold', now() + interval '30 days', ((:'o1')::jsonb ->> 'order_id')::uuid);

-- ---- non-owner cannot change settings
select tests.login(:'org');
set role authenticated;
select tests.throws(format($q$select public.admin_update_plan(%s,'Gold',1,1,'{}',null,3,true,true)$q$, :gold), 'Owner only');
select tests.throws($q$select public.admin_set_upi('x@y','X',true,'instant')$q$, 'Owner only');
select tests.throws($q$select public.admin_clear_upi()$q$, 'Owner only');
select tests.throws($q$select public.admin_set_free_mode(true)$q$, 'Owner only');
select tests.throws($q$select public.admin_set_free_plans('everyone')$q$, 'Owner only');
select tests.throws($q$select * from public.admin_settings_history()$q$, 'Owner only');
select tests.ok(count(*) = 0, 'audit hidden from users') from public.settings_audit;
reset role;

-- ---- owner changes price/duration and UPI
select tests.login(:'owner_id');
set role authenticated;
select tests.throws(format($q$select public.admin_update_plan(%s,'Gold',0,30,'{}',null,3,true,true)$q$, :gold), 'at least ₹1');
select tests.throws($q$select public.admin_set_upi('not-a-upi','X',true,'instant')$q$, 'name@bank');
select tests.throws($q$select public.admin_set_upi('new@okaxis','',true,'instant')$q$, 'Payee name');
select public.admin_update_plan(:gold, 'Gold', 299, 45, array['Full premium videos'], 'Best value', 3, true, true);
select public.admin_set_upi('newbiz@okaxis', 'Bytebox Media', true, 'instant');
select tests.throws($q$update public.plans set code = 'x' where code = 'gold'$q$, 'cannot be changed');
reset role;
select tests.ok(price_inr_at_order = 259 and duration_days_at_order = 30 and amount_paise = 25900, 'old order unchanged')
  from public.payment_orders where id = ((:'o1')::jsonb ->> 'order_id')::uuid;
select tests.ok(plan_code = 'gold' and ends_at < now() + interval '31 days', 'old subscription unchanged')
  from public.subscriptions where user_id = :'org';
select tests.ok(count(*) >= 4, 'audit rows for price, duration, upi, payee')
  from public.settings_audit where field in ('price_inr', 'duration_days', 'upi_id', 'payee_name') and changed_by = :'owner_id';
select tests.ok(old_value = '259' and new_value = '299', 'audit old → new') from public.settings_audit where field = 'price_inr';

select tests.login(:'ads');
set role authenticated;
select public.create_payment_order(:gold) as o2 \gset
select tests.ok(((:'o2')::jsonb ->> 'price_inr')::int = 299 and ((:'o2')::jsonb ->> 'duration_days')::int = 45, 'new order uses new price/duration');
select tests.ok((:'o2')::jsonb ->> 'upi_id' = 'newbiz@okaxis' and (:'o2')::jsonb ->> 'payee_name' = 'Bytebox Media', 'new order uses new UPI');
reset role;
-- activation uses the order's stored duration even if the plan changes again
select tests.login(:'owner_id');
set role authenticated;
select public.admin_update_plan(:gold, 'Gold', 299, 90, '{}', null, 3, true, true);
reset role;
select tests.login(:'ads');
set role authenticated;
select reference as ref2 from public.payment_orders where id = ((:'o2')::jsonb ->> 'order_id')::uuid \gset
select public.report_payment_result(((:'o2')::jsonb ->> 'order_id')::uuid, format('Status=SUCCESS&txnRef=%s&ApprovalRefNo=LIVE00000002', :'ref2'));
select tests.ok(ends_at between now() + interval '44 days' and now() + interval '46 days', 'activation uses order duration (45)')
  from public.subscriptions where user_id = :'ads';
-- same-plan open order is NOT reused after a UPI change
select public.create_payment_order(:trial) as o3 \gset
reset role;
select tests.login(:'owner_id');
set role authenticated;
select public.admin_set_upi('third@okhdfc', 'Bytebox', true, 'instant');
reset role;
select tests.login(:'ads');
set role authenticated;
select public.create_payment_order(:trial) as o4 \gset
select tests.ok((:'o4')::jsonb ->> 'order_id' <> (:'o3')::jsonb ->> 'order_id' and (:'o4')::jsonb ->> 'upi_id' = 'third@okhdfc', 'stale order replaced');
reset role;
select tests.ok(status = 'cancelled', 'stale order cancelled') from public.payment_orders where id = ((:'o3')::jsonb ->> 'order_id')::uuid;

-- ---- cleared UPI / disabled payments block orders; plans show unavailable
select tests.login(:'owner_id');
set role authenticated;
select public.admin_clear_upi();
reset role;
select tests.login(:'org');
set role authenticated;
select tests.ok(bool_and(pay_mode = 'unavailable'), 'unavailable when UPI cleared') from public.plans_for_me();
select tests.throws(format($q$select public.create_payment_order(%s)$q$, :trial), 'Payments are not available right now');
reset role;
select tests.login(:'owner_id');
set role authenticated;
select public.admin_set_upi('third@okhdfc', 'Bytebox', false, 'instant');
reset role;
select tests.login(:'org');
set role authenticated;
select tests.throws(format($q$select public.create_payment_order(%s)$q$, :trial), 'Payments are not available right now');
reset role;
select tests.login(:'owner_id');
set role authenticated;
select public.admin_set_upi('third@okhdfc', 'Bytebox', true, 'instant');

-- ---- free plans for organic users
select public.admin_set_free_plans('organic');
select promo_id as promo1 from public.app_mode \gset
update public.plans set free_eligible = false where code = 'diamond';  -- owner direct update allowed by RLS
reset role;
delete from public.subscriptions where user_id in (:'org', :'ads');

select tests.login(:'guest');
set role authenticated;
select tests.ok((select free_for_me from public.plans_for_me() where code = 'trial'), 'guest sees free (organic install)');
select tests.throws(format($q$select public.claim_free_plan(%s)$q$, :trial), 'log in');
reset role;

select tests.login(:'org');
set role authenticated;
select tests.ok((select pay_mode from public.plans_for_me() where code = 'trial') = 'free', 'organic: free');
select tests.ok((select pay_mode from public.plans_for_me() where code = 'diamond') = 'upi', 'per-plan free flag respected');
select tests.throws(format($q$select public.create_payment_order(%s)$q$, :trial), 'free for you');
select public.claim_free_plan(:trial) as c1 \gset
select tests.ok(ends_at between now() + interval '6 days 23 hours' and now() + interval '7 days 1 minute', 'exact duration')
  from public.subscriptions where user_id = :'org';
select tests.ok(public.my_status() ->> 'ads_access_status' = 'pending', 'organic free claim → pending approval');
select tests.ok(public.my_status() -> 'plan' ->> 'source' = 'free_promo', 'plan source free promo');
select tests.throws(format($q$select public.claim_free_plan(%s)$q$, :trial), 'already have an active plan');
reset role;
delete from public.subscriptions where user_id = :'org';
select tests.login(:'org');
set role authenticated;
select tests.throws(format($q$select public.claim_free_plan(%s)$q$, :trial), 'already claimed');
reset role;

select tests.login(:'ads');
set role authenticated;
select tests.ok((select pay_mode from public.plans_for_me() where code = 'trial') = 'upi', 'ads user must pay');
select tests.throws(format($q$select public.claim_free_plan(%s)$q$, :trial), 'not free for you');
reset role;

-- ---- free plans for ads users (new promotion after Off → on)
select tests.login(:'owner_id');
set role authenticated;
select public.admin_set_free_plans('none');
select public.admin_set_free_plans('ads');
reset role;
select tests.ok(promo_id <> :'promo1', 'new promo id') from public.app_mode;
select tests.login(:'org');
set role authenticated;
select tests.throws(format($q$select public.claim_free_plan(%s)$q$, :trial), 'not free for you');
reset role;
select tests.login(:'ads');
set role authenticated;
select public.claim_free_plan(:trial);
select tests.ok(public.my_status() ->> 'ads_access_status' = 'none', 'ads claim needs no approval');
reset role;

-- ---- everyone: organic can claim the same plan again in the new promotion
select tests.login(:'owner_id');
set role authenticated;
select public.admin_set_free_plans('everyone');
select tests.ok((public.admin_free_claims() ->> 'ads')::int = 1, 'claims counted per promo');
reset role;
select tests.login(:'org');
set role authenticated;
select tests.ok(public.claim_free_plan(:trial) ->> 'status' = 'success', 'new promo resets one-claim rule');
reset role;
select tests.ok(count(*) = 3 and sum(amount_paise) = 0, 'free orders stored with amount 0')
  from public.payment_orders where source = 'free_promo';

-- ---- free mode blocks orders with its own message
select tests.login(:'owner_id');
set role authenticated;
select public.admin_set_free_mode(true);
select tests.ok(count(*) >= 2, 'audit for app_mode') from public.settings_audit where table_name = 'app_mode';
reset role;
select tests.login(:'ads');
set role authenticated;
select tests.ok(not (public.my_status() ->> 'payments_available')::boolean, 'no payments in free mode');
select tests.throws(format($q$select public.create_payment_order(%s)$q$, :gold), 'Plans are free right now');
reset role;

-- settings_version bumps for Realtime
select tests.ok(version > 1, 'settings version bumped') from public.settings_version;

\echo 'live_controls: ok'
rollback;

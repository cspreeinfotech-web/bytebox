-- Stage 3: plans, UPI orders, instant activation safeguards, owner tools, free mode, quota, cloud.
begin;

select tests.new_user('owner3@test.dev') as owner_id \gset
select tests.new_user(null, true)        as guest    \gset
select tests.new_user('buyer@test.dev')  as buyer    \gset
select tests.new_user('adsb@test.dev')   as ads_buyer \gset
insert into public.admins (user_id, role) values (:'owner_id', 'owner');
update public.profiles set source = 'organic' where id = :'buyer';
update public.profiles set source = 'ads' where id = :'ads_buyer';

-- ---- plans: public read, seeded, no writes for users
select tests.login(:'guest');
set role authenticated;
select tests.ok(count(*) = 5, 'five seeded plans') from public.plans;
select tests.ok(badge = 'Best value' and price_inr = 259 and duration_days = 30, 'gold seed') from public.plans where code = 'gold';
update public.plans set price_inr = 1;
select tests.ok(min(price_inr) = 49, 'guest update has no effect') from public.plans;
select tests.throws($q$delete from public.plans$q$, 'permission denied');
select tests.ok(count(*) = 0, 'guests cannot read payment settings') from public.payment_settings;
select tests.throws($q$select public.create_payment_order('trial')$q$, 'log in');
select tests.ok(public.quota_bytes() = 0, 'guest quota 0');
select tests.throws($q$select public.cloud_begin_upload(null, 'a.txt', 10, 'text/plain')$q$, 'log in');
reset role;
set role anon;
select tests.ok(count(*) = 5, 'anon can read active plans') from public.plans;
reset role;

-- ---- buyer orders Trial ₹49
select tests.login(:'buyer');
set role authenticated;
select tests.ok(public.quota_bytes() = 0, 'paid mode without plan: quota 0');
select tests.throws($q$select public.cloud_begin_upload(null, 'a.txt', 10, 'text/plain')$q$, 'needs a Premium plan');
select (public.create_payment_order('trial')) as o1 \gset
select tests.ok((:'o1')::jsonb ->> 'amount' = '49.00', 'amount 2dp');
select tests.ok((:'o1')::jsonb ->> 'upi_id' = '2728412a@bandhan', 'upi id returned');
select tests.ok((:'o1')::jsonb ->> 'reference' ~ '^BB[0-9]{6}[0-9A-F]{12}$', 'reference format');
select (:'o1')::jsonb ->> 'order_id' as oid1, (:'o1')::jsonb ->> 'reference' as ref1 \gset
select tests.ok((public.create_payment_order('trial') ->> 'order_id') = :'oid1', 'same-plan open order reused');
select public.create_payment_order('gold') ->> 'order_id' as oid_gold \gset
select tests.ok(status = 'cancelled', 'other open order cancelled') from public.payment_orders where id = :'oid1';
-- back to trial: a new order is created, gold cancelled
select public.create_payment_order('trial') ->> 'order_id' as oid2 \gset
select reference as ref2 from public.payment_orders where id = :'oid2' \gset
select tests.ok(status = 'cancelled', 'gold cancelled') from public.payment_orders where id = :'oid_gold';

-- empty response / back → stays initiated
select tests.ok(public.report_payment_result(:'oid2', '') ->> 'status' = 'initiated', 'empty stays initiated');
-- wrong txnRef → pending with reason
select tests.ok(public.report_payment_result(:'oid2', 'Status=SUCCESS&txnRef=WRONG&ApprovalRefNo=123456789012') ->> 'status' = 'pending', 'ref mismatch → pending');
select tests.ok(reason = 'Reference mismatch', 'mismatch reason') from public.payment_orders where id = :'oid2';
reset role;

-- owner marks it paid with the UTR (already stored) → success
select tests.login(:'owner_id');
set role authenticated;
select tests.ok(public.admin_mark_paid(:'oid2', '123456789012') = 'success', 'owner mark paid');
select tests.ok(public.admin_mark_paid(:'oid2', '123456789012') = 'success', 'idempotent');
reset role;

select tests.login(:'buyer');
set role authenticated;
select tests.ok(public.is_premium_user(), 'premium after activation');
select tests.ok(public.quota_bytes() = 2199023255552, '2 TB with plan');
select tests.ok(public.my_status() ->> 'ads_access_status' = 'pending', 'organic buyer queued for approval');
select tests.ok((public.my_status() -> 'plan' ->> 'code') = 'trial', 'plan in my_status');
select ends_at as ends1 from public.subscriptions \gset

-- second purchase via instant auto-activation extends from current end
select public.create_payment_order('silver') ->> 'order_id' as oid3 \gset
select reference as ref3 from public.payment_orders where id = :'oid3' \gset
select tests.ok(public.report_payment_result(:'oid3',
  format('txnId=AXI123&responseCode=00&Status=SUCCESS&txnRef=%s&ApprovalRefNo=998877665544', :'ref3')) ->> 'status' = 'success', 'instant activation');
select tests.ok(ends_at > (:'ends1')::timestamptz + interval '6 days 23 hours', 'ends_at extended') from public.subscriptions;
-- reusing the same txn id on another order is refused
select public.create_payment_order('silver') ->> 'order_id' as oid4 \gset
select reference as ref4 from public.payment_orders where id = :'oid4' \gset
select tests.ok(public.report_payment_result(:'oid4',
  format('Status=SUCCESS&txnRef=%s&ApprovalRefNo=998877665544', :'ref4')) ->> 'status' = 'pending', 'reused txn → pending');
select tests.ok(reason = 'Transaction id already used', 'reuse reason') from public.payment_orders where id = :'oid4';
-- FAILURE → failed
select public.create_payment_order('gold') ->> 'order_id' as oid5 \gset
select tests.ok(public.report_payment_result(:'oid5', 'Status=FAILURE&txnRef=x') ->> 'status' = 'failed', 'failure');
-- invalid txn id format → pending
select public.create_payment_order('platinum') ->> 'order_id' as oid6 \gset
select reference as ref6 from public.payment_orders where id = :'oid6' \gset
select tests.ok(public.report_payment_result(:'oid6', format('Status=SUCCESS&txnRef=%s&ApprovalRefNo=12', :'ref6')) ->> 'status' = 'pending', 'short txn → pending');
-- users can't touch others' orders or write orders directly
select tests.throws($q$update public.payment_orders set status = 'success'$q$, 'permission denied');
reset role;

-- ---- 3 auto-activations per 24 h
select tests.login(:'ads_buyer');
set role authenticated;
do $$
declare o jsonb; i int;
begin
  for i in 1..4 loop
    o := public.create_payment_order(case when i % 2 = 0 then 'trial' else 'silver' end);
    o := public.report_payment_result((o->>'order_id')::uuid,
           format('Status=SUCCESS&txnRef=%s&ApprovalRefNo=LIMIT%s0000', o->>'reference', i));
    if i <= 3 then assert o->>'status' = 'success', 'auto ' || i;
    else assert o->>'status' = 'pending', 'fourth must be pending';
    end if;
  end loop;
end $$;
select tests.ok(public.my_status() ->> 'ads_access_status' = 'none', 'ads buyer needs no approval');
reset role;

-- order older than 2 h → pending
select tests.login(:'ads_buyer');
set role authenticated;
select public.create_payment_order('diamond') as od \gset
reset role;
update public.payment_orders set created_at = now() - interval '3 hours' where id = ((:'od')::jsonb ->> 'order_id')::uuid;
select tests.login(:'ads_buyer');
set role authenticated;
select tests.ok(public.report_payment_result(((:'od')::jsonb ->> 'order_id')::uuid,
  format('Status=SUCCESS&txnRef=%s&ApprovalRefNo=OLDORDER0001', (:'od')::jsonb ->> 'reference')) ->> 'status' = 'pending', '>2h → pending');
reset role;

-- ---- manual mode: SUCCESS → pending only
update public.payment_settings set activation_mode = 'manual';
select tests.new_user('manual@test.dev') as mu \gset
select tests.login(:'mu');
set role authenticated;
select public.create_payment_order('trial') as om \gset
select tests.ok(public.report_payment_result(((:'om')::jsonb ->> 'order_id')::uuid,
  format('Status=SUCCESS&txnRef=%s&ApprovalRefNo=MANUAL000001', (:'om')::jsonb ->> 'reference')) ->> 'status' = 'pending', 'manual mode');
reset role;
update public.payment_settings set activation_mode = 'instant';

-- ---- owner revokes the instant payment: plan ends, txn blocked
select tests.login(:'owner_id');
set role authenticated;
select public.admin_revoke_payment(:'oid3', 'Not found in bank statement');
select tests.ok(status = 'revoked', 'revoked') from public.payment_orders where id = :'oid3';
select tests.throws(format($q$select public.admin_mark_paid(%L, '998877665544')$q$, :'oid4'), 'blocked');
reset role;
select tests.login(:'buyer');
set role authenticated;
select tests.ok(not public.is_premium_user(), 'premium ends after revoke');
reset role;

-- ---- payments disabled
update public.payment_settings set enabled = false;
select tests.login(:'buyer');
set role authenticated;
select tests.throws($q$select public.create_payment_order('trial')$q$, 'Payments are not available right now');
reset role;
update public.payment_settings set enabled = true;

-- ---- stale order cleanup
update public.payment_orders set created_at = now() - interval '25 hours' where id = :'oid6';
update public.payment_orders set utr = null where id = :'oid6';
select tests.ok(private.cancel_stale_orders() >= 1, 'stale cancelled');
select tests.ok(status = 'cancelled', 'oid6 cancelled') from public.payment_orders where id = :'oid6';

-- ---- free mode
select tests.login(:'owner_id');
set role authenticated;
update public.app_mode set free_mode = true;
reset role;
select tests.new_user('free@test.dev') as fu \gset
update public.profiles set source = 'organic' where id = :'fu';
select tests.login(:'fu');
set role authenticated;
select tests.ok(public.quota_bytes() = 16106127360, '15 GB in free mode');
select tests.ok(not public.is_premium_user(), 'organic w/o approval not premium');
select tests.throws($q$select public.create_payment_order('trial')$q$, 'free right now');
select tests.ok(public.request_full_access() = 'pending', 'request full access');
reset role;
select tests.login(:'owner_id');
set role authenticated;
select public.admin_set_access(:'fu', 'approved');
reset role;
select tests.login(:'fu');
set role authenticated;
select tests.ok(public.is_premium_user(), 'free mode + approved → premium');
-- cloud: folders, upload, quota, move, delete
select public.cloud_create_folder(null, 'Photos') as f1 \gset
select public.cloud_create_folder(:'f1', 'Trip') as f2 \gset
select tests.throws(format($q$select public.cloud_move(%L, %L)$q$, :'f1', :'f2'), 'into itself');
select public.cloud_begin_upload(:'f2', 'a.jpg', 1000, 'image/jpeg') as up \gset
select tests.throws(format($q$select public.cloud_begin_upload(%L, 'a.jpg', 10, 'image/jpeg')$q$, :'f2'), 'already exists');
select tests.throws($q$select public.cloud_begin_upload(null, 'big.bin', 60000000, 'x')$q$, '50 MB');
insert into storage.objects (bucket_id, name, metadata) values ('cloud', (:'up')::jsonb ->> 'storage_key', '{"size": 1200}');
select tests.throws(format($q$insert into storage.objects (bucket_id, name) values ('cloud', '%s/random')$q$, :'fu'), 'row-level security');
select public.cloud_finish_upload(((:'up')::jsonb ->> 'file_id')::uuid);
select tests.ok(public.cloud_used_bytes() = 1200, 'usage from storage metadata');
select public.cloud_rename(:'f2', 'Goa');
select tests.ok(cardinality(public.cloud_delete(:'f1')) = 1, 'folder delete returns nested keys');
select tests.ok(count(*) = 0, 'tree gone') from public.cloud_files;
reset role;
-- quota exceeded
update public.profiles set play_free_cloud = false where id = :'fu';
insert into public.cloud_files (user_id, name, size_bytes, storage_key) select :'fu', 'f' || g, 52428800, :'fu' || '/k' || g from generate_series(1, 307) g;
select tests.throws(format($q$insert into public.cloud_files (user_id, name, size_bytes) values (%L, 'over', 52428800)$q$, :'fu'), 'storage quota exceeded');

-- free mode off → paid flow restored, quota back to 0 for plan-less users
update public.app_mode set free_mode = false;
select tests.login(:'fu');
set role authenticated;
select tests.ok(public.quota_bytes() = 0 and not public.is_premium_user(), 'free mode off restores paid flow');
-- Play build: 15 GB for logged in users
select public.enable_play_free_cloud();
select tests.ok(public.quota_bytes() = 16106127360, 'play free cloud');
reset role;

\echo 'plans_payments_cloud: ok'
rollback;

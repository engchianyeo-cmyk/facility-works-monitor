-- One-off Preview UAT data change (owner decision D-52, 12 Nov 2026): mark every remaining WO-TEST-### Work Order
-- as test data, so it leaves the Operations Workspace, the Work Orders list and Finance's lists (still reachable by
-- direct link; the list's "show" link brings them back). Extends D-46. Nothing is deleted or changed on the Work Order.
-- FW-2026-0004 (a real UAT Draft copied from WO-TEST-008) is NOT touched: only numbers starting WO-TEST- are marked.
-- Preview only (pvajuywwwpjlikqjnvgv). Check the host in the connection string before running.
-- Dry run by default (lists what would be marked, then rolls back):
--   psql -X -c "set role postgres" -f this file
-- Apply:
--   psql -X -v apply=yes -c "set role postgres" -f this file
-- Safe to run again.
\set ON_ERROR_STOP on
begin;
do $mark$
declare admin uuid; w record; marked int := 0;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if pg_catalog.to_regclass('public.work_order_test_data') is null then raise exception 'Increment M24 is not applied; nothing changed'; end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;
  for w in select wo.id, wo.work_order_number from public.work_orders wo
           where wo.work_order_number like 'WO-TEST-%'
             and not exists(select 1 from public.work_order_test_data t where t.work_order_id = wo.id)
           order by wo.work_order_number loop
    insert into public.work_order_test_data(work_order_id, reason, marked_by)
    values (w.id, 'UAT test Work Order (owner decision D-52, 12 Nov 2026)', admin);
    insert into public.activity_logs(user_id, work_order_id, action, actor, note)
    values (admin, w.id, 'work_order_marked_test_data', 'UAT data change (owner decision D-52)',
      pg_catalog.jsonb_build_object('reason', 'UAT test Work Order; hidden from lists', 'date', '2026-11-12')::text);
    marked := marked + 1;
  end loop;
  raise notice '% WO-TEST Work Orders marked as test data.', marked;
end;
$mark$;
select w.work_order_number, w.title, w.status, exists(select 1 from public.work_order_test_data t where t.work_order_id = w.id) as test_data
from public.work_orders w where w.work_order_number like 'WO-TEST-%' or w.work_order_number like 'FW-2026-%' order by 1;
\if :{?apply}
  \echo 'Applying the change.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

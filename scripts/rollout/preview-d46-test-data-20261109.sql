-- One-off Preview UAT data change (owner decision D-46, 9 Nov 2026): mark the old automated test records
-- FW-2026-0001 and FW-2026-0002 as test data, so they leave the Operations Workspace, the Work Orders
-- list and Finance's lists (still reachable by direct link). FW-2026-0003 and WO-TEST-012 were marked under D-41.
-- FW-2026-0004 is a real UAT Draft (a copy of WO-TEST-008), not test data: owner, 9 Nov 20:58, "No".
-- Preview only (pvajuywwwpjlikqjnvgv). Dry run by default:
--   psql -X -c "set role postgres" -f this file
-- Apply:
--   psql -X -v apply=yes -c "set role postgres" -f this file
-- Safe to run again.
\set ON_ERROR_STOP on
begin;
do $mark$
declare admin uuid; w public.work_orders%rowtype; n text;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if pg_catalog.to_regclass('public.work_order_test_data') is null then raise exception 'Increment M24 is not applied; nothing changed'; end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;
  foreach n in array array['FW-2026-0001', 'FW-2026-0002'] loop
    select * into w from public.work_orders where work_order_number = n;
    if w.id is null then raise notice '% not found; skipped.', n; continue; end if;
    if exists(select 1 from public.work_order_test_data where work_order_id = w.id) then raise notice '% already marked.', n; continue; end if;
    insert into public.work_order_test_data(work_order_id, reason, marked_by)
    values (w.id, 'Old automated test record (owner decision D-46, 9 Nov 2026)', admin);
    insert into public.activity_logs(user_id, work_order_id, action, actor, note)
    values (admin, w.id, 'work_order_marked_test_data', 'UAT data change (owner decision D-46)',
      pg_catalog.jsonb_build_object('reason', 'Old automated test record; hidden from lists', 'date', '2026-11-09')::text);
  end loop;
end;
$mark$;
select w.work_order_number, w.title, w.status, exists(select 1 from public.work_order_test_data t where t.work_order_id = w.id) as test_data
from public.work_orders w where w.work_order_number like 'FW-2026-000%' or w.work_order_number = 'WO-TEST-012' order by 1;
\if :{?apply}
  \echo 'Applying the change.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

-- One-off Preview UAT data correction (owner decision D-41, 7 Nov 2026). Run AFTER increment M24 is applied.
--  1. WO-TEST-007 (Sunvane): the payment was recorded with references copied by the browser from WO-TEST-010
--     (invoice VQ-INV-2026-1219, payment FS-FAST-20261030-0418) and a payment time 8 hours late (the time-zone fault).
--     Set the invoice number printed on the Sunvane invoice (SVS-INV-2026-0544), a UAT payment reference of its own
--     (FS-UAT-20261107-0007, fictional), and move the payment time back 8 hours (12:36 SGT, when Finance recorded it).
--  2. Mark WO-TEST-012 and FW-2026-0003 (old automated test records) as test data, so they leave Finance's lists.
-- Each correction is written to the activity log. Preview only (pvajuywwwpjlikqjnvgv). Dry run by default:
--   psql -X -c "set role postgres" -f this file
-- Apply:
--   psql -X -v apply=yes -c "set role postgres" -f this file
-- Safe to run again: a record already corrected is left alone.
\set ON_ERROR_STOP on
begin;
create temp table d41_report(stage text, work_order text, invoice_reference text, payment_reference text, paid_at_sgt text, test_data boolean);
create function pg_temp.snapshot(stage text) returns void language sql as $$
  insert into d41_report
  select stage, w.work_order_number, p.invoice_reference, p.payment_reference,
         pg_catalog.to_char(p.paid_at at time zone 'Asia/Singapore', 'DD Mon YYYY HH24:MI:SS'),
         exists(select 1 from public.work_order_test_data t where t.work_order_id = w.id)
  from public.work_orders w left join public.contractor_payment_assessments p on p.work_order_id = w.id
  where w.work_order_number in ('WO-TEST-007', 'WO-TEST-012', 'FW-2026-0003') $$;
do $fix$
declare
  admin uuid; w public.work_orders%rowtype; p public.contractor_payment_assessments%rowtype; n text;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if pg_catalog.to_regclass('public.work_order_test_data') is null then raise exception 'Increment M24 is not applied yet; nothing changed'; end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;
  perform pg_temp.snapshot('1 before');

  select * into w from public.work_orders where work_order_number = 'WO-TEST-007';
  if w.id is null then raise exception 'WO-TEST-007 not found; nothing changed'; end if;
  select * into p from public.contractor_payment_assessments where work_order_id = w.id;
  if p.id is null or p.paid_at is null then raise exception 'WO-TEST-007 has no recorded payment; nothing changed'; end if;
  if p.invoice_reference = 'VQ-INV-2026-1219' and p.payment_reference = 'FS-FAST-20261030-0418' then
    if (p.paid_at at time zone 'Asia/Singapore')::time < time '20:00' then raise exception 'WO-TEST-007 payment time is not the 8-hour-late value expected; nothing changed'; end if;
    update public.contractor_payment_assessments
       set invoice_reference = 'SVS-INV-2026-0544', payment_reference = 'FS-UAT-20261107-0007', paid_at = paid_at - interval '8 hours'
     where id = p.id;
    insert into public.activity_logs(user_id, work_order_id, action, actor, note)
    values (admin, w.id, 'payment_record_corrected', 'UAT data correction (owner decision D-41)',
      pg_catalog.jsonb_build_object('reason', 'References copied by browser autofill from WO-TEST-010; payment time 8 hours late (time-zone fault)',
        'invoice_reference', pg_catalog.jsonb_build_object('from', p.invoice_reference, 'to', 'SVS-INV-2026-0544'),
        'payment_reference', pg_catalog.jsonb_build_object('from', p.payment_reference, 'to', 'FS-UAT-20261107-0007'),
        'paid_at', pg_catalog.jsonb_build_object('from', p.paid_at, 'to', p.paid_at - interval '8 hours'), 'date', '2026-11-07')::text);
  else
    raise notice 'WO-TEST-007 already corrected (or changed since); left alone.';
  end if;

  foreach n in array array['WO-TEST-012', 'FW-2026-0003'] loop
    select * into w from public.work_orders where work_order_number = n;
    if w.id is null then raise notice '% not found; skipped.', n; continue; end if;
    if not exists(select 1 from public.work_order_test_data where work_order_id = w.id) then
      insert into public.work_order_test_data(work_order_id, reason, marked_by)
      values (w.id, 'Old automated test record (owner decision D-41, 7 Nov 2026)', admin);
      insert into public.activity_logs(user_id, work_order_id, action, actor, note)
      values (admin, w.id, 'work_order_marked_test_data', 'UAT data correction (owner decision D-41)',
        pg_catalog.jsonb_build_object('reason', 'Old automated test record; removed from Finance lists', 'date', '2026-11-07')::text);
    end if;
  end loop;
  perform pg_temp.snapshot('2 after');
end;
$fix$;
select * from d41_report order by stage, work_order;
\if :{?apply}
  \echo 'Applying the change.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

-- READ-ONLY diagnosis (always rolls back): try "Submit for approval" for one Work Order exactly as its
-- assigned Technician would, and print the database's reason if it fails. Nothing is kept.
-- Preview only. Run as: psql -X -v wo=WO-TEST-010 -c "set role postgres" -f this file
\set ON_ERROR_STOP on
begin;
select pg_catalog.set_config('fmworks.diag_wo', :'wo', true);
create temp table diag(step text, detail text);
grant insert, select on diag to authenticated;
do $prep$
declare w public.work_orders%rowtype;
begin
  select * into w from public.work_orders where work_order_number = pg_catalog.current_setting('fmworks.diag_wo');
  if w.id is null then raise exception 'Work Order not found'; end if;
  insert into diag values ('work order', w.work_order_number||' status='||w.status||' in_house='||w.in_house_work||' emergency='||w.emergency_work
    ||' technician='||coalesce((select email from public.profiles where id=w.assigned_technician_id),'(none)')
    ||' recommended_vendor='||coalesce(w.recommended_vendor_id::text,'(none)')||' asset='||coalesce(w.asset_id::text,'(none)')||' area='||coalesce(w.facility_area_id::text,'(none)'));
  perform pg_catalog.set_config('request.jwt.claim.sub', w.assigned_technician_id::text, true);
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.jsonb_build_object('sub', w.assigned_technician_id, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('fmworks.diag_id', w.id::text, true);
end;$prep$;
set local role authenticated;
do $try$
declare r jsonb; msg text; state text; ctx text; detail text;
begin
  insert into diag values ('readiness', public.work_order_approval_summary(pg_catalog.current_setting('fmworks.diag_id')::uuid)::text);
  begin
    r := public.transition_work_order(pg_catalog.current_setting('fmworks.diag_id')::uuid, 'submit', '{}'::jsonb);
    insert into diag values ('submit result', pg_catalog.left(r::text, 600));
  exception when others then
    get stacked diagnostics msg = message_text, state = returned_sqlstate, ctx = pg_exception_context, detail = pg_exception_detail;
    insert into diag values ('submit FAILED', state||' '||msg||' | detail: '||coalesce(detail,'')||' | where: '||pg_catalog.left(coalesce(ctx,''),700));
  end;
end;$try$;
set local role postgres;
select step, detail from diag;
rollback;

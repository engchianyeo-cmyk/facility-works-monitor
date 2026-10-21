-- One-off Preview UAT conversion of Work Orders left in old-process stages (owner request 21 Oct 2026).
-- Preview only (pvajuywwwpjlikqjnvgv). Run as: psql -v tech=<technician email> -c "set role postgres" -f this file.
-- 1. Awaiting Approval / Approved / Assigned Work Orders with no work recorded go back to Draft,
--    assigned to the named Technician, so he can add the layout mark, Before evidence and quotation.
-- 2. WO-TEST-008 (Submitted for Review, no Technician) is assigned to him so an approver can
--    reject and reopen it and he can complete the documents.
-- Each change is written to the Work Order's audit history. All-or-nothing.
\set ON_ERROR_STOP on
begin;
select pg_catalog.set_config('fmworks.uat_conversion_tech', :'tech', true);
do $conversion$
declare
  tech uuid; tech_name text; admin uuid; r record; converted int := 0;
  targets text[] := array['FW-2026-0001','WO-TEST-005','WO-TEST-007','WO-TEST-010','WO-TEST-015','WO-TEST-002','WO-TEST-011'];
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  select id, display_name into tech, tech_name from public.profiles
   where email = pg_catalog.current_setting('fmworks.uat_conversion_tech') and role = 'technician' and is_active and deleted_at is null;
  if tech is null then raise exception 'Technician % not found or not active', pg_catalog.current_setting('fmworks.uat_conversion_tech'); end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;

  for r in select w.* from public.work_orders w where w.work_order_number = any(targets) order by w.work_order_number for update loop
    if r.status not in ('submitted','approved','assigned') then
      raise exception '% is now %, not an expected stage; nothing changed', r.work_order_number, r.status;
    end if;
    if r.started_at is not null or exists(select 1 from public.evidence_items e where e.work_order_id = r.id and e.deleted_at is null)
       or exists(select 1 from public.contractor_quotations q where q.work_order_id = r.id) then
      raise exception '% already has work, evidence or quotations; nothing changed', r.work_order_number;
    end if;
    if not exists(select 1 from public.facility_memberships m where m.profile_id = tech and m.facility_id = r.facility_id and m.active) then
      raise exception 'The Technician has no membership at the facility of %; nothing changed', r.work_order_number;
    end if;
    update public.work_orders
       set status = 'draft', assigned_technician_id = tech, assigned_to = tech_name,
           submitted_at = null, submitted_by = null, approved_at = null, assigned_at = null, accepted_at = null,
           updated_at = pg_catalog.now()
     where id = r.id;
    insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
    values (admin, r.id, 'work_order_converted_lifecycle_v2', r.status, 'draft', 'UAT conversion (owner-approved)',
      pg_catalog.jsonb_build_object('reason','Converted to Lifecycle v2 for UAT: returned to Draft so the Technician can add the layout mark, Before evidence and quotation',
        'assigned_technician_id', tech, 'previous_technician_id', r.assigned_technician_id, 'date','2026-10-21')::text);
    converted := converted + 1;
  end loop;
  if converted <> pg_catalog.array_length(targets, 1) then
    raise exception 'Expected % Work Orders, found %; nothing changed', pg_catalog.array_length(targets, 1), converted;
  end if;

  select * into r from public.work_orders where work_order_number = 'WO-TEST-008' for update;
  if r.id is not null and r.status = 'completed' and r.assigned_technician_id is null then
    if not exists(select 1 from public.facility_memberships m where m.profile_id = tech and m.facility_id = r.facility_id and m.active) then
      raise exception 'The Technician has no membership at the facility of WO-TEST-008; nothing changed';
    end if;
    update public.work_orders set assigned_technician_id = tech, assigned_to = tech_name, updated_at = pg_catalog.now() where id = r.id;
    insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
    values (admin, r.id, 'work_order_converted_lifecycle_v2', r.status, r.status, 'UAT conversion (owner-approved)',
      pg_catalog.jsonb_build_object('reason','Technician assigned for Lifecycle v2 UAT; an approver may reject and reopen it for documents','assigned_technician_id', tech)::text);
  end if;
  raise notice 'UAT conversion: % Work Orders returned to Draft; WO-TEST-008 Technician assigned', converted;
end;
$conversion$;
select work_order_number, status, assigned_to from public.work_orders
 where work_order_number in ('FW-2026-0001','WO-TEST-005','WO-TEST-007','WO-TEST-010','WO-TEST-015','WO-TEST-002','WO-TEST-011','WO-TEST-008') order by 1;
commit;

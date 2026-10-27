-- One-off Preview UAT fix (owner request 27 Oct 2026 13:43): a Work Order declared "in-house" is to be
-- done by an external contractor, so a contractor quotation can be prepared and submitted for approval.
-- Technician on duty: Yang (koi.kpr@gmail.com) becomes the assigned Technician and preparer.
-- Preview only (pvajuywwwpjlikqjnvgv). Dry run by default:
--   psql -X -v wo=<Work Order number> -c "set role postgres" -f this file
-- Apply:
--   psql -X -v wo=<Work Order number> -v apply=yes -c "set role postgres" -f this file
-- Allowed only before any work: Draft, Awaiting Approval, or Approved/Assigned with no start, evidence of
-- work, cost, completion or review. The Work Order returns to Draft (approval cleared), in-house is removed,
-- and one audited activity entry records why. All-or-nothing.
\set ON_ERROR_STOP on
begin;
select pg_catalog.set_config('fmworks.fix_wo', :'wo', true);
create temp table wo_fix_report(item text, before text, after text);
do $fix$
declare
  w public.work_orders%rowtype; tech uuid; tech_name text; admin uuid; reason text;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  select * into w from public.work_orders where work_order_number = pg_catalog.current_setting('fmworks.fix_wo') for update;
  if w.id is null then raise exception 'Work Order % not found; nothing changed', pg_catalog.current_setting('fmworks.fix_wo'); end if;
  select id, display_name into tech, tech_name from public.profiles
   where email = 'koi.kpr@gmail.com' and role = 'technician' and is_active and deleted_at is null;
  if tech is null then raise exception 'Technician koi.kpr@gmail.com not found or not active; nothing changed'; end if;
  if not exists(select 1 from public.facility_memberships m where m.profile_id = tech and m.facility_id = w.facility_id and m.active) then
    raise exception 'Yang has no membership at the facility of %; nothing changed', w.work_order_number; end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;

  insert into wo_fix_report values
    ('Work Order', w.work_order_number || ' · ' || w.title, w.work_order_number || ' · ' || w.title),
    ('Status', w.status, 'draft'),
    ('In-house', w.in_house_work::text, 'false'),
    ('Assigned Technician', coalesce((select display_name from public.profiles where id = w.assigned_technician_id), '(none)'), tech_name),
    ('Created by', coalesce((select display_name from public.profiles where id = w.requested_by), '(unknown)'), '(unchanged)');

  if w.status not in ('draft','submitted','approved','assigned') then
    raise exception '% is %; only a Work Order before any work can be switched; nothing changed', w.work_order_number, w.status; end if;
  if w.started_at is not null or w.completed_at is not null or w.reviewed_at is not null
     or exists(select 1 from public.evidence_items e where e.work_order_id = w.id and e.category = 'after' and e.deleted_at is null)
     or exists(select 1 from public.work_order_cost_lines c where c.work_order_id = w.id and c.cost_phase = 'actual') then
    raise exception '% already has work recorded; nothing changed', w.work_order_number; end if;
  if not w.in_house_work and w.status = 'draft' and w.assigned_technician_id = tech then
    raise notice '% is already a contractor Draft assigned to Yang; nothing to change', w.work_order_number; return; end if;

  reason := 'UAT fix (owner-approved 27 Oct 2026): to be done by an external contractor, not in-house; returned to Draft with Yang as the Technician so the contractor quotation can be submitted for approval';
  update public.work_orders
     set in_house_work = false, status = 'draft', assigned_technician_id = tech, assigned_to = tech_name,
         submitted_at = null, submitted_by = null, approved_at = null, assigned_at = null, accepted_at = null,
         approval_limit_version_id = null, updated_at = pg_catalog.now()
   where id = w.id;
  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values (admin, w.id, 'work_order_uat_data_corrected', w.status, 'draft', 'UAT correction (owner-approved)',
    pg_catalog.jsonb_build_object('reason', reason, 'previous_in_house_work', w.in_house_work, 'in_house_work', false,
      'previous_technician_id', w.assigned_technician_id, 'assigned_technician_id', tech, 'date', '2026-10-27')::text);
  raise notice '% switched to an external-contractor Draft for Yang', w.work_order_number;
end;
$fix$;
select item, before, after from wo_fix_report;
\if :{?apply}
  \echo 'Applying the change.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

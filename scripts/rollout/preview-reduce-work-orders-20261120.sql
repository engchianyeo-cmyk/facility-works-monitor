-- One-off Preview UAT clean-up (owner, 20 Nov 2026): "this is not a real facility in operation yet ... reduce to 10 or
-- less work orders ... retain only the interesting ones."
--   1. Facility 2 planned maintenance -> Plan only (dates and reminders stay; no automatic Work Orders). The Daily round
--      keeps running (M37).
--   2. Keep at most 10 open Work Orders (test data marked under D-52 is not counted):
--        a. today's Daily round of each facility;
--        b. Work Orders raised by people (not planned maintenance), newest first;
--        c. planned-maintenance Work Orders on critical equipment, one per trade, earliest due first;
--        d. then other planned maintenance, one per trade, high criticality first;
--      until 10 are kept.
--   3. Every other open Work Order is CANCELLED with a reason (history kept; nothing is deleted), and its planned-
--      maintenance date is cancelled too so it is not created again.
-- Through the app's own functions, as the Super-Administrator (engchian.yeo@gmail.com); audited.
-- Preview only (pvajuywwwpjlikqjnvgv). Check the host in the connection string before running.
-- Dry run by default:   psql -X -c "set role postgres" -c "set fmworks.rollout_project_ref='pvajuywwwpjlikqjnvgv'" -f this file
-- Apply:                add -v apply=yes after -X
\set ON_ERROR_STOP on
begin;
select current_setting('fmworks.rollout_project_ref', true) is not distinct from 'pvajuywwwpjlikqjnvgv' as ok_ref \gset
\if :ok_ref
\else
  \echo 'Set fmworks.rollout_project_ref to pvajuywwwpjlikqjnvgv (Preview) first; nothing changed.'
  rollback;
  \quit
\endif
\o /dev/null
select coalesce((select p.id::text from public.profiles p where lower(p.email) = 'engchian.yeo@gmail.com' and p.role = 'administrator'), '') as admin,
       coalesce((select s.id::text from public.sites s where s.name ilike 'Facility 2%' and s.is_active order by s.code limit 1), '') as fac2 \gset
select set_config('fmw.admin', :'admin', true), set_config('fmw.fac2', :'fac2', true);

create temp table open_wo on commit drop as
select w.id, w.work_order_number, w.title, w.status, w.due_date, w.created_at, w.facility_id, s.name as facility, w.pm_occurrence_id, w.daily_round_date,
  a.criticality, a.asset_type, a.asset_tag, a.name as equipment,
  case when w.daily_round_date is not null then 'Daily round' when w.pm_occurrence_id is not null then 'Planned maintenance' else 'Raised by staff' end as kind
from public.work_orders w left join public.sites s on s.id = w.facility_id left join public.assets a on a.id = w.asset_id
where w.status not in ('closed','cancelled')
  and not exists(select 1 from public.work_order_test_data t where t.work_order_id = w.id);

create temp table keep on commit drop as
with ranked as (
  select o.*,
    case when o.daily_round_date = public.pm_business_date() then 1
         when o.kind = 'Raised by staff' then 2
         when o.kind = 'Planned maintenance' and o.criticality = 'critical' then 3
         when o.kind = 'Planned maintenance' then 4
         else 9 end as tier,
    row_number() over (partition by o.kind, o.asset_type order by case o.criticality when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end, o.due_date nulls last, o.work_order_number) as per_trade
  from open_wo o
), pick as (
  select r.*, row_number() over (order by r.tier, case when r.tier = 2 then -extract(epoch from r.created_at) else 0 end,
    case r.criticality when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end, r.due_date nulls last, r.work_order_number) as n
  from ranked r where r.tier < 9 and (r.tier not in (3, 4) or r.per_trade = 1)
)
select id from pick where n <= 10;

do $m$
declare admin uuid; fac uuid; r jsonb; q record; cancelled int := 0; occ int := 0; reason text := 'Trial load reduced: the facility is not yet fully staffed (owner, 20 Nov 2026)';
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  admin := nullif(current_setting('fmw.admin'), '')::uuid; fac := nullif(current_setting('fmw.fac2'), '')::uuid;
  if admin is null or not public.pilot_account_ready(admin) then raise exception 'Super-Administrator not found or not ready; nothing changed'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated')::text, true),
          set_config('request.jwt.claim.sub', admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  if fac is not null then
    r := public.admin_set_pm_mode(fac, 'plan_only', 'Owner 20 Nov 2026: facility not yet fully staffed; no automatic planned-maintenance Work Orders for now');
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Setting not changed, nothing changed: %', r; end if;
  end if;
  for q in select o.* from open_wo o where o.id not in (select id from keep) order by o.work_order_number loop
    r := public.transition_work_order(q.id, 'cancel', jsonb_build_object('reason', reason));
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Could not cancel %, nothing changed: %', q.work_order_number, r; end if;
    cancelled := cancelled + 1;
    if q.pm_occurrence_id is not null and exists(select 1 from public.pm_occurrences where id = q.pm_occurrence_id and generation_status <> 'cancelled') then
      r := public.cancel_pm_occurrence(q.pm_occurrence_id, reason);
      if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Could not cancel the planned date of %, nothing changed: %', q.work_order_number, r; end if;
      occ := occ + 1;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
  perform set_config('fmw.summary', format('%s open Work Orders before; %s kept; %s cancelled (%s planned dates cancelled with them)',
    (select count(*) from open_wo), (select count(*) from keep), cancelled, occ), true);
end;
$m$;
\o
select current_setting('fmw.summary') as done;
select o.kind, o.facility, count(*) filter (where k.id is not null) as kept, count(*) filter (where k.id is null) as cancelled
from open_wo o left join keep k on k.id = o.id group by 1, 2 order by 1, 2;
\echo 'Work Orders kept:'
select o.work_order_number, o.facility, o.kind, coalesce(o.asset_tag || ' ' || o.equipment, '') as equipment, o.title, o.status, o.due_date
from open_wo o join keep k on k.id = o.id order by o.kind, o.due_date nulls last, o.work_order_number;
select s.name as facility, coalesce(fs.pm_mode, 'plan_only') as planned_maintenance from public.sites s left join public.facility_settings fs on fs.facility_id = s.id where s.is_active order by s.name;
\if :{?apply}
  \echo 'apply=yes: committing.'
  commit;
\else
  \echo 'Dry run only: rolled back. Run again with -v apply=yes to keep it.'
  rollback;
\endif

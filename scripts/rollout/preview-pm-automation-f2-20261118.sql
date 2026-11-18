-- One-off Preview UAT data (owner D-67, 18 Nov 2026), after M35:
--   1. Facility 2 planned maintenance setting -> "Full for critical equipment only" (other facilities stay Plan only).
--   2. Decision H1: each Facility 2 contractor task without a Technician gets the in-house Technician by trade:
--      Technician 1 (koi.kpr+1): Electrical, Fire, Fire / ACMV, Security, Access, Access / lifting, Lifts, Controls;
--      Technician 2 (koi.kpr+2, or Technician 1 if not ready): every other trade.
--   3. One daily run now (lists the next 31 days, moves weekend dates, creates Work Orders due today for critical equipment).
-- Everything through the app's own functions, as the Super-Administrator (engchian.yeo@gmail.com); audited.
-- The 12 daily checks stay Draft (they become the Daily round in part 2).
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
       coalesce((select s.id::text from public.sites s where s.name ilike 'Facility 2%' and s.is_active order by s.code limit 1), '') as fac2,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+1@gmail.com'), '') as tech1,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+2@gmail.com'), '') as tech2 \gset
select set_config('fmw.admin', :'admin', true), set_config('fmw.fac2', :'fac2', true), set_config('fmw.tech1', :'tech1', true), set_config('fmw.tech2', :'tech2', true);
do $m$
declare admin uuid; fac uuid; t1 uuid; t2 uuid; r jsonb; q record; tech uuid; assigned int := 0;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if to_regprocedure('public.pm_daily_run(date)') is null then raise exception 'M35 is not applied; nothing changed'; end if;
  admin := nullif(current_setting('fmw.admin'), '')::uuid; fac := nullif(current_setting('fmw.fac2'), '')::uuid;
  t1 := nullif(current_setting('fmw.tech1'), '')::uuid; t2 := nullif(current_setting('fmw.tech2'), '')::uuid;
  if admin is null or not public.pilot_account_ready(admin) then raise exception 'Super-Administrator not found or not ready; nothing changed'; end if;
  if fac is null then raise exception 'No active facility named "Facility 2..."; nothing changed'; end if;
  if t1 is null or not public.active_facility_member(fac, 'technician', t1) then raise exception 'Technician 1 koi.kpr+1 is not a Technician of Facility 2; nothing changed'; end if;
  if t2 is null or not public.pilot_account_ready(t2) or not public.active_facility_member(fac, 'technician', t2) then t2 := t1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated')::text, true),
          set_config('request.jwt.claim.sub', admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  r := public.admin_set_pm_mode(fac, 'full_critical', 'Owner D-67 (18 Nov 2026): Facility 2 trial, Work Orders for critical equipment only');
  if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Setting not changed, nothing changed: %', r; end if;
  for q in
    select m.id, a.asset_type from public.maintenance_requirements m join public.assets a on a.id = m.asset_id
    where a.facility_id = fac and m.assigned_technician_id is null and m.state = 'active' and a.description like '%Serviced by: Contractor.%'
  loop
    tech := case when q.asset_type in ('Electrical','Fire','Fire / ACMV','Security','Access','Access / lifting','Lifts','Controls') then t1 else t2 end;
    r := public.assign_pm_technician(q.id, tech);
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Technician not assigned, nothing changed: %', r; end if;
    assigned := assigned + 1;
  end loop;
  perform set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
  r := public.pm_daily_run();
  if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Daily run failed, nothing changed: %', r; end if;
  perform set_config('fmw.summary', format('Facility 2 set to Full for critical only; %s contractor tasks given a Technician; daily run: %s', assigned, r::text), true);
end;
$m$;
\o
select current_setting('fmw.summary') as done;
select s.name as facility, coalesce(fs.pm_mode, 'plan_only') as planned_maintenance from public.sites s left join public.facility_settings fs on fs.facility_id = s.id where s.is_active order by s.name;
select coalesce(p.display_name, '(not assigned)') as technician, count(*) as active_tasks
from public.maintenance_requirements m join public.assets a on a.id = m.asset_id left join public.profiles p on p.id = m.assigned_technician_id
where a.facility_id = current_setting('fmw.fac2')::uuid and m.state = 'active' group by 1 order by 1;
\if :{?apply}
  \echo 'apply=yes: committing.'
  commit;
\else
  \echo 'Dry run only: rolled back. Run again with -v apply=yes to keep it.'
  rollback;
\endif

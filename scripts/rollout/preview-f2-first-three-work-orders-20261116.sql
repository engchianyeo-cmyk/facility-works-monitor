-- One-off Preview UAT data (owner request, 16 Nov 2026): the first three Facility 2 Work Orders, created as DRAFTS
-- through the app's own create_work_order() exactly as if Technician koi.kpr+1 / koi.kpr+2 had pressed
-- "+ New Work Order" (same checks, same audit entry). Photos, the layout mark and quotations are added in the app.
--   F2-WO-20 Battery charger BC-05 fault (in-house)            -> Technician 1 koi.kpr+1@gmail.com
--   F2-WO-04 Freezer unit RU-FZ-B high head-pressure trip       -> Technician 1 koi.kpr+1@gmail.com
--   F2-WO-01 CH-01 chiller quarterly service (3 quotations)     -> koi.kpr+2@gmail.com if ready, else koi.kpr+1
-- Preview only (pvajuywwwpjlikqjnvgv). Check the host in the connection string before running.
-- Dry run by default:   psql -X -c "set role postgres" -f this file
-- Apply:                psql -X -v apply=yes -c "set role postgres" -f this file
-- Refuses to run twice (stops if any of the three titles already exists at Facility 2).
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

select coalesce((select s.id::text from public.sites s where s.name ilike 'Facility 2%' and s.is_active order by s.code limit 1), '') as fac,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+1@gmail.com'), '') as tech1,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+2@gmail.com'), '') as tech2 \gset
select set_config('fmw.fac', :'fac', true), set_config('fmw.tech1', :'tech1', true), set_config('fmw.tech2', :'tech2', true);
select case when :'tech2' <> '' and :'fac' <> '' and public.pilot_account_ready(nullif(:'tech2','')::uuid)
              and public.active_facility_member(nullif(:'fac','')::uuid, 'technician', nullif(:'tech2','')::uuid)
            then :'tech2' else :'tech1' end as tech2 \gset

do $m$
declare fac uuid := nullif(current_setting('fmw.fac'), ''); t uuid; e text;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if fac is null then raise exception 'No active facility named "Facility 2..." found; nothing changed'; end if;
  -- Technician 1 (koi.kpr+1) is required. koi.kpr+2 is optional: if not ready, F2-WO-01 is created by koi.kpr+1 too.
  foreach e in array array['koi.kpr+1@gmail.com'] loop
    select id into t from public.profiles where lower(email) = e;
    if t is null then raise exception '% has no FMWorks account; nothing changed', e; end if;
    if not public.pilot_account_ready(t) or (select role from public.profiles where id = t) <> 'technician' then
      raise exception '% is not an active Technician who has set a password; nothing changed', e; end if;
    if not public.active_facility_member(fac, 'technician', t) then
      raise exception '% is not Technician staff of Facility 2 (Facilities > Facility 2 > Add a staff member); nothing changed', e; end if;
  end loop;
  if exists(select 1 from public.work_orders w where w.facility_id = fac and w.title in (
      'Battery charger BC-05 fault — E12, not charging', 'Freezer unit RU-FZ-B high head-pressure trip', 'CH-01 chiller quarterly service')) then
    raise exception 'These Work Orders already exist at Facility 2; nothing changed'; end if;
end;
$m$;

select coalesce((select a.id::text from public.facility_areas a where a.facility_id = :'fac' and a.area_code = 'F2-1-04'), '') as area04 \gset
select coalesce((select a.id::text from public.facility_areas a where a.facility_id = :'fac' and a.area_code = 'F2-2-10'), '') as area210 \gset
select coalesce((select a.id::text from public.facility_areas a where a.facility_id = :'fac' and a.area_code = 'F2-1-21'), '') as area121 \gset
select coalesce((select c.id::text from public.categories c where c.name ilike '%electric%' order by c.name limit 1), '') as cat_elec \gset
select coalesce((select c.id::text from public.categories c where c.name ~* '(acmv|air|hvac|refrig)' order by c.name limit 1), '') as cat_acmv \gset

-- F2-WO-20 as Technician 1
select set_config('request.jwt.claims', json_build_object('sub', :'tech1', 'role', 'authenticated')::text, true), set_config('request.jwt.claim.sub', :'tech1', true), set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.create_work_order(jsonb_build_object(
  'title', 'Battery charger BC-05 fault — E12, not charging',
  'description', 'Charger BC-05 shows fault E12 and does not charge. Forklift batteries on this charger cannot be charged. Check the input fuse and the battery connector; replace the connector if burnt. Isolate the charger before work. (UAT entry sheet F2-WO-20)',
  'location', '1.04 Battery Charging Room, charger BC-05', 'facility_id', :'fac', 'facility_area_id', :'area04',
  'category_id', :'cat_elec', 'priority', 'medium', 'source', 'reactive', 'in_house_work', true, 'emergency_work', false,
  'due_date', (current_date + 3)::text, 'estimated_hours', 2, 'status', 'draft')) as r1 \gset
set local role postgres;

-- F2-WO-04 as Technician 1
select set_config('request.jwt.claims', json_build_object('sub', :'tech1', 'role', 'authenticated')::text, true), set_config('request.jwt.claim.sub', :'tech1', true), set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.create_work_order(jsonb_build_object(
  'title', 'Freezer unit RU-FZ-B high head-pressure trip',
  'description', 'Freezer refrigeration unit B tripped on high head pressure twice this week; unit A is running alone with no standby. Find the cause (condenser fan, dirty condenser coil or overcharge) and repair. The Freezer must stay below -15 °C throughout the work; stock at risk if unit A also fails. (UAT entry sheet F2-WO-04)',
  'location', '2.10 Freezer (-20 °C), refrigeration unit RU-FZ-B (condensing unit on roof R.04)', 'facility_id', :'fac', 'facility_area_id', :'area210',
  'category_id', :'cat_acmv', 'priority', 'critical', 'source', 'reactive', 'in_house_work', false, 'emergency_work', false,
  'due_date', (current_date + 1)::text, 'estimated_hours', 4, 'status', 'draft')) as r2 \gset
set local role postgres;

-- F2-WO-01 as Technician 2
select set_config('request.jwt.claims', json_build_object('sub', :'tech2', 'role', 'authenticated')::text, true), set_config('request.jwt.claim.sub', :'tech2', true), set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.create_work_order(jsonb_build_object(
  'title', 'CH-01 chiller quarterly service',
  'description', 'Quarterly preventive service of chiller CH-01: check refrigerant charge and leaks, oil sample for analysis, brush condenser tubes if the approach is above 2 °C, check the VSD and log readings. Change over to standby chiller CH-03 during the work so the cold chain and warehouses stay in range. (UAT entry sheet F2-WO-01)',
  'location', '1.21 Central Plant Room, chiller CH-01', 'facility_id', :'fac', 'facility_area_id', :'area121',
  'category_id', :'cat_acmv', 'priority', 'medium', 'source', 'preventive', 'in_house_work', false, 'emergency_work', false,
  'due_date', (current_date + 14)::text, 'estimated_hours', 8, 'status', 'draft')) as r3 \gset
set local role postgres;
select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);

select set_config('fmw.r1', :'r1', true), set_config('fmw.r2', :'r2', true), set_config('fmw.r3', :'r3', true);
do $m$
declare n text; begin
  foreach n in array array['r1','r2','r3'] loop
    if coalesce((current_setting('fmw.'||n)::jsonb ->> 'ok')::boolean, false) is not true then
      raise exception 'Work Order % not created, nothing changed: %', n, current_setting('fmw.'||n); end if;
  end loop;
end;
$m$;

\o
select w.work_order_number, w.title, w.status, w.priority, w.in_house_work, p.email as technician, a.area_code
from public.work_orders w left join public.profiles p on p.id = w.assigned_technician_id
left join public.facility_areas a on a.id = w.facility_area_id
where w.facility_id = :'fac' order by w.created_at;
\if :{?apply}
  \echo 'Applying the change.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

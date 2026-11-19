-- One-off Preview UAT data (owner D-67 D-G, 18-19 Nov 2026), after M36:
--   Facility 2 Daily round: 12 checks with their tick-off items (readings with units where a value must be logged),
--   switched on every day, ready 07:00, due 10:00; done by Technician 2 (koi.kpr+2, or Technician 1 if not ready),
--   covered by Technician 1 (koi.kpr+1). The 12 proposed daily maintenance tasks (Draft) are taken out of use,
--   because the Daily round replaces them. Today's round is created at once.
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
       coalesce((select s.id::text from public.sites s where s.name ilike 'Facility 2%' and s.is_active order by s.code limit 1), '') as fac2,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+1@gmail.com'), '') as tech1,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+2@gmail.com'), '') as tech2 \gset
select set_config('fmw.admin', :'admin', true), set_config('fmw.fac2', :'fac2', true), set_config('fmw.tech1', :'tech1', true), set_config('fmw.tech2', :'tech2', true);

create temp table f2_check(n int primary key, title text, equipment text) on commit drop;
insert into f2_check values
 (1,'Forklift battery chargers','F2-BC-01 TO 12'),
 (2,'Chiller CH-01','F2-CH-01'),(3,'Chiller CH-02','F2-CH-02'),(4,'Chiller CH-03 (standby)','F2-CH-03'),
 (5,'Chiller Room 1 (2–8 °C)','F2-RU-CR1-A/B'),(6,'Chiller Room 2 (2–8 °C)','F2-RU-CR2-A/B'),(7,'Chiller Room 3 (2–8 °C)','F2-RU-CR3-A/B'),
 (8,'Freezer (−20 °C)','F2-RU-FZ-A/B'),(9,'Environmental monitoring system (EMS)','F2-EMS-01'),
 (10,'Oil-free air compressors','F2-CA-01/02'),(11,'GMP suite AHU (HEPA)','F2-AHU-G1'),
 (12,'Purified water system','F2-PW-01, PW-T1, PWP-01/02, UV-01');
create temp table f2_item(n int, pos int, label text, unit text) on commit drop;
insert into f2_item values
 (1,10,'Chargers show normal charge, no fault lights',null),(1,20,'No gassing, smell or heat at the battery bay',null),(1,30,'Hydrogen alarm panel clear',null),(1,40,'Eyewash at the battery bay ready',null),
 (2,10,'Chilled water supply temperature','°C'),(2,20,'Chilled water return temperature','°C'),(2,30,'Compressor current','A'),(2,40,'No alarms on the chiller panel',null),
 (3,10,'Chilled water supply temperature','°C'),(3,20,'Chilled water return temperature','°C'),(3,30,'Compressor current','A'),(3,40,'No alarms on the chiller panel',null),
 (4,10,'Standby chiller ready, no alarms',null),
 (5,10,'Room temperature on the EMS (2–8 °C)','°C'),(5,20,'Duty unit running, standby healthy',null),(5,30,'Door closes and seals, no ice',null),(5,40,'No open alarms',null),
 (6,10,'Room temperature on the EMS (2–8 °C)','°C'),(6,20,'Duty unit running, standby healthy',null),(6,30,'Door closes and seals, no ice',null),(6,40,'No open alarms',null),
 (7,10,'Room temperature on the EMS (2–8 °C)','°C'),(7,20,'Duty unit running, standby healthy',null),(7,30,'Door closes and seals, no ice',null),(7,40,'No open alarms',null),
 (8,10,'Freezer temperature on the EMS (−20 °C or colder)','°C'),(8,20,'Both units healthy',null),(8,30,'No ice on the coils',null),(8,40,'Door seals and heater strips working',null),
 (9,10,'All sensors online',null),(9,20,'No open alarms',null),(9,30,'Data recording (latest reading is today)',null),
 (10,10,'Line pressure','bar'),(10,20,'Dew point','°C'),(10,30,'Auto-drains working',null),
 (11,10,'Room pressure differentials within limits','Pa'),(11,20,'Filter gauges below the change mark',null),(11,30,'AHU running, no alarms',null),
 (12,10,'Conductivity','µS/cm'),(12,20,'TOC','ppb'),(12,30,'UV lamp on, hours within limit',null),(12,40,'No alarms',null);

do $m$
declare admin uuid; fac uuid; t1 uuid; t2 uuid; r jsonb; c record; i record; cid uuid; nchecks int := 0; nitems int := 0; retired int := 0; q record;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if to_regprocedure('public.create_daily_round(uuid,date)') is null then raise exception 'M36 is not applied; nothing changed'; end if;
  admin := nullif(current_setting('fmw.admin'), '')::uuid; fac := nullif(current_setting('fmw.fac2'), '')::uuid;
  t1 := nullif(current_setting('fmw.tech1'), '')::uuid; t2 := nullif(current_setting('fmw.tech2'), '')::uuid;
  if admin is null or not public.pilot_account_ready(admin) then raise exception 'Super-Administrator not found or not ready; nothing changed'; end if;
  if fac is null then raise exception 'No active facility named "Facility 2..."; nothing changed'; end if;
  if t1 is null or not public.active_facility_member(fac, 'technician', t1) then raise exception 'Technician 1 is not a Technician of Facility 2; nothing changed'; end if;
  if t2 is null or not public.pilot_account_ready(t2) or not public.active_facility_member(fac, 'technician', t2) then t2 := t1; end if;
  if exists(select 1 from public.daily_round_checks where facility_id = fac) then raise exception 'Facility 2 already has a Daily round checklist (this script has run before); nothing changed'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated')::text, true),
          set_config('request.jwt.claim.sub', admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  for c in select * from f2_check order by n loop
    r := public.save_daily_round_check(null, fac, c.title, c.equipment, c.n * 10, true);
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Check % not saved, nothing changed: %', c.title, r; end if;
    cid := (r ->> 'id')::uuid; nchecks := nchecks + 1;
    for i in select * from f2_item where n = c.n order by pos loop
      r := public.save_daily_round_item(null, cid, i.label, i.unit, i.pos, true);
      if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Item % not saved, nothing changed: %', i.label, r; end if;
      nitems := nitems + 1;
    end loop;
  end loop;
  r := public.set_daily_round_settings(fac, true, t2, case when t2 = t1 then null else t1 end, '07:00', '10:00', 'Owner D-67: every day, ready 07:00, due 10:00; Technician 2 does it, Technician 1 covers');
  if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Settings not saved, nothing changed: %', r; end if;
  for q in select m.id from public.maintenance_requirements m join public.assets a on a.id = m.asset_id join public.maintenance_requirement_revisions v on v.id = m.current_revision_id
           where a.facility_id = fac and m.state = 'draft' and v.interval_unit = 'day' loop
    r := public.deactivate_pm_requirement(q.id, 'Replaced by the Daily round (owner D-67 D-F)', false);
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Daily task not retired, nothing changed: %', r; end if;
    retired := retired + 1;
  end loop;
  r := public.create_daily_round(fac, public.pm_business_date());
  if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Today''s round not created, nothing changed: %', r; end if;
  perform set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
  perform set_config('fmw.summary', format('%s checks with %s items; %s proposed daily tasks taken out of use; today''s round %s', nchecks, nitems, retired, coalesce(r ->> 'work_order_number', r ->> 'code')), true);
end;
$m$;
\o
select current_setting('fmw.summary') as done;
select c.title as "check", count(i.id) as items, count(i.reading_unit) as readings from public.daily_round_checks c join public.daily_round_items i on i.check_id = c.id
where c.facility_id = current_setting('fmw.fac2')::uuid group by c.title, c.position order by c.position;
select w.work_order_number, w.title, w.status, p.display_name as technician from public.work_orders w left join public.profiles p on p.id = w.assigned_technician_id
where w.facility_id = current_setting('fmw.fac2')::uuid and w.daily_round_date is not null;
\if :{?apply}
  \echo 'apply=yes: committing.'
  commit;
\else
  \echo 'Dry run only: rolled back. Run again with -v apply=yes to keep it.'
  rollback;
\endif

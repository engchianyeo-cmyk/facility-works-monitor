-- One-off Preview UAT data (owner, 21 Nov 2026), after M38:
--   Normal ranges and short guides for the Facility 2 Daily round readings, so the Technician can judge OK / Not OK.
--   These are typical values for a pharmaceutical cold-chain site, PROPOSED for UAT; the Facility Manager or Supervisor
--   confirms or changes each one on Daily round › Set up (from the equipment manuals and the site's GMP limits).
--   Items whose limit depends on the nameplate get a guide only; tick-only items get a guide on what "OK" looks like.
-- Through the app's own function, as the Super-Administrator (engchian.yeo@gmail.com); audited. Changes only items
-- that have no range and no guide yet, so running it twice changes nothing.
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

create temp table f2_range(label text primary key, lo numeric, hi numeric, guide text) on commit drop;
insert into f2_range values
 -- Chillers
 ('Chilled water supply temperature', 6, 8, 'Design about 7 °C; check against the chiller panel set point'),
 ('Chilled water return temperature', 11, 14, 'Usually about 5 °C warmer than the supply'),
 ('Compressor current', null, null, 'Not above the nameplate full-load current (RLA); note a big change from yesterday'),
 ('No alarms on the chiller panel', null, null, 'Panel shows no active or unacknowledged alarm'),
 -- Cold rooms and freezer
 ('Room temperature on the EMS (2–8 °C)', 2, 8, 'Product storage limit; an EMS alarm also counts as Not OK'),
 ('Freezer temperature on the EMS (−20 °C or colder)', null, -20, 'Colder is fine; warmer than −20 °C is Not OK'),
 -- Oil-free air compressors
 ('Line pressure', 6, 7.5, 'Header pressure after the receiver; below 6 bar starves the users, above 7.5 bar check the controller'),
 ('Dew point', null, -40, 'Pressure dew point from the desiccant dryer: −40 °C or drier (ISO 8573-1 Class 2 for GMP use)'),
 ('Auto-drains working', null, null, 'Press the drain test button: it discharges, then the drain line runs dry'),
 -- GMP suite AHU
 ('Room pressure differentials within limits', 10, 15, 'Between cleanroom grades (EU GMP Annex 1 guidance 10–15 Pa); doors closed when reading'),
 ('Filter gauges below the change mark', null, null, 'Needle below the red change mark (about twice the clean-filter reading)'),
 ('AHU running, no alarms', null, null, 'Supply fan running; no alarm on the AHU panel or the BMS'),
 -- Purified water
 ('Conductivity', null, 1.3, 'USP <645> stage 1 limit at 25 °C'),
 ('TOC', null, 500, 'USP <643> limit'),
 ('UV lamp on, hours within limit', null, null, 'Lamp-on light lit; hours below the rated lamp life on the unit (often 8,000–9,000 h)'),
 ('No alarms', null, null, 'No alarm on the purified water panel or the EMS');

do $m$
declare admin uuid; fac uuid; r jsonb; i record; n int := 0; skipped int := 0;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if to_regprocedure('public.save_daily_round_item(uuid,uuid,text,text,integer,boolean,numeric,numeric,text)') is null then raise exception 'M38 is not applied; nothing changed'; end if;
  admin := nullif(current_setting('fmw.admin'), '')::uuid; fac := nullif(current_setting('fmw.fac2'), '')::uuid;
  if admin is null or not public.pilot_account_ready(admin) then raise exception 'Super-Administrator not found or not ready; nothing changed'; end if;
  if fac is null then raise exception 'No active facility named "Facility 2..."; nothing changed'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated')::text, true),
          set_config('request.jwt.claim.sub', admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  for i in select it.*, f.lo, f.hi, f.guide from public.daily_round_items it join public.daily_round_checks c on c.id = it.check_id
           join f2_range f on f.label = it.label where c.facility_id = fac and it.active order by c.position, it.position loop
    if i.reading_min is not null or i.reading_max is not null or i.reading_guide is not null then skipped := skipped + 1; continue; end if;
    r := public.save_daily_round_item(i.id, null, i.label, i.reading_unit, i.position, true, i.lo, i.hi, i.guide);
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Item % not saved, nothing changed: %', i.label, r; end if;
    n := n + 1;
  end loop;
  perform set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
  perform set_config('fmw.summary', format('%s items given a range or guide; %s already had one (left as they are)', n, skipped), true);
end;
$m$;
\o
select current_setting('fmw.summary') as done;
select c.title as "check", i.label as reading, public.daily_round_range_text(i.reading_min, i.reading_max, i.reading_unit) as normal, i.reading_guide as guide
from public.daily_round_items i join public.daily_round_checks c on c.id = i.check_id
where c.facility_id = current_setting('fmw.fac2')::uuid and i.active and (i.reading_unit is not null or i.reading_guide is not null) order by c.position, i.position;
\if :{?apply}
  \echo 'apply=yes: committing.'
  commit;
\else
  \echo 'Dry run only: rolled back. Run again with -v apply=yes to keep it.'
  rollback;
\endif

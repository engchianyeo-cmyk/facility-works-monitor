-- One-off Preview UAT data (owner D-82 / M40, 22 Nov 2026): make Facility One live, and tidy Facility 2's staff.
--   A. Staff: end the leftover "approver" memberships of Facility 2's Supervisor 1 and Facility Manager (their account
--      roles are Supervisor and Facility Manager; approval follows the account role), end facility_king@yahoo.com's
--      Facility One membership (replaced by sctpec2413+f1fm@gmail.com), and name Facility 2's Facility Manager its
--      designated Approver. Memberships are ended with a reason, never deleted.
--   B. Assets with no facility recorded (and no F2- tag) are recorded as Facility One's.
--   C. A maintenance task set for each Facility One asset, worked out from its type (chiller, cooling tower, pump,
--      AHU, split AC, fan, electrical, transformer, solar, generator, plumbing, lift, fire; otherwise an annual inspection). First
--      visits are spread over each period. Mechanical work -> Yang Ying Zhang (koi.kpr), electrical -> Ying Zhang
--      (ec@glorybene.com); contractor work is left for the Supervisor to assign. All Active.
--   D. A Daily round checklist for the Facility One plant that exists (chillers with ranges, cooling towers, pumps,
--      AHUs, split AC, electrical, solar, generator, plant-room walk), every day 07:00-10:00, Yang Ying Zhang with
--      Ying Zhang covering.
--   E. Planned maintenance at Facility One: Full for critical equipment (owner, 22 Nov); today's round is created.
-- Through the app's own functions, as the Super-Administrator (engchian.yeo@gmail.com); audited. Parts C and D are
-- skipped if Facility One already has maintenance tasks or a checklist, so a second run changes nothing further.
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
       coalesce((select s.id::text from public.sites s where s.code = 'UAT-FAC-001' and s.is_active), '') as fac1,
       coalesce((select s.id::text from public.sites s where s.name ilike 'Facility 2%' and s.is_active order by s.code limit 1), '') as fac2 \gset
select set_config('fmw.admin', :'admin', true), set_config('fmw.fac1', :'fac1', true), set_config('fmw.fac2', :'fac2', true);

-- C. Tasks by kind of equipment: kind, order, title, interval, contractor work?
create temp table f1_kind(kind text, pos int, title text, iv int, iu text, contractor boolean) on commit drop;
insert into f1_kind values
 ('chiller',1,'Monthly check: refrigerant pressures, oil level, leaks; log readings',1,'month',false),
 ('chiller',2,'Quarterly service per the O&M manual (chiller contractor)',3,'month',true),
 ('chiller',3,'Annual service: condenser tube cleaning, controls calibration (chiller contractor)',1,'year',true),
 ('tower',1,'Water treatment dosing and Legionella control test',1,'month',false),
 ('tower',2,'Clean basin and strainer; check fan, belts and drift eliminators',3,'month',false),
 ('tower',3,'Annual disinfection and inspection (water treatment contractor)',1,'year',true),
 ('pump',1,'Check vibration, noise, seal leaks and pressures; change over duty and standby',1,'month',false),
 ('pump',2,'Bearing lubrication, coupling alignment, motor insulation test',1,'year',false),
 ('ahu',1,'Check filters, belts and drain pan; record filter pressure drop',1,'month',false),
 ('ahu',2,'Clean coil and drain pan; check fan bearings and dampers',3,'month',false),
 ('ahu',3,'Annual service per the O&M manual',1,'year',false),
 ('splitac',1,'Clean filters and coils; check refrigerant and drain',3,'month',false),
 ('splitac',2,'Annual service per the O&M manual',1,'year',false),
 ('fan',1,'Check fan running, bearings, belts and controls',3,'month',false),
 ('fan',2,'Annual service per the O&M manual',1,'year',false),
 ('electrical',1,'Visual check: no heat, smell or tripped breakers; panel locked',3,'month',false),
 ('electrical',2,'Thermographic scan and terminal tightening (electrical contractor)',1,'year',true),
 ('transformer',1,'Check temperature, oil level, silica gel and noise',1,'month',false),
 ('transformer',2,'Annual servicing and testing (licensed electrical contractor)',1,'year',true),
 ('solar',1,'Check inverter faults, ventilation and generation against expected',3,'month',false),
 ('solar',2,'Annual inspection and panel cleaning (solar contractor)',1,'year',true),
 ('generator',1,'Run on load 30 min; check fuel, batteries, coolant, leaks',1,'month',false),
 ('generator',2,'Annual service and load bank test (generator contractor)',1,'year',true),
 ('plumbing',1,'Check taps, drains and pipework for leaks and blockages',6,'month',false),
 ('lift',1,'Statutory monthly servicing (lift contractor)',1,'month',true),
 ('lift',2,'Annual inspection and certification (lift contractor and authorised examiner)',1,'year',true),
 ('fire',1,'Test a zone and check the panel, batteries and faults',1,'month',false),
 ('fire',2,'Annual fire protection servicing and certification (fire contractor)',1,'year',true),
 ('other',1,'Annual inspection per the O&M manual',1,'year',false);

-- D. Daily round checks, added only when the equipment exists at Facility One
create temp table f1_check(n int primary key, title text, tag_like text, equipment text) on commit drop;
insert into f1_check values
 (1,'Chiller CH-01','CH-01','CH-01'),(2,'Chiller CH-02','CH-02','CH-02'),
 (3,'Cooling towers','CT-%','CT-01, CT-02'),(4,'Chilled water pumps','CHWP-%','CHWP-01, CHWP-02'),
 (5,'Condenser water pumps','CWP-%','CWP-01, CWP-02'),(6,'Air handling units','AHU-%','AHU-01, AHU-02'),
 (7,'Split air-conditioning units','ACCU-%','ACCU-01 to 03'),(8,'Electrical rooms','TR-%','TR-01, distribution boards'),
 (9,'Solar PV inverters','INV-PV-%','INV-PV'),(10,'Standby generator','GEN-%','GEN');
create temp table f1_item(n int, pos int, label text, unit text, lo numeric, hi numeric, guide text) on commit drop;
insert into f1_item values
 (1,10,'Chilled water supply temperature','°C',6,8,'Design about 7 °C; check against the chiller panel set point'),
 (1,20,'Chilled water return temperature','°C',11,14,'Usually about 5 °C warmer than the supply'),
 (1,30,'Compressor current','A',null,null,'Not above the nameplate full-load current (RLA); note a big change from yesterday'),
 (1,40,'No alarms on the chiller panel',null,null,null,'Panel shows no active or unacknowledged alarm'),
 (2,10,'Chilled water supply temperature','°C',6,8,'Design about 7 °C; check against the chiller panel set point'),
 (2,20,'Chilled water return temperature','°C',11,14,'Usually about 5 °C warmer than the supply'),
 (2,30,'Compressor current','A',null,null,'Not above the nameplate full-load current (RLA); note a big change from yesterday'),
 (2,40,'No alarms on the chiller panel',null,null,null,'Panel shows no active or unacknowledged alarm'),
 (3,10,'Fans running, no unusual noise or vibration',null,null,null,'Listen at each fan deck; no rattles or belt squeal'),
 (3,20,'Basin water level normal, make-up valve working',null,null,null,'Level between the marks; no overflow'),
 (3,30,'Leaving condenser water temperature','°C',null,32,'Design about 32 °C leaving the towers'),
 (4,10,'Duty pump running, standby healthy',null,null,null,'Standby selector in Auto; no trip lamp'),
 (4,20,'No leaks at seals; no unusual noise or vibration',null,null,null,'Dry floor under the pumps'),
 (5,10,'Duty pump running, standby healthy',null,null,null,'Standby selector in Auto; no trip lamp'),
 (5,20,'No leaks at seals; no unusual noise or vibration',null,null,null,'Dry floor under the pumps'),
 (6,10,'AHUs running, no alarms',null,null,null,'Fan running; no alarm on the AHU panel or the BMS'),
 (6,20,'Supply air temperature','°C',12,16,'Usually 13–15 °C off the cooling coil'),
 (6,30,'Filter gauges below the change mark',null,null,null,'Needle below the red change mark (about twice the clean-filter reading)'),
 (7,10,'Units running, no fault codes on the controllers',null,null,null,'Each controller shows the set point, no error code'),
 (7,20,'Condensing units: no unusual noise; drains clear',null,null,null,'No water pooling under the indoor units'),
 (8,10,'No heat, smell or tripped breakers in the switch and transformer rooms',null,null,null,'Doors locked; room cool; no burning smell'),
 (8,20,'Transformer winding temperature below the alarm mark',null,null,null,'Read the temperature indicator; note it if near the alarm needle'),
 (9,10,'Inverters online, no fault lights',null,null,null,'Display shows generation; no fault code'),
 (10,10,'Fuel level above three-quarters; no leaks',null,null,null,'Read the day-tank gauge'),
 (10,20,'Battery charger normal; panel in Auto, no alarms',null,null,null,'Charger lamp green; selector in Auto');

do $m$
declare admin uuid; fac1 uuid; fac2 uuid; t_mech uuid; t_elec uuid; fm2 uuid; fk uuid; sup1 uuid; r jsonb; a record; k record; c record; i record;
  cid uuid; rid uuid; v_kind text; tech uuid; n int := 0; ended int := 0; tagged int := 0; tasks int := 0; assigned int := 0; checks int := 0; items int := 0;
  days int; stage text; summary text := '';
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if not exists(select 1 from information_schema.columns where table_schema = 'public' and table_name = 'incidents' and column_name = 'facility_id') then raise exception 'M39 is not applied; nothing changed'; end if;
  admin := nullif(current_setting('fmw.admin'), '')::uuid; fac1 := nullif(current_setting('fmw.fac1'), '')::uuid; fac2 := nullif(current_setting('fmw.fac2'), '')::uuid;
  if admin is null or not public.pilot_account_ready(admin) then raise exception 'Super-Administrator not found or not ready; nothing changed'; end if;
  if fac1 is null or fac2 is null then raise exception 'Facility One (UAT-FAC-001) or Facility 2 not found; nothing changed'; end if;
  select id into t_mech from public.profiles where lower(email) = 'koi.kpr@gmail.com';
  select id into t_elec from public.profiles where lower(email) = 'ec@glorybene.com';
  if t_mech is null or not public.active_facility_member(fac1, 'technician', t_mech) then raise exception 'Yang Ying Zhang is not a Technician of Facility One; nothing changed'; end if;
  if t_elec is null or not public.pilot_account_ready(t_elec) or not public.active_facility_member(fac1, 'technician', t_elec) then t_elec := t_mech; end if;
  select id into fm2 from public.profiles where lower(email) = 'fmworks.notices@yahoo.com' and role = 'facility_manager';
  select id into sup1 from public.profiles where lower(email) = 'sctpec2413+1@gmail.com';
  select id into fk from public.profiles where lower(email) = 'facility_king@yahoo.com';
  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated')::text, true),
          set_config('request.jwt.claim.sub', admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);

  -- A. Staff
  insert into public.activity_logs(user_id, action, actor, note)
  select admin, 'facility_staff_removed', 'Rollout script (as Super-Administrator)', jsonb_build_object('facility_id', fac2, 'profile_id', p.id, 'display_name', p.display_name,
    'role', 'approver', 'reason', 'Leftover Approver membership from an earlier role; approval follows the account role (owner, 22 Nov 2026)', 'script', 'preview-m40-facility-one-live-20261122')::text
  from public.profiles p where p.id in (fm2, sup1) and p.role <> 'approver'
    and exists(select 1 from public.facility_memberships m where m.profile_id = p.id and m.facility_id = fac2 and m.active and m.membership_role = 'approver');
  update public.facility_memberships m set active = false, effective_to = greatest(now(), m.effective_from + interval '1 millisecond'), updated_at = now()
  from public.profiles p where p.id = m.profile_id and m.facility_id = fac2 and m.active and m.membership_role = 'approver' and p.role <> 'approver' and p.id in (fm2, sup1);
  get diagnostics n = row_count; ended := ended + n;
  if fk is not null and exists(select 1 from public.facility_memberships where facility_id = fac1 and profile_id = fk and active) then
    r := public.admin_set_facility_membership(fac1, fk, false, 'Replaced as Facility One Facility Manager by sctpec2413+f1fm@gmail.com; facility_king@yahoo.com is the app''s email sender (owner, 22 Nov 2026)');
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'facility_king not removed from Facility One, nothing changed: %', r; end if;
    ended := ended + 1;
  end if;
  if fm2 is not null then
    select endorsement_stage into stage from public.facility_settings where facility_id = fac2;
    r := public.set_facility_settings(fac2, fm2, coalesce(stage, 'before_review'), 'Facility Manager is the designated Approver; Supervisors approve too (owner, 22 Nov 2026)');
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Facility 2 designated Approver not set, nothing changed: %', r; end if;
  end if;
  summary := format('A. %s leftover membership(s) ended; Facility 2 designated Approver = its Facility Manager. ', ended);

  -- B. Assets with no facility recorded
  for a in select id, asset_tag from public.assets where facility_id is null and asset_tag !~* '^F2-' and lifecycle_status <> 'decommissioned' loop
    update public.assets set facility_id = fac1, updated_at = now(), updated_by = admin where id = a.id;
    insert into public.activity_logs(user_id, asset_id, action, actor, note) values (admin, a.id, 'asset_facility_recorded', 'Rollout script (as Super-Administrator)',
      jsonb_build_object('asset_tag', a.asset_tag, 'facility', 'Facility One', 'reason', 'No facility was recorded; Facility One goes live (owner, 22 Nov 2026)', 'script', 'preview-m40-facility-one-live-20261122')::text);
    tagged := tagged + 1;
  end loop;
  summary := summary || format('B. %s asset(s) recorded as Facility One''s. ', tagged);

  -- C. Maintenance tasks
  if exists(select 1 from public.maintenance_requirements q join public.assets s on s.id = q.asset_id where s.facility_id = fac1 and q.state in ('active','draft')) then
    summary := summary || 'C. Facility One already has maintenance tasks; none added. ';
  else
    n := 0;
    for a in select * from public.assets where facility_id = fac1 and lifecycle_status = 'active' order by asset_tag loop
      v_kind := case
        when a.asset_tag ~* '^CH-' or a.asset_type ~* 'chiller' then 'chiller'
        when a.asset_tag ~* '^CT-' or a.asset_type ~* 'cooling tower' then 'tower'
        when a.asset_tag ~* '^(CHWP|CWP)-' or a.asset_type ~* 'pump' then 'pump'
        when a.asset_tag ~* '^AHU-' or a.asset_type ~* 'air handling' then 'ahu'
        when a.asset_tag ~* '^(ACCU|FCU|SAC)-' or a.asset_type ~* 'condens|split|fan coil|compressor' then 'splitac'
        when a.asset_tag ~* '^(EF|SF|FAN)-' or a.asset_type ~* 'fan' then 'fan'
        when a.asset_tag ~* '^TR-' or a.asset_type ~* 'transformer' then 'transformer'
        when a.asset_tag ~* '^(DB|MSB|SSB|LV)-' or a.asset_type ~* 'switch|distribution|electrical|board' then 'electrical'
        when a.asset_tag ~* '^(INV|PV)-' or a.asset_type ~* 'solar|inverter|photovoltaic' then 'solar'
        when a.asset_tag ~* '^GEN-' or a.asset_type ~* 'generator' then 'generator'
        when a.asset_tag ~* '^(PLB|WB)-' or a.asset_type ~* 'basin|plumb|tap|toilet|water heater' then 'plumbing'
        when a.asset_tag ~* '^(LIFT|LF|ESC)-' or a.asset_type ~* 'lift|elevator|escalator' then 'lift'
        when a.asset_tag ~* '^(FA|FAP|SPK|FP|FH)-' or a.asset_type ~* 'fire|sprinkler|hose reel|smoke' then 'fire'
        else 'other' end;
      for k in select * from f1_kind where f1_kind.kind = v_kind order by pos loop
        days := case k.iu when 'month' then 28 * k.iv when 'year' then 336 else 7 * k.iv end;
        r := public.create_pm_requirement(jsonb_build_object('asset_id', a.id, 'title', k.title,
               'scope', k.title || ' — ' || a.name || coalesce(' at ' || a.location, '') || '. Cross-reference the O&M manual for this equipment.',
               'maintenance_type', 'preventive', 'interval_value', k.iv, 'interval_unit', k.iu,
               'first_due_date', (public.pm_business_date() + 7 + ((n * 5 + k.pos * 3) % days))::text, 'effective_date', public.pm_business_date()::text,
               'default_priority', case a.criticality when 'critical' then 'high' when 'high' then 'medium' else 'low' end));
        if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Task % on % not created, nothing changed: %', k.title, a.asset_tag, r; end if;
        rid := (r -> 'requirement' ->> 'id')::uuid; tasks := tasks + 1;
        r := public.activate_pm_requirement(rid, 'Facility One goes live (owner, 22 Nov 2026)');
        if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Task % on % not activated, nothing changed: %', k.title, a.asset_tag, r; end if;
        tech := case when k.contractor then null when v_kind in ('electrical','transformer','solar','generator') then t_elec else t_mech end;
        if tech is not null then
          r := public.assign_pm_technician(rid, tech);
          if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Technician not assigned for % on %, nothing changed: %', k.title, a.asset_tag, r; end if;
          assigned := assigned + 1;
        end if;
      end loop;
      n := n + 1;
    end loop;
    summary := summary || format('C. %s assets, %s tasks (all Active), %s with a Technician. ', n, tasks, assigned);
  end if;

  -- D. Daily round
  if exists(select 1 from public.daily_round_checks where facility_id = fac1) then
    summary := summary || 'D. Facility One already has a Daily round checklist; none added. ';
  else
    for c in select * from f1_check order by n loop
      continue when not exists(select 1 from public.assets s where s.facility_id = fac1 and s.lifecycle_status = 'active' and s.asset_tag ilike c.tag_like);
      r := public.save_daily_round_check(null, fac1, c.title, c.equipment, c.n * 10, true);
      if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Check % not saved, nothing changed: %', c.title, r; end if;
      cid := (r ->> 'id')::uuid; checks := checks + 1;
      for i in select * from f1_item where f1_item.n = c.n order by pos loop
        r := public.save_daily_round_item(null, cid, i.label, i.unit, i.pos, true, i.lo, i.hi, i.guide);
        if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Item % not saved, nothing changed: %', i.label, r; end if;
        items := items + 1;
      end loop;
    end loop;
    r := public.save_daily_round_check(null, fac1, 'Plant rooms walk-round', 'All plant rooms', 200, true);
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Walk-round check not saved, nothing changed: %', r; end if;
    cid := (r ->> 'id')::uuid; checks := checks + 1;
    r := public.save_daily_round_item(null, cid, 'No water leaks, smells or obstructions in the plant rooms', null, 10, true, null, null, 'Floors dry; access routes clear');
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Walk-round item not saved, nothing changed: %', r; end if;
    items := items + 1;
    r := public.set_daily_round_settings(fac1, true, t_mech, case when t_elec = t_mech then null else t_elec end, '07:00', '10:00', 'Facility One goes live: every day 07:00-10:00, Yang Ying Zhang, Ying Zhang covers (owner, 22 Nov 2026)');
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Daily round settings not saved, nothing changed: %', r; end if;
    summary := summary || format('D. %s checks with %s items. ', checks, items);
  end if;

  -- E. Planned maintenance setting, then today's round (the round needs the setting not to be Off)
  r := public.admin_set_pm_mode(fac1, 'full_critical', 'Facility One goes live: Work Orders for critical equipment (owner, 22 Nov 2026)');
  if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Planned maintenance setting not saved, nothing changed: %', r; end if;
  if exists(select 1 from public.daily_round_checks where facility_id = fac1 and active) then
    r := public.create_daily_round(fac1, public.pm_business_date());
    summary := summary || format('E. Full for critical equipment; today''s round: %s.', coalesce(r ->> 'work_order_number', r ->> 'code', r ->> 'message'));
  else
    summary := summary || 'E. Full for critical equipment.';
  end if;
  perform set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
  perform set_config('fmw.summary', summary, true);
end;
$m$;
\o
select current_setting('fmw.summary') as done;
\echo 'Facility One equipment and its maintenance tasks:'
select a.asset_tag, a.asset_type, a.criticality, count(q.id) as tasks, coalesce(string_agg(distinct v.interval_value || ' ' || v.interval_unit, ', '), '') as every,
       coalesce(string_agg(distinct p.display_name, ', '), 'not assigned') as technician
from public.assets a left join public.maintenance_requirements q on q.asset_id = a.id and q.state = 'active'
left join public.maintenance_requirement_revisions v on v.id = q.current_revision_id left join public.profiles p on p.id = q.assigned_technician_id
where a.facility_id = current_setting('fmw.fac1')::uuid group by a.asset_tag, a.asset_type, a.criticality order by a.asset_tag;
\echo 'Facility One Daily round:'
select c.title as "check", i.label as item, coalesce(public.daily_round_range_text(i.reading_min, i.reading_max, i.reading_unit), '') as normal
from public.daily_round_checks c join public.daily_round_items i on i.check_id = c.id where c.facility_id = current_setting('fmw.fac1')::uuid order by c.position, i.position;
\echo 'Memberships whose role differs from the account role, and facility_king (should be none):'
select s.code, p.display_name, p.email, m.membership_role from public.facility_memberships m join public.profiles p on p.id = m.profile_id join public.sites s on s.id = m.facility_id
where m.active and (m.effective_to is null or m.effective_to > now()) and (m.membership_role <> p.role or lower(p.email) = 'facility_king@yahoo.com') order by 1, 2;
\echo 'Facility settings:'
select s.name, fs.pm_mode, fs.daily_round_enabled, (select display_name from public.profiles where id = fs.designated_approver_id) as designated_approver
from public.sites s left join public.facility_settings fs on fs.facility_id = s.id where s.is_active order by s.name;
\if :{?apply}
  \echo 'apply=yes: committing.'
  commit;
\else
  \echo 'Dry run only: rolled back. Run again with -v apply=yes to keep it.'
  rollback;
\endif

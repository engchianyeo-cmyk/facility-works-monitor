-- One-off Preview UAT data (owner, 17 Nov 2026): Facility 2 maintenance plan after M34.
--   73 pieces of equipment (asset tags prefixed F2-) and 97 maintenance tasks from the reviewed plan:
--   daily 12, weekly 5, monthly 12, quarterly 34, six-monthly 11, annual 23.
--   Daily checks stay DRAFT (proposed, owner to confirm); all other tasks are made Active.
--   Default Technician: in-house / both, Electrical-Fire-Safety-Plumbing-Controls -> Technician 1 (koi.kpr+1);
--   other in-house / both -> koi.kpr+2 if ready, else koi.kpr+1; contractor work -> not assigned.
-- Tasks go through the app's own create_pm_requirement / activate_pm_requirement / assign_pm_technician, acting as
-- the Super-Administrator (engchian.yeo@gmail.com), so each step is audited. Assets are written directly with
-- facility = Facility 2 (create_asset has no facility field) plus the same 'asset_created' audit entry.
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
       coalesce((select s.name from public.sites s where s.name ilike 'Facility 2%' and s.is_active order by s.code limit 1), '') as fac2name,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+1@gmail.com'), '') as tech1,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+2@gmail.com'), '') as tech2 \gset
select set_config('fmw.admin', :'admin', true), set_config('fmw.fac2', :'fac2', true), set_config('fmw.fac2name', :'fac2name', true),
       set_config('fmw.tech1', :'tech1', true), set_config('fmw.tech2', :'tech2', true);

create temp table f2_eq(i int primary key, tag text, name text, discipline text, criticality text, location text, provider text, tech text) on commit drop;
insert into f2_eq values
  (0,'F2-TX-01','HT/LT transformer No. 1','Electrical','critical','1.13 Main LV Switch Room & Substation','Contractor','none'),
  (1,'F2-TX-02','HT/LT transformer No. 2','Electrical','critical','1.13 Main LV Switch Room & Substation','Contractor','none'),
  (2,'F2-MSB-01','Main switchboard','Electrical','critical','1.13 Main LV Switch Room & Substation','Contractor','none'),
  (3,'F2-GEN-01','Standby diesel generator','Electrical','critical','North yard, grid 9–10 at the boundary','Both','A'),
  (4,'F2-ATS-01','Automatic transfer switch (essential board)','Electrical','critical','1.13 Main LV Switch Room & Substation','In-house','A'),
  (5,'F2-UPS-01','UPS — cold rooms, EMS, vault security','Electrical','critical','M1.19 Server Room','Contractor','none'),
  (6,'F2-UPS-02','UPS — server room and network','Electrical','high','M1.19 Server Room','Contractor','none'),
  (7,'F2-PV-ARR-01','Solar PV array (west and east roofs)','Electrical','medium','R.01 / R.02 Roof','Contractor','none'),
  (8,'F2-PV-INV-01 TO 04','Solar PV string inverters','Electrical','medium','Roof plant area beside R.07','Contractor','none'),
  (9,'F2-BC-01 TO 12','Forklift battery chargers','Electrical','medium','1.04 Battery Charging Room','In-house','A'),
  (10,'F2-CH-01','Water-cooled centrifugal chiller No. 1','ACMV','critical','1.21 Central Plant Room','Contractor','none'),
  (11,'F2-CH-02','Water-cooled centrifugal chiller No. 2','ACMV','critical','1.21 Central Plant Room','Contractor','none'),
  (12,'F2-CH-03','Water-cooled centrifugal chiller No. 3 (standby)','ACMV','critical','1.21 Central Plant Room','Contractor','none'),
  (13,'F2-CT-01 TO 03','Cooling towers','ACMV','critical','R.03 Roof, grid 10–12 / D','Contractor','none'),
  (14,'F2-CHWP-01 TO 04','Chilled water pumps','ACMV','high','1.21 Central Plant Room','In-house','B'),
  (15,'F2-CWP-01 TO 04','Condenser water pumps','ACMV','high','1.21 Central Plant Room','In-house','B'),
  (16,'F2-AHU-1-1 TO 1-5','AHUs — Level 1 aircon warehouses','ACMV','high','M1.09 AHU Room 1 / M1.12 AHU Room 2','Both','B'),
  (17,'F2-AHU-2-1 TO 2-4','AHUs — Level 2 aircon warehouses','ACMV','high','M2.33 AHU Room 3','Both','B'),
  (18,'F2-AHU-L1','Laboratory AHU (100 % fresh air)','ACMV','high','M2.27 AHU Room','Contractor','none'),
  (19,'F2-FH-01 TO 06','Laboratory fume cupboards','ACMV','high','M2.21 QA/QC Lab / M2.22 R&D Lab','Contractor','none'),
  (20,'F2-VRF-01 TO 04','VRF outdoor units — offices (Level 2 office, mezzanine offices)','ACMV','medium','Roof beside R.04','Contractor','none'),
  (21,'F2-SEF-01 TO 08','Warehouse smoke exhaust fans','Fire / ACMV','critical','Roof — warehouse zones','Contractor','none'),
  (22,'F2-DC-01','Dust collector — redressing and packing areas','ACMV','high','R.05 Roof','In-house','B'),
  (23,'F2-EF-R1 TO R6','Roof exhaust fans (toilets, battery room, redressing)','ACMV','medium','R.05 Roof','In-house','B'),
  (24,'F2-RU-CR1-A/B','Refrigeration units — Chiller Room 1','Cold chain','critical','R.04 Roof / 2.07 Chiller Room 1','Contractor','none'),
  (25,'F2-RU-CR2-A/B','Refrigeration units — Chiller Room 2','Cold chain','critical','R.04 Roof / 2.08 Chiller Room 2','Contractor','none'),
  (26,'F2-RU-CR3-A/B','Refrigeration units — Chiller Room 3','Cold chain','critical','R.04 Roof / 2.09 Chiller Room 3','Contractor','none'),
  (27,'F2-RU-FZ-A/B','Refrigeration units — Freezer','Cold chain','critical','R.04 Roof / 2.10 Freezer','Contractor','none'),
  (28,'F2-EMS-01','Environmental monitoring system','Cold chain / GDP','critical','M1.04 Warehouse Office & Facility Control Room','Contractor','none'),
  (29,'F2-HSD-01 TO 06','High-speed doors','Doors','high','Receiving areas, cold-chain anteroom, cold roo','Contractor','none'),
  (30,'F2-FP-01','Sprinkler pump — electric duty','Fire','critical','Sprinkler pump room','In-house','A'),
  (31,'F2-FP-02','Sprinkler pump — diesel standby','Fire','critical','Sprinkler pump room','In-house','A'),
  (32,'F2-FP-03','Jockey pump','Fire','high','Sprinkler pump room','In-house','A'),
  (33,'F2-SPT-01/02','Sprinkler water tanks','Fire','critical','Between the ramp and the west wall','Contractor','none'),
  (34,'F2-FAP-01','Main fire alarm panel','Fire','critical','1.16 Security & CCTV Control Room','Contractor','none'),
  (35,'F2-GS-01','Gas suppression — server room','Fire','high','M1.19 Server Room','Contractor','none'),
  (36,'F2-CL-1','Cargo lift 1','Lifts','high','C1 Stair ST4 & Cargo Lift 1','Contractor','none'),
  (37,'F2-CL-2','Cargo lift 2','Lifts','high','C2 Stair ST6 & Cargo Lift 2','Contractor','none'),
  (38,'F2-PL-1','Office passenger lift','Lifts','medium','C7 Office Lift & Stair','Contractor','none'),
  (39,'F2-DL-01 TO 08','Dock levellers — Level 1','Docks','high','Truck docks L1','Contractor','none'),
  (40,'F2-DL-09 TO 16','Dock levellers — Level 2','Docks','high','2.04 Truck Docks D1-D8','Contractor','none'),
  (41,'F2-DS-01 TO 16','Dock shelters and sectional doors','Docks','medium','Truck docks L1 and L2','Contractor','none'),
  (42,'F2-CV-01','Dispatch conveyor','MHE','high','1.06 Conveyor & Dispatch Marshalling','In-house','B'),
  (43,'F2-RT-01 TO 10','Reach trucks','MHE','high','Aircon warehouses','Contractor','none'),
  (44,'F2-FL-01 TO 04','Counterbalance forklifts','MHE','medium','Receiving and dispatch','Contractor','none'),
  (45,'F2-RK-WH','Selective pallet racking — all warehouses','Storage','high','1.01, 1.02, 1.03, 2.01, 2.02','Both','B'),
  (46,'F2-ACS-01','Access control system','Security','high','1.16 Security & CCTV Control Room','Contractor','none'),
  (47,'F2-CCTV-01','CCTV system','Security','high','1.16 Security & CCTV Control Room','Contractor','none'),
  (48,'F2-IAS-CD','Intruder alarm — Controlled Drugs Vault','Security','critical','M1.08 Controlled Drugs Vault','Contractor','none'),
  (49,'F2-CA-01/02','Oil-free air compressors','Process utility','high','1.21 Central Plant Room','Contractor','none'),
  (50,'F2-DWP-01/02','Domestic water booster pumps','Plumbing','medium','Sprinkler pump room','In-house','A'),
  (51,'F2-BMS-01','Building management system','Controls','high','M1.04 Warehouse Office & Facility Control Room','Contractor','none'),
  (52,'F2-SC-01/02','Stability chambers','Laboratory','high','M2.21 QA/QC Laboratory','Contractor','none'),
  (53,'F2-HPLC-01 TO 03','HPLC systems','Laboratory','high','M2.21 QA/QC Laboratory','Contractor','none'),
  (54,'F2-LAF-01','Sampling booth (downflow, laminar air flow)','ACMV / QA','high','1.09 Quarantine Cage & Sampling Booth','Contractor','none'),
  (55,'F2-WS-01','Floor scale — Aircon Receiving','Weighing','medium','1.10 Aircon Receiving Area','Contractor','none'),
  (56,'F2-WS-02','Floor scale — Receiving (Level 2)','Weighing','medium','2.05 Receiving Area','Contractor','none'),
  (57,'F2-SW-01','Pallet stretch wrapper','MHE','low','1.11 Non-aircon Receiving Area','In-house','B'),
  (58,'F2-CW-01','Checkweigher (dispatch cartons)','Weighing','medium','2.06 QC Check & Packing','Contractor','none'),
  (59,'F2-EVC-01 TO 04','EV chargers — staff car park','Electrical','low','1.14 Car Park, lower 1st storey','Contractor','none'),
  (60,'F2-DB-L1, L1M, L2, L2M','Floor distribution boards (one per level)','Electrical','high','C3 / M1.16 Service risers','Contractor','none'),
  (61,'F2-CRAC-01/02','Precision air-conditioners — server room','ACMV','high','M1.19 Server Room','Contractor','none'),
  (62,'F2-EF-CY1','Cytotoxic store exhaust fan (negative pressure)','ACMV','high','M2.19 Cytotoxic Store & Anteroom','Contractor','none'),
  (63,'F2-ESS-01','Emergency eyewash and safety shower','Safety','high','M2.25 Glassware Wash & Lab Store','In-house','A'),
  (64,'F2-AED-01','Automated external defibrillator','Safety','high','M2.31 First Aid Room','In-house','A'),
  (65,'F2-EWH-01','Electric water heater — warehouse toilets','Plumbing','low','1.18 Warehouse Toilets','In-house','A'),
  (66,'F2-RK-RET, RK-PM','Racking — returns warehouse and packaging store','Storage','medium','1.12 Returns Warehouse / M1.02 Packaging Mater','Contractor','none'),
  (67,'F2-AHU-G1','GMP suite AHU (HEPA terminals)','ACMV','critical','M2.27 AHU Room','Contractor','none'),
  (68,'F2-PW-01, PW-T1, PWP-01/02, UV-01','Purified water system (generation, tank, loop pumps, UV)','Process utility','high','M2.28 Purified Water Plant','Contractor','none'),
  (69,'F2-EF-L1 TO L3','Laboratory exhaust fans (high-plume)','ACMV','high','R.06 Roof over the labs','Contractor','none'),
  (70,'F2-LAD-01, LAD-02','Caged roof ladders with lockable roof hatches','Access','high','Top of Stair ST7 and Stair ST4','Contractor','none'),
  (71,'F2-DV-01','Roof davit hoist','Access / lifting','medium','East parapet, grid 12 / E','Contractor','none'),
  (72,'F2-PVR-01 TO 04, TC-01/02','PV cleaning robots and transfer carts','Electrical','medium','R.07 PV Robot Store & Trolley Bay; arrays R.01','Contractor','none');
create temp table f2_task(j int primary key, eq int references f2_eq(i), frequency text, title text, interval_value int, interval_unit text, first_due_offset int, proposed boolean) on commit drop;
insert into f2_task values
  (0,0,'annual','Annual service and oil/insulation tests',1,'year',7,false),
  (1,1,'annual','Annual service and oil/insulation tests',1,'year',12,false),
  (2,2,'sixmonthly','Six-monthly thermography',6,'month',17,false),
  (3,2,'annual','Annual service and thermography',1,'year',22,false),
  (4,3,'monthly','Run on load 30 min; check fuel, batteries, coolant, leaks',1,'month',27,false),
  (5,3,'annual','Annual load-bank test',1,'year',32,false),
  (6,4,'quarterly','Quarterly service per the O&M manual',3,'month',37,false),
  (7,5,'quarterly','Quarterly service per the O&M manual',3,'month',42,false),
  (8,6,'quarterly','Quarterly service per the O&M manual',3,'month',47,false),
  (9,7,'quarterly','Quarterly cleaning',3,'month',52,false),
  (10,8,'sixmonthly','Six-monthly service per the O&M manual',6,'month',57,false),
  (11,9,'daily','Walk-round: chargers normal, no gassing or smell, hydrogen alarm clear',1,'day',1,true),
  (12,9,'quarterly','Quarterly service per the O&M manual',3,'month',67,false),
  (13,10,'daily','Log chiller readings: temperatures, pressures, amps; check alarms',1,'day',1,true),
  (14,10,'quarterly','Quarterly service per the O&M manual',3,'month',77,false),
  (15,11,'daily','Log chiller readings: temperatures, pressures, amps; check alarms',1,'day',1,true),
  (16,11,'quarterly','Quarterly service per the O&M manual',3,'month',87,false),
  (17,12,'daily','Log chiller readings: temperatures, pressures, amps; check alarms',1,'day',1,true),
  (18,12,'quarterly','Quarterly service per the O&M manual',3,'month',7,false),
  (19,13,'monthly','Water treatment: dosing and Legionella control test',1,'month',12,false),
  (20,13,'quarterly','Quarterly cleaning of basins and fill',3,'month',17,false),
  (21,14,'quarterly','Quarterly service per the O&M manual',3,'month',22,false),
  (22,15,'quarterly','Quarterly service per the O&M manual',3,'month',27,false),
  (23,16,'quarterly','Quarterly service per the O&M manual',3,'month',32,false),
  (24,17,'quarterly','Quarterly service per the O&M manual',3,'month',37,false),
  (25,18,'quarterly','Quarterly service per the O&M manual',3,'month',42,false),
  (26,19,'annual','Annual face velocity test',1,'year',137,false),
  (27,20,'quarterly','Quarterly service per the O&M manual',3,'month',52,false),
  (28,21,'monthly','Run each fan; check damper and controls',1,'month',27,false),
  (29,21,'annual','Annual smoke control test',1,'year',152,false),
  (30,22,'monthly','Empty bins, check filter pressure drop',1,'month',7,false),
  (31,23,'quarterly','Quarterly service per the O&M manual',3,'month',72,false),
  (32,24,'daily','Check room temperature on the EMS, unit running and alarms clear; log it',1,'day',1,true),
  (33,24,'quarterly','Quarterly service per the O&M manual',3,'month',82,false),
  (34,25,'daily','Check room temperature on the EMS, unit running and alarms clear; log it',1,'day',1,true),
  (35,25,'quarterly','Quarterly service per the O&M manual',3,'month',90,false),
  (36,26,'daily','Check room temperature on the EMS, unit running and alarms clear; log it',1,'day',1,true),
  (37,26,'quarterly','Quarterly service per the O&M manual',3,'month',12,false),
  (38,27,'daily','Check freezer at -20 °C on the EMS, both units healthy, no ice on coils; log it',1,'day',1,true),
  (39,27,'quarterly','Quarterly service per the O&M manual',3,'month',22,false),
  (40,28,'daily','Check all sensors online, no open alarms, data recording',1,'day',1,true),
  (41,28,'annual','Annual sensor calibration',1,'year',212,false),
  (42,29,'quarterly','Quarterly service per the O&M manual',3,'month',37,false),
  (43,30,'weekly','Run pump 30 min; check pressure, packing, alarms; log it',1,'week',7,false),
  (44,31,'weekly','Run diesel pump 30 min; check fuel, batteries, pressure; log it',1,'week',7,false),
  (45,32,'weekly','Check cut-in and cut-out pressures',1,'week',7,false),
  (46,33,'annual','Annual clean and inspection',1,'year',237,false),
  (47,34,'monthly','Test a zone each month, check batteries and faults',1,'month',30,false),
  (48,34,'annual','Annual certificate inspection',1,'year',247,false),
  (49,35,'sixmonthly','Six-monthly service per the O&M manual',6,'month',72,false),
  (50,36,'monthly','Statutory monthly servicing (lift contractor)',1,'month',17,false),
  (51,37,'monthly','Statutory monthly servicing (lift contractor)',1,'month',22,false),
  (52,38,'monthly','Statutory monthly servicing (lift contractor)',1,'month',27,false),
  (53,39,'quarterly','Quarterly service per the O&M manual',3,'month',90,false),
  (54,40,'quarterly','Quarterly service per the O&M manual',3,'month',7,false),
  (55,41,'sixmonthly','Six-monthly service per the O&M manual',6,'month',102,false),
  (56,42,'monthly','Check belts, rollers, e-stops and guards',1,'month',17,false),
  (57,43,'monthly','OEM monthly service',1,'month',22,false),
  (58,44,'monthly','OEM monthly service',1,'month',27,false),
  (59,45,'weekly','Walk-round: damaged uprights, overloading, missing safety pins',1,'week',7,false),
  (60,45,'annual','Annual racking inspection',1,'year',307,false),
  (61,46,'sixmonthly','Six-monthly service per the O&M manual',6,'month',132,false),
  (62,47,'sixmonthly','Six-monthly service per the O&M manual',6,'month',137,false),
  (63,48,'sixmonthly','Six-monthly service per the O&M manual',6,'month',142,false),
  (64,49,'daily','Check auto-drains, pressure and dew point',1,'day',1,true),
  (65,49,'quarterly','Quarterly service per the O&M manual',3,'month',62,false),
  (66,50,'quarterly','Quarterly service per the O&M manual',3,'month',67,false),
  (67,51,'sixmonthly','Six-monthly service per the O&M manual',6,'month',162,false),
  (68,52,'quarterly','Quarterly check of set points and alarms',3,'month',77,false),
  (69,52,'annual','Annual temperature and humidity mapping',1,'year',352,false),
  (70,53,'annual','Annual qualification service',1,'year',357,false),
  (71,54,'sixmonthly','Six-monthly service per the O&M manual',6,'month',180,false),
  (72,54,'annual','Annual HEPA integrity test',1,'year',365,false),
  (73,55,'annual','Annual calibration',1,'year',7,false),
  (74,56,'annual','Annual calibration',1,'year',12,false),
  (75,57,'quarterly','Quarterly service per the O&M manual',3,'month',22,false),
  (76,58,'quarterly','Quarterly check with test weights',3,'month',27,false),
  (77,58,'annual','Annual calibration',1,'year',27,false),
  (78,59,'sixmonthly','Six-monthly service per the O&M manual',6,'month',37,false),
  (79,60,'annual','Annual thermography',1,'year',37,false),
  (80,61,'quarterly','Quarterly service per the O&M manual',3,'month',47,false),
  (81,62,'quarterly','Quarterly service per the O&M manual',3,'month',52,false),
  (82,63,'weekly','Flush eyewash and shower 3 min; water clear, area unobstructed',1,'week',7,false),
  (83,63,'annual','Annual inspection',1,'year',57,false),
  (84,64,'monthly','Check status light, pads and battery expiry',1,'month',7,false),
  (85,65,'annual','Annual service',1,'year',67,false),
  (86,66,'annual','Annual racking inspection',1,'year',72,false),
  (87,67,'daily','Check GMP suite pressure differentials and filter gauges; log them',1,'day',1,true),
  (88,67,'quarterly','Quarterly service per the O&M manual',3,'month',87,false),
  (89,67,'annual','Annual HEPA integrity test',1,'year',87,false),
  (90,68,'daily','Log conductivity, TOC and UV lamp status; check for alarms',1,'day',1,true),
  (91,68,'quarterly','Quarterly service per the O&M manual',3,'month',12,false),
  (92,68,'sixmonthly','Six-monthly sanitisation',6,'month',107,false),
  (93,69,'quarterly','Quarterly service per the O&M manual',3,'month',22,false),
  (94,70,'annual','Annual inspection',1,'year',112,false),
  (95,71,'annual','Annual examination of lifting gear',1,'year',117,false),
  (96,72,'quarterly','Quarterly service per the O&M manual',3,'month',37,false);

do $m$
declare
  admin uuid; fac uuid; facname text; t1 uuid; t2 uuid; r jsonb; e record; t record; aid uuid; rid uuid; tech uuid;
  assets_made int := 0; tasks_made int := 0; active_made int := 0; assigned int := 0;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if to_regprocedure('public.assign_pm_technician(uuid,uuid)') is null then raise exception 'M34 is not applied; nothing changed'; end if;
  admin := nullif(current_setting('fmw.admin'), '')::uuid; fac := nullif(current_setting('fmw.fac2'), '')::uuid; facname := current_setting('fmw.fac2name');
  t1 := nullif(current_setting('fmw.tech1'), '')::uuid; t2 := nullif(current_setting('fmw.tech2'), '')::uuid;
  if admin is null or not public.pilot_account_ready(admin) then raise exception 'Super-Administrator engchian.yeo@gmail.com not found or not ready; nothing changed'; end if;
  if fac is null then raise exception 'No active facility named "Facility 2..."; nothing changed'; end if;
  if t1 is null or not public.active_facility_member(fac, 'technician', t1) then raise exception 'Technician 1 koi.kpr+1@gmail.com is not a Technician of Facility 2; nothing changed'; end if;
  if t2 is null or not public.pilot_account_ready(t2) or not public.active_facility_member(fac, 'technician', t2) then t2 := t1; end if;
  if exists(select 1 from public.assets a join f2_eq q on lower(a.asset_tag) = lower(q.tag)) then
    raise exception 'Some F2- asset tags already exist (this script has run before); nothing changed'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated')::text, true),
          set_config('request.jwt.claim.sub', admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);

  for e in select * from f2_eq order by i loop
    -- create_asset() cannot pick a facility for a Super-Administrator who serves several, so the row is written
    -- directly with facility_id = Facility 2 and the same 'asset_created' audit entry create_asset() writes.
    insert into public.assets(asset_tag, name, asset_type, criticality, lifecycle_status, site, location, description, facility_id, created_by, updated_by)
    values (upper(e.tag), e.name, e.discipline, e.criticality, 'active', facname, e.location,
            'Facility 2 maintenance plan (UAT, 17 Nov 2026). Serviced by: ' || e.provider || '.', fac, admin, admin)
    returning id into aid;
    insert into public.activity_logs(user_id, asset_id, action, actor, note)
    values (admin, aid, 'asset_created', 'Rollout script (as Super-Administrator)',
            jsonb_build_object('asset_tag', upper(e.tag), 'name', e.name, 'asset_type', e.discipline, 'facility', facname,
                               'script', 'preview-f2-maintenance-plan-20261117')::text);
    assets_made := assets_made + 1;
    for t in select * from f2_task where eq = e.i order by j loop
      r := public.create_pm_requirement(jsonb_build_object('asset_id', aid, 'title', t.title,
             'scope', t.title || ' — ' || e.name || ' at ' || e.location || '. Cross-reference the O&M manual for this equipment.'
                      || case when t.proposed then ' (Daily check proposed; owner to confirm.)' else '' end,
             'maintenance_type', case when t.frequency = 'daily' then 'inspection' else 'preventive' end,
             'interval_value', t.interval_value, 'interval_unit', t.interval_unit,
             'first_due_date', (current_date + t.first_due_offset)::text, 'effective_date', current_date::text,
             'default_priority', case e.criticality when 'critical' then 'high' when 'high' then 'medium' else 'low' end));
      if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Task % on % not created, nothing changed: %', t.title, e.tag, r; end if;
      rid := (r -> 'requirement' ->> 'id')::uuid; tasks_made := tasks_made + 1;
      if not t.proposed then
        r := public.activate_pm_requirement(rid, 'Facility 2 maintenance plan reviewed by the owner, 17 Nov 2026');
        if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Task % on % not activated, nothing changed: %', t.title, e.tag, r; end if;
        active_made := active_made + 1;
      end if;
      tech := case e.tech when 'A' then t1 when 'B' then t2 else null end;
      if tech is not null then
        r := public.assign_pm_technician(rid, tech);
        if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception 'Technician not assigned for % on %, nothing changed: %', t.title, e.tag, r; end if;
        assigned := assigned + 1;
      end if;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
  perform set_config('fmw.summary', format('%s assets, %s tasks (%s active, %s draft), %s with a Technician', assets_made, tasks_made, active_made, tasks_made - active_made, assigned), true);
end;
$m$;
\o
select current_setting('fmw.summary') as created;
select q.frequency, count(*) as tasks, count(*) filter (where m.state = 'active') as active, count(m.assigned_technician_id) as with_technician
from public.maintenance_requirements m join public.assets a on a.id = m.asset_id join f2_eq e on lower(e.tag) = lower(a.asset_tag)
join public.maintenance_requirement_revisions v on v.id = m.current_revision_id
join (select distinct frequency, title, eq from f2_task) q on q.eq = e.i and q.title = v.title
group by q.frequency order by min(case q.frequency when 'daily' then 1 when 'weekly' then 2 when 'monthly' then 3 when 'quarterly' then 4 when 'sixmonthly' then 5 else 6 end);
select coalesce(p.display_name, '(not assigned)') as technician, count(*) as tasks
from public.maintenance_requirements m join public.assets a on a.id = m.asset_id join f2_eq e on lower(e.tag) = lower(a.asset_tag)
left join public.profiles p on p.id = m.assigned_technician_id group by 1 order by 1;
\if :{?apply}
  \echo 'apply=yes: committing.'
  commit;
\else
  \echo 'Dry run only: rolled back. Run again with -v apply=yes to keep it.'
  rollback;
\endif

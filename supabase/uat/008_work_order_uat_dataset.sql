\set ON_ERROR_STOP on

-- Controlled Preview/UAT data package. This file is deliberately not a migration.
-- The caller must explicitly authorize the authoritative Preview project reference.
select :'fmworks_preview_project_ref' = 'pvajuywwwpjlikqjnvgv' as uat_target_authorized \gset
\if :uat_target_authorized
\else
  \echo 'Refusing WP-PILOT-GO-008 load: authoritative Preview project reference was not supplied.'
  \quit 3
\endif

begin;

do $preflight$
begin
  if to_regclass('public.assets') is null or to_regclass('public.work_orders') is null
    or to_regclass('public.departments') is null or to_regclass('public.activity_logs') is null then
    raise exception 'WP-PILOT-GO-008 prerequisites are missing';
  end if;
  if not exists(select 1 from public.departments where code='FAC' and is_active and deleted_at is null)
    or not exists(select 1 from public.departments where code='OPS' and is_active and deleted_at is null)
    or not exists(select 1 from public.departments where code='ENG' and is_active and deleted_at is null)
    or not exists(select 1 from public.departments where code='WH' and is_active and deleted_at is null) then
    raise exception 'WP-PILOT-GO-008 requires the active 0024 Department baseline';
  end if;
  if not exists(select 1 from public.profiles where role='administrator' and is_active and deleted_at is null) then
    raise exception 'WP-PILOT-GO-008 requires an active Administrator audit principal';
  end if;
end;
$preflight$;

create temp table uat_context on commit drop as
select
  (select id from public.profiles where role='administrator' and is_active and deleted_at is null order by created_at,id limit 1) actor_id,
  (select id from public.departments where code='FAC' and is_active and deleted_at is null order by created_at,id limit 1) fac_id,
  (select id from public.departments where code='OPS' and is_active and deleted_at is null order by created_at,id limit 1) ops_id,
  (select id from public.departments where code='ENG' and is_active and deleted_at is null order by created_at,id limit 1) eng_id,
  (select id from public.departments where code='WH' and is_active and deleted_at is null order by created_at,id limit 1) wh_id;

insert into public.maintenance_teams(id,name,department_id,is_active)
select seed.id,seed.name,case seed.department_code when 'OPS' then c.ops_id when 'ENG' then c.eng_id else c.fac_id end,true
from uat_context c cross join (values
 ('08000000-0000-4000-8000-000000000101'::uuid,'UAT Mechanical Maintenance','FAC'),
 ('08000000-0000-4000-8000-000000000102'::uuid,'UAT HVAC Maintenance','FAC'),
 ('08000000-0000-4000-8000-000000000103'::uuid,'UAT Electrical Maintenance','ENG'),
 ('08000000-0000-4000-8000-000000000104'::uuid,'UAT Building Maintenance','FAC'),
 ('08000000-0000-4000-8000-000000000105'::uuid,'UAT Facilities Management','FAC'),
 ('08000000-0000-4000-8000-000000000106'::uuid,'UAT Engineering','ENG')
) seed(id,name,department_code)
on conflict (id) do nothing;

insert into public.vendors(id,name,trade,active)
values
 ('08000000-0000-4000-8000-000000000201','ABC Fire Systems (UAT)','Fire protection',true),
 ('08000000-0000-4000-8000-000000000202','XYZ Elevator (UAT)','Vertical transportation',true),
 ('08000000-0000-4000-8000-000000000203','Maintenance Contractor (UAT)','Building maintenance',true)
on conflict (id) do nothing;

create temp table uat_assets(
 id uuid, asset_tag text, name text, asset_type text, criticality text,
 site text, location text, department_code text
) on commit drop;
insert into uat_assets values
 ('08000000-0000-4000-8000-000000000301','P-CHW-01','Chilled Water Pump No. 1','Pump','critical','Utility Block','Chiller Plant Room','FAC'),
 ('08000000-0000-4000-8000-000000000302','AHU-02','Air Handling Unit No. 2','Air handling unit','medium','Main Building','Level 2 AHU Room','FAC'),
 ('08000000-0000-4000-8000-000000000303','DB-L2-03','Distribution Board L2-03','Distribution board','high','Main Building','Level 2 Electrical Room','ENG'),
 ('08000000-0000-4000-8000-000000000304','SD-L1-024','Smoke Detector L1-024','Smoke detector','high','Warehouse','Level 1','WH'),
 ('08000000-0000-4000-8000-000000000305','PLB-L1-WB-03','Wash Basin Plumbing L1-WB-03','Plumbing fixture','low','Main Building','Level 1 Male Toilet','FAC'),
 ('08000000-0000-4000-8000-000000000306','LIFT-01','Passenger Lift No. 1','Lift','critical','Main Building','Lift core','FAC'),
 ('08000000-0000-4000-8000-000000000307','INV-PV-02','Solar Inverter No. 2','Solar inverter','medium','Utility Block','Solar Inverter Room','ENG'),
 ('08000000-0000-4000-8000-000000000308','GEN-01','Emergency Generator No. 1','Generator','high','Utility Block','Generator Room','ENG'),
 ('08000000-0000-4000-8000-000000000309','EF-05','Exhaust Fan No. 5','Exhaust fan','medium','Main Building','Roof','FAC'),
 ('08000000-0000-4000-8000-000000000310','TR-01','Transformer No. 1','Transformer','high','Utility Block','Transformer Yard','ENG'),
 ('08000000-0000-4000-8000-000000000311','CT-02-FAN','Cooling Tower No. 2 Fan','Cooling tower fan','high','Utility Block','Roof','FAC'),
 ('08000000-0000-4000-8000-000000000312','RS-01','Loading Bay Roller Shutter No. 1','Roller shutter','medium','Warehouse','Loading Bay','WH'),
 ('08000000-0000-4000-8000-000000000313','SOCKET-L2-P-04','Pantry Socket L2-P-04','Electrical socket','critical','Main Building','Level 2 Pantry','ENG'),
 ('08000000-0000-4000-8000-000000000314','FCU-L2-08','Fan Coil Unit L2-08','Fan coil unit','low','Main Building','Level 2 Office','FAC'),
 ('08000000-0000-4000-8000-000000000315','P-CHW-03-MTR','Chilled Water Pump No. 3 Motor','Electric motor','high','Utility Block','Chiller Plant Room','ENG');

do $asset_collision$
begin
  if exists(select 1 from uat_assets u join public.assets a on lower(a.asset_tag)=lower(u.asset_tag) where a.id<>u.id) then
    raise exception 'WP-PILOT-GO-008 asset tag collides with a non-UAT Asset';
  end if;
end;
$asset_collision$;

insert into public.assets(id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,description,department_id,created_by,updated_by)
select u.id,u.asset_tag,u.name,u.asset_type,u.criticality,'active',u.site,u.location,
  'Controlled synthetic Asset for WP-PILOT-GO-008 Preview/UAT only.',
  case u.department_code when 'ENG' then c.eng_id when 'WH' then c.wh_id else c.fac_id end,c.actor_id,c.actor_id
from uat_assets u cross join uat_context c on conflict(id) do nothing;

create temp table uat_orders(
  id uuid, number text, title text, description text, location text, site text, asset_id uuid,
  priority text, canonical_status text, source text, source_status text, department_code text,
  reported_by text, assigned_label text, assignment_kind text, assignment_id uuid,
  reported_date date, due_date date, estimated_hours numeric, actual_hours numeric,
  estimated_cost numeric, actual_cost numeric, metadata text
) on commit drop;

insert into uat_orders values
('08000000-0000-4000-8000-000000000001','WO-TEST-001','Chilled Water Pump P-CHW-01 Tripped','Pump tripped; standby pump is operating. Inspect relay, MCC, coupling, bearing and operating current.','Chiller Plant Room','Utility Block','08000000-0000-4000-8000-000000000301','critical','submitted','reactive','Open','OPS','Operations Control Room','Mechanical Technician A','team','08000000-0000-4000-8000-000000000101','2026-08-27','2026-08-27',3,null,800,null,'Work type: Corrective Maintenance | Category: Mechanical | Safety: Lockout/tagout (LOTO) required'),
('08000000-0000-4000-8000-000000000002','WO-TEST-002','Quarterly PM AHU-02','Quarterly preventive maintenance: inspect filters, belt, bearings, drain pan and safety interlocks.','Level 2 AHU Room','Main Building','08000000-0000-4000-8000-000000000302','medium','approved','preventive','Scheduled','FAC','PM Schedule','HVAC Technician A','team','08000000-0000-4000-8000-000000000102','2026-08-25','2026-08-30',2,null,150,null,'Work type: Preventive Maintenance | Category: HVAC | Scheduled date: 2026-08-30'),
('08000000-0000-4000-8000-000000000003','WO-TEST-003','Thermal Hotspot at DB-L2-03','Investigate thermal hotspot; inspect connections and loading.','Level 2 Electrical Room','Main Building','08000000-0000-4000-8000-000000000303','high','in_progress','inspection','In Progress','ENG','Electrical Technician','Senior Electrical Technician','team','08000000-0000-4000-8000-000000000103','2026-08-26','2026-08-28',4,null,500,null,'Work type: Corrective Maintenance | Category: Electrical | Safety: LOTO and arc-flash PPE required'),
('08000000-0000-4000-8000-000000000004','WO-TEST-004','Smoke Detector SD-L1-024 Fault','Investigate and rectify smoke detector fault.','Level 1','Warehouse','08000000-0000-4000-8000-000000000304','high','assigned','reactive','Pending Vendor','FAC','Security Control','Fire Alarm Contractor','vendor','08000000-0000-4000-8000-000000000201','2026-08-24','2026-08-28',null,null,380,null,'Work type: Corrective Maintenance | Category: Fire Protection | Vendor: ABC Fire Systems'),
('08000000-0000-4000-8000-000000000005','WO-TEST-005','Water Leak at Wash Basin PLB-L1-WB-03','Repair leaking wash basin connection.','Level 1 Male Toilet','Main Building','08000000-0000-4000-8000-000000000305','low','submitted','reactive','Open','FAC','Building User','Technician B','team','08000000-0000-4000-8000-000000000104','2026-08-27','2026-09-01',1,null,50,null,'Work type: Corrective Maintenance | Category: Plumbing'),
('08000000-0000-4000-8000-000000000006','WO-TEST-006','Passenger Lift LIFT-01 Breakdown','Lift isolated and out-of-service signage installed pending specialist response.','Lift Core','Main Building','08000000-0000-4000-8000-000000000306','critical','assigned','reactive','Pending Vendor','FAC','Security','Lift Contractor','vendor','08000000-0000-4000-8000-000000000202','2026-08-27','2026-08-27',null,null,1200,null,'Work type: Breakdown | Category: Vertical Transportation | Vendor: XYZ Elevator | Safety: Isolated and signed out of service'),
('08000000-0000-4000-8000-000000000007','WO-TEST-007','Solar Inverter INV-PV-02 Alarm','Investigate inverter alarm and verify DC/AC operating values.','Solar Inverter Room','Utility Block','08000000-0000-4000-8000-000000000307','medium','submitted','condition_based','Open','ENG','BMS Operator','Electrical Technician B','team','08000000-0000-4000-8000-000000000103','2026-08-26','2026-08-31',2,null,200,null,'Work type: Corrective Maintenance | Category: Renewable Energy'),
('08000000-0000-4000-8000-000000000008','WO-TEST-008','Emergency Generator GEN-01 Monthly Test','Monthly generator inspection and load test completed; result passed.','Generator Room','Utility Block','08000000-0000-4000-8000-000000000308','medium','completed','preventive','Completed','ENG','PM Schedule','Electrical Technician A','team','08000000-0000-4000-8000-000000000103','2026-08-20','2026-08-20',1.5,1.4,100,95,'Work type: Preventive Maintenance / Testing | Category: Electrical | Result: Passed'),
('08000000-0000-4000-8000-000000000009','WO-TEST-009','Exhaust Fan EF-05 Excessive Vibration','Investigate excessive vibration and inspect mounting, alignment and bearings.','Roof','Main Building','08000000-0000-4000-8000-000000000309','medium','submitted','reactive','Open - Overdue','FAC','Maintenance Technician','Mechanical Technician B','team','08000000-0000-4000-8000-000000000101','2026-08-10','2026-08-15',null,null,450,null,'Work type: Corrective Maintenance | Category: Mechanical | Overdue scenario retained by due date'),
('08000000-0000-4000-8000-000000000010','WO-TEST-010','Transformer TR-01 Oil Leak Assessment','Assess oil leak and recommend specialist repair and shutdown decision.','Transformer Yard','Utility Block','08000000-0000-4000-8000-000000000310','high','submitted','inspection','Awaiting Approval','ENG','Facilities Engineer','Unassigned pending approval','none',null,'2026-08-27','2026-09-03',null,null,4500,null,'Work type: Inspection / Corrective | Category: Electrical | Approval decision: specialist and shutdown'),
('08000000-0000-4000-8000-000000000011','WO-TEST-011','Cooling Tower CT-02-FAN Bearing Replacement','Replace failed fan drive bearing when part is available.','Roof','Utility Block','08000000-0000-4000-8000-000000000311','high','assigned','reactive','On Hold - Awaiting Parts','FAC','Mechanical Technician','Mechanical Technician A','team','08000000-0000-4000-8000-000000000101','2026-08-22','2026-09-05',null,null,1800,null,'Work type: Corrective Maintenance | Category: Mechanical | Parts required: 1 fan drive bearing | Hold reason retained'),
('08000000-0000-4000-8000-000000000012','WO-TEST-012','Roller Shutter RS-01 Closure Defect','Previous repair failed verification; closure rejected and work reopened.','Loading Bay','Warehouse','08000000-0000-4000-8000-000000000312','medium','in_progress','reactive','Reopened','WH','Warehouse Supervisor','Maintenance Contractor','vendor','08000000-0000-4000-8000-000000000203','2026-08-18','2026-08-23',null,null,650,null,'Work type: Corrective Maintenance | Category: Building Architectural | Original completion: 2026-08-23 | Verification failed; closure rejected and reopened'),
('08000000-0000-4000-8000-000000000013','WO-TEST-013','Damaged Socket SOCKET-L2-P-04','Damaged socket isolated and warning posted; repair and test before return to service.','Level 2 Pantry','Main Building','08000000-0000-4000-8000-000000000313','critical','in_progress','reactive','In Progress','ENG','Staff','Electrical Technician B','team','08000000-0000-4000-8000-000000000103','2026-08-27','2026-08-27',null,null,80,null,'Work type: Safety Corrective | Category: Electrical | Immediate control: isolated and warning posted'),
('08000000-0000-4000-8000-000000000014','WO-TEST-014','FCU-L2-08 Not Cooling Inspection','Inspection found no equipment fault; user advised on controls.','Level 2 Office','Main Building','08000000-0000-4000-8000-000000000314','low','closed','inspection','Closed','FAC','Office User','HVAC Technician B','team','08000000-0000-4000-8000-000000000102','2026-08-21','2026-08-21',null,0.5,null,30,'Work type: Inspection | Category: HVAC | Finding: No fault found | Closure code: NFF | Resolution: User advised'),
('08000000-0000-4000-8000-000000000015','WO-TEST-015','Chilled Water Pump P-CHW-03 Motor Replacement','Motor insulation failure; proposed motor replacement and alignment.','Chiller Plant Room','Utility Block','08000000-0000-4000-8000-000000000315','high','submitted','condition_based','Awaiting Management Approval','ENG','Facilities Engineer','Unassigned pending management approval','none',null,'2026-08-27','2026-09-15',24,null,18500,null,'Work type: Major Corrective | Category: Mechanical / Electrical | Approval required: expenditure threshold | Estimated duration: 3 days');

do $collision$
begin
  if exists(select 1 from uat_orders u join public.work_orders w on w.work_order_number=u.number where w.id<>u.id) then
    raise exception 'WP-PILOT-GO-008 Work Order number collides with a non-UAT record';
  end if;
end;
$collision$;

insert into public.work_orders(
 id,user_id,requested_by,work_order_number,title,description,location,site,asset_id,priority,status,source,source_reference,
 department_id,due_date,estimated_hours,actual_labour_hours,completion_notes,internal_notes,submitted_by,assigned_to,
 assigned_team_id,assigned_vendor_id,submitted_at,approved_at,assigned_at,started_at,completed_at,reviewed_at,closed_at,created_at,updated_at
)
select u.id,c.actor_id,c.actor_id,u.number,u.title,u.description,u.location,u.site,u.asset_id,u.priority,u.canonical_status,u.source,
 'WP-PILOT-GO-008 / source status: '||u.source_status,
 case u.department_code when 'ENG' then c.eng_id when 'WH' then c.wh_id when 'OPS' then c.ops_id else c.fac_id end,
 u.due_date,u.estimated_hours,u.actual_hours,
 case when u.canonical_status in ('completed','reviewed','closed') then u.metadata else null end,
 u.metadata||' | Estimated cost: '||coalesce('S$'||u.estimated_cost::text,'Not recorded')||' | Actual cost: '||coalesce('S$'||u.actual_cost::text,'Not recorded')||' | Source assigned to: '||u.assigned_label,
 u.reported_by,u.assigned_label,
 case when u.assignment_kind='team' then u.assignment_id end,case when u.assignment_kind='vendor' then u.assignment_id end,
 u.reported_date::timestamptz,
 case when u.canonical_status in ('approved','assigned','in_progress','completed','reviewed','closed') then u.reported_date::timestamptz end,
 case when u.canonical_status in ('assigned','in_progress','completed','reviewed','closed') then u.reported_date::timestamptz end,
 case when u.canonical_status in ('in_progress','completed','reviewed','closed') then u.reported_date::timestamptz end,
 case when u.canonical_status in ('completed','reviewed','closed') then u.reported_date::timestamptz end,
 case when u.canonical_status in ('reviewed','closed') then u.reported_date::timestamptz end,
 case when u.canonical_status='closed' then u.reported_date::timestamptz end,
 u.reported_date::timestamptz,u.reported_date::timestamptz
from uat_orders u cross join uat_context c
on conflict(id) do nothing;

insert into public.activity_logs(user_id,work_order_id,asset_id,action,from_status,to_status,actor,note,created_at)
select c.actor_id,u.id,u.asset_id,'uat_dataset_loaded',null,u.canonical_status,'WP-PILOT-GO-008 controlled loader',
 jsonb_build_object('source_status',u.source_status,'reported_by',u.reported_by,'assigned_to',u.assigned_label,'estimated_cost_sgd',u.estimated_cost,'actual_cost_sgd',u.actual_cost,'mapping','Canonical fields plus labelled notes; no security bypass')::text,
 u.reported_date::timestamptz
from uat_orders u cross join uat_context c
where not exists(select 1 from public.activity_logs l where l.work_order_id=u.id and l.action='uat_dataset_loaded');

do $postcondition$
begin
 if (select count(*) from public.work_orders where work_order_number like 'WO-TEST-%') <> 15 then
   raise exception 'WP-PILOT-GO-008 postcondition failed: exactly 15 UAT Work Orders required';
 end if;
end;
$postcondition$;

commit;

\set ON_ERROR_STOP on
-- M34: maintenance plan — Technician responsible per requirement, generated Work Orders assigned, O&M documents. Rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Maintenance plan regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d340000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 super-administrator, 2 supervisor F2, 3 technician F2, 4 technician F1, 5 facility manager F1, 6 technician F2 (other)
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m34.'||n||'@example.test',jsonb_build_object('display_name','M34 '||role||' '||n)
from (values ('administrator',1),('supervisor',2),('technician',3),('technician',4),('facility_manager',5),('technician',6)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Electrical' end
from (values ('administrator',1),('supervisor',2),('technician',3),('technician',4),('facility_manager',5),('technician',6)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.sites(id,code,name,is_active) values (pg_temp.u(101),'M34-F1','M34 Facility One',true),(pg_temp.u(102),'M34-F2','M34 Facility 2',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(102),pg_temp.u(2),'supervisor',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(3),'technician',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(6),'technician',pg_temp.u(1)),
 (pg_temp.u(101),pg_temp.u(4),'technician',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(5),'facility_manager',pg_temp.u(1));
insert into public.assets(id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,facility_id,created_by,updated_by)
values (pg_temp.u(201),'M34-F2-FP-01','M34 sprinkler pump','Pump','critical','active','M34 Facility 2','Pump room',pg_temp.u(102),pg_temp.u(1),pg_temp.u(1));

select pg_temp.act(pg_temp.u(1));
select public.create_pm_requirement(jsonb_build_object('asset_id',pg_temp.u(201),'title','Weekly — sprinkler pump run','scope','Run pump 30 min; check pressure','maintenance_type','inspection','interval_value',1,'interval_unit','week','first_due_date',current_date)) as req \gset
select pg_temp.assert_true(((:'req')::jsonb->>'ok')::boolean,'a requirement is created');
select set_config('m34.req',(:'req')::jsonb->'requirement'->>'id',true);
select pg_temp.assert_true((public.activate_pm_requirement(current_setting('m34.req')::uuid)->>'ok')::boolean,'the requirement is active');

-- Assigning: the facility's Supervisor yes; a Facility Manager of another facility no; only this facility's Technicians.
select pg_temp.act(pg_temp.u(5));
select pg_temp.assert_true((public.assign_pm_technician(current_setting('m34.req')::uuid,pg_temp.u(3))->>'code')='ACCESS_DENIED','another facility''s Facility Manager cannot assign');
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((public.assign_pm_technician(current_setting('m34.req')::uuid,pg_temp.u(4))->>'code')='INVALID_REFERENCE','a Technician of another facility is refused');
select pg_temp.assert_true((public.assign_pm_technician(current_setting('m34.req')::uuid,pg_temp.u(3))->>'ok')::boolean,'the Supervisor assigns a Facility 2 Technician');
select pg_temp.assert_true((public.assign_pm_technician(current_setting('m34.req')::uuid,pg_temp.u(3))->>'code')='NO_CHANGE','assigning the same person again changes nothing');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where action='pm_technician_assigned' and maintenance_requirement_id=current_setting('m34.req')::uuid),'assignment is audited');
select pg_temp.assert_true((select count(*) from public.facility_technicians(pg_temp.u(102)))=2,'the planner sees the facility''s two Technicians');

-- Reading the plan: the facility's Technician yes, another facility's Technician no.
set local role authenticated;
select pg_temp.act(pg_temp.u(6));
select pg_temp.assert_true((select count(*) from public.maintenance_requirements where id=current_setting('m34.req')::uuid)=1,'a Technician of the facility reads its plan');
select pg_temp.act(pg_temp.u(4));
select pg_temp.assert_true((select count(*) from public.maintenance_requirements where id=current_setting('m34.req')::uuid)=0,'another facility''s Technician does not');
reset role;

-- A generated Work Order goes to the Technician responsible.
select pg_temp.act(pg_temp.u(1));
select public.materialize_pm_occurrences(current_date+7) as mat \gset
select pg_temp.assert_true(((:'mat')::jsonb->>'ok')::boolean,'occurrences are listed');
select public.generate_pm_work_order((select id from public.pm_occurrences where requirement_id=current_setting('m34.req')::uuid order by current_due_date limit 1)) as gen \gset
select pg_temp.assert_true(((:'gen')::jsonb->>'ok')::boolean,'a Work Order is generated: '||(:'gen'));
select pg_temp.assert_true((select w.assigned_technician_id=pg_temp.u(3) from public.work_orders w join public.pm_occurrences o on o.id=w.pm_occurrence_id where o.requirement_id=current_setting('m34.req')::uuid limit 1),'the generated Work Order is assigned to the Technician responsible');

-- O&M manual: the Supervisor files it; the facility reads it; a Technician cannot file; other facilities cannot read.
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((public.register_asset_document(pg_temp.u(201),'om_manual','O&M manual','fp01.pdf','application/pdf',1000,'asset-documents/x/fp01.pdf')->>'code')='ACCESS_DENIED','a Technician cannot file documents');
select pg_temp.act(pg_temp.u(2));
select public.register_asset_document(pg_temp.u(201),'om_manual','O&M manual — sprinkler pump','fp01.pdf','application/pdf',1000,'asset-documents/x/fp01.pdf') as doc \gset
select pg_temp.assert_true(((:'doc')::jsonb->>'ok')::boolean,'the Supervisor files the O&M manual');
select pg_temp.assert_true((public.register_asset_document(pg_temp.u(201),'om_manual','Bad','x.exe','application/x-msdownload',10,'asset-documents/x/x.exe')->>'code')='VALIDATION_ERROR','only PDF and images');
set local role authenticated;
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((select count(*) from public.asset_documents)=1,'the facility''s Technician reads the manual');
select pg_temp.act(pg_temp.u(4));
select pg_temp.assert_true((select count(*) from public.asset_documents)=0,'another facility does not');
reset role;
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((public.retire_asset_document(((:'doc')::jsonb->>'id')::uuid,'Replaced by revision B')->>'ok')::boolean,'a manual can be retired with a reason');

select 'maintenance_plan tests passed' as result;
rollback;

\set ON_ERROR_STOP on
-- M39 (D-81): the emergency on-call roster and incidents belong to a facility. Rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Facility on-call regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d390000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 super-administrator; Facility A: 2 technician, 3 supervisor; Facility B: 4 technician, 5 supervisor, 6 facility manager, 7 approver
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m39.'||n||'@example.test',jsonb_build_object('display_name','M39 '||role||' '||n)
from (values ('administrator',1),('technician',2),('supervisor',3),('technician',4),('supervisor',5),('facility_manager',6),('approver',7)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false
from (values ('administrator',1),('technician',2),('supervisor',3),('technician',4),('supervisor',5),('facility_manager',6),('approver',7)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.sites(id,code,name,is_active) values (pg_temp.u(101),'M39-A','M39 Facility A',true),(pg_temp.u(102),'M39-B','M39 Facility B',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(101),pg_temp.u(2),'technician',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(3),'supervisor',pg_temp.u(1)),
 (pg_temp.u(102),pg_temp.u(4),'technician',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(5),'supervisor',pg_temp.u(1)),
 (pg_temp.u(102),pg_temp.u(6),'facility_manager',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(7),'approver',pg_temp.u(1));

-- Roster: each facility its own entry; a Supervisor manages only their own facility and its Technicians.
select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((public.upsert_emergency_roster(null,jsonb_build_object('profile_id',pg_temp.u(2),'escalation_order',1))->>'code')='VALIDATION_ERROR','an entry needs a facility');
select pg_temp.assert_true((public.upsert_emergency_roster(null,jsonb_build_object('facility_id',pg_temp.u(101),'profile_id',pg_temp.u(2),'escalation_order',1))->>'ok')::boolean,'Facility A on call: its Technician');
select pg_temp.act(pg_temp.u(5));
select pg_temp.assert_true((public.upsert_emergency_roster(null,jsonb_build_object('facility_id',pg_temp.u(101),'profile_id',pg_temp.u(2),'escalation_order',2))->>'code')='ACCESS_DENIED','a Supervisor cannot change another facility''s roster');
select pg_temp.assert_true((public.upsert_emergency_roster(null,jsonb_build_object('facility_id',pg_temp.u(102),'profile_id',pg_temp.u(2),'escalation_order',1))->>'code')='INVALID_ASSIGNMENT','only this facility''s Technicians');
select pg_temp.assert_true((public.upsert_emergency_roster(null,jsonb_build_object('facility_id',pg_temp.u(102),'profile_id',pg_temp.u(4),'escalation_order',1))->>'ok')::boolean,'Facility B''s Supervisor puts its Technician on call');
select pg_temp.assert_true((select count(*) from public.get_emergency_roster() where facility_id in (pg_temp.u(101),pg_temp.u(102)))=1
  and exists(select 1 from public.get_emergency_roster() where facility_id=pg_temp.u(102) and facility_name='M39 Facility B'),'a Supervisor sees only their facility''s roster');
select pg_temp.assert_true(not exists(select 1 from public.get_emergency_response_options() where target_id=pg_temp.u(2)),'and is offered only their facility''s Technicians');
select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((select count(*) from public.get_emergency_roster() where facility_id in (pg_temp.u(101),pg_temp.u(102)))=2,'the Super-Administrator sees every facility');

-- An incident at Facility B (reported by its Approver, facility worked out) alerts Facility B's on-call Technician,
-- its Supervisor and Facility Manager and the Super-Administrator — not Facility A's people.
select pg_temp.act(pg_temp.u(7));
select public.create_incident(jsonb_build_object('incident_type','flood','severity','high','location','M39 Level 1','description','Water on the floor')) as inc \gset
select pg_temp.assert_true(((:'inc')::jsonb->>'ok')::boolean,'the Approver reports an incident: '||:'inc');
select set_config('m39.inc',(:'inc')::jsonb#>>'{incident,id}',true);
select pg_temp.assert_true((select facility_id=pg_temp.u(102) and assigned_technician_id=pg_temp.u(4) from public.incidents where id=current_setting('m39.inc')::uuid),'it is at the reporter''s facility and goes to its on-call Technician');
select pg_temp.assert_true((select count(distinct recipient_profile_id) from public.notification_outbox where incident_id=current_setting('m39.inc')::uuid and recipient_profile_id in (pg_temp.u(1),pg_temp.u(4),pg_temp.u(5),pg_temp.u(6)))=4,'Super-Administrator, on-call Technician, Supervisor and Facility Manager of the facility are alerted');
select pg_temp.assert_true(not exists(select 1 from public.notification_outbox where incident_id=current_setting('m39.inc')::uuid and recipient_profile_id in (pg_temp.u(2),pg_temp.u(3))),'Facility A''s people are not');

-- The Super-Administrator chooses Facility A: its own on-call Technician.
select pg_temp.act(pg_temp.u(1));
select public.create_incident(jsonb_build_object('facility_id',pg_temp.u(101),'incident_type','fire','location','M39 A','description','Smoke')) as inc2 \gset
select pg_temp.assert_true((select facility_id=pg_temp.u(101) and assigned_technician_id=pg_temp.u(2) from public.incidents where id=((:'inc2')::jsonb#>>'{incident,id}')::uuid),'an incident at Facility A goes to Facility A''s on-call Technician');
-- Someone may not report for another facility.
select pg_temp.act(pg_temp.u(7));
select pg_temp.assert_true((public.create_incident(jsonb_build_object('facility_id',pg_temp.u(101),'incident_type','fire','location','x','description','y'))->>'code')='ACCESS_DENIED','not at a facility one is not staff of');

select 'facility_on_call tests passed' as result;
rollback;

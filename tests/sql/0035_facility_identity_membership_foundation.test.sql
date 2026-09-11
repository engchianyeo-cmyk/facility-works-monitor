\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_true(value boolean,message text)
returns void language plpgsql as $$
begin
  if value is not true then raise exception '0035 regression failed: %',message; end if;
end$$;

\set other_technician '96000000-0000-4000-8000-000000000002'

select id as admin from public.profiles
where role='administrator' and is_active and deleted_at is null and not password_change_required
order by id limit 1 \gset
select fm.profile_id as technician
from public.facility_memberships fm
join public.profiles p on p.id=fm.profile_id
where fm.membership_role='technician' and fm.active
  and fm.effective_from<=now() and (fm.effective_to is null or fm.effective_to>now())
  and p.role='technician' and p.is_active and p.deleted_at is null and not p.password_change_required
order by fm.profile_id limit 1 \gset

select pg_temp.assert_true(
  not exists(select 1 from public.work_orders where facility_id is null),
  'a Work Order has no authoritative Facility'
);
select pg_temp.assert_true(
  not exists(select 1 from public.facility_areas where facility_id is null),
  'a Facility Area has no authoritative Facility'
);
select pg_temp.assert_true(
  not exists(select 1 from public.assets where facility_id is null),
  'an Asset has no authoritative Facility'
);
select pg_temp.assert_true(
  exists(
    select 1 from public.work_orders w join public.sites s on s.id=w.facility_id
    where w.work_order_number='WO-TEST-001' and s.code='UAT-FAC-001'
  ),
  'WO-TEST-001 is not linked to UAT-FAC-001'
);

-- Existing RPCs can still insert in the single-Facility UAT state without
-- changing their payload contract; the trigger supplies facility_id.
select set_config('request.jwt.claim.sub',:'admin',true);
select pg_temp.assert_true(
  (public.create_work_order(jsonb_build_object(
    'title','0035 creation regression',
    'location','Disposable database',
    'status','draft'
  ))->>'ok')::boolean,
  'existing create_work_order RPC no longer works'
);
select pg_temp.assert_true(
  exists(
    select 1 from public.work_orders w join public.sites s on s.id=w.facility_id
    where w.title='0035 creation regression' and s.code='UAT-FAC-001'
  ),
  'created Work Order did not receive the sole authoritative Facility'
);

-- Create a second Facility only inside this rolled-back test transaction.
insert into public.sites(id,code,name,is_active)
values('95000000-0000-4000-8000-000000000002','TEST-FAC-B','Disposable Facility B',true);

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select :'other_technician',instance_id,'authenticated','authenticated','technician-0035@example.test',encrypted_password,now(),now(),now()
from auth.users limit 1;
select set_config('request.jwt.claim.sub',:'admin',true);
select set_config('fmworks.profile_admin_rpc','on',true);
update public.profiles
set email='technician-0035@example.test',display_name='Other Technician 0035',role='technician',
    is_active=true,deleted_at=null,password_change_required=false
where id=:'other_technician';
select set_config('fmworks.profile_admin_rpc','off',true);

insert into public.work_orders(
  id,work_order_number,title,description,location,status,requested_by,user_id,
  assigned_technician_id,assigned_to,assigned_at,started_at,facility_id
)
values
('95000000-0000-4000-8000-000000000011','WO-0035-A','Facility A visibility','Disposable','A','in_progress',:'admin',:'admin',:'technician','Technician',now(),now(),(select id from public.sites where code='UAT-FAC-001')),
('95000000-0000-4000-8000-000000000012','WO-0035-B','Facility B isolation','Disposable','B','in_progress',:'admin',:'admin',:'technician','Technician',now(),now(),'95000000-0000-4000-8000-000000000002'),
('95000000-0000-4000-8000-000000000013','WO-0035-UNASSIGNED','Facility A unassigned','Disposable','A','in_progress',:'admin',:'admin',null,null,null,now(),(select id from public.sites where code='UAT-FAC-001')),
('95000000-0000-4000-8000-000000000014','WO-0035-OTHER','Facility A other assignment','Disposable','A','in_progress',:'admin',:'admin',:'other_technician','Other Technician',now(),now(),(select id from public.sites where code='UAT-FAC-001'));

set local role authenticated;
select set_config('request.jwt.claim.sub',:'technician',true);
select pg_temp.assert_true(
  (select count(*) from public.work_orders where id in ('95000000-0000-4000-8000-000000000011','95000000-0000-4000-8000-000000000012','95000000-0000-4000-8000-000000000013','95000000-0000-4000-8000-000000000014'))=3,
  'Technician did not receive exactly the three matching-Facility Work Orders'
);
select pg_temp.assert_true(
  exists(select 1 from public.work_orders where id='95000000-0000-4000-8000-000000000011'),
  'active Facility A membership did not grant Facility A read'
);
select pg_temp.assert_true(
  not exists(select 1 from public.work_orders where id='95000000-0000-4000-8000-000000000012'),
  'Facility A membership leaked Facility B Work Order'
);
select pg_temp.assert_true(
  exists(select 1 from public.work_orders where id='95000000-0000-4000-8000-000000000013'),
  'same-Facility unassigned Work Order was not readable'
);

reset role;
update public.facility_memberships set active=false where profile_id=:'technician';
set local role authenticated;
select set_config('request.jwt.claim.sub',:'technician',true);
select pg_temp.assert_true(
  not exists(select 1 from public.work_orders where id in ('95000000-0000-4000-8000-000000000011','95000000-0000-4000-8000-000000000013')),
  'inactive membership granted Work Order read'
);

reset role;
update public.facility_memberships set active=true where profile_id=:'technician';

-- Assignment, not membership, controls execution. Cover valid assignment,
-- another Technician's assignment, and the formerly fail-open NULL assignee.
select set_config('request.jwt.claim.sub',:'technician',true);
select pg_temp.assert_true(
  (public.record_work_order_execution('95000000-0000-4000-8000-000000000011',jsonb_build_object('completion_notes','Authorized execution','actual_labour_hours',1))->>'ok')::boolean,
  'assigned Technician execution was rejected'
);
select pg_temp.assert_true(
  public.record_work_order_execution('95000000-0000-4000-8000-000000000014',jsonb_build_object('completion_notes','Unauthorized','actual_labour_hours',1))->>'code'='ACCESS_DENIED',
  'different Technician execution was allowed'
);
select pg_temp.assert_true(
  public.record_work_order_execution('95000000-0000-4000-8000-000000000013',jsonb_build_object('completion_notes','Unauthorized','actual_labour_hours',1))->>'code'='ACCESS_DENIED',
  'NULL-assignee execution was allowed'
);

-- Membership is read authority only: it grants no formal-completion or
-- completed-work verification authority.
insert into public.work_orders(
  id,work_order_number,title,description,location,status,requested_by,user_id,
  assigned_technician_id,completion_notes,actual_labour_hours,facility_id
)
values
('95000000-0000-4000-8000-000000000021','WO-0035-NO-EXEC','Membership is not assignment','Disposable','A','in_progress',:'admin',:'admin',:'admin','Recorded by assigned worker',1,(select id from public.sites where code='UAT-FAC-001')),
('95000000-0000-4000-8000-000000000022','WO-0035-NO-VERIFY','Membership is not verification','Disposable','A','completed',:'admin',:'admin',:'admin','Completed fixture',1,(select id from public.sites where code='UAT-FAC-001'));

select pg_temp.assert_true(
  public.record_work_order_execution('95000000-0000-4000-8000-000000000021',jsonb_build_object('completion_notes','Unauthorized','actual_labour_hours',2))->>'code'='ACCESS_DENIED',
  'membership alone granted execution authority'
);
select pg_temp.assert_true(
  public.transition_work_order('95000000-0000-4000-8000-000000000021','complete','{}'::jsonb)->>'code'='ACCESS_DENIED',
  'membership alone granted formal completion authority'
);
select pg_temp.assert_true(
  public.verify_completed_work('95000000-0000-4000-8000-000000000022',jsonb_build_object('decision','verify'))->>'code'='ACCESS_DENIED',
  'membership alone granted completed-work verification authority'
);

-- Existing Administrator read behavior remains facility-independent.
set local role authenticated;
select set_config('request.jwt.claim.sub',:'admin',true);
select pg_temp.assert_true(
  (select count(*) from public.work_orders where id in ('95000000-0000-4000-8000-000000000011','95000000-0000-4000-8000-000000000012','95000000-0000-4000-8000-000000000013','95000000-0000-4000-8000-000000000014'))=4,
  'Administrator read behavior changed'
);

reset role;
select pg_temp.assert_true(
  exists(
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid='public.profiles'::regclass
      and t.tgname='protect_profile_authorization_fields'
      and t.tgenabled='O' and not t.tgisinternal
  ),
  'protected profile trigger is not enabled'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated','public.resolve_facility_for_write(uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.assign_work_order_facility()','EXECUTE'),
  'internal Facility functions are directly callable'
);

rollback;

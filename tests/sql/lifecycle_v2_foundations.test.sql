\set ON_ERROR_STOP on
-- WP-LC2-M1 foundations: Finance role, Approver facility scope, Administrator-only limits,
-- quotation threshold and terminology, single approval-authority rule. Synthetic, rolled back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Lifecycle v2 foundations regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;

insert into auth.users(id,email,raw_user_meta_data)
select ('1c200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'lc2.'||role||n||'@example.test',jsonb_build_object('display_name','LC2 '||role)
from (values ('technician',1),('approver',2),('supervisor',3),('facility_manager',4),('administrator',5),('finance',6),('initiator',7),('approver',8)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,
  trade_discipline=case when a.role='technician' then 'Electrical' else null end
from (values ('technician',1),('approver',2),('supervisor',3),('facility_manager',4),('administrator',5),('finance',6),('initiator',7),('approver',8)) a(role,n)
where p.id=('1c200000-0000-4000-8000-'||lpad(a.n::text,12,'0'))::uuid;
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

-- Synthetic Work Order at an active facility, raised by the Technician.
create temp table lc2 as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from lc2),p.id,p.role,'1c200000-0000-4000-8000-000000000005' from public.profiles p
where p.id in ('1c200000-0000-4000-8000-000000000001','1c200000-0000-4000-8000-000000000002','1c200000-0000-4000-8000-000000000003','1c200000-0000-4000-8000-000000000004');
insert into public.work_orders(id,user_id,requested_by,assigned_technician_id,work_order_number,title,location,priority,status,source,facility_id,created_at,updated_at)
values('1c200000-0000-4000-8000-0000000000aa','1c200000-0000-4000-8000-000000000001','1c200000-0000-4000-8000-000000000001','1c200000-0000-4000-8000-000000000001',
  'WO-LC2-001','Foundations test','Synthetic','medium','submitted','manual',(select facility_id from lc2),now(),now());

grant select on lc2 to authenticated;
set local role authenticated;
do $test$
declare r jsonb; v uuid; wo uuid:='1c200000-0000-4000-8000-0000000000aa';
begin
  -- Finance role is a ready account and sees Work Orders company-wide (read only).
  perform pg_temp.act('1c200000-0000-4000-8000-000000000006');
  perform pg_temp.assert_true(public.pilot_account_ready('1c200000-0000-4000-8000-000000000006'),'Finance account ready');
  perform pg_temp.assert_true(public.release1_work_order_visible(wo),'Finance sees Work Order');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,10)->>'code'='ACCESS_DENIED','Finance has no approval authority');

  -- Approver: member sees and may approve within S$250,000; non-member denied.
  perform pg_temp.act('1c200000-0000-4000-8000-000000000002');
  perform pg_temp.assert_true(public.release1_work_order_visible(wo),'member Approver sees Work Order');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,250000) is null,'Approver approves at S$250,000');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,250000.01)->>'code'='APPROVAL_AUTHORITY_EXCEEDED','Approver denied above S$250,000');
  perform pg_temp.act('1c200000-0000-4000-8000-000000000008');
  perform pg_temp.assert_true(not public.release1_work_order_visible(wo),'non-member Approver cannot see Work Order');
  perform pg_temp.assert_true(not exists(select 1 from public.work_orders where id=wo),'non-member Approver RLS hides Work Order');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,10)->>'code'='ACCESS_DENIED','non-member Approver denied');

  -- Supervisor / Facility Manager / Administrator tiers.
  perform pg_temp.act('1c200000-0000-4000-8000-000000000003');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,250000) is null,'Supervisor within limit');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,300000)->>'code'='APPROVAL_AUTHORITY_EXCEEDED','Supervisor over limit');
  perform pg_temp.act('1c200000-0000-4000-8000-000000000004');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,500000) is null,'Facility Manager within limit');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,500000.01)->>'code'='APPROVAL_AUTHORITY_EXCEEDED','Facility Manager over limit');
  perform pg_temp.act('1c200000-0000-4000-8000-000000000005');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,99999999) is null,'Administrator unlimited');

  -- Independence: the raising/assigned Technician has no authority; Initiator none.
  perform pg_temp.act('1c200000-0000-4000-8000-000000000001');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,10)->>'code'='ACCESS_DENIED','Technician has no approval authority');
  perform pg_temp.act('1c200000-0000-4000-8000-000000000007');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,10)->>'code'='ACCESS_DENIED','Initiator has no approval authority');

  -- Approval limits: Administrator only, optimistic concurrency, audited, versioned.
  select version_id into v from public.work_order_approval_limit_policy;
  perform pg_temp.act('1c200000-0000-4000-8000-000000000004');
  perform pg_temp.assert_true(public.change_work_order_approval_limits('{"approver":1,"supervisor":1,"facility_manager":1}','FM attempt',v)->>'code'='ACCESS_DENIED','Facility Manager cannot change limits');
  perform pg_temp.act('1c200000-0000-4000-8000-000000000005');
  perform pg_temp.assert_true(public.change_work_order_approval_limits('{"approver":100,"supervisor":200}','Missing FM',v)->>'code'='VALIDATION_ERROR','all three limits required');
  perform pg_temp.assert_true(public.change_work_order_approval_limits('{"approver":-1,"supervisor":200,"facility_manager":300}','Negative',v)->>'code'='VALIDATION_ERROR','negative limit denied');
  perform pg_temp.assert_true(public.change_work_order_approval_limits('{"approver":"NaN","supervisor":200,"facility_manager":300}','NaN',v)->>'code'='VALIDATION_ERROR','NaN limit denied');
  r:=public.change_work_order_approval_limits('{"approver":1000,"supervisor":2000,"facility_manager":3000}','Company policy change',v);
  perform pg_temp.assert_true((r->>'ok')::boolean,'Administrator changes limits');
  perform pg_temp.assert_true(public.change_work_order_approval_limits('{"approver":5,"supervisor":5,"facility_manager":5}','Stale',v)->>'code'='POLICY_CONFLICT','stale limit change denied');
  perform pg_temp.act('1c200000-0000-4000-8000-000000000003');
  perform pg_temp.assert_true(public.work_order_approval_authority(wo,2000) is null and public.work_order_approval_authority(wo,2000.01)->>'code'='APPROVAL_AUTHORITY_EXCEEDED','new Supervisor limit applies');
  perform pg_temp.assert_true(public.work_order_role_approval_limit('supervisor',v)=250000,'previous version retained');

  -- Quotation threshold: Administrator only.
  perform pg_temp.act('1c200000-0000-4000-8000-000000000004');
  perform pg_temp.assert_true(public.change_procurement_policy(1500,'FM attempt',(select version_id from public.procurement_company_policy))->>'code'='ACCESS_DENIED','Facility Manager cannot change quotation threshold');

  -- Terminology: Administrator only; validated codes; reset by blank label.
  perform pg_temp.assert_true(public.set_terminology_label('role:approver','Authoriser')->>'code'='ACCESS_DENIED','Facility Manager cannot rename');
  perform pg_temp.act('1c200000-0000-4000-8000-000000000005');
  perform pg_temp.assert_true((public.set_terminology_label('role:approver','Authoriser')->>'ok')::boolean,'Administrator renames role');
  perform pg_temp.assert_true((select label='Authoriser' from public.terminology_labels where code='role:approver'),'label stored');
  perform pg_temp.assert_true(public.set_terminology_label('role:ceo','Boss')->>'code'='VALIDATION_ERROR','unknown role rejected');
  perform pg_temp.assert_true(public.set_terminology_label('status:reviewed',repeat('x',61))->>'code'='VALIDATION_ERROR','long label rejected');
  perform pg_temp.assert_true((public.set_terminology_label('role:approver','')->>'ok')::boolean,'blank label accepted');
  perform pg_temp.assert_true(not exists(select 1 from public.terminology_labels where code='role:approver'),'blank label resets');
end;
$test$;
reset role;

-- Direct table writes are not granted; limit history is immutable.
select pg_temp.assert_true(not has_table_privilege('authenticated','public.work_order_approval_limits','INSERT'),'no direct limit insert');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.terminology_labels','INSERT'),'no direct label insert');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.work_order_copied_parties','INSERT'),'no direct copied-party insert');
select pg_temp.assert_true(not has_function_privilege('anon','public.change_work_order_approval_limits(jsonb,text,uuid)','EXECUTE'),'anon cannot change limits');
do $immutable$ begin
  begin update public.work_order_approval_limits set maximum_amount=1; raise exception 'mutation allowed';
  exception when raise_exception then if sqlerrm not like '%immutable%' then raise; end if; end;
end;$immutable$;
select pg_temp.assert_true((select count(*) from public.activity_logs where action in ('approval_limits_changed','terminology_label_changed'))>=3,'changes audited');
rollback;

-- Run only against a disposable database with migrations through 0038 applied.
-- The caller must provide an outer rollback-only transaction.

create or replace function pg_temp.assert_true(value boolean,description text) returns void language plpgsql as $$
begin if value is not true then raise exception '0038 FAIL - %',description; end if; raise notice '0038 PASS - %',description; end$$;

select id facility_id from public.sites where is_active order by id limit 1 \gset
select '03800000-0000-4000-8000-000000000001'::uuid tech1 \gset
select '03800000-0000-4000-8000-000000000002'::uuid tech2 \gset
select '03800000-0000-4000-8000-000000000003'::uuid reviewer \gset
select '03800000-0000-4000-8000-000000000004'::uuid admin_id \gset
select id vendor_id from public.vendors where active and deleted_at is null order by id limit 1 \gset

do $defer_auth_fks$
declare item record;
begin
  for item in
    select c.conrelid::regclass relation_name,c.conname
    from pg_catalog.pg_constraint c
    where c.contype='f' and c.confrelid='auth.users'::regclass
      and c.conrelid in ('public.profiles'::regclass,'public.work_orders'::regclass,'public.activity_logs'::regclass)
  loop execute format('alter table %s alter constraint %I deferrable initially deferred',item.relation_name,item.conname); end loop;
end;$defer_auth_fks$;

insert into public.profiles(id,display_name,email,role,is_active,deleted_at,password_change_required,created_at,updated_at) values
(:'tech1','0038 Technician 1','0038-tech1@example.invalid','technician',true,null,false,now(),now()),
(:'tech2','0038 Technician 2','0038-tech2@example.invalid','technician',true,null,false,now(),now()),
(:'reviewer','0038 Reviewer','0038-reviewer@example.invalid','reviewer',true,null,false,now(),now()),
(:'admin_id','0038 Administrator','0038-admin@example.invalid','administrator',true,null,false,now(),now());
insert into public.facility_memberships(facility_id,profile_id,membership_role,active,effective_from,created_by) values
(:'facility_id',:'tech1','technician',true,now()-interval '1 day',:'reviewer'),
(:'facility_id',:'tech2','technician',true,now()-interval '1 day',:'reviewer');
insert into public.sites(id,code,name,is_active)
values('03800000-0000-4000-8000-000000000010','WP038-XFAC','0038 rollback-only cross facility',true);

insert into public.work_orders(id,work_order_number,title,description,location,priority,status,user_id,requested_by,assigned_technician_id,assigned_to,created_at,updated_at,facility_id) values
('03800000-0000-4000-8000-000000000101','WO-0038-ACTIVE','Actual cost active','Disposable','Test','medium','in_progress',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000102','WO-0038-UNASSIGNED','Actual cost unassigned','Disposable','Test','medium','assigned',null,:'reviewer',null,null,now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000103','WO-0038-OTHER','Actual cost other owner','Disposable','Test','medium','in_progress',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000104','WO-0038-COMPLETED','Actual cost completed','Disposable','Test','medium','completed',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000105','WO-0038-CLOSED','Actual cost closed','Disposable','Test','medium','closed',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000106','WO-0038-XFAC','Actual cost cross facility','Disposable','Test','medium','in_progress',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),'03800000-0000-4000-8000-000000000010'),
('03800000-0000-4000-8000-000000000107','WO-0038-ZERO','Zero cost completion','Disposable','Test','medium','in_progress',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000108','WO-0038-NOSTATEMENT','Missing statement','Disposable','Test','medium','in_progress',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000109','WO-0038-NOLABOUR','Missing labour','Disposable','Test','medium','in_progress',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000110','WO-0038-NOAFTER','Missing After','Disposable','Test','medium','in_progress',null,:'reviewer',:'tech1','0038 Technician 1',now(),now(),:'facility_id'),
('03800000-0000-4000-8000-000000000111','WO-0038-PROPOSED','New proposed classification','Disposable','Test','medium','submitted',null,:'admin_id',null,null,now(),now(),:'facility_id');
update public.work_orders set assigned_vendor_id=:'vendor_id' where id='03800000-0000-4000-8000-000000000101';
update public.work_orders set completion_notes='Completed safely',actual_labour_hours=1 where id in ('03800000-0000-4000-8000-000000000101','03800000-0000-4000-8000-000000000107','03800000-0000-4000-8000-000000000110');
update public.work_orders set actual_labour_hours=1 where id='03800000-0000-4000-8000-000000000108';
update public.work_orders set completion_notes='Completed safely' where id='03800000-0000-4000-8000-000000000109';
insert into public.evidence_items(id,parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path) values
('03800000-0000-4000-8000-000000000201','work_order','03800000-0000-4000-8000-000000000101',:'tech1','after.png','image/png',10,'after','evidence/work-order/0038/101/after.png'),
('03800000-0000-4000-8000-000000000207','work_order','03800000-0000-4000-8000-000000000107',:'tech1','after.png','image/png',10,'after','evidence/work-order/0038/107/after.png'),
('03800000-0000-4000-8000-000000000208','work_order','03800000-0000-4000-8000-000000000108',:'tech1','after.png','image/png',10,'after','evidence/work-order/0038/108/after.png'),
('03800000-0000-4000-8000-000000000209','work_order','03800000-0000-4000-8000-000000000109',:'tech1','after.png','image/png',10,'after','evidence/work-order/0038/109/after.png');
insert into public.work_order_cost_lines(work_order_id,cost_type,description,quantity,unit,unit_rate,entered_by,cost_phase)
values('03800000-0000-4000-8000-000000000101','service','Approved proposed cost',1,'lump_sum',1000,:'reviewer','proposed');

set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select pg_temp.assert_true((public.set_work_order_approval_basis('03800000-0000-4000-8000-000000000111',jsonb_build_object('proposed_cost',500,'cost_basis','Quoted','execution_arrangement','Contractor','safety_isolation_information','Permit controls'))->>'ok')::boolean and exists(select 1 from public.work_order_cost_lines where work_order_id='03800000-0000-4000-8000-000000000111' and cost_phase='proposed'),'0037 proposed-cost writer classifies new row as proposed');
reset role;

set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1',true);
select pg_temp.assert_true((public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"cost_type":"labour","description":"Field labour","quantity":2,"unit":"hour","unit_rate":50}'::jsonb)->>'ok')::boolean,'assigned Technician creates actual labour');
select pg_temp.assert_true((public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"cost_type":"material","description":"Replacement detector","quantity":1,"unit":"each","unit_rate":80}'::jsonb)->>'ok')::boolean,'assigned Technician creates actual material');
select pg_temp.assert_true((public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"cost_type":"service","description":"Contractor attendance","quantity":1,"unit":"visit","unit_rate":120,"vendor_id":"ffffffff-ffff-4fff-8fff-ffffffffffff"}'::jsonb)->>'ok')::boolean,'assigned Technician creates actual contractor service');
select pg_temp.assert_true((select vendor_id=:'vendor_id' from public.work_order_cost_lines where work_order_id='03800000-0000-4000-8000-000000000101' and cost_phase='actual' and cost_type='service'),'service contractor comes from Work Order and ignores spoofed payload');
select id labour_line from public.work_order_cost_lines where work_order_id='03800000-0000-4000-8000-000000000101' and cost_phase='actual' and cost_type='labour' \gset
select pg_temp.assert_true((public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',:'labour_line','{"cost_type":"labour","description":"Corrected field labour","quantity":2.5,"unit":"hour","unit_rate":50}'::jsonb)->>'ok')::boolean,'Technician updates own active actual line');
select proposed_id from public.work_order_cost_lines where work_order_id='03800000-0000-4000-8000-000000000101' and cost_phase='proposed' \gset
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',:'proposed_id','{"cost_type":"service","description":"Attack","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='PROPOSED_COST_PROTECTED','proposed cost cannot be overwritten');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where work_order_id='03800000-0000-4000-8000-000000000101' and user_id=:'tech1' and action in ('work_order_actual_cost_created','work_order_actual_cost_updated') and note::jsonb ?& array['facility_id','cost_line_id','new','recorded_at']),'actual cost audit written');
select pg_temp.assert_true((select note::jsonb ?& array['previous','new'] from public.activity_logs where work_order_id='03800000-0000-4000-8000-000000000101' and action='work_order_actual_cost_updated' order by created_at desc,id desc limit 1),'actual cost update audits previous and new values');

select pg_temp.assert_true((public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000107',null,'{"operation":"confirm"}'::jsonb)->>'ok')::boolean and not exists(select 1 from public.work_order_cost_lines where work_order_id='03800000-0000-4000-8000-000000000107' and cost_phase='actual'),'zero-cost outcome explicitly confirmed without fake line');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where work_order_id='03800000-0000-4000-8000-000000000107' and action='work_order_actual_costing_confirmed'),'costing confirmation audited');
select pg_temp.assert_true((public.submit_physical_completion('03800000-0000-4000-8000-000000000107','{}')->>'ok')::boolean,'confirmed zero-cost job submits physical completion');

select pg_temp.assert_true(public.submit_physical_completion('03800000-0000-4000-8000-000000000101','{}')->>'code'='ACTUAL_COSTING_CONFIRMATION_REQUIRED','physical completion requires explicit actual-cost confirmation');
select pg_temp.assert_true((public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"operation":"confirm"}'::jsonb)->>'ok')::boolean,'actual costing confirmation accepted');
select pg_temp.assert_true((public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',:'labour_line','{"cost_type":"labour","description":"Final field labour","quantity":3,"unit":"hour","unit_rate":50}'::jsonb)->>'ok')::boolean and (select actual_costs_confirmed_at is null and actual_costs_confirmed_by is null from public.work_orders where id='03800000-0000-4000-8000-000000000101'),'editing actual cost clears confirmation');
select pg_temp.assert_true(public.submit_physical_completion('03800000-0000-4000-8000-000000000101','{}')->>'code'='ACTUAL_COSTING_CONFIRMATION_REQUIRED','submission blocked until costing reconfirmed');
select pg_temp.assert_true((public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"operation":"confirm"}'::jsonb)->>'ok')::boolean and (public.submit_physical_completion('03800000-0000-4000-8000-000000000101','{}')->>'ok')::boolean,'reconfirmed actual costing permits governed completion');

select public.manage_work_order_actual_cost(id,null,'{"operation":"confirm"}'::jsonb) from public.work_orders where id in ('03800000-0000-4000-8000-000000000108','03800000-0000-4000-8000-000000000109','03800000-0000-4000-8000-000000000110');
select pg_temp.assert_true(public.submit_physical_completion('03800000-0000-4000-8000-000000000108','{}')->>'code'='COMPLETION_DETAILS_REQUIRED','work statement remains required');
select pg_temp.assert_true(public.submit_physical_completion('03800000-0000-4000-8000-000000000109','{}')->>'code'='COMPLETION_DETAILS_REQUIRED','actual labour remains required');
select pg_temp.assert_true(public.submit_physical_completion('03800000-0000-4000-8000-000000000110','{}')->>'code'='AFTER_EVIDENCE_REQUIRED','active exact After evidence remains required');

create function pg_temp.reject_0038_audit() returns trigger language plpgsql as $$begin if new.action='work_order_actual_cost_created' then raise exception 'forced audit failure'; end if; return new; end$$;
create trigger wp0038_forced_audit_failure before insert on public.activity_logs for each row execute function pg_temp.reject_0038_audit();
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000110',null,'{"cost_type":"material","description":"Must roll back","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='INTERNAL_ERROR','forced audit failure returned safe error');
select pg_temp.assert_true(not exists(select 1 from public.work_order_cost_lines where work_order_id='03800000-0000-4000-8000-000000000110' and description='Must roll back'),'forced audit failure leaves no cost mutation');
drop trigger wp0038_forced_audit_failure on public.activity_logs;

reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'tech2',true);
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000103',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACCESS_DENIED','other Technician denied');
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1',true);
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000102',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACCESS_DENIED','unassigned Technician denied');
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000104',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACTUAL_COST_READ_ONLY','completed Work Order denied');
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000105',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACTUAL_COST_READ_ONLY','closed Work Order denied');
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000106',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACCESS_DENIED','cross-facility Technician denied');

reset role; update public.facility_memberships set active=false where facility_id=:'facility_id' and profile_id=:'tech1';
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1',true);
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACCESS_DENIED','inactive membership denied');
reset role; update public.facility_memberships set active=true,effective_from=now()+interval '1 day' where facility_id=:'facility_id' and profile_id=:'tech1';
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1',true);
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACCESS_DENIED','future-effective membership denied');
reset role; update public.facility_memberships set effective_from=now()-interval '2 days',effective_to=now()-interval '1 day' where facility_id=:'facility_id' and profile_id=:'tech1';
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1',true);
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACCESS_DENIED','expired membership denied');

reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'reviewer',true);
select pg_temp.assert_true(public.manage_work_order_actual_cost('03800000-0000-4000-8000-000000000101',null,'{"cost_type":"material","description":"Denied","quantity":1,"unit":"each","unit_rate":1}'::jsonb)->>'code'='ACCESS_DENIED','non-operational view-only identity denied');
reset role;

select pg_temp.assert_true(not has_function_privilege('public','public.manage_work_order_actual_cost(uuid,uuid,jsonb)','execute') and not has_function_privilege('anon','public.manage_work_order_actual_cost(uuid,uuid,jsonb)','execute'),'PUBLIC and anon execution denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.work_order_cost_lines','insert') and not has_table_privilege('authenticated','public.work_order_cost_lines','update') and not has_table_privilege('authenticated','public.work_order_cost_lines','delete'),'direct authenticated cost mutation denied');
select pg_temp.assert_true(pg_get_functiondef('public.pilot_account_ready(uuid)'::regprocedure) not like '%''view_only''%','unsupported view_only profile cannot become operational');
select pg_temp.assert_true(pg_get_functiondef('public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'::regprocedure) like '%w.assigned_technician_id=actor_id%' and pg_get_functiondef('public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'::regprocedure) like '%w.status in (''assigned'',''in_progress'')%','0036 evidence authority remains intact');
select pg_temp.assert_true(pg_get_functiondef('public.accept_work_responsibility(uuid)'::regprocedure) like '%ASSIGNMENT_CONFLICT%' and pg_get_functiondef('public.submit_physical_completion(uuid,jsonb)'::regprocedure) like '%w.assigned_technician_id<>actor_id%' and pg_get_functiondef('public.submit_physical_completion(uuid,jsonb)'::regprocedure) like '%AFTER_EVIDENCE_REQUIRED%','0037 responsibility and completion authority remain intact');

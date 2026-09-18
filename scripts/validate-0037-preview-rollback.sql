\set ON_ERROR_STOP on
\echo 'FMWorks 0037 PREVIEW ROLLBACK VALIDATION'

select current_database() as database_name, current_user as database_user, current_timestamp as validation_started_at;
do $$begin
  if current_database() <> 'postgres' then raise exception 'SAFETY STOP: expected database postgres, connected to %',current_database(); end if;
end$$;

create temp table wp026e_baseline_data(name text primary key,row_count bigint,fingerprint text);
insert into wp026e_baseline_data
select 'work_orders',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.work_orders t union all
select 'evidence_items',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.evidence_items t union all
select 'activity_logs',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.activity_logs t union all
select 'facility_memberships',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.facility_memberships t union all
select 'work_order_cost_lines',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.work_order_cost_lines t union all
select 'profiles',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.profiles t;

create temp table wp026e_baseline_functions as
select p.oid::regprocedure::text identity,md5(pg_get_functiondef(p.oid)) definition_hash,p.proacl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('pilot_account_ready','transition_work_order','verify_completed_work','record_work_order_execution','technician_facility_read_permitted','register_evidence_item');
create temp table wp026e_baseline_policies as
select c.relname,p.polname,p.polcmd,p.polroles,md5(coalesce(pg_get_expr(p.polqual,p.polrelid),'')) qualification_hash
from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('work_orders','evidence_items','facility_memberships');
create temp table wp026e_baseline_constraints as
select c.conrelid::regclass::text relation_name,c.conname,md5(pg_get_constraintdef(c.oid)) definition_hash
from pg_constraint c where c.conrelid in ('public.work_orders'::regclass,'public.evidence_items'::regclass,'public.activity_logs'::regclass,'public.facility_memberships'::regclass,'public.work_order_cost_lines'::regclass,'public.profiles'::regclass);
create temp table wp026e_candidate_absence(object_name text primary key,was_absent boolean);
insert into wp026e_candidate_absence values
('public.work_order_approval_basis',to_regclass('public.work_order_approval_basis') is null),
('public.facility_manager_facility_permitted(uuid)',to_regprocedure('public.facility_manager_facility_permitted(uuid)') is null),
('public.supervisor_facility_permitted(uuid)',to_regprocedure('public.supervisor_facility_permitted(uuid)') is null),
('public.set_work_order_approval_basis(uuid,jsonb)',to_regprocedure('public.set_work_order_approval_basis(uuid,jsonb)') is null),
('public.work_order_approval_readiness(uuid)',to_regprocedure('public.work_order_approval_readiness(uuid)') is null),
('public.accept_work_responsibility(uuid)',to_regprocedure('public.accept_work_responsibility(uuid)') is null),
('public.submit_physical_completion(uuid,jsonb)',to_regprocedure('public.submit_physical_completion(uuid,jsonb)') is null),
('public.work_order_verification_readiness(uuid)',to_regprocedure('public.work_order_verification_readiness(uuid)') is null),
('public.verify_completed_work_0037_core(uuid,jsonb)',to_regprocedure('public.verify_completed_work_0037_core(uuid,jsonb)') is null);

create or replace function pg_temp.wp026e_ok(value boolean,test_number integer,description text) returns void
language plpgsql as $$begin
  if value is not true then raise exception 'FAIL % - %',test_number,description; end if;
  raise notice 'PASS % - %',test_number,description;
end$$;
create or replace function pg_temp.wp026e_require(value boolean,description text) returns void
language plpgsql as $$begin
  if value is not true then raise exception 'PREREQUISITE FAIL - %',description; end if;
end$$;

\echo 'Baseline captured'
begin;
\ir ../supabase/migrations/0037_governed_work_order_lifecycle.sql

-- All role identities used by the regression are rollback-only profiles. No
-- Auth user or live profile is created, selected as an actor, or changed.
select id facility1_id from public.sites where is_active order by id limit 1 \gset
select '026e0000-0000-4000-8000-000000000001'::uuid fm_id \gset
select '026e0000-0000-4000-8000-000000000003'::uuid admin_id \gset
select '026e0000-0000-4000-8000-000000000004'::uuid supervisor_id \gset
select '026e0000-0000-4000-8000-000000000005'::uuid tech1_id \gset
select '026e0000-0000-4000-8000-000000000006'::uuid tech2_id \gset
select '026e0000-0000-4000-8000-000000000007'::uuid reviewer_id \gset

-- Defer only the profiles.id -> auth.users.id foreign key so the synthetic
-- JWT identity can exist for this rollback-only transaction without creating
-- or changing an Auth user. ROLLBACK restores the constraint definition.
do $synthetic_identities$
declare auth_fkey name; auth_fkey_count integer; requested_by_fkey name; activity_user_fkey name;
begin
  select (array_agg(c.conname order by c.conname))[1],count(*) into auth_fkey,auth_fkey_count
  from pg_constraint c
  where c.conrelid='public.profiles'::regclass
    and c.confrelid='auth.users'::regclass
    and c.contype='f'
    and c.conkey=array[(select a.attnum from pg_attribute a where a.attrelid='public.profiles'::regclass and a.attname='id')]::smallint[];
  if auth_fkey_count<>1 then raise exception 'PREREQUISITE FAIL - expected exactly one profiles.id Auth foreign key, found %',auth_fkey_count; end if;
  execute format('alter table public.profiles alter constraint %I deferrable initially deferred',auth_fkey);
  select (array_agg(c.conname order by c.conname))[1],count(*) into requested_by_fkey,auth_fkey_count
  from pg_constraint c
  where c.conrelid='public.work_orders'::regclass and c.confrelid='auth.users'::regclass and c.contype='f'
    and c.conkey=array[(select a.attnum from pg_attribute a where a.attrelid='public.work_orders'::regclass and a.attname='requested_by')]::smallint[];
  if auth_fkey_count<>1 then raise exception 'PREREQUISITE FAIL - expected exactly one work_orders.requested_by Auth foreign key, found %',auth_fkey_count; end if;
  execute format('alter table public.work_orders alter constraint %I deferrable initially deferred',requested_by_fkey);
  select (array_agg(c.conname order by c.conname))[1],count(*) into activity_user_fkey,auth_fkey_count
  from pg_constraint c
  where c.conrelid='public.activity_logs'::regclass and c.confrelid='auth.users'::regclass and c.contype='f'
    and c.conkey=array[(select a.attnum from pg_attribute a where a.attrelid='public.activity_logs'::regclass and a.attname='user_id')]::smallint[];
  if auth_fkey_count<>1 then raise exception 'PREREQUISITE FAIL - expected exactly one activity_logs.user_id Auth foreign key, found %',auth_fkey_count; end if;
  execute format('alter table public.activity_logs alter constraint %I deferrable initially deferred',activity_user_fkey);
end;$synthetic_identities$;
insert into public.profiles(id,display_name,email,role,is_active,deleted_at,password_change_required,created_at,updated_at)
values
(:'fm_id','WP-FMW-026E Rollback Facility Manager','wp-fmw-026e-fm@example.invalid','facility_manager',true,null,false,now(),now()),
(:'admin_id','WP-FMW-026E Rollback Administrator','wp-fmw-026e-admin@example.invalid','administrator',true,null,false,now(),now()),
(:'supervisor_id','WP-FMW-026E Rollback Supervisor','wp-fmw-026e-supervisor@example.invalid','supervisor',true,null,false,now(),now()),
(:'tech1_id','WP-FMW-026E Rollback Technician 1','wp-fmw-026e-tech1@example.invalid','technician',true,null,false,now(),now()),
(:'tech2_id','WP-FMW-026E Rollback Technician 2','wp-fmw-026e-tech2@example.invalid','technician',true,null,false,now(),now()),
(:'reviewer_id','WP-FMW-026E Rollback Reviewer','wp-fmw-026e-reviewer@example.invalid','reviewer',true,null,false,now(),now());

insert into public.sites(id,code,name,is_active) values('026e0000-0000-4000-8000-000000000002','WP026E-XFAC','WP-FMW-026E rollback-only cross facility',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,active,effective_from,created_by)
select :'facility1_id',:'fm_id','facility_manager',true,now()-interval '1 day',:'admin_id'
where not exists(select 1 from public.facility_memberships where facility_id=:'facility1_id' and profile_id=:'fm_id' and membership_role='facility_manager' and active);
insert into public.facility_memberships(facility_id,profile_id,membership_role,active,effective_from,created_by)
values(:'facility1_id',:'supervisor_id','supervisor',true,now()-interval '1 day',:'admin_id');
insert into public.facility_memberships(facility_id,profile_id,membership_role,active,effective_from,created_by)
select :'facility1_id',p.id,'technician',true,now()-interval '1 day',:'admin_id' from public.profiles p where p.id in (:'tech1_id',:'tech2_id')
and not exists(select 1 from public.facility_memberships fm where fm.facility_id=:'facility1_id' and fm.profile_id=p.id and fm.membership_role='technician' and fm.active);

-- Fixed rollback-only Work Orders.
insert into public.work_orders(id,work_order_number,title,description,location,site,priority,status,user_id,requested_by,assigned_technician_id,assigned_to,completion_notes,actual_labour_hours,created_at,updated_at,facility_id)
values
('026e0000-0000-4000-8000-000000000101','WP-FMW-026E-READY','Ready approval','Synthetic governed scope','Rollback room','WP026E','medium','submitted',null,:'admin_id',null,null,null,null,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000102','WP-FMW-026E-NOTE','Note-only approval','Synthetic governed scope','Rollback room','WP026E','medium','submitted',null,:'admin_id',null,null,null,null,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000103','WP-FMW-026E-ACCEPT','Responsibility','Synthetic governed scope','Rollback room','WP026E','medium','approved',null,:'admin_id',null,null,null,null,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000104','WP-FMW-026E-XFAC','Cross facility','Synthetic governed scope','Rollback room','WP026E','medium','in_progress',null,:'admin_id',:'tech2_id','Cross-facility Technician','Ready work',2,now(),now(),'026e0000-0000-4000-8000-000000000002'),
('026e0000-0000-4000-8000-000000000105','WP-FMW-026E-OWNED','Owned work','Synthetic governed scope','Rollback room','WP026E','medium','assigned',null,:'admin_id',:'tech2_id','Other Technician',null,null,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000106','WP-FMW-026E-SUBMITTED','Awaiting approval','Synthetic governed scope','Rollback room','WP026E','medium','submitted',null,:'admin_id',null,null,null,null,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000107','WP-FMW-026E-COMPLETED','Completed fixture','Synthetic governed scope','Rollback room','WP026E','medium','completed',null,:'admin_id',null,null,'Done',1,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000108','WP-FMW-026E-CLOSED','Closed fixture','Synthetic governed scope','Rollback room','WP026E','medium','closed',null,:'admin_id',null,null,'Done',1,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000109','WP-FMW-026E-COMPLETE','Physical completion','Synthetic governed scope','Rollback room','WP026E','medium','in_progress',null,:'admin_id',:'tech1_id','Assigned Technician','Ready work',2,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000110','WP-FMW-026E-NOSTATEMENT','No statement','Synthetic governed scope','Rollback room','WP026E','medium','in_progress',null,:'admin_id',:'tech1_id','Assigned Technician',null,2,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000111','WP-FMW-026E-NOLABOUR','No labour','Synthetic governed scope','Rollback room','WP026E','medium','in_progress',null,:'admin_id',:'tech1_id','Assigned Technician','Ready work',null,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000112','WP-FMW-026E-NOAFTER','No After','Synthetic governed scope','Rollback room','WP026E','medium','in_progress',null,:'admin_id',:'tech1_id','Assigned Technician','Ready work',2,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000113','WP-FMW-026E-DELETEDAFTER','Deleted After','Synthetic governed scope','Rollback room','WP026E','medium','in_progress',null,:'admin_id',:'tech1_id','Assigned Technician','Ready work',2,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000114','WP-FMW-026E-ADMINCOMPLETE','Admin completion','Synthetic governed scope','Rollback room','WP026E','medium','completed',null,:'admin_id',null,null,'Done',1,now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000117','WP-FMW-026E-NULL-OWNER','No individual owner','Synthetic governed scope','Rollback room','WP026E','medium','in_progress',null,:'admin_id',null,null,null,null,now(),now(),:'facility1_id');
update public.work_orders set internal_notes='Estimated cost S$4,500' where id='026e0000-0000-4000-8000-000000000102';
insert into public.evidence_items(id,parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path,deleted_at)
values
('026e0000-0000-4000-8000-000000000201','work_order','026e0000-0000-4000-8000-000000000109',:'tech1_id','after.png','image/png',100,'after','evidence/work-order/026e0000-0000-4000-8000-000000000109/026e0000-0000-4000-8000-000000000201/after.png',null),
('026e0000-0000-4000-8000-000000000202','work_order','026e0000-0000-4000-8000-000000000110',:'tech1_id','after.png','image/png',100,'after','evidence/work-order/026e0000-0000-4000-8000-000000000110/026e0000-0000-4000-8000-000000000202/after.png',null),
('026e0000-0000-4000-8000-000000000203','work_order','026e0000-0000-4000-8000-000000000111',:'tech1_id','after.png','image/png',100,'after','evidence/work-order/026e0000-0000-4000-8000-000000000111/026e0000-0000-4000-8000-000000000203/after.png',null),
('026e0000-0000-4000-8000-000000000204','work_order','026e0000-0000-4000-8000-000000000113',:'tech1_id','after.png','image/png',100,'after','evidence/work-order/026e0000-0000-4000-8000-000000000113/026e0000-0000-4000-8000-000000000204/after.png',now());
insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
values(:'admin_id','026e0000-0000-4000-8000-000000000114','work_order_complete','in_progress','completed','Rollback Administrator',jsonb_build_object('evidence_ids','[]'::jsonb)::text);

-- Facility Manager and security contracts.
select pg_temp.wp026e_ok(public.pilot_account_ready(:'fm_id'),1,'facility_manager accepted by pilot readiness');
select pg_temp.wp026e_ok((select pg_get_functiondef('public.facility_manager_facility_permitted(uuid)'::regprocedure) like '%fm.active%' and pg_get_functiondef('public.facility_manager_facility_permitted(uuid)'::regprocedure) like '%effective_from%'),2,'effective same-facility membership required');
set local role authenticated; select set_config('request.jwt.claim.sub',:'fm_id',true);
select pg_temp.wp026e_ok((select count(*)=1 from public.work_orders where id='026e0000-0000-4000-8000-000000000101'),3,'matching-facility Work Order visible');
select pg_temp.wp026e_ok((select count(*)=0 from public.work_orders where id='026e0000-0000-4000-8000-000000000104'),4,'cross-facility Work Order hidden');
reset role;

-- Prepare structured approval fixtures with Administrator authority.
set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select public.set_work_order_approval_basis('026e0000-0000-4000-8000-000000000101',jsonb_build_object('proposed_cost',250000.01,'cost_basis','Rollback quotation','execution_arrangement','Rollback contractor','safety_isolation_information','No isolation required for synthetic test'));
reset role;
set local role authenticated; select set_config('request.jwt.claim.sub',:'fm_id',true);
select pg_temp.wp026e_ok((public.transition_work_order('026e0000-0000-4000-8000-000000000101','approve','{}')->>'ok')::boolean,5,'Facility Manager approval band above 250000 through 500000');
select pg_temp.wp026e_ok((public.work_order_verification_readiness('026e0000-0000-4000-8000-000000000107')->>'ok')::boolean,6,'Facility Manager verification authority retained');
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000103')->>'code')='ACCESS_DENIED' and (public.submit_physical_completion('026e0000-0000-4000-8000-000000000109','{}')->>'code')='ACCESS_DENIED',7,'Facility Manager receives no Technician authority');
reset role;

set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select pg_temp.wp026e_ok(not (public.work_order_approval_readiness('026e0000-0000-4000-8000-000000000102')->>'ready')::boolean,8,'incomplete approval basis not ready');
select pg_temp.wp026e_ok((public.work_order_approval_readiness('026e0000-0000-4000-8000-000000000102')->'missing_requirements') ? 'structured_proposed_cost',9,'internal-notes monetary text ignored');
select pg_temp.wp026e_ok((public.work_order_approval_readiness('026e0000-0000-4000-8000-000000000101')->>'proposed_cost')::numeric=250000.01,10,'structured proposed cost recognized');
select pg_temp.wp026e_ok((select case when 250000::numeric<=250000 then 'supervisor' end)='supervisor',11,'250000 Supervisor boundary');
select pg_temp.wp026e_ok((select case when 250000.01::numeric<=250000 then 'supervisor' when 250000.01<=500000 then 'facility_manager' end)='facility_manager',12,'250000.01 Facility Manager boundary');
select pg_temp.wp026e_ok((select case when 500000::numeric<=250000 then 'supervisor' when 500000<=500000 then 'facility_manager' end)='facility_manager',13,'500000 Facility Manager boundary');
select pg_temp.wp026e_ok((select case when 500000.01::numeric<=250000 then 'supervisor' when 500000.01<=500000 then 'facility_manager' when 500000.01<=1000000 then 'administrator' end)='administrator',14,'500000.01 Administrator boundary');
select pg_temp.wp026e_ok((select case when 1000000::numeric<=1000000 then 'administrator' end)='administrator',15,'1000000 Administrator boundary');
select pg_temp.wp026e_ok((public.set_work_order_approval_basis('026e0000-0000-4000-8000-000000000102',jsonb_build_object('proposed_cost',1000000.01,'cost_basis','Board test','execution_arrangement','Synthetic','safety_isolation_information','Synthetic'))->>'code')='BOARD_APPROVAL_REQUIRED',16,'above 1000000 Board reference required');
select pg_temp.wp026e_ok((public.set_work_order_approval_basis('026e0000-0000-4000-8000-000000000102',jsonb_build_object('proposed_cost',1000000.01,'cost_basis','Board test','execution_arrangement','Synthetic','safety_isolation_information','Synthetic','board_approval_reference','BR-026E','board_supporting_document_reference','DOC-026E'))->>'code')='BOARD_APPROVAL_REQUIRED',17,'above 1000000 Board date required');
select pg_temp.wp026e_ok((public.set_work_order_approval_basis('026e0000-0000-4000-8000-000000000102',jsonb_build_object('proposed_cost',1000000.01,'cost_basis','Board test','execution_arrangement','Synthetic','safety_isolation_information','Synthetic','board_approval_reference','BR-026E','board_approval_date','2026-09-12'))->>'code')='BOARD_APPROVAL_REQUIRED',18,'above 1000000 supporting document required');
reset role;

-- Self-approval results are tested on ready rollback-only records.
insert into public.work_orders(id,work_order_number,title,description,location,site,priority,status,user_id,requested_by,created_at,updated_at,facility_id)
values('026e0000-0000-4000-8000-000000000115','WP-FMW-026E-SELF-S','Supervisor self','Synthetic scope','Rollback room','WP026E','medium','submitted',null,:'supervisor_id',now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000116','WP-FMW-026E-SELF-A','Administrator self','Synthetic scope','Rollback room','WP026E','medium','submitted',null,:'admin_id',now(),now(),:'facility1_id');
set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select public.set_work_order_approval_basis('026e0000-0000-4000-8000-000000000115',jsonb_build_object('proposed_cost',1,'cost_basis','Synthetic','execution_arrangement','Synthetic','safety_isolation_information','Synthetic'));
select public.set_work_order_approval_basis('026e0000-0000-4000-8000-000000000116',jsonb_build_object('proposed_cost',1,'cost_basis','Synthetic','execution_arrangement','Synthetic','safety_isolation_information','Synthetic'));
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'supervisor_id',true);
select pg_temp.wp026e_ok((public.transition_work_order('026e0000-0000-4000-8000-000000000115','approve','{}')->>'code')='SELF_APPROVAL_DENIED',19,'non-Administrator self-approval denied');
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select pg_temp.wp026e_ok((public.transition_work_order('026e0000-0000-4000-8000-000000000116','approve','{}')->>'code')='OVERRIDE_REASON_REQUIRED',20,'Administrator self-approval reason required');
reset role;

-- Technician responsibility.
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1_id',true);
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000103')->>'ok')::boolean,21,'eligible same-facility Technician acceptance');
select pg_temp.wp026e_ok((select assigned_technician_id=:'tech1_id' from public.work_orders where id='026e0000-0000-4000-8000-000000000103'),22,'assignment UUID becomes actor');
select pg_temp.wp026e_ok(exists(select 1 from public.activity_logs where work_order_id='026e0000-0000-4000-8000-000000000103' and action='work_order_responsibility_accepted' and user_id=:'tech1_id'),23,'acceptance audit exists');
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000104')->>'code')='ACCESS_DENIED',24,'cross-facility Technician acceptance denied');
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000105')->>'code')='ASSIGNMENT_CONFLICT',25,'another Technician assignment cannot be stolen');
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000106')->>'code')='INVALID_TRANSITION',26,'Awaiting Approval acceptance denied');
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000107')->>'code')='INVALID_TRANSITION',27,'completed acceptance denied');
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000108')->>'code')='INVALID_TRANSITION',28,'closed acceptance denied');
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'reviewer_id',true);
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000103')->>'code')='ACCESS_DENIED',29,'view-only actor denied');
reset role;

-- Physical completion.
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1_id',true);
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000109','{}')->>'ok')::boolean,30,'assigned Technician ready submission succeeds');
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000110','{}')->>'code')='COMPLETION_DETAILS_REQUIRED',31,'work statement required');
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000111','{}')->>'code')='COMPLETION_DETAILS_REQUIRED',32,'labour required');
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000111',jsonb_build_object('actual_labour_hours',-1))->>'code')='COMPLETION_DETAILS_REQUIRED',33,'negative labour denied');
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000112','{}')->>'code')='AFTER_EVIDENCE_REQUIRED',34,'active After evidence required');
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000113','{}')->>'code')='AFTER_EVIDENCE_REQUIRED',35,'deleted After evidence ignored');
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'tech2_id',true);
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000112','{}')->>'code')='ACCESS_DENIED',36,'other Technician denied');
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000104','{}')->>'code')='ACCESS_DENIED',37,'cross-facility Technician denied');
reset role;
update public.facility_memberships set active=false where facility_id=:'facility1_id' and profile_id=:'tech2_id' and membership_role='technician';
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech2_id',true);
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000105','{}')->>'code')='ACCESS_DENIED',73,'inactive Technician membership denies physical completion');
reset role;
update public.facility_memberships set active=true,effective_from=now()+interval '1 day' where facility_id=:'facility1_id' and profile_id=:'tech2_id' and membership_role='technician';
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech2_id',true);
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000105','{}')->>'code')='ACCESS_DENIED',74,'not-yet-effective Technician membership denies physical completion');
reset role;
update public.facility_memberships set effective_from=now()-interval '2 days',effective_to=now()-interval '1 day' where facility_id=:'facility1_id' and profile_id=:'tech2_id' and membership_role='technician';
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech2_id',true);
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000105','{}')->>'code')='ACCESS_DENIED',75,'expired Technician membership denies physical completion');
reset role;
update public.facility_memberships set effective_from=now()-interval '1 day',effective_to=null where facility_id=:'facility1_id' and profile_id=:'tech2_id' and membership_role='technician';
select pg_temp.wp026e_ok((select status='completed' from public.work_orders where id='026e0000-0000-4000-8000-000000000109'),38,'successful submission stores completed');
select pg_temp.wp026e_ok(exists(select 1 from public.activity_logs where work_order_id='026e0000-0000-4000-8000-000000000109' and action='work_order_complete'),39,'work_order_complete written');
select pg_temp.wp026e_ok(exists(select 1 from public.activity_logs where work_order_id='026e0000-0000-4000-8000-000000000109' and action='work_order_complete' and user_id=:'tech1_id'),40,'completion event records actor');
select pg_temp.wp026e_ok(exists(select 1 from public.activity_logs where work_order_id='026e0000-0000-4000-8000-000000000109' and action='work_order_complete' and (note::jsonb ? 'completed_at')),41,'completion event records timestamp');
select pg_temp.wp026e_ok(exists(select 1 from public.activity_logs where work_order_id='026e0000-0000-4000-8000-000000000109' and action='work_order_complete' and (note::jsonb->'evidence_ids') ? '026e0000-0000-4000-8000-000000000201'),42,'completion event records active After evidence');
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1_id',true);
select pg_temp.wp026e_ok((public.register_evidence_item('work_order','026e0000-0000-4000-8000-000000000109','later.png','image/png',100,'after','Denied after completion','evidence/work-order/026e0000-0000-4000-8000-000000000109/026e0000-0000-4000-8000-000000000299/later.png')->>'code')='EVIDENCE_READ_ONLY',43,'Technician evidence denied after completion');

-- Verification readiness.
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select pg_temp.wp026e_ok((public.work_order_verification_readiness('026e0000-0000-4000-8000-000000000109')->>'completion_event_found')::boolean,44,'governed completion event recognized');
select pg_temp.wp026e_ok(not (public.work_order_verification_readiness('026e0000-0000-4000-8000-000000000107')->>'verification_ready')::boolean,45,'missing completion event blocks readiness');
select pg_temp.wp026e_ok((public.work_order_verification_readiness('026e0000-0000-4000-8000-000000000107')->>'legacy_completion_record')::boolean,46,'legacy completion identified');
select pg_temp.wp026e_ok((public.work_order_verification_readiness('026e0000-0000-4000-8000-000000000114')->>'self_verification_reason_required')::boolean,47,'Administrator same-actor reason surfaced');
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'fm_id',true);
select pg_temp.wp026e_ok((public.work_order_verification_readiness('026e0000-0000-4000-8000-000000000109')->>'verification_ready')::boolean,48,'Facility Manager governed verification available');
reset role;

-- 0035/0036 preservation and privilege checks.
set local role authenticated; select set_config('request.jwt.claim.sub',:'tech1_id',true);
select pg_temp.wp026e_ok((select count(*)=1 from public.work_orders where id='026e0000-0000-4000-8000-000000000112'),49,'same-facility Technician read retained');
select pg_temp.wp026e_ok((select count(*)=0 from public.work_orders where id='026e0000-0000-4000-8000-000000000104'),50,'cross-facility Technician read denied');
select pg_temp.wp026e_ok(public.technician_facility_read_permitted(:'facility1_id') and not public.technician_facility_read_permitted('026e0000-0000-4000-8000-000000000002'),51,'effective membership retained');
select pg_temp.wp026e_ok((public.record_work_order_execution('026e0000-0000-4000-8000-000000000117',jsonb_build_object('completion_notes','Denied','actual_labour_hours',1))->>'code')='ACCESS_DENIED',52,'NULL-assignee execution denied');
select pg_temp.wp026e_ok((public.record_work_order_execution('026e0000-0000-4000-8000-000000000105',jsonb_build_object('completion_notes','Denied','actual_labour_hours',1))->>'code')='ACCESS_DENIED',53,'other-Technician execution denied');
select pg_temp.wp026e_ok((public.register_evidence_item('work_order','026e0000-0000-4000-8000-000000000112','eligible.png','image/png',100,'after','Eligible authority probe','evidence/work-order/026e0000-0000-4000-8000-000000000112/026e0000-0000-4000-8000-000000000298/eligible.png')->>'code')='INVALID_STORAGE_OBJECT',54,'0036 assigned-Technician evidence authority retained');
select pg_temp.wp026e_ok((public.register_evidence_item('work_order','026e0000-0000-4000-8000-000000000104','cross.png','image/png',100,'after','Denied','evidence/work-order/026e0000-0000-4000-8000-000000000104/026e0000-0000-4000-8000-000000000297/cross.png')->>'code')='EVIDENCE_READ_ONLY',55,'cross-facility evidence denied');
select pg_temp.wp026e_ok((public.register_evidence_item('work_order','026e0000-0000-4000-8000-000000000109','closed.png','image/png',100,'after','Denied','evidence/work-order/026e0000-0000-4000-8000-000000000109/026e0000-0000-4000-8000-000000000296/closed.png')->>'code')='EVIDENCE_READ_ONLY',56,'post-completion evidence denied');
reset role;
select pg_temp.wp026e_ok(not has_function_privilege('anon','public.submit_physical_completion(uuid,jsonb)','EXECUTE'),57,'anonymous execution denied');
select pg_temp.wp026e_ok(not exists(select 1 from pg_proc p,lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid in ('public.accept_work_responsibility(uuid)'::regprocedure,'public.submit_physical_completion(uuid,jsonb)'::regprocedure,'public.transition_work_order(uuid,text,jsonb)'::regprocedure) and a.grantee=0 and a.privilege_type='EXECUTE'),58,'PUBLIC execute denied');
set local role authenticated; select set_config('request.jwt.claim.sub',:'reviewer_id',true);
select pg_temp.wp026e_ok((public.submit_physical_completion('026e0000-0000-4000-8000-000000000112','{}')->>'code')='ACCESS_DENIED',59,'view-only lifecycle mutation denied');
reset role;

-- Real UAT assertions are read only.
set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select pg_temp.wp026e_ok(exists(select 1 from public.work_orders w where w.work_order_number='WO-TEST-010' and not (public.work_order_approval_readiness(w.id)->>'ready')::boolean and public.work_order_approval_readiness(w.id)->'missing_requirements' ?& array['structured_proposed_cost','cost_basis','execution_arrangement','safety_isolation_information']),60,'WO-TEST-010 remains not ready with exact governed gaps');
select l.user_id wo003_actor from public.activity_logs l join public.work_orders w on w.id=l.work_order_id where w.work_order_number='WO-TEST-003' and l.action='work_order_complete' order by l.created_at desc,l.id desc limit 1 \gset
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'wo003_actor',true);
select pg_temp.wp026e_ok(exists(select 1 from public.work_orders w where w.work_order_number='WO-TEST-003' and (public.work_order_verification_readiness(w.id)->>'completion_event_found')::boolean and (public.work_order_verification_readiness(w.id)->>'self_verification_reason_required')::boolean),61,'WO-TEST-003 completion event and self-verification reason recognized');
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select pg_temp.wp026e_ok(exists(select 1 from public.work_orders w where w.work_order_number='WO-TEST-008' and not (public.work_order_verification_readiness(w.id)->>'completion_event_found')::boolean and (public.work_order_verification_readiness(w.id)->>'legacy_completion_record')::boolean and not (public.work_order_verification_readiness(w.id)->>'verification_ready')::boolean),62,'WO-TEST-008 remains blocked legacy completion');
reset role;

-- Synthetic Supervisor facility scope and authority.
select pg_temp.wp026e_ok(public.pilot_account_ready(:'supervisor_id'),63,'Supervisor accepted by pilot readiness');
set local role authenticated; select set_config('request.jwt.claim.sub',:'supervisor_id',true);
select pg_temp.wp026e_ok((select count(*)=1 from public.work_orders where id='026e0000-0000-4000-8000-000000000101'),64,'Supervisor same-facility Work Order visible');
select pg_temp.wp026e_ok((select count(*)=0 from public.work_orders where id='026e0000-0000-4000-8000-000000000104'),65,'Supervisor cross-facility Work Order denied');
reset role;
update public.facility_memberships set active=false where facility_id=:'facility1_id' and profile_id=:'supervisor_id' and membership_role='supervisor';
set local role authenticated; select set_config('request.jwt.claim.sub',:'supervisor_id',true);
select pg_temp.wp026e_ok((select count(*)=0 from public.work_orders where id='026e0000-0000-4000-8000-000000000101'),66,'inactive Supervisor membership denies Work Order visibility');
reset role;
update public.facility_memberships set active=true,effective_from=now()+interval '1 day' where facility_id=:'facility1_id' and profile_id=:'supervisor_id' and membership_role='supervisor';
set local role authenticated; select set_config('request.jwt.claim.sub',:'supervisor_id',true);
select pg_temp.wp026e_ok((select count(*)=0 from public.work_orders where id='026e0000-0000-4000-8000-000000000101'),67,'not-yet-effective Supervisor membership denies Work Order visibility');
reset role;
update public.facility_memberships set effective_from=now()-interval '2 days',effective_to=now()-interval '1 day' where facility_id=:'facility1_id' and profile_id=:'supervisor_id' and membership_role='supervisor';
set local role authenticated; select set_config('request.jwt.claim.sub',:'supervisor_id',true);
select pg_temp.wp026e_ok((select count(*)=0 from public.work_orders where id='026e0000-0000-4000-8000-000000000101'),68,'expired Supervisor membership denies Work Order visibility');
reset role;
update public.facility_memberships set effective_from=now()-interval '1 day',effective_to=null where facility_id=:'facility1_id' and profile_id=:'supervisor_id' and membership_role='supervisor';
insert into public.work_orders(id,work_order_number,title,description,location,site,priority,status,user_id,requested_by,created_at,updated_at,facility_id)
values
('026e0000-0000-4000-8000-000000000118','WP-FMW-026E-SUP-250K','Supervisor approval boundary','Synthetic scope','Rollback room','WP026E','medium','submitted',null,:'admin_id',now(),now(),:'facility1_id'),
('026e0000-0000-4000-8000-000000000119','WP-FMW-026E-SUP-OVER','Supervisor escalation boundary','Synthetic scope','Rollback room','WP026E','medium','submitted',null,:'admin_id',now(),now(),:'facility1_id');
set local role authenticated; select set_config('request.jwt.claim.sub',:'admin_id',true);
select public.set_work_order_approval_basis('026e0000-0000-4000-8000-000000000118',jsonb_build_object('proposed_cost',250000,'cost_basis','Synthetic','execution_arrangement','Synthetic','safety_isolation_information','Synthetic'));
select public.set_work_order_approval_basis('026e0000-0000-4000-8000-000000000119',jsonb_build_object('proposed_cost',250000.01,'cost_basis','Synthetic','execution_arrangement','Synthetic','safety_isolation_information','Synthetic'));
reset role; set local role authenticated; select set_config('request.jwt.claim.sub',:'supervisor_id',true);
select pg_temp.wp026e_ok((public.transition_work_order('026e0000-0000-4000-8000-000000000118','approve','{}')->>'ok')::boolean,69,'Supervisor approval allowed at 250000');
select pg_temp.wp026e_ok((public.transition_work_order('026e0000-0000-4000-8000-000000000119','approve','{}')->>'code')='APPROVAL_AUTHORITY_EXCEEDED',70,'Supervisor approval above 250000 denied');
select pg_temp.wp026e_ok((public.work_order_verification_readiness('026e0000-0000-4000-8000-000000000114')->>'verification_ready')::boolean,71,'same-facility Supervisor verification allowed');
select pg_temp.wp026e_ok((public.accept_work_responsibility('026e0000-0000-4000-8000-000000000103')->>'code')='ACCESS_DENIED' and (public.submit_physical_completion('026e0000-0000-4000-8000-000000000112','{}')->>'code')='ACCESS_DENIED',72,'Supervisor receives no Technician authority');
reset role;

\echo '0037 SQL REGRESSION: 75/75 PASS'
rollback;

-- Post-rollback comparison against session-temporary baselines.
do $postrollback$
declare mismatch text; synthetic_count bigint;
begin
  with current_data as (
    select 'work_orders' name,count(*) row_count,md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) fingerprint from public.work_orders t union all
    select 'evidence_items',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.evidence_items t union all
    select 'activity_logs',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.activity_logs t union all
    select 'facility_memberships',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.facility_memberships t union all
    select 'work_order_cost_lines',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.work_order_cost_lines t union all
    select 'profiles',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.profiles t
  ) select string_agg(b.name,',') into mismatch from wp026e_baseline_data b full join current_data c using(name)
    where (b.row_count,b.fingerprint) is distinct from (c.row_count,c.fingerprint);
  if mismatch is not null then raise exception 'Post-rollback data differs: %',mismatch; end if;
  if exists(select 1 from wp026e_baseline_functions b full join (
    select p.oid::regprocedure::text identity,md5(pg_get_functiondef(p.oid)) definition_hash,p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('pilot_account_ready','transition_work_order','verify_completed_work','record_work_order_execution','technician_facility_read_permitted','register_evidence_item')) c using(identity)
    where b.identity is null or c.identity is null or (b.definition_hash,b.proacl) is distinct from (c.definition_hash,c.proacl)) then raise exception 'Post-rollback function definition or ACL differs'; end if;
  if exists(select 1 from wp026e_baseline_policies b full join (
    select c.relname,p.polname,p.polcmd,p.polroles,md5(coalesce(pg_get_expr(p.polqual,p.polrelid),'')) qualification_hash
    from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('work_orders','evidence_items','facility_memberships')) x using(relname,polname)
    where b.relname is null or x.relname is null or (b.polcmd,b.polroles,b.qualification_hash) is distinct from (x.polcmd,x.polroles,x.qualification_hash)) then raise exception 'Post-rollback policy differs'; end if;
  if exists(select 1 from wp026e_baseline_constraints b full join (
    select c.conrelid::regclass::text relation_name,c.conname,md5(pg_get_constraintdef(c.oid)) definition_hash from pg_constraint c
    where c.conrelid in ('public.work_orders'::regclass,'public.evidence_items'::regclass,'public.activity_logs'::regclass,'public.facility_memberships'::regclass,'public.work_order_cost_lines'::regclass,'public.profiles'::regclass)) x using(relation_name,conname)
    where b.relation_name is null or x.relation_name is null or b.definition_hash is distinct from x.definition_hash) then raise exception 'Post-rollback constraint differs'; end if;
  if exists(select 1 from wp026e_candidate_absence where was_absent and case
    when object_name='public.work_order_approval_basis' then to_regclass(object_name) is not null
    else to_regprocedure(object_name) is not null end) then raise exception 'Candidate-only object remains after rollback'; end if;
  select
    (select count(*) from public.profiles where id in (
      '026e0000-0000-4000-8000-000000000001','026e0000-0000-4000-8000-000000000003',
      '026e0000-0000-4000-8000-000000000004','026e0000-0000-4000-8000-000000000005',
      '026e0000-0000-4000-8000-000000000006','026e0000-0000-4000-8000-000000000007'))
    +(select count(*) from public.sites where id='026e0000-0000-4000-8000-000000000002')
    +(select count(*) from public.work_orders where work_order_number like 'WP-FMW-026E-%')
  into synthetic_count;
  if synthetic_count<>0 then raise exception 'Synthetic rollback fixtures remain: %',synthetic_count; end if;
end;$postrollback$;

\echo 'ROLLBACK CONFIRMED'
\echo 'PREVIEW PERSISTENT CHANGES: NONE'

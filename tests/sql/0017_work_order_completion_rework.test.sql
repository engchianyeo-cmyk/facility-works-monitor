\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(value boolean, message text)
returns void language plpgsql as $$
begin if value is not true then raise exception 'ASSERTION FAILED: %',message; end if; end
$$;

select pg_temp.assert_true(
  to_regprocedure('public.transition_work_order(uuid,text,jsonb)') is not null,
  'transition RPC exists after 0017'
);
select pg_temp.assert_true((
  select p.prosecdef and p.proconfig @> array['search_path=pg_catalog']
  from pg_proc p where p.oid='public.transition_work_order(uuid,text,jsonb)'::regprocedure
), 'transition RPC is SECURITY DEFINER with fixed pg_catalog search_path');
select pg_temp.assert_true(has_function_privilege('authenticated','public.transition_work_order(uuid,text,jsonb)','EXECUTE'),'authenticated execute granted');
select pg_temp.assert_true(not has_function_privilege('anon','public.transition_work_order(uuid,text,jsonb)','EXECUTE'),'anon execute denied');
select pg_temp.assert_true(not has_function_privilege('service_role','public.transition_work_order(uuid,text,jsonb)','EXECUTE'),'service role execute denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.work_orders','UPDATE'),'direct Work Order update remains denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.activity_logs','INSERT'),'direct audit insert remains denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.notification_outbox','INSERT'),'direct outbox insert remains denied');
select pg_temp.assert_true((select count(*)=3 from public.work_orders where id in (
  '30000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000003'
)), 'existing Work Orders remain present');

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select public.create_work_order(jsonb_build_object(
  'title','Repeated rework validation','location','Plant Room','status','submitted','source','reactive'
)) as result \gset main_created_
select pg_temp.assert_true((:'main_created_result'::jsonb->>'ok')::boolean,'main Work Order created');
select (:'main_created_result'::jsonb#>>'{work_order,id}') as main_id \gset

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select public.transition_work_order(:'main_id'::uuid,'approve','{}') as result \gset main_approve_
select pg_temp.assert_true((:'main_approve_result'::jsonb->>'ok')::boolean,'Approver approved initial request');
select public.assign_work_order(:'main_id'::uuid,'technician','10000000-0000-4000-8000-000000000004') as result \gset main_assign_
select pg_temp.assert_true((:'main_assign_result'::jsonb->>'ok')::boolean,'active Technician assigned');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',false);
select public.transition_work_order(:'main_id'::uuid,'accept','{}') as result \gset main_accept_
select public.transition_work_order(:'main_id'::uuid,'start','{}') as result \gset main_start_
select pg_temp.assert_true((:'main_accept_result'::jsonb->>'ok')::boolean and (:'main_start_result'::jsonb->>'ok')::boolean,'assigned Technician accepted and started');
reset role;

insert into public.evidence_items(
  id,parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path
) values (
  '60000000-0000-4000-8000-000000000001','work_order',:'main_id'::uuid,
  '10000000-0000-4000-8000-000000000004','bearing-before.jpg','image/jpeg',128,'before',
  'evidence/work-order/'||:'main_id'||'/60000000-0000-4000-8000-000000000001/bearing-before.jpg'
);

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',false);
select public.transition_work_order(:'main_id'::uuid,'complete',jsonb_build_object(
  'completion_notes','Initial bearing replacement','actual_labour_hours',2.5
)) as result \gset cycle_one_
select pg_temp.assert_true((:'cycle_one_result'::jsonb#>>'{work_order,status}')='completed','Technician completion reached completed');
select pg_temp.assert_true((:'cycle_one_result'::jsonb->>'cycle')::integer=1,'first completion is cycle one');
select pg_temp.assert_true((select (note::jsonb->>'cycle')::integer=1 and note::jsonb->'evidence_ids' ? '60000000-0000-4000-8000-000000000001' from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_complete'),'completion snapshot preserves cycle and evidence ID');
select count(*) as value from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_complete' \gset complete_before_retry_
select count(*) as value from public.notification_outbox where work_order_id=:'main_id'::uuid \gset outbox_before_retry_
select public.transition_work_order(:'main_id'::uuid,'complete',jsonb_build_object('completion_notes','Duplicate','actual_labour_hours',2.5)) as result \gset complete_retry_
select pg_temp.assert_true(:'complete_retry_result'::jsonb->>'code'='NO_CHANGE','completion retry is an idempotent success');
select pg_temp.assert_true((select count(*)=:'complete_before_retry_value'::integer from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_complete'),'completion retry creates no audit row');
select pg_temp.assert_true((select count(*)=:'outbox_before_retry_value'::integer from public.notification_outbox where work_order_id=:'main_id'::uuid),'completion retry creates no outbox row');

reset role;
insert into public.evidence_items(
  id,parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path
) values (
  '60000000-0000-4000-8000-000000000002','work_order',:'main_id'::uuid,
  '10000000-0000-4000-8000-000000000004','post-submission.jpg','image/jpeg',64,'after',
  'evidence/work-order/'||:'main_id'||'/60000000-0000-4000-8000-000000000002/post-submission.jpg'
);
set role authenticated;

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select public.transition_work_order(:'main_id'::uuid,'review','{}') as result \gset unauthorized_review_
select pg_temp.assert_true(:'unauthorized_review_result'::jsonb->>'code'='ACCESS_DENIED','unauthorized review denied');
select public.transition_work_order(:'main_id'::uuid,'return_for_rework',jsonb_build_object('reason','Not permitted')) as result \gset unauthorized_return_
select pg_temp.assert_true(:'unauthorized_return_result'::jsonb->>'code'='ACCESS_DENIED','unauthorized return denied');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select public.transition_work_order(:'main_id'::uuid,'return_for_rework','{}') as result \gset reason_required_
select pg_temp.assert_true(:'reason_required_result'::jsonb->>'code'='REWORK_REASON_REQUIRED','rework reason required');
reset role;
update public.profiles set is_active=false where id='10000000-0000-4000-8000-000000000004';
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select public.transition_work_order(:'main_id'::uuid,'return_for_rework',jsonb_build_object('reason','Correct alignment')) as result \gset inactive_assignment_
select pg_temp.assert_true(:'inactive_assignment_result'::jsonb->>'code'='INVALID_ASSIGNMENT','active Technician assignment enforced');
reset role;
update public.profiles set is_active=true where id='10000000-0000-4000-8000-000000000004';

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select public.transition_work_order(:'main_id'::uuid,'return_for_rework',jsonb_build_object('reason','Correct shaft alignment')) as result \gset return_one_
select pg_temp.assert_true((:'return_one_result'::jsonb#>>'{work_order,status}')='in_progress','completed returned to in_progress');
select pg_temp.assert_true((:'return_one_result'::jsonb->>'cycle')::integer=1,'first return refers to cycle one');
select pg_temp.assert_true((select completed_at is null from public.work_orders where id=:'main_id'::uuid),'completed_at cleared only after preservation');
select pg_temp.assert_true((select note::jsonb#>>'{previous_completion,completion_notes}'='Initial bearing replacement' and note::jsonb#>'{previous_completion,evidence_ids}' ? '60000000-0000-4000-8000-000000000001' and not (note::jsonb#>'{previous_completion,evidence_ids}' ? '60000000-0000-4000-8000-000000000002') from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_returned_for_rework'),'rework audit preserves the evidence snapshot captured at completion submission');
select count(*) as value from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_returned_for_rework' \gset return_before_retry_
select public.transition_work_order(:'main_id'::uuid,'return_for_rework',jsonb_build_object('reason','Duplicate retry')) as result \gset return_retry_
select pg_temp.assert_true(:'return_retry_result'::jsonb->>'code'='NO_CHANGE','rework retry is idempotent');
select pg_temp.assert_true((select count(*)=:'return_before_retry_value'::integer from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_returned_for_rework'),'rework retry creates no audit row');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',false);
select public.transition_work_order(:'main_id'::uuid,'complete',jsonb_build_object('completion_notes','Alignment corrected','actual_labour_hours',2.0)) as result \gset low_hours_
select pg_temp.assert_true(:'low_hours_result'::jsonb->>'code'='CUMULATIVE_LABOUR_REQUIRED','resubmission cannot lower cumulative labour');
select public.transition_work_order(:'main_id'::uuid,'complete',jsonb_build_object('completion_notes','Alignment corrected','actual_labour_hours',3.5)) as result \gset cycle_two_
select pg_temp.assert_true((:'cycle_two_result'::jsonb->>'cycle')::integer=2,'resubmission is cycle two');
select pg_temp.assert_true((select (note::jsonb->>'resubmission')::boolean from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_complete' order by created_at desc,id desc limit 1),'resubmission is marked in audit');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select public.transition_work_order(:'main_id'::uuid,'return_for_rework',jsonb_build_object('reason','Retest vibration')) as result \gset return_two_
select pg_temp.assert_true((:'return_two_result'::jsonb->>'cycle')::integer=2,'Approver can return cycle two');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',false);
select public.transition_work_order(:'main_id'::uuid,'complete',jsonb_build_object('completion_notes','Vibration retest passed','actual_labour_hours',4.0)) as result \gset cycle_three_
select pg_temp.assert_true((:'cycle_three_result'::jsonb->>'cycle')::integer=3,'third completion has deterministic cycle three');
select pg_temp.assert_true((select count(*)=3 from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_complete'),'all completion submissions preserved');
select pg_temp.assert_true((select count(*)=2 from public.evidence_items where work_order_id=:'main_id'::uuid),'evidence remains unchanged across rework cycles');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select public.transition_work_order(:'main_id'::uuid,'review',jsonb_build_object('note','Completion accepted after vibration retest')) as result \gset supervisor_review_
select pg_temp.assert_true((:'supervisor_review_result'::jsonb#>>'{work_order,status}')='reviewed','Supervisor review accepted');
select count(*) as value from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_review' \gset review_before_retry_
select public.transition_work_order(:'main_id'::uuid,'review','{}') as result \gset review_retry_
select pg_temp.assert_true(:'review_retry_result'::jsonb->>'code'='NO_CHANGE','review retry is idempotent');
select pg_temp.assert_true((select count(*)=:'review_before_retry_value'::integer from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_review'),'review retry creates no audit row');
select public.transition_work_order(:'main_id'::uuid,'close','{}') as result \gset supervisor_close_
select pg_temp.assert_true(:'supervisor_close_result'::jsonb->>'code'='ACCESS_DENIED','Supervisor final closure remains denied');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select public.transition_work_order(:'main_id'::uuid,'close','{}') as result \gset approver_close_
select pg_temp.assert_true((:'approver_close_result'::jsonb#>>'{work_order,status}')='closed','Approver final closure remains allowed');
reset role;

-- Approver completion review on an independently completed Work Order.
insert into public.work_orders(user_id,requested_by,title,location,priority,status,source,assigned_technician_id,completion_notes,actual_labour_hours,completed_at)
values('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003','Approver review validation','Workshop','medium','completed','manual','10000000-0000-4000-8000-000000000004','Completed for Approver',1,now()) returning id as approver_review_id \gset
insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
values('10000000-0000-4000-8000-000000000004',:'approver_review_id','work_order_complete','in_progress','completed','Technician',jsonb_build_object('cycle',1)::text);
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select public.transition_work_order(:'approver_review_id'::uuid,'review','{}') as result \gset approver_review_
select pg_temp.assert_true((:'approver_review_result'::jsonb#>>'{work_order,status}')='reviewed','Approver review remains allowed');
reset role;

-- Administrator self-review requires an immutable override reason.
insert into public.work_orders(user_id,requested_by,title,location,priority,status,source,assigned_technician_id,completion_notes,actual_labour_hours,completed_at)
values('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Administrator self-review validation','Office','medium','completed','manual','10000000-0000-4000-8000-000000000004','Administrator completion',1,now()) returning id as admin_review_id \gset
insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
values('10000000-0000-4000-8000-000000000001',:'admin_review_id','work_order_complete','in_progress','completed','Admin',jsonb_build_object('cycle',1)::text);
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select public.transition_work_order(:'admin_review_id'::uuid,'review','{}') as result \gset admin_review_denied_
select pg_temp.assert_true(:'admin_review_denied_result'::jsonb->>'code'='OVERRIDE_REASON_REQUIRED','Administrator silent self-review prevented');
select public.transition_work_order(:'admin_review_id'::uuid,'review',jsonb_build_object('reason','Emergency duty separation override')) as result \gset admin_review_allowed_
select pg_temp.assert_true((:'admin_review_allowed_result'::jsonb#>>'{work_order,status}')='reviewed','reasoned Administrator self-review allowed');
select pg_temp.assert_true((select (note::jsonb->>'administrator_override')::boolean from public.activity_logs where work_order_id=:'admin_review_id'::uuid and action='work_order_review'),'Administrator override recorded immutably');
reset role;

-- Forced audit failure must roll back the return and outbox atomically.
insert into public.work_orders(user_id,requested_by,title,location,priority,status,source,assigned_technician_id,completion_notes,actual_labour_hours,completed_at)
values('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003','Atomic return validation','Plant','medium','completed','manual','10000000-0000-4000-8000-000000000004','Atomic completion',1,now()) returning id as atomic_id \gset
insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
values('10000000-0000-4000-8000-000000000004',:'atomic_id','work_order_complete','in_progress','completed','Technician',jsonb_build_object('cycle',1)::text);
create or replace function pg_temp.fail_rework_audit() returns trigger language plpgsql as $$
begin if new.action='work_order_returned_for_rework' then raise exception 'forced rework audit failure'; end if; return new; end
$$;
create trigger force_rework_audit before insert on public.activity_logs for each row execute function pg_temp.fail_rework_audit();
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select public.transition_work_order(:'atomic_id'::uuid,'return_for_rework',jsonb_build_object('reason','Must roll back')) as result \gset atomic_return_
select pg_temp.assert_true(:'atomic_return_result'::jsonb->>'code'='INTERNAL_ERROR','audit failure is reported safely');
reset role;
select pg_temp.assert_true((select status='completed' and completed_at is not null from public.work_orders where id=:'atomic_id'),'audit failure rolls back Work Order mutation');
select pg_temp.assert_true(not exists(select 1 from public.notification_outbox where work_order_id=:'atomic_id'),'audit failure creates no outbox row');
drop trigger force_rework_audit on public.activity_logs;

select pg_temp.assert_true((select count(*)=2 from public.activity_logs where work_order_id=:'main_id'::uuid and action='work_order_returned_for_rework'),'two immutable rework cycles retained');
select pg_temp.assert_true((select count(*)=9 from public.notification_outbox where work_order_id=:'main_id'::uuid),'all main-cycle outbox recipients queued once');
select pg_temp.assert_true(not exists(select 1 from public.notification_outbox where work_order_id=:'main_id'::uuid and delivery_status<>'pending'),'outbox rows remain queued only');
select pg_temp.assert_true((select count(*)=count(distinct event_key||':'||coalesce(recipient_profile_id::text,'')||':'||coalesce(channel,'')) from public.notification_outbox where work_order_id=:'main_id'::uuid),'outbox deduplication keys remain unique');

select '0017 completion rework database tests passed' as result;

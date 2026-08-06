\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(value boolean, message text)
returns void language plpgsql as $$ begin if value is not true then raise exception 'ASSERTION FAILED: %', message; end if; end $$;

select pg_temp.assert_true(to_regprocedure('public.create_work_order(jsonb)') is not null, 'create RPC exists');
select pg_temp.assert_true(to_regprocedure('public.update_work_order(uuid,jsonb)') is not null, 'update RPC exists');
select pg_temp.assert_true(to_regprocedure('public.assign_work_order(uuid,text,uuid)') is not null, 'assign RPC exists');
select pg_temp.assert_true(to_regprocedure('public.list_public_work_orders()') is not null, 'public read RPC exists');
select pg_temp.assert_true(to_regprocedure('public.transition_work_order(uuid,text,jsonb)') is not null, 'transition RPC exists');
select pg_temp.assert_true(to_regprocedure('public.duplicate_work_order(uuid)') is not null, 'duplicate RPC exists');
select pg_temp.assert_true(to_regprocedure('public.admin_correct_work_order(uuid,jsonb,text)') is not null, 'correction RPC exists');

select pg_temp.assert_true(not has_function_privilege('anon','public.create_work_order(jsonb)','EXECUTE'), 'anon create denied');
select pg_temp.assert_true(has_function_privilege('anon','public.list_public_work_orders()','EXECUTE'), 'anon public read granted');
select pg_temp.assert_true(not has_table_privilege('anon','public.work_orders','SELECT'), 'anon direct work-order read denied');
select pg_temp.assert_true(has_function_privilege('authenticated','public.create_work_order(jsonb)','EXECUTE'), 'authenticated create granted');
select pg_temp.assert_true(not has_function_privilege('service_role','public.create_work_order(jsonb)','EXECUTE'), 'service role create deliberately denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.work_orders','INSERT'), 'authenticated insert denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.work_orders','UPDATE'), 'authenticated update denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.work_orders','DELETE'), 'authenticated delete denied');

set role anon;
select pg_temp.assert_true(not exists (select 1 from public.list_public_work_orders() where status = 'draft'), 'public read excludes drafts');
reset role;

select pg_temp.assert_true((select status = 'completed' and work_order_number = 'FW-2025-0042' from public.work_orders where id='30000000-0000-4000-8000-000000000001'), 'legacy completed reference preserved');
select pg_temp.assert_true((select status = 'submitted' from public.work_orders where id='30000000-0000-4000-8000-000000000002'), 'legacy reviewed converted to submitted');
select pg_temp.assert_true((select status = 'cancelled' from public.work_orders where id='30000000-0000-4000-8000-000000000003'), 'legacy rejected converted to cancelled');

insert into public.vendors (id,name,active) values
 ('40000000-0000-4000-8000-000000000001','Active Vendor',true),
 ('40000000-0000-4000-8000-000000000002','Inactive Vendor',false);
insert into public.maintenance_teams (id,name,is_active) values
 ('50000000-0000-4000-8000-000000000001','Active Team',true),
 ('50000000-0000-4000-8000-000000000002','Inactive Team',false);

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select public.create_work_order(jsonb_build_object(
  'title','Predictive bearing replacement','location','Plant Room','status','submitted',
  'source','predictive','prediction_reference','PRED-42','health_score_at_creation',42,
  'failure_probability',0.82,'confidence_score',0.91,'recommended_action','Replace bearing'
)) as result \gset created_
select pg_temp.assert_true((:'created_result'::jsonb ->> 'ok')::boolean, 'predictive work order created');
select (:'created_result'::jsonb #>> '{work_order,id}') as work_order_id \gset

select public.create_work_order(jsonb_build_object('title','Invalid score','location','Plant','confidence_score',1.2)) as result \gset invalid_
select pg_temp.assert_true(:'invalid_result'::jsonb ->> 'code' = 'VALIDATION_ERROR', 'invalid confidence rejected');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select public.transition_work_order(:'work_order_id'::uuid,'approve','{}'::jsonb) as result \gset approve_
select pg_temp.assert_true((:'approve_result'::jsonb ->> 'ok')::boolean, 'approver approved');
select public.assign_work_order(:'work_order_id'::uuid,'technician','10000000-0000-4000-8000-000000000004') as result \gset assign_
select pg_temp.assert_true((:'assign_result'::jsonb ->> 'ok')::boolean, 'active technician assigned');
select count(*) as value from public.activity_logs where work_order_id = :'work_order_id'::uuid \gset no_op_before_
select public.assign_work_order(:'work_order_id'::uuid,'technician','10000000-0000-4000-8000-000000000004') as result \gset no_op_
select pg_temp.assert_true(:'no_op_result'::jsonb ->> 'code' = 'NO_CHANGE', 'same assignee is a no-op');
select count(*) as value from public.activity_logs where work_order_id = :'work_order_id'::uuid \gset no_op_after_
select pg_temp.assert_true(:'no_op_before_value'::integer = :'no_op_after_value'::integer, 'same-assignee no-op does not create a mutation audit');

select public.assign_work_order(:'work_order_id'::uuid,'technician','10000000-0000-4000-8000-000000000005') as result \gset inactive_
select pg_temp.assert_true(:'inactive_result'::jsonb ->> 'code' = 'INACTIVE_REFERENCE', 'inactive technician rejected');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',false);
select public.transition_work_order(:'work_order_id'::uuid,'accept','{}'::jsonb) as result \gset accept_
select pg_temp.assert_true((:'accept_result'::jsonb ->> 'ok')::boolean, 'assigned technician accepted');
select public.transition_work_order(:'work_order_id'::uuid,'start','{}'::jsonb) as result \gset start_
select pg_temp.assert_true((:'start_result'::jsonb ->> 'ok')::boolean, 'assigned technician started');
select public.transition_work_order(:'work_order_id'::uuid,'complete',jsonb_build_object('completion_notes','Bearing replaced','actual_labour_hours',2.5)) as result \gset complete_
select pg_temp.assert_true((:'complete_result'::jsonb ->> 'ok')::boolean, 'completion details accepted');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
select public.transition_work_order(:'work_order_id'::uuid,'review','{}'::jsonb) as result \gset review_
select pg_temp.assert_true((:'review_result'::jsonb ->> 'ok')::boolean, 'approver reviewed');
select public.transition_work_order(:'work_order_id'::uuid,'close','{}'::jsonb) as result \gset close_
select pg_temp.assert_true((:'close_result'::jsonb ->> 'ok')::boolean, 'approver closed');
select public.update_work_order(:'work_order_id'::uuid,jsonb_build_object('title','Illegal terminal edit')) as result \gset terminal_
select pg_temp.assert_true(:'terminal_result'::jsonb ->> 'code' = 'TERMINAL_IMMUTABLE', 'closed record immutable');

select public.create_work_order(jsonb_build_object('title','Approver request','location','Office','status','submitted')) as result \gset own_
select (:'own_result'::jsonb #>> '{work_order,id}') as own_id \gset
select public.transition_work_order(:'own_id'::uuid,'approve','{}'::jsonb) as result \gset self_
select pg_temp.assert_true(:'self_result'::jsonb ->> 'code' = 'SELF_APPROVAL_DENIED', 'approver self approval denied');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select public.create_work_order(jsonb_build_object('title','Admin request','location','Office','status','submitted')) as result \gset admin_own_
select (:'admin_own_result'::jsonb #>> '{work_order,id}') as admin_own_id \gset
select public.transition_work_order(:'admin_own_id'::uuid,'approve','{}'::jsonb) as result \gset admin_no_reason_
select pg_temp.assert_true(:'admin_no_reason_result'::jsonb ->> 'code' = 'OVERRIDE_REASON_REQUIRED', 'administrator self approval requires reason');
select public.transition_work_order(:'admin_own_id'::uuid,'approve',jsonb_build_object('reason','Emergency safety response')) as result \gset admin_override_
select pg_temp.assert_true((:'admin_override_result'::jsonb ->> 'ok')::boolean, 'reasoned administrator override accepted');

select public.duplicate_work_order(:'work_order_id'::uuid) as result \gset duplicate_
select pg_temp.assert_true((:'duplicate_result'::jsonb #>> '{work_order,status}') = 'draft', 'duplicate is draft');
select pg_temp.assert_true((:'duplicate_result'::jsonb #>> '{work_order,duplicated_from_id}') = :'work_order_id', 'duplicate provenance recorded');
select pg_temp.assert_true((:'duplicate_result'::jsonb #>> '{work_order,work_order_number}') <> (select work_order_number from public.work_orders where id=:'work_order_id'::uuid), 'duplicate number unique');

reset role;
create or replace function pg_temp.fail_work_order_update_audit() returns trigger language plpgsql as $$ begin if new.action='work_order_updated' then raise exception 'forced audit failure'; end if; return new; end $$;
create trigger force_audit_failure before insert on public.activity_logs for each row execute function pg_temp.fail_work_order_update_audit();
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select public.update_work_order(:'admin_own_id'::uuid,jsonb_build_object('title','Should roll back')) as result \gset rollback_
select pg_temp.assert_true(:'rollback_result'::jsonb ->> 'code' = 'INTERNAL_ERROR', 'audit failure reported');
select pg_temp.assert_true((select title <> 'Should roll back' from public.work_orders where id=:'admin_own_id'::uuid), 'audit failure rolled back mutation');
reset role;
drop trigger force_audit_failure on public.activity_logs;

select pg_temp.assert_true((select count(*) = count(distinct work_order_number) from public.work_orders), 'work-order numbers unique');

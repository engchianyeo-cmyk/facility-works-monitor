\set ON_ERROR_STOP on
create or replace function pg_temp.assert_true(condition boolean,message text) returns void language plpgsql as $$begin if not coalesce(condition,false) then raise exception 'ASSERTION FAILED: %',message; end if; end$$;

select pg_temp.assert_true((select count(*)=15 from public.work_orders where work_order_number like 'WO-TEST-%'),'exactly 15 UAT Work Orders load');
select pg_temp.assert_true((select count(distinct priority)=4 from public.work_orders where work_order_number like 'WO-TEST-%'),'all four priorities are represented');
select pg_temp.assert_true((select count(distinct status)>=5 from public.work_orders where work_order_number like 'WO-TEST-%'),'lifecycle diversity is represented');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-TEST-004' and assigned_vendor_id is not null) and exists(select 1 from public.work_orders where work_order_number='WO-TEST-006' and assigned_vendor_id is not null),'vendor scenarios have governed relationships');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-TEST-013' and priority='critical' and internal_notes like '%Immediate control%'),'safety-critical scenario is retained');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-TEST-002' and source='preventive'),'PM provenance is retained');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-TEST-008' and actual_labour_hours=1.4 and internal_notes like '%Actual cost: S$95%'),'completed actual cost/hours are retained');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-TEST-012' and status='in_progress' and source_reference like '%Reopened%'),'reopened scenario is mapped explicitly');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-TEST-014' and status='closed' and internal_notes like '%Closure code: NFF%'),'no-fault closure is retained');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-TEST-015' and internal_notes like '%S$18500%'),'high-value approval scenario is retained');
select pg_temp.assert_true((select count(*)=15 from public.work_orders w join public.assets a on a.id=w.asset_id where w.work_order_number like 'WO-TEST-%' and a.lifecycle_status='active'),'all UAT Work Orders target active controlled Assets');
select pg_temp.assert_true((select count(*)=15 from public.activity_logs where action='uat_dataset_loaded'),'one loader audit event exists per Work Order');

-- Rerun is idempotent.
\ir ../../supabase/uat/008_work_order_uat_dataset.sql
select pg_temp.assert_true((select count(*)=15 from public.work_orders where work_order_number like 'WO-TEST-%') and (select count(*)=15 from public.activity_logs where action='uat_dataset_loaded'),'rerun creates neither Work Orders nor audit duplicates');

-- Five rejected invalid-input contracts, each isolated by a savepoint.
begin;
select id as actor_id from public.profiles where role='administrator' and is_active and deleted_at is null order by id limit 1 \gset
savepoint missing_assignment;
create temp table rejected_assignment(status text,assignment_id uuid,check(status not in ('assigned','in_progress','completed','reviewed','closed') or assignment_id is not null));
\set ON_ERROR_STOP off
insert into rejected_assignment values('assigned',null);
\set missing_assignment_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to missing_assignment;
select pg_temp.assert_true(:'missing_assignment_state'<>'00000','assigned status without assignee/relationship is rejected');

savepoint invalid_target;
\set ON_ERROR_STOP off
insert into public.work_orders(id,user_id,work_order_number,title,location,priority,status,source,asset_id,created_at,updated_at) values(gen_random_uuid(),:'actor_id','WO-REJECT-TARGET','Invalid target','UAT','medium','submitted','manual','ffffffff-ffff-4fff-8fff-ffffffffffff',now(),now());
\set invalid_target_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to invalid_target;
select pg_temp.assert_true(:'invalid_target_state'<>'00000','invalid target relationship is rejected');

savepoint duplicate_number;
\set ON_ERROR_STOP off
insert into public.work_orders(id,user_id,work_order_number,title,location,priority,status,source,created_at,updated_at) values(gen_random_uuid(),:'actor_id','WO-TEST-001','Duplicate number','UAT','medium','submitted','manual',now(),now());
\set duplicate_number_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to duplicate_number;
select pg_temp.assert_true(:'duplicate_number_state'='23505','duplicate Work Order number is rejected');

savepoint inactive_asset;
update public.assets set lifecycle_status='decommissioned',decommissioned_at=now() where id='08000000-0000-4000-8000-000000000315';
\set ON_ERROR_STOP off
insert into public.work_orders(id,user_id,work_order_number,title,location,priority,status,source,asset_id,created_at,updated_at) values(gen_random_uuid(),:'actor_id','WO-REJECT-ASSET','Inactive asset','UAT','medium','submitted','manual','08000000-0000-4000-8000-000000000315',now(),now());
\set inactive_asset_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to inactive_asset;
select pg_temp.assert_true(:'inactive_asset_state'<>'00000','decommissioned Asset target is rejected');

savepoint invalid_cost;
create temp table invalid_cost(value numeric check(value>=0));
\set ON_ERROR_STOP off
insert into invalid_cost values(-1);
\set invalid_cost_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to invalid_cost;
select pg_temp.assert_true(:'invalid_cost_state'='23514','negative cost is rejected by loader input contract');
rollback;

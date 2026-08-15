\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(condition boolean,message text)
returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'ASSERTION FAILED: %',message; end if; end $$;

select pg_temp.assert_true(to_regclass('public.maintenance_requirements') is not null,'requirements table exists');
select pg_temp.assert_true(to_regclass('public.maintenance_requirement_revisions') is not null,'revisions table exists');
select pg_temp.assert_true(to_regclass('public.pm_occurrences') is not null,'occurrences table exists');
select pg_temp.assert_true(to_regclass('public.pm_occurrence_deferrals') is not null,'deferrals table exists');
select pg_temp.assert_true((select count(*)=0 from public.maintenance_requirements),'migration creates no requirements');
select pg_temp.assert_true((select count(*)=0 from public.pm_occurrences),'migration creates no occurrences');
select pg_temp.assert_true((select count(*)=3 from public.work_orders),'existing Work Orders retained');
select pg_temp.assert_true((select count(*)=0 from public.work_orders where pm_occurrence_id is not null),'existing Work Orders not reclassified');
select pg_temp.assert_true((select not convalidated from pg_constraint where conname='work_orders_asset_id_fkey'),'0018 orphan Asset FK remains not valid');
select pg_temp.assert_true((select pg_get_constraintdef(oid) like '%pm_occurrence_id IS NOT NULL%' from pg_constraint where conname='work_orders_due_date_check'),'due constraint has narrow PM exception');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.maintenance_requirements','INSERT'),'direct requirement insert denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.pm_occurrences','UPDATE'),'direct occurrence update denied');
select pg_temp.assert_true(has_table_privilege('authenticated','public.pm_occurrences','SELECT'),'occurrence select granted');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.calculate_pm_due_date(uuid,integer)','EXECUTE'),'recurrence helper internal only');
select pg_temp.assert_true(not has_function_privilege('service_role','public.generate_pm_work_order(uuid)','EXECUTE'),'manual generator not exposed to service role');
select pg_temp.assert_true((select proconfig=array['search_path=pg_catalog'] from pg_proc where oid='public.generate_pm_work_order(uuid)'::regprocedure),'generator fixed search path');
select pg_temp.assert_true((select proconfig=array['search_path=pg_catalog'] from pg_proc where oid='public.materialize_pm_occurrences(date)'::regprocedure),'materializer fixed search path');

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select pg_temp.assert_true((public.create_pm_requirement('{}'::jsonb)->>'code')='ACCESS_DENIED','reviewer cannot create PM requirement');
reset role;

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select public.create_asset(jsonb_build_object('asset_tag','PUMP-PM-001','name','Primary Pump','asset_type','Pump','criticality','low','site','Central Site','location','Basement Plantroom')) as asset_result \gset
select (:'asset_result'::jsonb#>>'{asset,id}') as asset_id \gset
select pg_temp.assert_true(:'asset_id' is not null,'test Asset created');

select public.create_pm_requirement(jsonb_build_object(
  'asset_id',:'asset_id','title','Inspect primary pump','scope','Inspect seals, bearings and operating condition.',
  'maintenance_type','preventive','interval_value',1,'interval_unit','day',
  'effective_date',public.pm_business_date()-3,'first_due_date',public.pm_business_date()-3,
  'lead_time_days',2,'default_priority','medium','estimated_hours',1.5,
  'instructions','Follow approved isolation procedure.','evidence_guidance','Record an after photograph.','procedure_reference','SOP-PUMP-01'
)) as requirement_result \gset
select (:'requirement_result'::jsonb#>>'{requirement,id}') as requirement_id,
       (:'requirement_result'::jsonb#>>'{revision,id}') as revision_id \gset
select pg_temp.assert_true((:'requirement_result'::jsonb->>'ok')::boolean,'requirement creation succeeds');
select pg_temp.assert_true((select requirement_number ~ '^PM-[0-9]{4}-[0-9]{6}$' from public.maintenance_requirements where id=:'requirement_id'::uuid),'safe human requirement number');
select pg_temp.assert_true((select state='draft' and current_revision_id=:'revision_id'::uuid from public.maintenance_requirements where id=:'requirement_id'::uuid),'requirement starts draft with current revision');
select pg_temp.assert_true((select revision_number=1 from public.maintenance_requirement_revisions where id=:'revision_id'::uuid),'first revision numbered one');

create or replace function pg_temp.assert_revision_immutable(p_revision_id uuid) returns void language plpgsql as $$
begin
  begin update public.maintenance_requirement_revisions set title='Forbidden mutation' where id=p_revision_id; raise exception 'immutable update unexpectedly succeeded';
  exception when object_not_in_prerequisite_state then null; end;
end $$;
select pg_temp.assert_revision_immutable(:'revision_id'::uuid);

select public.create_pm_requirement(jsonb_build_object('asset_id',:'asset_id','title','Month-end PM','scope','Month end recurrence test','maintenance_type','preventive','interval_value',1,'interval_unit','month','effective_date','2024-01-01','first_due_date','2024-01-31')) as monthly_result \gset
select (:'monthly_result'::jsonb#>>'{revision,id}') as monthly_revision_id \gset
select pg_temp.assert_true(public.calculate_pm_due_date(:'monthly_revision_id'::uuid,1)='2024-01-31','monthly anchor preserved');
select pg_temp.assert_true(public.calculate_pm_due_date(:'monthly_revision_id'::uuid,2)='2024-02-29','January 31 reaches leap February end');
select pg_temp.assert_true(public.calculate_pm_due_date(:'monthly_revision_id'::uuid,3)='2024-03-31','monthly recurrence returns to anchor day');

select public.create_pm_requirement(jsonb_build_object('asset_id',:'asset_id','title','Thirty January PM','scope','Thirty January recurrence test','maintenance_type','preventive','interval_value',1,'interval_unit','month','effective_date','2023-01-01','first_due_date','2023-01-30')) as jan30_result \gset
select public.create_pm_requirement(jsonb_build_object('asset_id',:'asset_id','title','Twenty-nine January PM','scope','Twenty-nine January recurrence test','maintenance_type','preventive','interval_value',1,'interval_unit','month','effective_date','2023-01-01','first_due_date','2023-01-29')) as jan29_result \gset
select pg_temp.assert_true(public.calculate_pm_due_date((:'jan30_result'::jsonb#>>'{revision,id}')::uuid,2)='2023-02-28','January 30 month end');
select pg_temp.assert_true(public.calculate_pm_due_date((:'jan29_result'::jsonb#>>'{revision,id}')::uuid,2)='2023-02-28','January 29 month end');

select public.create_pm_requirement(jsonb_build_object('asset_id',:'asset_id','title','Leap annual PM','scope','Leap recurrence test','maintenance_type','inspection','interval_value',1,'interval_unit','year','effective_date','2024-01-01','first_due_date','2024-02-29')) as leap_result \gset
select pg_temp.assert_true(public.calculate_pm_due_date((:'leap_result'::jsonb#>>'{revision,id}')::uuid,2)='2025-02-28','leap annual non-leap year');
select pg_temp.assert_true(public.calculate_pm_due_date((:'leap_result'::jsonb#>>'{revision,id}')::uuid,5)='2028-02-29','leap annual returns on leap year');

select public.create_pm_requirement(jsonb_build_object('asset_id',:'asset_id','title','Weekly PM','scope','Weekly recurrence test','maintenance_type','preventive','interval_value',2,'interval_unit','week','effective_date','2026-01-01','first_due_date','2026-01-01')) as weekly_result \gset
select public.create_pm_requirement(jsonb_build_object('asset_id',:'asset_id','title','Quarterly PM','scope','Quarterly recurrence test','maintenance_type','preventive','interval_value',3,'interval_unit','month','effective_date','2026-01-01','first_due_date','2026-01-31')) as quarterly_result \gset
select pg_temp.assert_true(public.calculate_pm_due_date((:'weekly_result'::jsonb#>>'{revision,id}')::uuid,2)='2026-01-15','custom weekly interval');
select pg_temp.assert_true(public.calculate_pm_due_date((:'quarterly_result'::jsonb#>>'{revision,id}')::uuid,2)='2026-04-30','custom N-month interval');
select pg_temp.assert_true(public.pm_business_date()=(now() at time zone 'Asia/Singapore')::date,'Singapore business date deterministic');

select pg_temp.assert_true((public.revise_pm_requirement(:'requirement_id'::uuid,'{}'::jsonb,null)->>'code')='REASON_REQUIRED','revision reason required');
select public.revise_pm_requirement(:'requirement_id'::uuid,jsonb_build_object('title','Inspect primary pump revised','scope','Inspect seals, bearings, alignment and operating condition.','maintenance_type','preventive','interval_value',1,'interval_unit','day','effective_date',public.pm_business_date()-3,'first_due_date',public.pm_business_date()-3,'default_priority','medium'),'Approved scope refinement') as revised_result \gset
select pg_temp.assert_true((:'revised_result'::jsonb#>>'{revision,revision_number}')::integer=2,'revision number increments');
select pg_temp.assert_true((select count(*)=2 from public.maintenance_requirement_revisions where requirement_id=:'requirement_id'::uuid),'previous revision preserved');

select public.activate_pm_requirement(:'requirement_id'::uuid,'Approved PM activation') as activated_result \gset
select pg_temp.assert_true((:'activated_result'::jsonb#>>'{requirement,state}')='active','requirement activated');
select public.materialize_pm_occurrences(public.pm_business_date()+5) as materialized_result \gset
select pg_temp.assert_true((:'materialized_result'::jsonb->>'created_occurrences')::integer=9,'bounded daily occurrences materialized');
select public.materialize_pm_occurrences(public.pm_business_date()+5) as rerun_result \gset
select pg_temp.assert_true((:'rerun_result'::jsonb->>'created_occurrences')::integer=0,'materialization rerun idempotent');
select pg_temp.assert_true((select count(*)=count(distinct original_due_date) from public.pm_occurrences where requirement_id=:'requirement_id'::uuid),'occurrence due dates unique');
select pg_temp.assert_true((public.materialize_pm_occurrences(public.pm_business_date()+367)->>'code')='INVALID_HORIZON','unreasonable horizon rejected');

select id as occurrence_id from public.pm_occurrences where requirement_id=:'requirement_id'::uuid order by original_due_date limit 1 \gset
select public.generate_pm_work_order(:'occurrence_id'::uuid) as generated_result \gset
select (:'generated_result'::jsonb#>>'{work_order,id}') as pm_work_order_id \gset
select pg_temp.assert_true((:'generated_result'::jsonb->>'ok')::boolean,'PM Work Order generated');
select pg_temp.assert_true((select status='submitted' and source='preventive' and due_date<created_at::date from public.work_orders where id=:'pm_work_order_id'::uuid),'late-generated PM preserves historical due date and starts submitted');
select pg_temp.assert_true((select asset_id=:'asset_id'::uuid and location='Basement Plantroom' and site='Central Site' from public.work_orders where id=:'pm_work_order_id'::uuid),'Asset location snapshot inherited');
select pg_temp.assert_true((select priority='medium' from public.work_orders where id=:'pm_work_order_id'::uuid),'requirement priority independent from low Asset criticality');
select public.generate_pm_work_order(:'occurrence_id'::uuid) as retry_result \gset
select pg_temp.assert_true((:'retry_result'::jsonb#>>'{work_order,id}')=:'pm_work_order_id','generation retry returns existing Work Order');
select pg_temp.assert_true((select count(*)=1 from public.work_orders where pm_occurrence_id=:'occurrence_id'::uuid),'one occurrence has one Work Order');
select pg_temp.assert_true((select count(*)=1 from public.activity_logs where pm_occurrence_id=:'occurrence_id'::uuid and action='pm_work_order_generated'),'retry creates no duplicate generation audit');

select public.create_work_order(jsonb_build_object('title','Ordinary historical due test','location','Plantroom','due_date',(public.pm_business_date()-2)::text,'status','submitted')) as ordinary_result \gset
select pg_temp.assert_true((:'ordinary_result'::jsonb->>'ok')::boolean=false,'ordinary Work Order historical due date rejected');

select public.defer_pm_occurrence(:'occurrence_id'::uuid,public.pm_business_date()+7,'Access window changed') as deferred_result \gset
select pg_temp.assert_true((:'deferred_result'::jsonb#>>'{deferral,sequence_number}')::integer=1,'first deferral recorded');
select pg_temp.assert_true((select original_due_date<>current_due_date from public.pm_occurrences where id=:'occurrence_id'::uuid),'original due date preserved');
select pg_temp.assert_true((select due_date=public.pm_business_date()+7 from public.work_orders where id=:'pm_work_order_id'::uuid),'generated Work Order due date synchronized');
select public.defer_pm_occurrence(:'occurrence_id'::uuid,public.pm_business_date()+14,'Second access change') as deferred_again_result \gset
select pg_temp.assert_true((:'deferred_again_result'::jsonb#>>'{deferral,sequence_number}')::integer=2,'repeated deferral recorded');
select pg_temp.assert_true((select repeatedly_deferred from public.pm_occurrence_compliance where id=:'occurrence_id'::uuid),'repeated deferral derived');
update public.work_orders set status='in_progress',started_at=now() where id=:'pm_work_order_id'::uuid;
select pg_temp.assert_true((public.defer_pm_occurrence(:'occurrence_id'::uuid,public.pm_business_date()+21,'Too late')->>'code')='WORK_ALREADY_STARTED','deferral denied after start');

select id as cancel_occurrence_id from public.pm_occurrences where requirement_id=:'requirement_id'::uuid and generation_status='pending' order by original_due_date desc limit 1 \gset
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select pg_temp.assert_true((public.cancel_pm_occurrence(:'cancel_occurrence_id'::uuid,'Supervisor attempt')->>'code')='ACCESS_DENIED','Supervisor cannot cancel occurrence');
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select pg_temp.assert_true((public.cancel_pm_occurrence(:'cancel_occurrence_id'::uuid,'Requirement no longer applicable')->>'ok')::boolean,'Administrator cancels ungenerated occurrence');
select pg_temp.assert_true((select generation_status='cancelled' and cancellation_reason is not null from public.pm_occurrences where id=:'cancel_occurrence_id'::uuid),'cancellation history retained');

select public.create_asset(jsonb_build_object('asset_tag','PUMP-PM-002','name','Retired Pump','asset_type','Pump','criticality','critical','site','Central Site','location','Roof Plantroom')) as retired_asset_result \gset
select (:'retired_asset_result'::jsonb#>>'{asset,id}') as retired_asset_id \gset
select public.create_pm_requirement(jsonb_build_object('asset_id',:'retired_asset_id','title','Retired pump PM','scope','Test decommissioned Asset behavior','maintenance_type','preventive','interval_value',1,'interval_unit','day','effective_date',public.pm_business_date(),'first_due_date',public.pm_business_date())) as retired_req_result \gset
select (:'retired_req_result'::jsonb#>>'{requirement,id}') as retired_req_id \gset
select public.activate_pm_requirement(:'retired_req_id'::uuid,'Activate before retirement');
select public.materialize_pm_occurrences(public.pm_business_date());
select id as retired_occurrence_id from public.pm_occurrences where requirement_id=:'retired_req_id'::uuid \gset
select public.change_asset_status(:'retired_asset_id'::uuid,'decommissioned','Asset permanently retired');
select pg_temp.assert_true((public.generate_pm_work_order(:'retired_occurrence_id'::uuid)->>'code')='ASSET_DECOMMISSIONED','decommissioned Asset generation denied');
select pg_temp.assert_true((select generation_status='generation_failed' and last_generation_error_code='ASSET_DECOMMISSIONED' from public.pm_occurrences where id=:'retired_occurrence_id'::uuid),'generation failure persisted safely');
select pg_temp.assert_true((select count(*)>0 and bool_and(delivery_status='pending') from public.notification_outbox where pm_occurrence_id=:'retired_occurrence_id'::uuid),'generation failure outbox is queued only');
select count(*) as retired_failure_audits from public.activity_logs where pm_occurrence_id=:'retired_occurrence_id'::uuid and action='pm_generation_failed' \gset
select count(*) as retired_failure_outbox from public.notification_outbox where pm_occurrence_id=:'retired_occurrence_id'::uuid \gset
select pg_temp.assert_true((public.generate_pm_work_order(:'retired_occurrence_id'::uuid)->>'code')='ASSET_DECOMMISSIONED','committed generation failure can be retried safely');
select pg_temp.assert_true((select generation_attempts=2 from public.pm_occurrences where id=:'retired_occurrence_id'::uuid),'failure retry count retained');
select pg_temp.assert_true((select count(*)=:'retired_failure_audits'::integer from public.activity_logs where pm_occurrence_id=:'retired_occurrence_id'::uuid and action='pm_generation_failed'),'same failure retry creates no duplicate audit');
select pg_temp.assert_true((select count(*)=:'retired_failure_outbox'::integer from public.notification_outbox where pm_occurrence_id=:'retired_occurrence_id'::uuid),'same failure retry creates no duplicate outbox');

select public.create_asset(jsonb_build_object('asset_tag','PUMP-PM-003','name','Offline Pump','asset_type','Pump','criticality','high','site','Central Site','location','Annex Plantroom','lifecycle_status','out_of_service')) as offline_asset_result \gset
select (:'offline_asset_result'::jsonb#>>'{asset,id}') as offline_asset_id \gset
select public.create_pm_requirement(jsonb_build_object('asset_id',:'offline_asset_id','title','Offline pump PM','scope','Out-of-service obligations remain explicit','maintenance_type','inspection','interval_value',1,'interval_unit','day','effective_date',public.pm_business_date(),'first_due_date',public.pm_business_date())) as offline_req_result \gset
select (:'offline_req_result'::jsonb#>>'{requirement,id}') as offline_req_id \gset
select public.activate_pm_requirement(:'offline_req_id'::uuid,'Explicitly maintain while offline');
select public.materialize_pm_occurrences(public.pm_business_date());
select pg_temp.assert_true((select count(*)=1 from public.pm_occurrences where requirement_id=:'offline_req_id'::uuid),'out-of-service obligation not silently cancelled');

update public.work_orders set status='reviewed',reviewed_at=(current_due_date::timestamp at time zone 'Asia/Singapore')
from public.pm_occurrences where work_orders.pm_occurrence_id=pm_occurrences.id and work_orders.id=:'pm_work_order_id'::uuid;
select pg_temp.assert_true((select compliance_state='completed_on_time' from public.pm_occurrence_compliance where id=:'occurrence_id'::uuid),'accepted review derives completed on time');

select pg_temp.assert_true((select count(*)>0 from public.activity_logs where maintenance_requirement_id=:'requirement_id'::uuid and action='pm_requirement_created'),'requirement audit recorded');
select pg_temp.assert_true((select count(*)>=2 from public.activity_logs where pm_occurrence_id=:'occurrence_id'::uuid and action='pm_occurrence_deferred'),'deferral audit history recorded');

create or replace function pg_temp.fail_pm_audit() returns trigger language plpgsql as $$ begin if new.action='pm_requirement_created' then raise exception 'forced audit failure'; end if; return new; end $$;
create trigger fail_pm_audit before insert on public.activity_logs for each row execute function pg_temp.fail_pm_audit();
select count(*) as requirement_count_before_failure from public.maintenance_requirements \gset
select public.create_pm_requirement(jsonb_build_object('asset_id',:'asset_id','title','Audit rollback PM','scope','This creation must roll back','maintenance_type','preventive','interval_value',1,'interval_unit','year','effective_date',public.pm_business_date(),'first_due_date',public.pm_business_date())) as failed_audit_result \gset
select pg_temp.assert_true((:'failed_audit_result'::jsonb->>'ok')::boolean=false,'forced audit failure returns safe error');
select pg_temp.assert_true((select count(*)=:'requirement_count_before_failure'::integer from public.maintenance_requirements),'failed audit rolls back requirement creation');
drop trigger fail_pm_audit on public.activity_logs;

select pg_temp.assert_true((select count(*)=3 from public.work_orders where pm_occurrence_id is null and id in ('30000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000003')),'historical Work Orders preserved');
select '0019 Preventive Maintenance foundation tests passed' as result;

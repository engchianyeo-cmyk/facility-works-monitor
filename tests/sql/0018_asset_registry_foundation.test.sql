\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(value boolean,message text)
returns void language plpgsql as $$ begin if value is not true then raise exception 'ASSERTION FAILED: %',message; end if; end $$;

select pg_temp.assert_true(to_regclass('public.asset_systems') is not null,'asset_systems exists');
select pg_temp.assert_true(to_regclass('public.assets') is not null,'assets exists');
select pg_temp.assert_true((select not convalidated from pg_constraint where conname='work_orders_asset_id_fkey'),'Work Order Asset FK remains NOT VALID');
select pg_temp.assert_true((select asset_id='70000000-0000-4000-8000-000000000099'::uuid from public.work_orders where id='30000000-0000-4000-8000-000000000001'),'existing orphan UUID retained');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.assets','INSERT'),'authenticated direct Asset insert denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.assets','UPDATE'),'authenticated direct Asset update denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.assets','DELETE'),'authenticated direct Asset delete denied');
select pg_temp.assert_true(has_table_privilege('authenticated','public.assets','SELECT'),'authenticated Asset read granted');
select pg_temp.assert_true(to_regprocedure('public.delete_asset(uuid)') is null,'no hard-delete Asset RPC');

select pg_temp.assert_true((select bool_and(p.prosecdef and p.proconfig @> array['search_path=pg_catalog']) from pg_proc p where p.oid in (
  'public.create_asset_system(jsonb)'::regprocedure,'public.update_asset_system(uuid,jsonb,text)'::regprocedure,
  'public.create_asset(jsonb)'::regprocedure,'public.update_asset_details(uuid,jsonb,text)'::regprocedure,
  'public.change_asset_criticality(uuid,text,text)'::regprocedure,'public.change_asset_tag(uuid,text,text)'::regprocedure,
  'public.change_asset_status(uuid,text,text)'::regprocedure,'public.set_work_order_asset(uuid,uuid,text)'::regprocedure,
  'public.set_incident_asset(uuid,uuid,text)'::regprocedure,'public.create_incident_with_asset(jsonb)'::regprocedure
)),'all public Asset RPCs are SECURITY DEFINER with fixed search_path');
select pg_temp.assert_true((select bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE')) from pg_proc p where p.oid in (
  'public.create_asset_system(jsonb)'::regprocedure,'public.update_asset_system(uuid,jsonb,text)'::regprocedure,
  'public.create_asset(jsonb)'::regprocedure,'public.update_asset_details(uuid,jsonb,text)'::regprocedure,
  'public.change_asset_criticality(uuid,text,text)'::regprocedure,'public.change_asset_tag(uuid,text,text)'::regprocedure,
  'public.change_asset_status(uuid,text,text)'::regprocedure,'public.set_work_order_asset(uuid,uuid,text)'::regprocedure,
  'public.set_incident_asset(uuid,uuid,text)'::regprocedure,'public.create_incident_with_asset(jsonb)'::regprocedure
)),'Asset RPC grants are least privilege');

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select public.create_asset_system(jsonb_build_object('system_code','HVAC','name','HVAC','site','Main')) as result \gset unauthorized_system_
select pg_temp.assert_true(:'unauthorized_system_result'::jsonb->>'code'='ACCESS_DENIED','non-Administrator cannot configure Systems');
select public.create_asset(jsonb_build_object('asset_tag','BAD-1','name','Denied','asset_type','Pump','site','Main','location','Plant')) as result \gset unauthorized_asset_
select pg_temp.assert_true(:'unauthorized_asset_result'::jsonb->>'code'='ACCESS_DENIED','unauthorized Asset creation denied');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select public.create_asset_system(jsonb_build_object('system_code',' hvac ','name','Mechanical Ventilation','site','Main Site')) as result \gset system_
select pg_temp.assert_true((:'system_result'::jsonb#>>'{asset_system,system_code}')='HVAC','System code trimmed and uppercased');
select (:'system_result'::jsonb#>>'{asset_system,id}') as system_id \gset
select public.create_asset_system(jsonb_build_object('system_code','hvac','name','Duplicate','site','Main Site')) as result \gset duplicate_system_
select pg_temp.assert_true(:'duplicate_system_result'::jsonb->>'code'='DUPLICATE_SYSTEM_CODE','System code uniqueness is case insensitive');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select public.create_asset(jsonb_build_object('asset_tag',' ahu-l03-001 ','name','Level 3 AHU','asset_type','Air Handling Unit','criticality','critical','site','Main Site','location','Level 3 Plant Room','system_id',:'system_id')) as result \gset asset_one_
select pg_temp.assert_true((:'asset_one_result'::jsonb#>>'{asset,asset_tag}')='AHU-L03-001','Asset tag normalized');
select pg_temp.assert_true((:'asset_one_result'::jsonb#>>'{asset,criticality}')='critical','criticality stored');
select (:'asset_one_result'::jsonb#>>'{asset,id}') as asset_one_id \gset
select public.create_asset(jsonb_build_object('asset_tag','ahu-l03-001','name','Duplicate','asset_type','AHU','site','Main Site','location','Plant')) as result \gset duplicate_asset_
select pg_temp.assert_true(:'duplicate_asset_result'::jsonb->>'code'='DUPLICATE_ASSET_TAG','Asset tag uniqueness is case insensitive');
select public.create_asset(jsonb_build_object('asset_tag','BAD-CRIT','name','Bad','asset_type','Pump','criticality','urgent','site','Main','location','Plant')) as result \gset invalid_criticality_
select pg_temp.assert_true(:'invalid_criticality_result'::jsonb->>'code'='VALIDATION_ERROR','invalid criticality denied');
select public.create_asset(jsonb_build_object('asset_tag','BAD-STATUS','name','Bad','asset_type','Pump','lifecycle_status','healthy','site','Main','location','Plant')) as result \gset invalid_status_
select pg_temp.assert_true(:'invalid_status_result'::jsonb->>'code'='VALIDATION_ERROR','invalid lifecycle status denied');

select public.create_asset(jsonb_build_object('asset_tag','PUMP-CHW-002','name','CHW Pump 2','asset_type','Pump','criticality','medium','site','Main Site','location','Basement Plant','system_id',:'system_id')) as result \gset asset_two_
select (:'asset_two_result'::jsonb#>>'{asset,id}') as asset_two_id \gset
select public.change_asset_criticality(:'asset_one_id'::uuid,'high','') as result \gset no_criticality_reason_
select pg_temp.assert_true(:'no_criticality_reason_result'::jsonb->>'code'='REASON_REQUIRED','criticality reason required');
select public.change_asset_criticality(:'asset_one_id'::uuid,'high','Risk assessment updated') as result \gset changed_criticality_
select pg_temp.assert_true((:'changed_criticality_result'::jsonb#>>'{asset,criticality}')='high','Supervisor changes criticality with reason');
select public.change_asset_tag(:'asset_one_id'::uuid,'AHU-CORRECTED','Reason') as result \gset supervisor_tag_
select pg_temp.assert_true(:'supervisor_tag_result'::jsonb->>'code'='ACCESS_DENIED','Supervisor cannot correct tag');
select public.change_asset_status(:'asset_one_id'::uuid,'out_of_service','') as result \gset no_status_reason_
select pg_temp.assert_true(:'no_status_reason_result'::jsonb->>'code'='REASON_REQUIRED','status reason required');
select public.change_asset_status(:'asset_one_id'::uuid,'out_of_service','Isolation for inspection') as result \gset out_of_service_
select pg_temp.assert_true((:'out_of_service_result'::jsonb#>>'{asset,lifecycle_status}')='out_of_service','Supervisor marks Asset out of service');
select public.change_asset_status(:'asset_one_id'::uuid,'active','Inspection passed') as result \gset reactivated_
select pg_temp.assert_true((:'reactivated_result'::jsonb#>>'{asset,lifecycle_status}')='active','Supervisor reactivates Asset');
select public.change_asset_status(:'asset_one_id'::uuid,'decommissioned','Retired') as result \gset supervisor_decommission_
select pg_temp.assert_true(:'supervisor_decommission_result'::jsonb->>'code'='ACCESS_DENIED','Supervisor cannot decommission');

select public.create_work_order(jsonb_build_object('title','Asset link validation','location','Plant','status','submitted','source','reactive')) as result \gset work_
select (:'work_result'::jsonb#>>'{work_order,id}') as work_id \gset
select public.set_work_order_asset(:'work_id'::uuid,:'asset_one_id'::uuid,null) as result \gset work_link_
select pg_temp.assert_true((:'work_link_result'::jsonb#>>'{work_order,asset_id}')=:'asset_one_id','Work Order linked to Asset');
select public.set_work_order_asset(:'work_id'::uuid,:'asset_two_id'::uuid,null) as result \gset work_change_no_reason_
select pg_temp.assert_true(:'work_change_no_reason_result'::jsonb->>'code'='REASON_REQUIRED','Work Order Asset change requires reason');
select public.set_work_order_asset(:'work_id'::uuid,:'asset_two_id'::uuid,'Wrong equipment selected') as result \gset work_change_
select pg_temp.assert_true((:'work_change_result'::jsonb#>>'{work_order,asset_id}')=:'asset_two_id','Work Order Asset changed');
select public.set_work_order_asset(:'work_id'::uuid,null,'General location work') as result \gset work_unlink_
select pg_temp.assert_true((:'work_unlink_result'::jsonb#>>'{work_order,asset_id}') is null,'Work Order Asset unlinked');
select pg_temp.assert_true((select priority='medium' from public.work_orders where id=:'work_id'::uuid),'Asset criticality does not mutate Work Order priority');
select public.set_work_order_asset(:'work_id'::uuid,'70000000-0000-4000-8000-000000000098','Invalid') as result \gset invalid_work_asset_
select pg_temp.assert_true(:'invalid_work_asset_result'::jsonb->>'code'='INVALID_REFERENCE','new invalid Work Order Asset rejected');

select public.create_incident_with_asset(jsonb_build_object('incident_type','electrical_failure','severity','high','location','Switch Room','description','Loss of supply','asset_id',:'asset_two_id')) as result \gset incident_created_
select pg_temp.assert_true((:'incident_created_result'::jsonb#>>'{incident,asset_id}')=:'asset_two_id','Incident created with optional primary Asset');
select (:'incident_created_result'::jsonb#>>'{incident,id}') as incident_id \gset
select public.set_incident_asset(:'incident_id'::uuid,:'asset_one_id'::uuid,'Affected equipment corrected') as result \gset incident_change_
select pg_temp.assert_true((:'incident_change_result'::jsonb#>>'{incident,asset_id}')=:'asset_one_id','Incident Asset changed');
select public.set_incident_asset(:'incident_id'::uuid,null,'No primary equipment') as result \gset incident_unlink_
select pg_temp.assert_true((:'incident_unlink_result'::jsonb#>>'{incident,asset_id}') is null,'Incident Asset unlinked');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select public.change_asset_tag(:'asset_two_id'::uuid,' pump-chw-002a ','Tag corrected after survey') as result \gset corrected_tag_
select pg_temp.assert_true((:'corrected_tag_result'::jsonb#>>'{asset,asset_tag}')='PUMP-CHW-002A','Administrator corrects tag with audit reason');
select public.set_work_order_asset(:'work_id'::uuid,:'asset_two_id'::uuid,null) as result \gset historical_link_
select public.change_asset_status(:'asset_two_id'::uuid,'decommissioned','Asset permanently retired') as result \gset decommissioned_
select pg_temp.assert_true((:'decommissioned_result'::jsonb#>>'{asset,lifecycle_status}')='decommissioned','Administrator decommissions Asset');
select pg_temp.assert_true((select asset_id=:'asset_two_id'::uuid from public.work_orders where id=:'work_id'::uuid),'historical Work Order link retained after decommission');
select public.change_asset_status(:'asset_two_id'::uuid,'active','Invalid reactivation') as result \gset reactivate_decommissioned_
select pg_temp.assert_true(:'reactivate_decommissioned_result'::jsonb->>'code'='TERMINAL_IMMUTABLE','decommissioned Asset cannot reactivate');

reset role;
create or replace function pg_temp.invalid_asset_link_rejected(p_work_order_id uuid)
returns boolean language plpgsql as $$
begin
  begin
    update public.work_orders set asset_id='70000000-0000-4000-8000-000000000098' where id=p_work_order_id;
    return false;
  exception when foreign_key_violation then return true; end;
end $$;
select pg_temp.assert_true(pg_temp.invalid_asset_link_rejected(:'work_id'::uuid),'new invalid direct Asset link rejected');

create or replace function pg_temp.fail_asset_audit() returns trigger language plpgsql as $$ begin if new.action='asset_created' then raise exception 'forced audit failure'; end if; return new; end $$;
create trigger force_asset_audit before insert on public.activity_logs for each row execute function pg_temp.fail_asset_audit();
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
select public.create_asset(jsonb_build_object('asset_tag','ATOMIC-FAIL','name','Rollback','asset_type','Pump','site','Main','location','Plant')) as result \gset atomic_
select pg_temp.assert_true(:'atomic_result'::jsonb->>'code'='INTERNAL_ERROR','audit failure reported safely');
reset role;
select pg_temp.assert_true(not exists(select 1 from public.assets where asset_tag='ATOMIC-FAIL'),'audit failure rolls back Asset creation');
drop trigger force_asset_audit on public.activity_logs;

select pg_temp.assert_true(exists(select 1 from public.activity_logs where asset_id=:'asset_one_id'::uuid and action='asset_created'),'Asset creation audit exists');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where asset_id=:'asset_one_id'::uuid and action='asset_criticality_changed'),'criticality audit exists');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where work_order_id=:'work_id'::uuid and action='work_order_asset_changed'),'Work Order Asset-change audit exists');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where incident_id=:'incident_id'::uuid and action='incident_asset_unlinked'),'Incident Asset-unlink audit exists');
select pg_temp.assert_true((select count(*)>=3 from public.work_orders),'existing Work Orders retained');
select pg_temp.assert_true((select asset_id='70000000-0000-4000-8000-000000000099'::uuid from public.work_orders where id='30000000-0000-4000-8000-000000000001'),'unknown historical Asset remains unchanged');

select '0018 Asset Registry foundation tests passed' as result;

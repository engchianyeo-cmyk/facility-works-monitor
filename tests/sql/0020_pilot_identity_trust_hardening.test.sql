\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition,false) then raise exception 'ASSERTION FAILED: %',message; end if;
end $$;

select pg_temp.assert_true(
  not has_function_privilege('anon','public.list_public_work_orders()','EXECUTE'),
  'anonymous public Work Order RPC execution is denied'
);
select pg_temp.assert_true(
  not has_table_privilege('anon','public.work_orders','SELECT')
  and not has_table_privilege('anon','public.assets','SELECT')
  and not has_table_privilege('anon','public.incidents','SELECT')
  and not has_table_privilege('anon','public.pm_occurrences','SELECT')
  and not has_table_privilege('anon','public.profiles','SELECT'),
  'anonymous users cannot read operational tables'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated','public.record_incident_notification_result(uuid,text,boolean,text,text)','EXECUTE'),
  'browser-authenticated notification result writes are denied'
);
select pg_temp.assert_true(
  has_function_privilege('service_role','public.record_incident_notification_result(uuid,text,boolean,text,text)','EXECUTE'),
  'notification result write is reserved for a future trusted provider worker'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated','public.admin_record_permanent_delete_result(uuid,uuid,boolean,text)','EXECUTE')
  and has_function_privilege('service_role','public.admin_record_permanent_delete_result(uuid,uuid,boolean,text)','EXECUTE'),
  'external Auth deletion result audit is service-only'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated','public.complete_password_change_trusted(uuid)','EXECUTE')
  and has_function_privilege('service_role','public.complete_password_change_trusted(uuid)','EXECUTE'),
  'password readiness reconciliation is service-only'
);

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select public.create_incident(jsonb_build_object(
  'incident_type','fire',
  'severity','emergency',
  'location','Trusted notification boundary test',
  'description','Local SQL assertion only'
)) as result \gset trusted_notification_incident_
reset role;
set role service_role;
select public.record_incident_notification_result(
  (:'trusted_notification_incident_result'::jsonb#>>'{incident,id}')::uuid,
  'sms',
  true,
  'DELIVERED',
  'local-test-provider'
) as result \gset trusted_notification_result_
reset role;
select pg_temp.assert_true(
  (:'trusted_notification_result_result'::jsonb->>'ok')::boolean
  and exists(
    select 1 from public.notification_outbox
    where incident_id=(:'trusted_notification_incident_result'::jsonb#>>'{incident,id}')::uuid
      and channel='sms' and delivery_status='sent' and result_code='DELIVERED'
  )
  and exists(
    select 1 from public.activity_logs
    where incident_id=(:'trusted_notification_incident_result'::jsonb#>>'{incident,id}')::uuid
      and action='incident_notification_result' and actor='Trusted notification worker'
  ),
  'service-only worker boundary records a genuine provider result'
);

insert into auth.users(id,email,raw_user_meta_data) values(
  '10000000-0000-4000-8000-000000000099',
  'external-signup@example.test',
  '{"public_signup_role":"administrator","display_name":"External signup"}'::jsonb
);
select pg_temp.assert_true(
  (select is_active=false and password_change_required=true and role='reviewer'
   from public.profiles where id='10000000-0000-4000-8000-000000000099'),
  'external self-signup is quarantined and cannot choose a privileged role'
);

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000099',false);
select pg_temp.assert_true(public.current_user_role() is null,'quarantine account has no operational role');
select pg_temp.assert_true((select count(*)=0 from public.work_orders),'quarantine account cannot read operational Work Orders');
reset role;

-- Inactive, archived, and missing-profile Auth identities cannot mutate.
set fmworks.profile_admin_rpc='on';
update public.profiles set is_active=false
where id='10000000-0000-4000-8000-000000000003';
reset fmworks.profile_admin_rpc;
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select pg_temp.assert_true(
  (public.create_work_order('{}'::jsonb)->>'code')='ACCESS_DENIED',
  'inactive profile cannot perform an operational mutation'
);
reset role;
set fmworks.profile_admin_rpc='on';
update public.profiles set deleted_at=pg_catalog.now()
where id='10000000-0000-4000-8000-000000000003';
reset fmworks.profile_admin_rpc;
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select pg_temp.assert_true(
  (public.create_work_order('{}'::jsonb)->>'code')='ACCESS_DENIED',
  'archived profile cannot perform an operational mutation'
);
reset role;
set fmworks.profile_admin_rpc='on';
update public.profiles set is_active=true,deleted_at=null
where id='10000000-0000-4000-8000-000000000003';
reset fmworks.profile_admin_rpc;

insert into auth.users(id,email,raw_user_meta_data) values(
  '10000000-0000-4000-8000-000000000098',
  'missing-profile@example.test',
  '{}'::jsonb
);
delete from public.profiles where id='10000000-0000-4000-8000-000000000098';
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000098',false);
select pg_temp.assert_true(
  (public.create_work_order('{}'::jsonb)->>'code')='ACCESS_DENIED',
  'Auth identity without a canonical profile cannot mutate operational data'
);
reset role;

-- A password-pending active user still fails closed at the database boundary.
set fmworks.profile_admin_rpc='on';
update public.profiles set password_change_required=true
where id='10000000-0000-4000-8000-000000000003';
reset fmworks.profile_admin_rpc;
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select pg_temp.assert_true(public.current_user_role() is null,'password-pending user has no operational role');
select pg_temp.assert_true((select count(*)=0 from public.work_orders),'password-pending owner cannot use an owner RLS path');
select pg_temp.assert_true(
  (public.register_evidence_item('work_order','30000000-0000-4000-8000-000000000001','proof.jpg','image/jpeg',10,'other',null,'evidence/work-order/invalid') ->> 'code')='ACCESS_DENIED',
  'password-pending user cannot call a legacy evidence SECURITY DEFINER path'
);
select count(*) as value from public.emergency_response_roster \gset pending_roster_before_
select public.upsert_emergency_roster(null,jsonb_build_object(
  'profile_id','10000000-0000-4000-8000-000000000004',
  'escalation_order',77,
  'active',true
)) as result \gset pending_roster_
select pg_temp.assert_true(
  coalesce((:'pending_roster_result'::jsonb->>'ok')::boolean,false)=false
  and (select count(*)=:'pending_roster_before_value'::integer from public.emergency_response_roster),
  'table readiness trigger blocks a legacy null-role mutation path'
);
reset role;
set fmworks.profile_admin_rpc='on';
update public.profiles set password_change_required=false
where id='10000000-0000-4000-8000-000000000003';
reset fmworks.profile_admin_rpc;

-- Direct profile authorization changes are refused, even to an authenticated Administrator.
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
do $test$
begin
  begin
    update public.profiles set role='approver'
    where id='10000000-0000-4000-8000-000000000003';
    raise exception 'direct profile role update unexpectedly succeeded';
  exception when others then
    if sqlerrm='direct profile role update unexpectedly succeeded' then raise; end if;
  end;
end $test$;

select public.admin_update_profile(
  '10000000-0000-4000-8000-000000000003',
  jsonb_build_object(
    'display_name','Reviewer promoted',
    'department_id',(select department_id from public.profiles where id='10000000-0000-4000-8000-000000000001'),
    'role','initiator',
    'is_active',true
  )
);
select pg_temp.assert_true(
  (select role='initiator' from public.profiles where id='10000000-0000-4000-8000-000000000003')
  and exists(select 1 from public.activity_logs where action='user_admin_profile_updated' and note like '%10000000-0000-4000-8000-000000000003%'),
  'Administrator profile mutation and audit commit together'
);

select public.admin_prepare_permanent_profile_deletion(
  '10000000-0000-4000-8000-000000000003',
  'reviewer@example.test'
);
select pg_temp.assert_true(
  exists(select 1 from public.activity_logs where action='user_admin_permanent_deletion_requested' and note like '%10000000-0000-4000-8000-000000000003%')
  and not exists(select 1 from public.activity_logs where action='user_admin_permanent_deletion_completed' and note like '%10000000-0000-4000-8000-000000000003%'),
  'permanent deletion preflight records only a pending external Auth action'
);

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select public.create_work_order(jsonb_build_object(
  'title','Initiator approval denial',
  'location','Test location',
  'priority','medium',
  'status','submitted'
)) as result \gset initiator_work_
select public.transition_work_order(
  (:'initiator_work_result'::jsonb#>>'{work_order,id}')::uuid,
  'approve',
  '{}'::jsonb
) as result \gset initiator_approve_
select pg_temp.assert_true(
  :'initiator_approve_result'::jsonb->>'code'='ACCESS_DENIED',
  'Initiator cannot approve a Work Order'
);

reset role;

set role service_role;
select public.admin_record_permanent_delete_result(
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000003',
  false,
  'AUTH_DELETE_FAILED'
);
reset role;
select pg_temp.assert_true(
  exists(select 1 from public.activity_logs where action='user_admin_permanent_deletion_failed' and note like '%AUTH_DELETE_FAILED%'),
  'trusted boundary records the external Auth deletion result only after the attempt'
);

create or replace function pg_temp.reject_admin_audit()
returns trigger language plpgsql as $$
begin
  if new.action='user_admin_profile_updated' then raise exception 'forced audit failure'; end if;
  return new;
end $$;
create trigger reject_admin_audit before insert on public.activity_logs
for each row execute function pg_temp.reject_admin_audit();
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
do $test$
begin
  begin
    perform public.admin_update_profile(
      '10000000-0000-4000-8000-000000000003',
      jsonb_build_object('display_name','Must roll back','department_id',(select department_id from public.profiles where id='10000000-0000-4000-8000-000000000001'),'role','reviewer','is_active',true)
    );
  exception when others then
    null;
  end;
end $test$;
select pg_temp.assert_true(
  (select role='initiator' and display_name='Reviewer promoted' from public.profiles where id='10000000-0000-4000-8000-000000000003'),
  'audit failure rolls the profile mutation back'
);
reset role;
drop trigger reject_admin_audit on public.activity_logs;

-- Service-only reconciliation unlocks an active password-pending account.
set fmworks.profile_admin_rpc='on';
update public.profiles set password_change_required=true
where id='10000000-0000-4000-8000-000000000003';
reset fmworks.profile_admin_rpc;
set role service_role;
select public.complete_password_change_trusted('10000000-0000-4000-8000-000000000003');
reset role;
select pg_temp.assert_true(
  (select password_change_required=false from public.profiles where id='10000000-0000-4000-8000-000000000003'),
  'trusted password reconciliation unlocks the profile'
);

-- Existing PM authorization remains role authoritative after hardening.
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',false);
select pg_temp.assert_true(
  (public.create_pm_requirement('{}'::jsonb)->>'code')='ACCESS_DENIED',
  'Technician cannot mutate PM requirements'
);
reset role;

select 'WP-PILOT-001 SQL assertions passed' as result;

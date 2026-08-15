\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(value boolean,message text)
returns void language plpgsql as $$ begin if value is not true then raise exception 'ASSERTION FAILED: %',message; end if; end $$;

select pg_temp.assert_true(to_regclass('public.incidents') is not null,'incidents table exists');
select pg_temp.assert_true(to_regclass('public.emergency_response_roster') is not null,'roster table exists');
select pg_temp.assert_true(to_regprocedure('public.create_incident(jsonb)') is not null,'create incident RPC exists');
select pg_temp.assert_true(to_regprocedure('public.assign_incident(uuid,text,uuid)') is not null,'assign incident RPC exists');
select pg_temp.assert_true(to_regprocedure('public.transition_incident(uuid,text)') is not null,'transition incident RPC exists');
select pg_temp.assert_true(to_regprocedure('public.link_work_order_to_incident(uuid,uuid)') is not null,'link work order RPC exists');
select pg_temp.assert_true(not has_function_privilege('anon','public.create_incident(jsonb)','EXECUTE'),'anon create denied');
select pg_temp.assert_true(has_function_privilege('authenticated','public.create_incident(jsonb)','EXECUTE'),'authenticated create granted');
select pg_temp.assert_true(not has_function_privilege('service_role','public.create_incident(jsonb)','EXECUTE'),'service role create denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.incidents','INSERT'),'direct incident insert denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.incidents','UPDATE'),'direct incident update denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.notification_outbox','INSERT'),'direct outbox insert denied');

insert into auth.users(id,email) values
 ('10000000-0000-4000-8000-000000000007','other-tech@example.test');
set fmworks.profile_admin_rpc='on';
update public.profiles set
 display_name='Other Technician', department='Facilities', role='technician',
 is_active=true, password_change_required=false
where id='10000000-0000-4000-8000-000000000007';
reset fmworks.profile_admin_rpc;

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
insert into public.emergency_response_roster(profile_id,created_by,escalation_order)
values('10000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001',1);
select pg_temp.assert_true((select created_by=auth.uid() from public.emergency_response_roster limit 1),'created_by cannot be spoofed');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select public.create_incident(jsonb_build_object('incident_type','lift_entrapment','severity','emergency','location','Level 3 Lift Lobby','description','Passenger trapped')) as result \gset first_
select pg_temp.assert_true((:'first_result'::jsonb->>'ok')::boolean,'incident created');
select (:'first_result'::jsonb#>>'{incident,id}') as incident_id \gset
select pg_temp.assert_true(:'first_result'::jsonb->>'assignment_state'='ASSIGNED','unique roster auto-assigned');
select pg_temp.assert_true((:'first_result'::jsonb#>>'{incident,assigned_technician_id}')='10000000-0000-4000-8000-000000000004','correct technician assigned');
select pg_temp.assert_true((:'first_result'::jsonb#>>'{incident,incident_number}') ~ '^INC-[0-9]{4}-[0-9]{6}$','incident number formatted');
select pg_temp.assert_true((select acknowledgement_deadline-reported_at=interval '5 minutes' from public.incidents where id=:'incident_id'::uuid),'five minute deadline persisted');
reset role;

select pg_temp.assert_true((select count(*)=6 from public.notification_outbox where incident_id=:'incident_id'::uuid),'admin supervisor and responder receive two channels each');
select pg_temp.assert_true((select count(distinct channel)=2 from public.notification_outbox where incident_id=:'incident_id'::uuid),'SMS and WhatsApp queued independently');
select pg_temp.assert_true((select count(*)=1 from public.activity_logs where incident_id=:'incident_id'::uuid and action='incident_created'),'creation audited');

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
update public.emergency_response_roster set sms_enabled=false where profile_id='10000000-0000-4000-8000-000000000004';
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select public.create_incident(jsonb_build_object('incident_type','major_water_leak','location','Roof','description','Major leak')) as result \gset preference_
reset role;
select pg_temp.assert_true((select count(*)=5 from public.notification_outbox where incident_id=(:'preference_result'::jsonb#>>'{incident,id}')::uuid),'responder channel preferences applied while mandatory recipients retain both channels');
select pg_temp.assert_true(not exists(select 1 from public.notification_outbox where incident_id=(:'preference_result'::jsonb#>>'{incident,id}')::uuid and recipient_profile_id='10000000-0000-4000-8000-000000000004' and channel='sms'),'disabled responder SMS not queued');

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000007',false);
select public.transition_incident(:'incident_id'::uuid,'acknowledge') as result \gset denied_
select pg_temp.assert_true(:'denied_result'::jsonb->>'code'='ACCESS_DENIED','other technician acknowledgement denied');
select pg_temp.assert_true(not exists(select 1 from public.incidents where id=:'incident_id'::uuid),'RLS hides another technician incident');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',false);
select public.transition_incident(:'incident_id'::uuid,'acknowledge') as result \gset ack_
select pg_temp.assert_true((:'ack_result'::jsonb->>'ok')::boolean,'assigned technician acknowledged');
select public.transition_incident(:'incident_id'::uuid,'mobilise') as result \gset mobilise_
select public.transition_incident(:'incident_id'::uuid,'arrive') as result \gset arrive_
select public.transition_incident(:'incident_id'::uuid,'start_rescue') as result \gset rescue_
select public.transition_incident(:'incident_id'::uuid,'make_safe') as result \gset safe_
select public.transition_incident(:'incident_id'::uuid,'start_recovery') as result \gset recovery_
select pg_temp.assert_true((:'recovery_result'::jsonb#>>'{incident,status}')='recovery','responder completed response lifecycle to recovery');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select public.transition_incident(:'incident_id'::uuid,'close') as result \gset close_
select pg_temp.assert_true((:'close_result'::jsonb#>>'{incident,status}')='closed','administrator closed incident');
select public.link_work_order_to_incident('30000000-0000-4000-8000-000000000002',:'incident_id'::uuid) as result \gset link_
select pg_temp.assert_true((:'link_result'::jsonb->>'ok')::boolean,'corrective work linked');
select pg_temp.assert_true((select incident_id=:'incident_id'::uuid from public.work_orders where id='30000000-0000-4000-8000-000000000002'),'link persisted');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',false);
insert into public.emergency_response_roster(profile_id,created_by,escalation_order)
values('10000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000006',1);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select public.create_incident(jsonb_build_object('incident_type','fire','location','Plant','description','Smoke observed')) as result \gset ambiguous_
select pg_temp.assert_true(:'ambiguous_result'::jsonb->>'assignment_state'='UNASSIGNED_EMERGENCY','ambiguous roster remains unassigned');
select pg_temp.assert_true((:'ambiguous_result'::jsonb#>>'{incident,assigned_technician_id}') is null,'no incorrect responder selected');
reset role;

select pg_temp.assert_true((select count(*)=2 from public.notification_outbox where incident_id=(:'ambiguous_result'::jsonb#>>'{incident,id}')::uuid and recipient_profile_id='10000000-0000-4000-8000-000000000001'),'administrator still notified when unassigned');
select pg_temp.assert_true((select count(*)=2 from public.notification_outbox where incident_id=(:'ambiguous_result'::jsonb#>>'{incident,id}')::uuid and recipient_profile_id='10000000-0000-4000-8000-000000000006'),'supervisor still notified when unassigned');

reset role;
create or replace function pg_temp.fail_incident_audit() returns trigger language plpgsql as $$ begin if new.action='incident_acknowledge' then raise exception 'forced audit failure'; end if; return new; end $$;
create trigger force_incident_audit_failure before insert on public.activity_logs for each row execute function pg_temp.fail_incident_audit();
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select public.create_incident(jsonb_build_object('incident_type','other','location','Test','description','Rollback test')) as result \gset rollback_create_
select (:'rollback_create_result'::jsonb#>>'{incident,id}') as rollback_id \gset
select public.transition_incident(:'rollback_id'::uuid,'acknowledge') as result \gset rollback_
select pg_temp.assert_true(:'rollback_result'::jsonb->>'code'='INTERNAL_ERROR','audit failure is safely contained');
select pg_temp.assert_true((select status='reported' and acknowledged_at is null from public.incidents where id=:'rollback_id'::uuid),'audit failure rolls transition back');
reset role;
drop trigger force_incident_audit_failure on public.activity_logs;

select '0014 emergency incident database tests passed' as result;

\set ON_ERROR_STOP on
create or replace function pg_temp.assert_true(c boolean,m text)returns void language plpgsql as $$begin if not coalesce(c,false)then raise exception 'ASSERTION FAILED: %',m;end if;end$$;
insert into auth.users(id,email,raw_user_meta_data)values('26000000-0000-4000-8000-000000000001','sla-admin@example.test','{"display_name":"SLA Administrator"}');
set fmworks.profile_admin_rpc='on';update public.profiles set role='administrator',is_active=true,deleted_at=null,password_change_required=false where id='26000000-0000-4000-8000-000000000001';reset fmworks.profile_admin_rpc;
insert into public.sla_agreements(id,agreement_code,name,created_by)values('26000000-0000-4000-8000-000000000010','SLA-UAT','UAT Agreement','26000000-0000-4000-8000-000000000001');
insert into public.sla_agreement_versions(id,agreement_id,version_number,effective_from,source_reference,approval_status,created_by)values('26000000-0000-4000-8000-000000000011','26000000-0000-4000-8000-000000000010',1,'2026-01-01','Clause 4.2','pending_approval','26000000-0000-4000-8000-000000000001');
insert into public.sla_rules(id,version_id,service_category_id,priority_class,work_order_priority,acknowledgement_minutes,response_minutes,attendance_minutes,make_safe_minutes,rectification_minutes,kpi_target_percent,source_clause)select'26000000-0000-4000-8000-000000000012','26000000-0000-4000-8000-000000000011',id,'P1','critical',15,30,60,120,240,95,'4.2'from public.service_categories where code='GENERAL';
insert into public.escalation_matrix_steps(version_id,threshold_percent,escalation_level,recipient_role,is_immediate_for_critical_safety)values('26000000-0000-4000-8000-000000000011',50,'warning','supervisor',false),('26000000-0000-4000-8000-000000000011',75,'supervisor','supervisor',false),('26000000-0000-4000-8000-000000000011',90,'facility_manager','administrator',false),('26000000-0000-4000-8000-000000000011',100,'breach','administrator',false),('26000000-0000-4000-8000-000000000011',0,'client_management','administrator',true);
set role authenticated;select set_config('request.jwt.claim.sub','26000000-0000-4000-8000-000000000001',false);
select public.approve_sla_version('26000000-0000-4000-8000-000000000011','Approved against source')as result \gset
select pg_temp.assert_true((:'result'::jsonb)->>'ok'='true','authorized human approval activates the version');
select public.create_work_order(jsonb_build_object('title','Critical SLA test','location','Plant','priority','critical','status','submitted','source','reactive'))as created \gset
select pg_temp.assert_true((:'created'::jsonb)->>'ok'='true','approved rule permits governed Work Order creation');
select pg_temp.assert_true(exists(select 1 from public.work_order_sla_clocks where work_order_id=((:'created'::jsonb)->'work_order'->>'id')::uuid and acknowledgement_deadline=started_at+interval'15 minutes' and rectification_deadline=started_at+interval'240 minutes'),'all deterministic deadlines attach from approved rule');
select public.refresh_work_order_sla(((:'created'::jsonb)->'work_order'->>'id')::uuid,((:'created'::jsonb)->'work_order'->>'submitted_at')::timestamptz+interval'190 minutes');
select pg_temp.assert_true(exists(select 1 from public.work_order_sla_clocks where risk_state='at_risk'),'75 percent consumption becomes at risk');
select public.process_sla_escalations(((:'created'::jsonb)->'work_order'->>'submitted_at')::timestamptz+interval'190 minutes');
select pg_temp.assert_true((select count(*)=3 from public.sla_escalation_events),'50/75 percent and immediate safety escalations are durable');
select id as escalation_id from public.sla_escalation_events order by triggered_at,id limit 1 \gset
select public.acknowledge_sla_escalation(:'escalation_id','Management acknowledged the escalation');
select pg_temp.assert_true(exists(select 1 from public.sla_escalation_events where id=:'escalation_id' and acknowledged_at is not null and acknowledgement_note='Management acknowledged the escalation'),'escalation acknowledgement is durable');
select public.refresh_work_order_sla(((:'created'::jsonb)->'work_order'->>'id')::uuid,((:'created'::jsonb)->'work_order'->>'submitted_at')::timestamptz+interval'241 minutes');
select pg_temp.assert_true(exists(select 1 from public.work_order_sla_clocks where risk_state='breached'),'deadline passage becomes breached');
select public.create_report_schedule(jsonb_build_object('name','Daily management','cadence','daily','recipient_roles',jsonb_build_array('administrator')))as daily \gset
select public.create_report_schedule(jsonb_build_object('name','Weekly management','cadence','weekly'))as weekly \gset
select public.create_report_schedule(jsonb_build_object('name','Monthly management','cadence','monthly'))as monthly \gset
select pg_temp.assert_true((select count(*)=3 from public.report_schedules where last_delivery_status='NOT_CONFIGURED'),'daily weekly monthly schedules do not pretend delivery');reset role;
insert into auth.users(id,email,raw_user_meta_data)values('26000000-0000-4000-8000-000000000002','sla-tech@example.test','{"display_name":"SLA Technician"}');set fmworks.profile_admin_rpc='on';update public.profiles set role='technician',is_active=true,deleted_at=null,password_change_required=false where id='26000000-0000-4000-8000-000000000002';reset fmworks.profile_admin_rpc;
set role authenticated;select set_config('request.jwt.claim.sub','26000000-0000-4000-8000-000000000002',false);select pg_temp.assert_true((select count(*)=0 from public.sla_agreements),'technician cannot read commercial SLA agreements');reset role;
select pg_temp.assert_true(exists(select 1 from public.activity_logs where action='sla_version_approved')and exists(select 1 from public.activity_logs where action='sla_escalated')and exists(select 1 from public.activity_logs where action='sla_escalation_acknowledged'),'approval, escalation and acknowledgement are audited');

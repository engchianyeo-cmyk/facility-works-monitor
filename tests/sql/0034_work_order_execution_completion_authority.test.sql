\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$begin
  if value is not true then raise exception '0034 regression failed: %',message; end if;
end$$;

-- Disposable identities. Existing ready fixtures cover every role except Facility Manager.
\set admin '4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b'
\set approver '057e5915-809a-4b26-8140-bea21219b44b'
\set reviewer 'f8d0c3ee-396c-4e2f-b40c-09fd7f57bae3'
\set supervisor 'c04dbf45-f78c-4943-8914-be0c4b09594c'
\set technician 'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'
\set fm '92000000-0000-4000-8000-000000000006'

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select :'fm',instance_id,'authenticated','authenticated','fm-0034@example.test',encrypted_password,now(),now(),now()
from auth.users limit 1;
select set_config('request.jwt.claim.sub',:'admin',true);
select set_config('fmworks.profile_admin_rpc','on',true);
update public.profiles set email='fm-0034@example.test',display_name='Facility Manager 0034',role='facility_manager',is_active=true,deleted_at=null,password_change_required=false where id=:'fm';
select set_config('fmworks.profile_admin_rpc','off',true);

-- Prove work_order_actor enforces operational readiness, independently of 0033.
select set_config('fmworks.profile_admin_rpc','on',true);
update public.profiles set password_change_required=true where id=:'technician';
select set_config('fmworks.profile_admin_rpc','off',true);
select set_config('request.jwt.claim.sub',:'technician',true);
select pg_temp.assert_true(public.work_order_actor() is null,'work_order_actor authorized a profile before operational readiness');
select set_config('request.jwt.claim.sub',:'admin',true);
select set_config('fmworks.profile_admin_rpc','on',true);
update public.profiles set password_change_required=false where id=:'technician';
select set_config('fmworks.profile_admin_rpc','off',true);
select set_config('request.jwt.claim.sub',:'technician',true);
select pg_temp.assert_true(public.work_order_actor()->>'role'='technician','work_order_actor did not resolve the ready profile');

create or replace function pg_temp.make_order(case_id integer,assigned uuid,status_value text default 'in_progress') returns uuid language plpgsql as $$
declare new_id uuid := ('94000000-0000-4000-8000-'||lpad(case_id::text,12,'0'))::uuid;
begin
  insert into public.work_orders(id,work_order_number,title,description,location,status,assigned_technician_id,assigned_to,assigned_at,started_at,requested_by,user_id,completion_notes,actual_labour_hours,completed_at,closed_at,cancelled_at)
  values(new_id,'WO-0034-'||case_id,'Disposable 0034 regression','Local database only','Test location',status_value,assigned,'Disposable Technician',now(),case when status_value='in_progress' then now() else null end,'f8d0c3ee-396c-4e2f-b40c-09fd7f57bae3','f8d0c3ee-396c-4e2f-b40c-09fd7f57bae3',case when status_value in ('closed','cancelled') then 'Terminal work record' end,case when status_value in ('closed','cancelled') then 1 end,case when status_value in ('closed','cancelled') then now() end,case when status_value='closed' then now() end,case when status_value='cancelled' then now() end);
  return new_id;
end$$;

create or replace function pg_temp.add_evidence(order_id uuid,category_value text,deleted boolean default false) returns void language plpgsql as $$
begin
  insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path,deleted_at,deleted_by,deletion_reason)
  values('work_order',order_id,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','0034.png','image/png',8,category_value,'Disposable regression fixture','evidence/work-order/'||order_id||'/'||gen_random_uuid()||'/0034.png',case when deleted then now() else null end,case when deleted then '4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b'::uuid else null end,case when deleted then 'Disposable regression fixture' else null end);
end$$;

-- Assigned Technician records work; status/timestamps remain unchanged and audit is durable.
select set_config('request.jwt.claim.sub',:'technician',true);
select pg_temp.assert_true((public.record_work_order_execution(pg_temp.make_order(1,:'technician'),jsonb_build_object('completion_notes','Reset and tested','actual_labour_hours',1.5))->>'ok')::boolean,'assigned Technician record rejected');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-0034-1' and status='in_progress' and completion_notes='Reset and tested' and actual_labour_hours=1.5 and completed_at is null and reviewed_at is null),'work record changed lifecycle or was not stored');
select pg_temp.assert_true(exists(select 1 from public.activity_logs l join public.work_orders w on w.id=l.work_order_id where w.work_order_number='WO-0034-1' and l.action='work_order_execution_recorded' and l.from_status=l.to_status),'work-record audit absent');

-- Rejected operations are compared against complete row/audit/notification snapshots.
create or replace function pg_temp.assert_rejected_atomic(order_id uuid,actor_id uuid,operation text,payload jsonb,expected_code text) returns void language plpgsql as $$
declare before_row jsonb;after_row jsonb;before_activity jsonb;after_activity jsonb;before_notice jsonb;after_notice jsonb;before_evidence jsonb;after_evidence jsonb;result jsonb;
begin
  select to_jsonb(w) into before_row from public.work_orders w where id=order_id;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into before_activity from public.activity_logs x where work_order_id=order_id;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into before_notice from public.notification_outbox x where work_order_id=order_id;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into before_evidence from public.evidence_items x where work_order_id=order_id;
  perform set_config('request.jwt.claim.sub',actor_id::text,true);
  result := case when operation='record' then public.record_work_order_execution(order_id,payload) else public.transition_work_order(order_id,'complete',payload) end;
  perform pg_temp.assert_true(result->>'code'=expected_code,operation||' returned '||coalesce(result->>'code','NULL')||', expected '||expected_code);
  select to_jsonb(w) into after_row from public.work_orders w where id=order_id;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into after_activity from public.activity_logs x where work_order_id=order_id;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into after_notice from public.notification_outbox x where work_order_id=order_id;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into after_evidence from public.evidence_items x where work_order_id=order_id;
  perform pg_temp.assert_true(before_row=after_row and before_activity=after_activity and before_notice=after_notice and before_evidence=after_evidence,'rejected operation was not atomic');
end$$;

select pg_temp.assert_rejected_atomic(pg_temp.make_order(2,:'admin'),:'technician','record',jsonb_build_object('completion_notes','malicious','actual_labour_hours',1),'ACCESS_DENIED');

-- Administrator can record without completing.
select set_config('request.jwt.claim.sub',:'admin',true);
select pg_temp.assert_true((public.record_work_order_execution(pg_temp.make_order(3,:'technician'),jsonb_build_object('completion_notes','Administrator record','actual_labour_hours',2))->>'ok')::boolean,'Administrator record rejected');
select pg_temp.assert_true(exists(select 1 from public.work_orders where work_order_number='WO-0034-3' and status='in_progress' and completed_at is null and reviewed_at is null),'Administrator record changed lifecycle');

-- Every non-Administrator formal completion attempt is rejected, including crafted fields.
do $$declare actor uuid;case_no int:=10;oid uuid;begin
  foreach actor in array array['e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'::uuid,'f8d0c3ee-396c-4e2f-b40c-09fd7f57bae3'::uuid,'057e5915-809a-4b26-8140-bea21219b44b'::uuid,'c04dbf45-f78c-4943-8914-be0c4b09594c'::uuid,'92000000-0000-4000-8000-000000000006'::uuid] loop
    perform set_config('request.jwt.claim.sub','4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b',true);
    oid:=pg_temp.make_order(case_no,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'::uuid);
    update public.work_orders set completion_notes='Ready',actual_labour_hours=1 where id=oid;
    perform pg_temp.add_evidence(oid,'after');
    perform pg_temp.assert_rejected_atomic(oid,actor,'complete',jsonb_build_object('role','administrator','status','completed','completed_at',now(),'reviewed_at',now()),'ACCESS_DENIED');
    case_no:=case_no+1;
  end loop;
end$$;

-- Missing and invalid prerequisites reject atomically.
do $$declare oid uuid;begin
  perform set_config('request.jwt.claim.sub','4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b',true);
  oid:=pg_temp.make_order(20,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'); update public.work_orders set actual_labour_hours=1 where id=oid; perform pg_temp.add_evidence(oid,'after'); perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','complete','{}','COMPLETION_DETAILS_REQUIRED');
  oid:=pg_temp.make_order(21,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'); update public.work_orders set completion_notes='Ready' where id=oid; perform pg_temp.add_evidence(oid,'after'); perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','complete','{}','COMPLETION_DETAILS_REQUIRED');
  oid:=pg_temp.make_order(22,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'); perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','record',jsonb_build_object('completion_notes','Ready','actual_labour_hours',-1),'COMPLETION_DETAILS_REQUIRED');
  oid:=pg_temp.make_order(23,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'); update public.work_orders set completion_notes='Ready',actual_labour_hours=1 where id=oid; perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','complete','{}','AFTER_EVIDENCE_REQUIRED');
  oid:=pg_temp.make_order(24,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'); update public.work_orders set completion_notes='Ready',actual_labour_hours=1 where id=oid; perform pg_temp.add_evidence(oid,'completion'); perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','complete','{}','AFTER_EVIDENCE_REQUIRED');
  oid:=pg_temp.make_order(25,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8'); update public.work_orders set completion_notes='Ready',actual_labour_hours=1 where id=oid; perform pg_temp.add_evidence(oid,'after',true); perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','complete','{}','AFTER_EVIDENCE_REQUIRED');
  oid:=pg_temp.make_order(26,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8','submitted'); perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','complete','{}','INVALID_TRANSITION');
  oid:=pg_temp.make_order(27,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8','closed'); perform pg_temp.add_evidence(oid,'after'); perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','complete','{}','TERMINAL_IMMUTABLE');
  oid:=pg_temp.make_order(28,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8','cancelled'); perform pg_temp.add_evidence(oid,'after'); perform pg_temp.assert_rejected_atomic(oid,'4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b','complete','{}','TERMINAL_IMMUTABLE');
end$$;

-- Valid Administrator completion preserves work, sets timestamp, audits and queues notifications.
do $$declare oid uuid;result jsonb;begin
  oid:=pg_temp.make_order(30,'e6e6350d-ed05-4372-9ea6-a38dabb4a7c8');
  perform set_config('request.jwt.claim.sub','e6e6350d-ed05-4372-9ea6-a38dabb4a7c8',true);
  perform public.record_work_order_execution(oid,jsonb_build_object('completion_notes','Pump reset and tested','actual_labour_hours',2.5));
  perform pg_temp.add_evidence(oid,'after');
  perform set_config('request.jwt.claim.sub','4ddc7a39-5dd5-41a7-8716-03dcc1c3f87b',true);
  result:=public.transition_work_order(oid,'complete',jsonb_build_object('completion_notes','crafted overwrite','actual_labour_hours',999,'status','reviewed'));
  perform pg_temp.assert_true((result->>'ok')::boolean,'valid Administrator completion rejected');
  perform pg_temp.assert_true(exists(select 1 from public.work_orders where id=oid and status='completed' and completed_at is not null and reviewed_at is null and completion_notes='Pump reset and tested' and actual_labour_hours=2.5),'valid completion postconditions failed or crafted payload won');
  perform pg_temp.assert_true(exists(select 1 from public.activity_logs where work_order_id=oid and action='work_order_complete'),'completion audit absent');
  perform pg_temp.assert_true(exists(select 1 from public.notification_outbox where work_order_id=oid and event_type='work_order_completion_submitted'),'completion notification absent');
  result:=public.verify_completed_work(oid,jsonb_build_object('reason','Disposable Administrator self-verification regression'));
  perform pg_temp.assert_true((result->>'ok')::boolean and exists(select 1 from public.work_orders where id=oid and status='reviewed'),'verify_completed_work regression failed');
end$$;

-- Actual ACL attack surface: no indirect PUBLIC grant and no private-core execution.
select pg_temp.assert_true(not has_function_privilege('anon','public.transition_work_order_0034_core(uuid,text,jsonb)','EXECUTE'),'anon private-core execution');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.transition_work_order_0034_core(uuid,text,jsonb)','EXECUTE'),'authenticated private-core execution');
select pg_temp.assert_true(not has_function_privilege('service_role','public.transition_work_order_0034_core(uuid,text,jsonb)','EXECUTE'),'service_role private-core execution');
select pg_temp.assert_true(not exists(select 1 from pg_proc p,lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.transition_work_order_0034_core(uuid,text,jsonb)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC private-core execution');

rollback;

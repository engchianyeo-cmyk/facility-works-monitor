\set ON_ERROR_STOP on
-- D-49 (10 Nov 2026): Technician 2 is named on the Work Order, notified when named and when the endorsement is due,
-- and is the only Technician who may endorse. Self-contained synthetic identities and data; everything rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Named Technician 2 regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d490000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.site(wo uuid) returns void language plpgsql security definer as $site$
declare who uuid;
begin
  select coalesce(assigned_technician_id,requested_by) into who from public.work_orders where id=wo;
  insert into public.work_order_markups(work_order_id,source_type,source_reference,drawing_revision,x_percent,y_percent,annotation_type,geometry,note,created_by)
  values(wo,'drawing','FW-006','A (10 Nov 2026)',20.4,35.5,'marker','{"points":[{"x":20.4,"y":35.5}]}','AHU Room',who);
  insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
  values('work_order',wo,who,'before.jpg','image/jpeg',100,'before','evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/before.jpg');
end;$site$;

-- 1 Technician A (raises; Technician 1), 2 Technician B, 3 Technician C, 4 supervisor, 5 approver, 6 administrator, 7 other-facility Technician
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'d49.'||n||'@example.test',jsonb_build_object('display_name','D49 '||role||' '||n)
from (values ('technician',1),('technician',2),('technician',3),('supervisor',4),('approver',5),('administrator',6),('technician',7)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('technician',3),('supervisor',4),('approver',5),('administrator',6),('technician',7)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.sites(id,code,name,is_active) values ('1d490000-0000-4000-8000-0000000000f2','D49-OTHER','D49 Other Facility',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(6) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3),pg_temp.u(4),pg_temp.u(5));
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values ('1d490000-0000-4000-8000-0000000000f2',pg_temp.u(7),'technician',pg_temp.u(6));
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert, update on ids to authenticated;

do $test$
declare r jsonb; wo uuid; path text; checks jsonb := '{"supervised_work":true,"final_quotation":true,"field_evidence":true,"site_evidence":true,"quotation_scope":true}'::jsonb;
begin
  perform pg_temp.assert_true(to_regprocedure('public.set_work_order_second_technician(uuid,uuid)') is not null, 'RPC exists');
  perform pg_temp.assert_true(has_function_privilege('authenticated','public.set_work_order_second_technician(uuid,uuid)','EXECUTE'), 'authenticated may call it');
  perform pg_temp.assert_true(not has_function_privilege('authenticated','public.work_order_notify_person(uuid,text,uuid)','EXECUTE'), 'the notice helper is internal');

  set local role authenticated;
  perform pg_temp.act(pg_temp.u(1));
  r:=public.create_work_order(jsonb_build_object('title','AHU-02 quarterly PM','location','AHU Room','facility_id',(select facility_id from f),'in_house_work',true,
    'description','Quarterly preventive maintenance of AHU-02.'));
  wo:=(r->'work_order'->>'id')::uuid; insert into ids values('wo',wo);
  reset role; perform pg_temp.site(wo); set local role authenticated;

  -- Who may name Technician 2, and whom
  perform pg_temp.assert_true(public.set_work_order_second_technician(wo,pg_temp.u(2))->>'code'='ACCESS_DENIED','a Technician cannot name Technician 2');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.set_work_order_second_technician(wo,pg_temp.u(1))->>'code'='VALIDATION_ERROR','Technician 1 / the raiser cannot be Technician 2');
  perform pg_temp.assert_true(public.set_work_order_second_technician(wo,pg_temp.u(7))->>'code'='INACTIVE_REFERENCE','a Technician of another facility cannot be Technician 2');
  perform pg_temp.assert_true(public.set_work_order_second_technician(wo,pg_temp.u(5))->>'code'='INACTIVE_REFERENCE','an Approver cannot be Technician 2');
  r:=public.set_work_order_second_technician(wo,pg_temp.u(2));
  perform pg_temp.assert_true((r->>'ok')::boolean and (r->'work_order'->>'second_technician_id')::uuid=pg_temp.u(2),'Supervisor names Technician 2: '||coalesce(r->>'code',''));
  perform pg_temp.assert_true(public.set_work_order_second_technician(wo,pg_temp.u(2))->>'code'='NO_CHANGE','naming the same person again is NO_CHANGE');
  reset role;
  perform pg_temp.assert_true(exists(select 1 from public.notification_outbox where work_order_id=wo and recipient_profile_id=pg_temp.u(2) and event_type='work_order_second_technician_named'),'Technician 2 is told when named');
  perform pg_temp.assert_true(exists(select 1 from public.work_order_copied_parties where work_order_id=wo and profile_id=pg_temp.u(2)),'Technician 2 is copied');
  perform pg_temp.assert_true(exists(select 1 from public.activity_logs where work_order_id=wo and action='work_order_second_technician_set'),'naming is audited');
  set local role authenticated;
  perform pg_temp.assert_true(public.set_work_order_technician(wo,pg_temp.u(2))->>'code'='VALIDATION_ERROR','the named Technician 2 cannot become Technician 1');

  -- Through to Submitted for Review
  perform pg_temp.act(pg_temp.u(1));
  r:=public.transition_work_order(wo,'submit');
  perform pg_temp.assert_true(r->'work_order'->>'status'='submitted','submitted: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  perform pg_temp.act(pg_temp.u(5));
  r:=public.transition_work_order(wo,'approve');
  perform pg_temp.assert_true(r->'work_order'->>'status' in ('approved','assigned'),'approved: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  perform pg_temp.act(pg_temp.u(1));
  if (select status from public.work_orders where id=wo)='approved' then perform public.transition_work_order(wo,'accept'); end if;
  perform pg_temp.assert_true((public.transition_work_order(wo,'start')->>'ok')::boolean,'started');
  perform pg_temp.assert_true((public.set_work_order_actual_times(wo,now()-interval '5 hours',now()-interval '1 hour')->>'ok')::boolean,'times recorded');
  r:=public.record_work_order_execution(wo,'{"completion_notes":"Filters, belts, bearings, drain pan and interlocks checked.","actual_labour_hours":2}');
  r:=public.manage_work_order_actual_cost(wo,null,'{"operation":"confirm"}');
  reset role;
  path:='evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/after.jpg';
  insert into storage.objects(bucket_id,name) values('field-evidence',path);
  set local role authenticated;
  r:=public.register_evidence_item('work_order',wo,'after.jpg','image/jpeg',10,'after','After PM',path);
  r:=public.submit_physical_completion(wo,'{"completion_notes":"Filters, belts, bearings, drain pan and interlocks checked.","actual_labour_hours":2}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='completed','submitted for review: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
  perform pg_temp.assert_true(exists(select 1 from public.notification_outbox where work_order_id=wo and recipient_profile_id=pg_temp.u(2) and event_type='work_order_endorsement_due'),'Technician 2 is told the endorsement is due');
  perform pg_temp.assert_true(not exists(select 1 from public.notification_outbox where work_order_id=wo and recipient_profile_id=pg_temp.u(3) and event_type='work_order_endorsement_due'),'other Technicians are not');
  set local role authenticated;

  -- Only the named Technician 2 may endorse; a manager may change the name until the endorsement is given
  perform pg_temp.act(pg_temp.u(3));
  r:=public.endorse_work_order(wo,'Checked the AHU on site against the records.',checks);
  perform pg_temp.assert_true(r->>'code'='ACCESS_DENIED' and r->>'message' like '%named Technician 2%','another Technician cannot endorse: '||coalesce(r->>'code',''));
  perform pg_temp.act(pg_temp.u(4));
  r:=public.set_work_order_second_technician(wo,pg_temp.u(3));
  perform pg_temp.assert_true((r->>'ok')::boolean and (r->>'endorsement_due')::boolean,'Technician 2 changed while the endorsement is due');
  reset role;
  perform pg_temp.assert_true(not exists(select 1 from public.work_order_copied_parties where work_order_id=wo and profile_id=pg_temp.u(2)),'the previous Technician 2 is no longer copied');
  perform pg_temp.assert_true(exists(select 1 from public.notification_outbox where work_order_id=wo and recipient_profile_id=pg_temp.u(3) and event_type='work_order_endorsement_due'),'the new Technician 2 is told the endorsement is due');
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.endorse_work_order(wo,'Checked the AHU on site against the records.',checks)->>'code'='ACCESS_DENIED','the former Technician 2 cannot endorse');
  perform pg_temp.act(pg_temp.u(3));
  r:=public.endorse_work_order(wo,'Checked the AHU on site against the records.',checks);
  perform pg_temp.assert_true((r->>'ok')::boolean,'the named Technician 2 endorses: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.set_work_order_second_technician(wo,pg_temp.u(2))->>'code'='INVALID_TRANSITION','Technician 2 cannot be changed after endorsing');
  reset role;
end;$test$;

-- A Work Order without a named Technician 2 still works as before (any other Technician of the facility endorses).
do $test$
begin
  perform pg_temp.assert_true(pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.endorse_work_order(uuid,text,jsonb)'::regprocedure),
    'w.second_technician_id is not null and actor_id <> w.second_technician_id') > 0, 'the named check applies only when Technician 2 is named');
end;$test$;
rollback;

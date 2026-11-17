\set ON_ERROR_STOP on
-- M31 (D-59a, D-58): the fault library and the assistant's settings. Synthetic data; everything rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Fault library regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d310000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 super-administrator, 2 technician F1, 3 technician F1 (other), 4 technician F2, 5 approver F1, 6 facility manager F1, 7 finance F1
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m31.'||n||'@example.test',jsonb_build_object('display_name','M31 '||role||' '||n)
from (values ('administrator',1),('technician',2),('technician',3),('technician',4),('approver',5),('facility_manager',6),('finance',7)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Electrical' end
from (values ('administrator',1),('technician',2),('technician',3),('technician',4),('approver',5),('facility_manager',6),('finance',7)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

insert into public.sites(id,code,name,is_active) values (pg_temp.u(101),'M31-F1','M31 Facility One',true),(pg_temp.u(102),'M31-F2','M31 Facility 2',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(101),pg_temp.u(2),'technician',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(3),'technician',pg_temp.u(1)),
 (pg_temp.u(102),pg_temp.u(4),'technician',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(5),'approver',pg_temp.u(1)),
 (pg_temp.u(101),pg_temp.u(6),'facility_manager',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(7),'finance',pg_temp.u(1));
insert into public.work_orders(id,user_id,requested_by,assigned_technician_id,work_order_number,title,location,priority,status,source,facility_id,created_at,updated_at,completed_at,reviewed_at) values
 (pg_temp.u(201),pg_temp.u(2),pg_temp.u(2),pg_temp.u(2),'WO-M31-1','Battery charger BC-05 gassing and boiling','1.04 Battery Charging Room','high','reviewed','manual',pg_temp.u(101),now()-interval '60 days',now(),now()-interval '50 days',now()-interval '49 days'),
 (pg_temp.u(202),pg_temp.u(2),pg_temp.u(2),pg_temp.u(2),'WO-M31-2','Battery charger BC-05 not charging','1.04 Battery Charging Room','medium','draft','manual',pg_temp.u(101),now(),now(),null,null),
 (pg_temp.u(203),pg_temp.u(2),pg_temp.u(2),pg_temp.u(2),'WO-M31-3','Lift door not closing','Lobby','medium','in_progress','manual',pg_temp.u(101),now(),now(),null,null),
 (pg_temp.u(204),pg_temp.u(4),pg_temp.u(4),pg_temp.u(4),'WO-M31-4','Battery charger BC-05 alarm','Charging','medium','draft','manual',pg_temp.u(102),now(),now(),null,null);

-- Sharing: only once the work is done, only people on the Work Order, at least one answer.
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((public.share_work_order_learning(pg_temp.u(203),'{"tip":"Check the door sensor first"}')->>'code')='INVALID_STATE','not before the work is done');
select pg_temp.assert_true((public.share_work_order_learning(pg_temp.u(201),'{}')->>'code')='VALIDATION_ERROR','something must be written');
select pg_temp.assert_true((public.share_work_order_learning(pg_temp.u(201),'{"tip":"ok","confirmed_cause":"x"}')->>'code')='VALIDATION_ERROR','answers of at least 3 characters');
select pg_temp.assert_true((public.share_work_order_learning(pg_temp.u(201),'{"confirmed_cause":"Charger voltage sensing lead broken; two shorted cells","fix_that_worked":"Replaced control board and cells C14 and C15","tip":"Isolate at the wall breaker and ventilate before going near","ai_suggestion":"partly"}')->>'ok')::boolean,'Technician 1 shares');
select pg_temp.assert_true((public.share_work_order_learning(pg_temp.u(201),'{"tip":"Isolate at the wall breaker first, then ventilate"}')->>'ok')::boolean,'sharing again updates');
select pg_temp.assert_true((select count(*) from public.work_order_learnings where work_order_id=pg_temp.u(201))=1,'one learning per person per Work Order');
select pg_temp.assert_true((select confirmed_cause is null and tip like 'Isolate at the wall%' from public.work_order_learnings where work_order_id=pg_temp.u(201)),'update replaces the answers');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where work_order_id=pg_temp.u(201) and action='work_order_learning_shared'),'sharing is audited');
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((public.share_work_order_learning(pg_temp.u(201),'{"tip":"I was not on this job"}')->>'code')='ACCESS_DENIED','a Technician not on the job cannot share');
select pg_temp.act(pg_temp.u(5));
select pg_temp.assert_true((public.share_work_order_learning(pg_temp.u(201),'{"confirmed_cause":"Charger sensing lead and two shorted cells","fix_that_worked":"Board and cells replaced"}')->>'ok')::boolean,'the facility approver shares');
select pg_temp.act(pg_temp.u(7));
select pg_temp.assert_true((public.share_work_order_learning(pg_temp.u(201),'{"tip":"Invoice matched"}')->>'code') in ('ACCESS_DENIED','NOT_FOUND'),'Finance does not share fault learnings');

-- Reading follows the Work Order: same facility yes, other facility no; direct writes refused.
set local role authenticated;
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((select count(*) from public.work_order_learnings where work_order_id=pg_temp.u(201))=2,'a Technician of the facility reads the learnings');
select pg_temp.act(pg_temp.u(4));
select pg_temp.assert_true((select count(*) from public.work_order_learnings where work_order_id=pg_temp.u(201))=0,'another facility does not see them');
select pg_temp.assert_true((select count(*) from public.work_order_learning_matches(pg_temp.u(204)))=0,'matches respect facility visibility');
do $$ begin
  begin insert into public.work_order_learnings(work_order_id,shared_by_name,tip) values (pg_temp.u(201),'x','direct write');
    raise exception 'Fault library regression: direct insert allowed'; exception when insufficient_privilege then null; end;
end $$;

-- Matching: the new BC-05 job at the same facility finds the earlier fix, proven (Completed, no repeat fault).
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((select count(*) from public.work_order_learning_matches(pg_temp.u(202)))=2,'BC-05 job finds both learnings');
select pg_temp.assert_true((select bool_and(proven and not repeat_fault and work_order_number='WO-M31-1') from public.work_order_learning_matches(pg_temp.u(202))),'the earlier fix is proven');
select pg_temp.assert_true((select count(*) from public.work_order_learning_matches(pg_temp.u(203)))=0,'an unrelated lift job finds nothing');
reset role;

-- Repeat fault: a new Work Order on the same asset within 30 days of completion un-proves the fix (rule checked here;
-- assets need the registry's reference data).
select pg_temp.assert_true(pg_catalog.pg_get_functiondef('public.work_order_learning_matches(uuid,integer)'::regprocedure) like '%interval ''30 days''%','repeat fault window is 30 days');

-- Hiding: Facility Manager of the facility yes (with reason); Technician no; hidden rows leave the matches.
set local role authenticated;
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((public.hide_work_order_learning((select id from public.work_order_learnings where work_order_id=pg_temp.u(201) and shared_by=pg_temp.u(5)),'wrong')->>'code')='ACCESS_DENIED','a Technician cannot hide');
reset role;
select pg_temp.act(pg_temp.u(6));
select pg_temp.assert_true((public.hide_work_order_learning((select id from public.work_order_learnings where work_order_id=pg_temp.u(201) and shared_by=pg_temp.u(5)),'no')->>'code')='VALIDATION_ERROR','hiding needs a reason');
select pg_temp.assert_true((public.hide_work_order_learning((select id from public.work_order_learnings where work_order_id=pg_temp.u(201) and shared_by=pg_temp.u(5)),'Duplicate of the Technician''s entry')->>'ok')::boolean,'the Facility Manager hides');
set local role authenticated;
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((select count(*) from public.work_order_learning_matches(pg_temp.u(202)))=1,'hidden learnings are not offered');
reset role;

-- Assistant settings: Super-Administrator only; name and picture checked; default Ollie when no picture.
select pg_temp.act(pg_temp.u(6));
select pg_temp.assert_true((public.set_assistant_settings('Max',null)->>'code')='ACCESS_DENIED','only the Super-Administrator changes the assistant');
select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((public.set_assistant_settings('',null)->>'code')='VALIDATION_ERROR','a name is needed');
select pg_temp.assert_true((public.set_assistant_settings('Ollie','data:text/html;base64,PHNjcmlwdD4=')->>'code')='VALIDATION_ERROR','only images are accepted');
select pg_temp.assert_true((public.set_assistant_settings('Max','data:image/png;base64,iVBORw0KGgo=')->>'ok')::boolean,'the Super-Administrator sets a name and picture');
select pg_temp.assert_true((select display_name='Max' and image_data_url like 'data:image/png;base64,%' from public.assistant_settings),'settings stored');
select pg_temp.assert_true((public.set_assistant_settings('Ollie',null)->>'ok')::boolean,'reset accepted');
select pg_temp.assert_true((select image_data_url is null and display_name='Ollie' from public.assistant_settings),'back to the default Ollie');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where action='assistant_settings_changed'),'changes are audited');

select 'fault_library tests passed' as result;
rollback;

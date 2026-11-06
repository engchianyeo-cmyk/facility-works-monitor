\set ON_ERROR_STOP on
-- D-37 (6 Nov 2026): contractor admission - Contractor needed, recommendation, pre-qualification by a Procurement
-- Manager, owner's approval recorded, trial jobs scored, admission at the pass mark, rejection. Everything rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Contractor admission regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d370000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.code(r jsonb) returns text language sql immutable as $$ select coalesce(r->>'code', case when r->>'ok'='true' then 'OK' end, 'NONE') $$;

-- 1 Technician 1, 2 Technician 2, 3 approver, 4 facility manager, 5 administrator, 6 finance (Procurement Manager), 7 approver elsewhere
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'d37.'||n||'@example.test',jsonb_build_object('display_name','D37 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('facility_manager',4),('administrator',5),('finance',6),('approver',7)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('facility_manager',4),('administrator',5),('finance',6),('approver',7)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.sites(id,code,name,is_active) values ('1d370000-0000-4000-8000-0000000000f2','D37-OTHER','D37 Other Facility',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(5) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3),pg_temp.u(4));
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
values ('1d370000-0000-4000-8000-0000000000f2',pg_temp.u(7),'approver',pg_temp.u(5));
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert, update on ids to authenticated;

-- Work Orders for Technician 1: one live, three to be completed by a trial contractor.
do $t$ declare r jsonb; n text; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  foreach n in array array['live','job1','job2','job3','job4'] loop
    r:=public.create_work_order(jsonb_build_object('title','D37 '||n,'location','Plant room','facility_id',(select facility_id from f)));
    perform pg_temp.assert_true(r->>'ok'='true','Technician creates Work Order '||n||': '||coalesce(r->>'message',''));
    insert into ids values (n,(r->'work_order'->>'id')::uuid);
  end loop;
end;$t$;

-- Procurement Manager designation.
do $t$ declare r jsonb; begin
  perform pg_temp.act(pg_temp.u(4)); set local role authenticated;
  perform pg_temp.assert_true(pg_temp.code(public.designate_procurement_manager(pg_temp.u(6),null))='ACCESS_DENIED','a Facility Manager cannot designate a Procurement Manager');
  perform pg_temp.act(pg_temp.u(5));
  r:=public.designate_procurement_manager(pg_temp.u(6),null);
  perform pg_temp.assert_true(r->>'ok'='true','an Administrator designates a company-wide Procurement Manager');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(public.procurement_manager_permitted((select facility_id from f)),'the company-wide Procurement Manager covers the facility');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(not public.procurement_manager_permitted((select facility_id from f)),'a Facility Manager is not a Procurement Manager by role alone');
end;$t$;

-- Contractor needed, recommendation, pre-qualification and the owner's approval.
do $t$ declare r jsonb; req uuid; adm uuid; begin
  perform pg_temp.act(pg_temp.u(2)); set local role authenticated;
  perform pg_temp.assert_true(pg_temp.code(public.raise_contractor_request((select id from ids where name='live'),'Solar PV','No solar specialist listed'))='ACCESS_DENIED','only the assigned Technician raises Contractor needed');
  perform pg_temp.act(pg_temp.u(1));
  r:=public.raise_contractor_request((select id from ids where name='live'),'Solar PV and inverters','No solar specialist on the list for the inverter alarm.');
  perform pg_temp.assert_true(r->>'ok'='true','Technician 1 raises Contractor needed: '||coalesce(r->>'message',''));
  req:=(r->'request'->>'id')::uuid;
  perform pg_temp.assert_true(pg_temp.code(public.recommend_contractor(jsonb_build_object('request_id',req,'reason','Known solar firm','new_vendor',jsonb_build_object('name','Sunvane D37','company_registration_no','201834562K'))))='ACCESS_DENIED','a Technician cannot recommend a contractor');
  perform pg_temp.act(pg_temp.u(4));
  r:=public.recommend_contractor(jsonb_build_object('request_id',req,'reason','Reliable solar specialist used at other facilities.',
    'new_vendor',jsonb_build_object('name','Sunvane D37','company_registration_no','201834562k','contact_name','Ong Jun Hao')));
  perform pg_temp.assert_true(r->>'ok'='true' and r->'admission'->>'status'='recommended','the Facility Manager recommends a new contractor: '||coalesce(r->>'message',''));
  adm:=(r->'admission'->>'id')::uuid; insert into ids values ('adm',adm), ('vendor',(r->'admission'->>'vendor_id')::uuid);
  perform pg_temp.assert_true((select status from public.contractor_requests where id=req)='answered','the request is answered');
  perform pg_temp.assert_true(pg_temp.code(public.recommend_contractor(jsonb_build_object('facility_id',(select facility_id from f),'service','Solar PV','reason','Again please','vendor_id',(select id from ids where name='vendor'))))='ALREADY_IN_PROGRESS','the same contractor cannot be recommended twice at once');
  perform pg_temp.assert_true(pg_temp.code(public.prequalify_contractor(adm,'UEN checked'))='ACCESS_DENIED','a Facility Manager cannot pre-qualify');
  perform pg_temp.assert_true(pg_temp.code(public.record_contractor_owner_approval(adm,'Owner email 6 Nov'))='INVALID_STATE','the owner''s approval waits for pre-qualification');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(pg_temp.code(public.prequalify_contractor(adm,'ok'))='VALIDATION_ERROR','pre-qualification records what was checked');
  r:=public.prequalify_contractor(adm,'UEN, public liability insurance and LEW licence checked.');
  perform pg_temp.assert_true(r->>'ok'='true' and r->'admission'->>'status'='prequalified','the Procurement Manager pre-qualifies');
  perform pg_temp.act(pg_temp.u(3));
  perform pg_temp.assert_true(pg_temp.code(public.record_contractor_owner_approval(adm,'Owner email 6 Nov'))='ACCESS_DENIED','an Approver does not record the owner''s approval');
  perform pg_temp.act(pg_temp.u(4));
  r:=public.record_contractor_owner_approval(adm,'Owner''s director approved by email on 6 Nov 2026.');
  perform pg_temp.assert_true(r->>'ok'='true' and r->'admission'->>'status'='on_trial','the Facility Manager records the owner''s approval; contractor on trial');
  perform pg_temp.act(pg_temp.u(1));
  r:=public.work_order_eligible_contractors((select id from ids where name='live'));
  perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(r->'contractors') c where c->>'id'=(select id::text from ids where name='vendor') and c->>'admission_status'='trial'),
    'Prepare Proposal lists the contractor as on trial');
end;$t$;

-- Trial jobs: two completed jobs, scored by the permitted people; admission exactly at the pass mark.
reset role;
update public.work_orders set assigned_vendor_id=(select id from ids where name='vendor'), status='reviewed', reviewed_at=now()
where id in (select id from ids where name in ('job1','job2'));
update public.work_orders set assigned_vendor_id=(select id from ids where name='vendor'), status='in_progress'
where id=(select id from ids where name='job3');
insert into public.work_order_endorsements(work_order_id,stage,endorsed_by,statement,cycle)
values ((select id from ids where name='job1'),'review',pg_temp.u(2),'D37 endorsement',1);
do $t$ declare r jsonb; four jsonb:='{"quality":4,"on_time":4,"safety":4,"documents":4,"price":4}'; three jsonb:='{"quality":3,"on_time":3,"safety":3,"documents":3,"price":3}'; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  perform pg_temp.assert_true(pg_temp.code(public.score_contractor_trial_job((select id from ids where name='job3'),four))='INVALID_STATE','a job is scored only once approved as Completed');
  perform pg_temp.assert_true(pg_temp.code(public.score_contractor_trial_job((select id from ids where name='job1'),'{"quality":6,"on_time":4,"safety":4,"documents":4,"price":4}'))='VALIDATION_ERROR','scores are 1 to 5');
  r:=public.score_contractor_trial_job((select id from ids where name='job1'),four);
  perform pg_temp.assert_true(r->>'ok'='true' and r->'evaluation'->>'scorer_capacity'='technician_1','Technician 1 scores the trial job: '||coalesce(r->>'message',''));
  perform pg_temp.assert_true(pg_temp.code(public.score_contractor_trial_job((select id from ids where name='job1'),four))='ALREADY_SCORED','one score per person per job');
  perform pg_temp.act(pg_temp.u(2));
  r:=public.score_contractor_trial_job((select id from ids where name='job1'),four);
  perform pg_temp.assert_true(r->'evaluation'->>'scorer_capacity'='technician_2','Technician 2 (the endorser) scores');
  perform pg_temp.act(pg_temp.u(7));
  perform pg_temp.assert_true(pg_temp.code(public.score_contractor_trial_job((select id from ids where name='job1'),four))='ACCESS_DENIED','an Approver of another facility cannot score');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(pg_temp.code(public.score_contractor_trial_job((select id from ids where name='job1'),four))='ACCESS_DENIED','Finance does not score trial jobs');
  perform pg_temp.assert_true(pg_temp.code(public.admit_contractor((select id from ids where name='adm'),null))='TRIAL_NOT_PASSED','one scored job is not enough');
  perform pg_temp.act(pg_temp.u(4));
  r:=public.score_contractor_trial_job((select id from ids where name='job2'),three);
  perform pg_temp.assert_true(r->'evaluation'->>'scorer_capacity'='facility_manager','the Facility Manager scores');
  perform pg_temp.assert_true((r->'trial'->>'jobs_scored')::int=2 and (r->'trial'->>'average')::numeric=3.5 and (r->'trial'->>'passed')::boolean,
    'two jobs averaging exactly 3.5 with no 1 on safety pass: '||(r->'trial')::text);
  perform pg_temp.assert_true(pg_temp.code(public.admit_contractor((select id from ids where name='adm'),null))='ACCESS_DENIED','a Facility Manager does not admit');
  perform pg_temp.act(pg_temp.u(6));
  r:=public.admit_contractor((select id from ids where name='adm'),'Passed both trial jobs.');
  perform pg_temp.assert_true(r->>'ok'='true' and r->'admission'->>'status'='admitted','the Procurement Manager admits the contractor');
end;$t$;
reset role;
do $t$ begin
  perform pg_temp.assert_true((select admission_status='shortlisted' and active from public.vendor_facility_eligibility
    where vendor_id=(select id from ids where name='vendor') and facility_id=(select facility_id from f)),'the admitted contractor is on the facility''s shortlist');
end;$t$;

-- Safety rule and rejection.
do $t$ declare r jsonb; adm uuid; v uuid; begin
  perform pg_temp.act(pg_temp.u(5)); set local role authenticated;
  r:=public.recommend_contractor(jsonb_build_object('facility_id',(select facility_id from f),'service','Plumbing','reason','Quick plumbing support.',
    'new_vendor',jsonb_build_object('name','Pipefast D37','company_registration_no','202299999Z')));
  perform pg_temp.assert_true(r->>'ok'='true','an Administrator recommends a contractor');
  adm:=(r->'admission'->>'id')::uuid; v:=(r->'admission'->>'vendor_id')::uuid; insert into ids values ('adm2',adm),('vendor2',v);
  perform pg_temp.act(pg_temp.u(6));
  perform public.prequalify_contractor(adm,'UEN and insurance checked.');
  perform public.record_contractor_owner_approval(adm,'Owner approved by phone, confirmed by email 6 Nov.');
  perform pg_temp.assert_true((select status from public.contractor_admissions where id=adm)='on_trial','the Procurement Manager may also record the owner''s approval');
end;$t$;
reset role;
update public.work_orders set assigned_vendor_id=(select id from ids where name='vendor2'), status='reviewed', reviewed_at=now()
where id in (select id from ids where name in ('job3','job4'));
do $t$ declare r jsonb; begin
  perform pg_temp.act(pg_temp.u(4)); set local role authenticated;
  perform public.score_contractor_trial_job((select id from ids where name='job3'),'{"quality":5,"on_time":5,"safety":1,"documents":5,"price":5}');
  r:=public.score_contractor_trial_job((select id from ids where name='job4'),'{"quality":5,"on_time":5,"safety":5,"documents":5,"price":5}');
  perform pg_temp.assert_true((r->'trial'->>'average')::numeric>=3.5 and not (r->'trial'->>'passed')::boolean,'a score of 1 on safety fails the trial whatever the average');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(pg_temp.code(public.admit_contractor((select id from ids where name='adm2'),null))='TRIAL_NOT_PASSED','a contractor that failed on safety cannot be admitted');
  perform pg_temp.act(pg_temp.u(3));
  perform pg_temp.assert_true(pg_temp.code(public.reject_contractor((select id from ids where name='adm2'),'Unsafe work practice'))='ACCESS_DENIED','an Approver does not reject contractors');
  perform pg_temp.act(pg_temp.u(4));
  r:=public.reject_contractor((select id from ids where name='adm2'),'Unsafe isolation on trial job 1.');
  perform pg_temp.assert_true(r->>'ok'='true' and r->'admission'->>'status'='rejected','the Facility Manager rejects the contractor');
end;$t$;
reset role;
do $t$ begin
  perform pg_temp.assert_true((select not active from public.vendor_facility_eligibility
    where vendor_id=(select id from ids where name='vendor2') and facility_id=(select facility_id from f)),'a rejected trial contractor no longer appears for the facility');
  perform pg_temp.assert_true((select count(*) from public.activity_logs where action like 'contractor_%' and note::jsonb->>'facility_id'=(select facility_id::text from f))>=8,'each step is logged');
end;$t$;
rollback;

\set ON_ERROR_STOP on
-- WP-LC2-M7 (D-11): facility settings, second-Technician endorsement, actual work times, Finance copied at Completed.
-- Self-contained synthetic identities and data; everything rolls back.
begin;
-- D-08 (M6): location markup and Before evidence, registered as postgres for rollback-only tests.
create function pg_temp.site(wo uuid) returns void language plpgsql security definer as $site$
declare who uuid;
begin
  select coalesce(assigned_technician_id,requested_by) into who from public.work_orders where id=wo;
  insert into public.work_order_markups(work_order_id,source_type,source_reference,drawing_revision,x_percent,y_percent,annotation_type,geometry,note,created_by)
  values(wo,'drawing','FW-001','A (25 May 2024)',23.1,37.4,'marker','{"points":[{"x":23.1,"y":37.4}]}','Work location',who);
  insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
  values('work_order',wo,who,'before.jpg','image/jpeg',100,'before','evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/before.jpg');
end;$site$;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Lifecycle v2 facility settings regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1c800000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 tech A, 2 tech B, 3 approver, 4 supervisor, 5 facility manager, 6 administrator,
-- 7 finance, 8 initiator, 9 reviewer, 10 non-member approver, 11 copied party (reviewer)
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'lc2m7.'||n||'@example.test',jsonb_build_object('display_name','LC2 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11),('finance',12)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11),('finance',12)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.sites(id,code,name,is_active) values ('1c800000-0000-4000-8000-0000000000f2','LC7-OTHER','LC2 Other Facility',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(6) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3),pg_temp.u(4),pg_temp.u(5));
insert into public.vendors(id,name,trade,active) values ('1c800000-0000-4000-8000-0000000000e1','LC2 Contractor','Mechanical',true);
insert into public.vendor_facility_eligibility(vendor_id,facility_id,procurement_prequalified,facility_confirmed,confirmation_basis,active)
values ('1c800000-0000-4000-8000-0000000000e1',(select facility_id from f),true,true,'LC2 rollback-only test',true);
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert, update on ids to authenticated;

-- Quotation helper: preparer prepares a S$650 draft; the document is registered as postgres; the preparer submits it.
create function pg_temp.quote(wo uuid, preparer uuid, amount numeric) returns uuid language plpgsql as $$
declare r jsonb; qid uuid;
begin
  perform pg_temp.act(preparer); set local role authenticated;
  r:=public.prepare_work_order_proposal(wo,jsonb_build_object('vendor_id','1c800000-0000-4000-8000-0000000000e1','proposed_amount',amount,'scope_summary','LC2 repair scope'));
  perform pg_temp.assert_true((r->>'ok')::boolean,'preparer prepares Draft quotation: '||coalesce(r->>'code',''));
  qid:=(r->'quotation'->>'id')::uuid;
  reset role;
  insert into public.work_order_commercial_documents(work_order_id,document_type,quotation_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
  values(wo,'quotation',qid,preparer,'quote.pdf','application/pdf',100,'commercial/work-order/'||wo::text||'/'||qid::text||'.pdf');
  set local role authenticated;
  r:=public.submit_work_order_proposal(wo,qid,'Authentic contractor quotation');
  perform pg_temp.assert_true((r->>'ok')::boolean,'preparer submits quotation: '||coalesce(r->>'code',''));
  reset role;
  return qid;
end;$$;
-- Other-facility Supervisor (13) for the facility-scope gap regression.
insert into auth.users(id,email,raw_user_meta_data) values (pg_temp.u(13),'lc2m7.13@example.test','{"display_name":"LC2 other supervisor"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='supervisor',is_active=true,password_change_required=false where id=pg_temp.u(13);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values ('1c800000-0000-4000-8000-0000000000f2',pg_temp.u(13),'supervisor',pg_temp.u(6));


-- Technician 14 at the other facility (cannot endorse here).
insert into auth.users(id,email,raw_user_meta_data) values (pg_temp.u(14),'lc2m7.14@example.test','{"display_name":"LC7 other technician"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='technician',is_active=true,password_change_required=false,trade_discipline='Mechanical' where id=pg_temp.u(14);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values ('1c800000-0000-4000-8000-0000000000f2',pg_temp.u(14),'technician',pg_temp.u(6));

-- A. Facility settings ---------------------------------------------------------------
do $test$
declare r jsonb; fac uuid:=(select facility_id from f);
begin
  perform pg_temp.assert_true(public.work_order_endorsement_stage(fac)='before_review','default endorsement stage is before the review');
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(5));
  perform pg_temp.assert_true(public.set_facility_settings(fac,pg_temp.u(3),'both','x set')->>'code'='ACCESS_DENIED','Facility Manager cannot change facility settings');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(public.set_facility_settings(fac,pg_temp.u(10),'both','Designate Approver')->>'code'='VALIDATION_ERROR','non-member Approver refused');
  perform pg_temp.assert_true(public.set_facility_settings(fac,pg_temp.u(1),'both','Designate Approver')->>'code'='VALIDATION_ERROR','a Technician cannot be the Approver');
  perform pg_temp.assert_true(public.set_facility_settings(fac,pg_temp.u(3),'sometimes','Designate Approver')->>'code'='VALIDATION_ERROR','unknown stage refused');
  r:=public.set_facility_settings(fac,pg_temp.u(3),'before_submission','Approver 3 designated; endorse before submission');
  perform pg_temp.assert_true((r->>'ok')::boolean and r->'settings'->>'endorsement_stage'='before_submission','Administrator sets the designated Approver and stage');
  perform pg_temp.assert_true(exists(select 1 from public.facility_approver_candidates(fac) c where c.id=pg_temp.u(3)) and not exists(select 1 from public.facility_approver_candidates(fac) c where c.id=pg_temp.u(10)),'candidates are facility approvers');
  reset role;
  perform pg_temp.assert_true((select count(*) from public.facility_settings_history where facility_id=fac)=1,'change recorded in history');
end;$test$;

-- B. Endorsement before submission ----------------------------------------------------
do $test$
declare r jsonb; wo uuid;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(1));
  r:=public.create_work_order(jsonb_build_object('title','Repaint door','location','Plant room','facility_id',(select facility_id from f),'in_house_work',true,
    'description','Door corroded; repaint by the in-house team.','copied_party_ids',jsonb_build_array(pg_temp.u(7),pg_temp.u(11))));
  wo:=(r->'work_order'->>'id')::uuid; insert into ids values('wo',wo);
  perform pg_temp.assert_true(not exists(select 1 from public.work_order_copied_parties where work_order_id=wo and profile_id=pg_temp.u(7))
    and exists(select 1 from public.work_order_copied_parties where work_order_id=wo and profile_id=pg_temp.u(11)),'Finance is not a selectable copied party at creation');
  reset role; perform pg_temp.site(wo); set local role authenticated;
  perform pg_temp.assert_true(public.work_order_approval_summary(wo)->'missing_requirements' @> '["Second Technician endorsement"]','summary lists the endorsement');
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='ENDORSEMENT_REQUIRED','submission waits for the endorsement');
  perform pg_temp.assert_true(public.endorse_work_order(wo,'I checked it myself.')->>'code'='ACCESS_DENIED','the responsible Technician cannot endorse');
  perform pg_temp.act(pg_temp.u(14));
  perform pg_temp.assert_true(public.endorse_work_order(wo,'Checked the photos and the site.')->>'code'='ACCESS_DENIED','a Technician of another facility cannot endorse');
  perform pg_temp.act(pg_temp.u(3));
  perform pg_temp.assert_true(public.endorse_work_order(wo,'Checked the photos and the site.')->>'code'='ACCESS_DENIED','an Approver cannot endorse');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.endorse_work_order(wo,'short')->>'code'='VALIDATION_ERROR','the statement must say what was checked');
  r:=public.endorse_work_order(wo,'Checked the photos and the site: door corroded as described.');
  perform pg_temp.assert_true((r->>'ok')::boolean and r->'endorsement'->>'stage'='submission','second Technician endorses the Draft');
  perform pg_temp.assert_true(public.endorse_work_order(wo,'Checked the photos and the site again.')->>'code'='NO_CHANGE','repeat endorsement is NO_CHANGE');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->'work_order'->>'status'='submitted','endorsed Draft is submitted');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.transition_work_order(wo,'return','{"reason":"Add a second Before photo."}')->'work_order'->>'status'='draft','returned to Draft');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='ENDORSEMENT_REQUIRED','a returned Draft needs a fresh endorsement');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true((public.endorse_work_order(wo,'Checked the updated Draft and photos.')->>'ok')::boolean,'fresh endorsement');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->'work_order'->>'status'='submitted','resubmitted');
  perform pg_temp.act(pg_temp.u(3));
  perform pg_temp.assert_true(public.transition_work_order(wo,'approve')->'work_order'->>'status'='assigned','approved');
  reset role;
end;$test$;

-- C. Actual times and endorsement before the review -----------------------------------
do $test$
declare r jsonb; wo uuid:=(select id from ids where name='wo'); path text;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true((public.set_facility_settings((select facility_id from f),pg_temp.u(3),'both','Endorse before submission and before the review')->>'ok')::boolean,'stage both');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true((public.transition_work_order(wo,'start')->>'ok')::boolean,'started');
  perform pg_temp.assert_true(public.set_work_order_actual_times(wo,null,null)->>'code'='VALIDATION_ERROR','start time required');
  perform pg_temp.assert_true(public.set_work_order_actual_times(wo,now()+interval '1 day',null)->>'code'='VALIDATION_ERROR','no future start');
  perform pg_temp.assert_true(public.set_work_order_actual_times(wo,now()-interval '1 hour',now()-interval '2 hours')->>'code'='VALIDATION_ERROR','end after start');
  perform pg_temp.assert_true((public.set_work_order_actual_times(wo,now()-interval '5 hours',null)->>'ok')::boolean,'start entered now, end later');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.set_work_order_actual_times(wo,now()-interval '5 hours',now())->>'code'='ACCESS_DENIED','only the assigned Technician records times');
  perform pg_temp.act(pg_temp.u(1));
  r:=public.record_work_order_execution(wo,'{"completion_notes":"Door sanded, primed and repainted.","actual_labour_hours":2}');
  r:=public.manage_work_order_actual_cost(wo,null,'{"operation":"confirm"}');
  reset role;
  path:='evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/after.jpg';
  insert into storage.objects(bucket_id,name) values('field-evidence',path);
  set local role authenticated;
  r:=public.register_evidence_item('work_order',wo,'after.jpg','image/jpeg',10,'after','After repaint',path);
  r:=public.submit_physical_completion(wo,'{"completion_notes":"Door sanded, primed and repainted.","actual_labour_hours":2}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='completed','work submitted without the end time: '||coalesce(r->>'code',''));
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.work_order_verification_readiness(wo)->'missing_requirements' @> '["Actual start and end times of the work","Second Technician endorsement"]','review readiness lists times and endorsement');
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{"note":"x"}')->>'code'='ACTUAL_TIMES_REQUIRED','review waits for the times');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true((public.set_work_order_actual_times(wo,now()-interval '5 hours',now()-interval '1 hour')->>'ok')::boolean,'end time filled in later');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{"note":"x"}')->>'code'='ENDORSEMENT_REQUIRED','review waits for the endorsement (the Draft endorsement does not count)');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true((public.endorse_work_order(wo,'Inspected the repainted door on site.')->>'ok')::boolean,'second Technician endorses before the review');
  perform pg_temp.act(pg_temp.u(4));
  r:=public.verify_completed_work(wo,'{"note":"Repaint verified."}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='reviewed','approved as Completed: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
  perform pg_temp.assert_true((select count(*) from public.work_order_copied_parties where work_order_id=wo and profile_id in (pg_temp.u(7),pg_temp.u(12)))=2,'every Finance user copied at Completed');
  perform pg_temp.assert_true((select count(*) from public.work_order_endorsements where work_order_id=wo)=3,'all endorsements kept as history');
  set local role authenticated; perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.set_work_order_actual_times(wo,now()-interval '5 hours',now()-interval '1 hour')->>'code' in ('INVALID_TRANSITION','ACCESS_DENIED'),'times locked after the review');
  reset role;
end;$test$;
rollback;

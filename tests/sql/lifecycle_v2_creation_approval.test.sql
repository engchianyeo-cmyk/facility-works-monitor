\set ON_ERROR_STOP on
-- WP-LC2-M2: creation, Draft quotation, submit, single approval, return, emergency start.
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
begin if value is not true then raise exception 'Lifecycle v2 creation/approval regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1c300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 tech A, 2 tech B, 3 approver, 4 supervisor, 5 facility manager, 6 administrator,
-- 7 finance, 8 initiator, 9 reviewer, 10 non-member approver, 11 copied party (reviewer)
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'lc2m2.'||n||'@example.test',jsonb_build_object('display_name','LC2 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.sites(id,code,name,is_active) values ('1c300000-0000-4000-8000-0000000000f2','LC2-OTHER','LC2 Other Facility',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(6) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3),pg_temp.u(4),pg_temp.u(5));
insert into public.vendors(id,name,trade,active) values ('1c300000-0000-4000-8000-0000000000e1','LC2 Contractor','Mechanical',true);
insert into public.vendor_facility_eligibility(vendor_id,facility_id,procurement_prequalified,facility_confirmed,confirmation_basis,active)
values ('1c300000-0000-4000-8000-0000000000e1',(select facility_id from f),true,true,'LC2 rollback-only test',true);
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert, update on ids to authenticated;

-- Quotation helper: preparer prepares a S$650 draft; the document is registered as postgres; the preparer submits it.
create function pg_temp.quote(wo uuid, preparer uuid, amount numeric) returns uuid language plpgsql as $$
declare r jsonb; qid uuid;
begin
  perform pg_temp.act(preparer); set local role authenticated;
  r:=public.prepare_work_order_proposal(wo,jsonb_build_object('vendor_id','1c300000-0000-4000-8000-0000000000e1','proposed_amount',amount,'scope_summary','LC2 repair scope'));
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

do $test$
declare r jsonb; wo uuid; wo2 uuid; wo3 uuid; em uuid; n int; v uuid;
begin
  set local role authenticated;
  -- A. Creation rules -------------------------------------------------------------
  foreach n in array array[7,8,9] loop
    perform pg_temp.act(pg_temp.u(n));
    perform pg_temp.assert_true(public.create_work_order('{"title":"Denied","location":"X"}')->>'code'='ACCESS_DENIED','role '||n||' cannot create');
  end loop;
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.create_work_order('{"title":"Wrong status","location":"X","status":"submitted"}')->>'code'='VALIDATION_ERROR','must be created as Draft');
  perform pg_temp.assert_true(public.create_work_order(jsonb_build_object('title','Other site','location','X','facility_id','1c300000-0000-4000-8000-0000000000f2'))->>'code'='ACCESS_DENIED','Technician cannot create at a non-member facility');
  r:=public.create_work_order(jsonb_build_object('title','Pump bearing noise','location','Plant room','facility_id',(select facility_id from f),'copied_party_ids',jsonb_build_array(pg_temp.u(11))));
  perform pg_temp.assert_true((r->>'ok')::boolean,'Technician creates Work Order');
  wo:=(r->'work_order'->>'id')::uuid; perform pg_temp.site(wo);
  perform pg_temp.assert_true(r->'work_order'->>'status'='draft' and (r->'work_order'->>'assigned_technician_id')::uuid=pg_temp.u(1),'Draft auto-assigned to creating Technician');
  perform pg_temp.assert_true(exists(select 1 from public.work_order_copied_parties where work_order_id=wo and profile_id=pg_temp.u(11)),'copied party recorded');

  -- B/C. Draft quotation and submit gates -----------------------------------------
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='JUSTIFICATION_REQUIRED','justification required');
  perform pg_temp.assert_true((public.update_work_order(wo,'{"description":"Bearing noise; vibration rising for two weeks."}')->>'ok')::boolean,'preparer edits Draft');
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='QUOTATION_REQUIRED','quotation required before submit');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.prepare_work_order_proposal(wo,'{"vendor_id":"1c300000-0000-4000-8000-0000000000e1","proposed_amount":1,"scope_summary":"x"}')->>'code'='ACCESS_DENIED','other Technician cannot prepare quotation');
  insert into ids values('wo',wo);
end;
$test$;
reset role;
select pg_temp.quote((select id from ids where name='wo'),pg_temp.u(1),650);

do $test$
declare r jsonb; wo uuid:=(select id from ids where name='wo'); wo2 uuid; n int;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='ACCESS_DENIED','other Technician cannot submit');
  perform pg_temp.act(pg_temp.u(1));
  r:=public.transition_work_order(wo,'submit');
  perform pg_temp.assert_true(r->'work_order'->>'status'='submitted','Technician submits with quotation: '||coalesce(r->>'code',''));
  reset role;
  perform pg_temp.assert_true((select count(*) from public.notification_outbox where work_order_id=wo and event_type='work_order_submitted_for_approval' and recipient_profile_id=pg_temp.u(11))=1,'copied party notified of submission');
  set local role authenticated;
  reset role;
  perform pg_temp.assert_true((select count(*) from public.notification_outbox where work_order_id=wo and event_type='work_order_submitted_for_approval' and recipient_profile_id=pg_temp.u(10))=0,'non-member Approver not notified');
  set local role authenticated;

  -- D. Approval ------------------------------------------------------------------
  perform pg_temp.assert_true(public.transition_work_order(wo,'approve')->>'code'='ACCESS_DENIED','Technician cannot approve');
  perform pg_temp.act(pg_temp.u(10));
  perform pg_temp.assert_true(public.transition_work_order(wo,'approve')->>'code'='ACCESS_DENIED','non-member Approver cannot approve');
  perform pg_temp.assert_true(public.transition_work_order(wo,'cancel','{"reason":"x"}')->>'code'='ACCESS_DENIED','non-member Approver cannot cancel');
  perform pg_temp.act(pg_temp.u(3));
  r:=public.transition_work_order(wo,'approve','{"note":"Approved within limit"}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'member Approver approves S$650: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  perform pg_temp.assert_true(r->'work_order'->>'status'='assigned' and r->'work_order'->>'accepted_at' is not null and r->'work_order'->>'approval_limit_version_id' is not null,'approved Work Order is Assigned, accepted, limit version pinned');
  reset role;
  perform pg_temp.assert_true((select status='approved' from public.contractor_quotations where work_order_id=wo and status='approved'),'quotation approved');
  set local role authenticated;
  reset role;
  perform pg_temp.assert_true((select approved_budget=650 and cost_status='approved' from public.work_order_financial_controls where work_order_id=wo),'budget approved at S$650');
  set local role authenticated;
  perform pg_temp.assert_true(public.transition_work_order(wo,'approve')->>'code'='NO_CHANGE','repeat approval is NO_CHANGE');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.transition_work_order(wo,'start')->'work_order'->>'status'='in_progress','Technician starts approved work');

  -- G. Superior-created Work Order: Technician required; creator cannot approve ------
  perform pg_temp.act(pg_temp.u(4));
  r:=public.create_work_order(jsonb_build_object('title','Chiller alarm','location','Roof','facility_id',(select facility_id from f),'description','Chiller high-pressure alarm repeatedly tripping.'));
  perform pg_temp.assert_true((r->>'ok')::boolean and r->'work_order'->>'assigned_technician_id' is null,'Supervisor creates when Technician unavailable');
  wo2:=(r->'work_order'->>'id')::uuid; insert into ids values('wo2',wo2); perform pg_temp.site(wo2);
  perform pg_temp.assert_true(public.transition_work_order(wo2,'submit')->>'code'='TECHNICIAN_REQUIRED','Technician must be assigned before submit');
  perform pg_temp.assert_true(public.set_work_order_technician(wo2,pg_temp.u(9))->>'code'='INACTIVE_REFERENCE','non-Technician cannot be assigned');
  perform pg_temp.assert_true((public.set_work_order_technician(wo2,pg_temp.u(2))->>'ok')::boolean,'Supervisor assigns Technician B');
end;
$test$;
reset role;
select pg_temp.quote((select id from ids where name='wo2'),pg_temp.u(4),650);

do $test$
declare r jsonb; wo2 uuid:=(select id from ids where name='wo2'); em uuid; v uuid;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.transition_work_order(wo2,'submit')->'work_order'->>'status'='submitted','creating Supervisor submits');
  perform pg_temp.assert_true(public.transition_work_order(wo2,'approve')->>'code'='SELF_APPROVAL_DENIED','creating Supervisor cannot approve');

  -- E. Return to Draft and resubmit -------------------------------------------------
  perform pg_temp.act(pg_temp.u(5));
  perform pg_temp.assert_true(public.transition_work_order(wo2,'return')->>'code'='VALIDATION_ERROR','return needs a reason');
  r:=public.transition_work_order(wo2,'return','{"reason":"Attach the isolation plan."}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='draft','Facility Manager returns to Draft');
  reset role;
  perform pg_temp.assert_true((select cost_status='returned' from public.work_order_financial_controls where work_order_id=wo2),'quotation returned for revision');
  set local role authenticated;

  -- F. Monetary limit applies (Administrator lowers Facility Manager limit to S$500).
  perform pg_temp.act(pg_temp.u(6));
  select version_id into v from public.work_order_approval_limit_policy;
  perform pg_temp.assert_true((public.change_work_order_approval_limits('{"approver":250000,"supervisor":250000,"facility_manager":500}','LC2 limit test',v)->>'ok')::boolean,'Administrator lowers FM limit');

  -- H. Emergency: start immediately, quotation follows ---------------------------------
  perform pg_temp.act(pg_temp.u(1));
  r:=public.create_work_order(jsonb_build_object('title','Burst pipe','location','Level 3 riser','facility_id',(select facility_id from f),'emergency_work',true,'description','Burst pipe flooding Level 3 corridor; isolate and repair now.'));
  em:=(r->'work_order'->>'id')::uuid; perform pg_temp.site(em);
  r:=public.transition_work_order(em,'submit','{"reason":"Active flooding"}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='in_progress' and (r->>'emergency')::boolean,'emergency starts immediately without quotation');
  reset role;
  perform pg_temp.assert_true((select count(*) from public.notification_outbox where work_order_id=em and event_type='work_order_emergency_started' and recipient_profile_id in (pg_temp.u(3),pg_temp.u(4),pg_temp.u(5),pg_temp.u(6)))=4,'approval authorities notified of emergency start');
  set local role authenticated;
  r:=public.prepare_work_order_proposal(em,'{"vendor_id":"1c300000-0000-4000-8000-0000000000e1","proposed_amount":880,"scope_summary":"After-the-fact emergency quotation"}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'emergency quotation prepared after work started');
  insert into ids values('em',em);
end;
$test$;
reset role;
-- Resubmit wo2 quotation (revision) and Work Order, then over-limit and in-limit approval.
do $resubmit$ declare qid uuid; begin
  select id into qid from public.contractor_quotations where work_order_id=(select id from ids where name='wo2') and status='returned';
  perform pg_temp.act(pg_temp.u(4)); set local role authenticated;
  perform pg_temp.assert_true((public.submit_work_order_proposal((select id from ids where name='wo2'),qid,'Revised with isolation plan')->>'ok')::boolean,'returned quotation resubmitted');
  perform pg_temp.assert_true(public.transition_work_order((select id from ids where name='wo2'),'submit')->'work_order'->>'status'='submitted','Work Order resubmitted');
  perform pg_temp.act(pg_temp.u(5));
  perform pg_temp.assert_true(public.transition_work_order((select id from ids where name='wo2'),'approve')->>'code'='APPROVAL_AUTHORITY_EXCEEDED','Facility Manager over lowered limit');
  perform pg_temp.act(pg_temp.u(3));
  perform pg_temp.assert_true((public.transition_work_order((select id from ids where name='wo2'),'approve')->>'ok')::boolean,'Approver approves within limit');
  perform pg_temp.assert_true((select accepted_at is null from public.work_orders where id=(select id from ids where name='wo2')),'assigned Technician still accepts superior-created work');
  reset role;
end;$resubmit$;
select pg_temp.assert_true((select count(*) from public.activity_logs where work_order_id in (select id from ids) and action in ('work_order_submit','work_order_approve','work_order_returned_to_draft','work_order_emergency_started'))>=5,'lifecycle actions audited');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.transition_work_order_20261020_core(uuid,text,jsonb)','EXECUTE'),'core transition not exposed');
rollback;

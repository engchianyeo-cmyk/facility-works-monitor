\set ON_ERROR_STOP on
-- WP-LC2-M3: review to Completed (limits, facility, independence), invoice, Finance, auto-close.
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
begin if value is not true then raise exception 'Lifecycle v2 review/finance regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1c400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 tech A, 2 tech B, 3 approver, 4 supervisor, 5 facility manager, 6 administrator,
-- 7 finance, 8 initiator, 9 reviewer, 10 non-member approver, 11 copied party (reviewer)
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'lc2m3.'||n||'@example.test',jsonb_build_object('display_name','LC2 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11),('finance',12)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11),('finance',12)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.sites(id,code,name,is_active) values ('1c400000-0000-4000-8000-0000000000f2','LC3-OTHER','LC2 Other Facility',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(6) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3),pg_temp.u(4),pg_temp.u(5));
insert into public.vendors(id,name,trade,active) values ('1c400000-0000-4000-8000-0000000000e1','LC2 Contractor','Mechanical',true);
insert into public.vendor_facility_eligibility(vendor_id,facility_id,procurement_prequalified,facility_confirmed,confirmation_basis,active)
values ('1c400000-0000-4000-8000-0000000000e1',(select facility_id from f),true,true,'LC2 rollback-only test',true);
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert, update on ids to authenticated;

-- Quotation helper: preparer prepares a S$650 draft; the document is registered as postgres; the preparer submits it.
create function pg_temp.quote(wo uuid, preparer uuid, amount numeric) returns uuid language plpgsql as $$
declare r jsonb; qid uuid;
begin
  perform pg_temp.act(preparer); set local role authenticated;
  r:=public.prepare_work_order_proposal(wo,jsonb_build_object('vendor_id','1c400000-0000-4000-8000-0000000000e1','proposed_amount',amount,'scope_summary','LC2 repair scope'));
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
insert into auth.users(id,email,raw_user_meta_data) values (pg_temp.u(13),'lc2m3.13@example.test','{"display_name":"LC2 other supervisor"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='supervisor',is_active=true,password_change_required=false where id=pg_temp.u(13);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values ('1c400000-0000-4000-8000-0000000000f2',pg_temp.u(13),'supervisor',pg_temp.u(6));

-- Drive a Work Order from approval to "submitted for review" as its Technician.
create function pg_temp.execute(wo uuid, tech uuid, cost numeric) returns void language plpgsql as $$
declare r jsonb; path text;
begin
  perform pg_temp.act(tech); set local role authenticated;
  if (select status from public.work_orders where id=wo)='assigned' then
    r:=public.transition_work_order(wo,'start'); perform pg_temp.assert_true((r->>'ok')::boolean,'start: '||coalesce(r->>'code',''));
  end if;
  r:=public.record_work_order_execution(wo,'{"completion_notes":"Replaced bearing and realigned coupling.","actual_labour_hours":3}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'record work: '||coalesce(r->>'code',''));
  r:=public.manage_work_order_actual_cost(wo,null,jsonb_build_object('cost_type','service','description','Contractor repair','unit','job','quantity',1,'unit_rate',cost));
  perform pg_temp.assert_true((r->>'ok')::boolean,'actual cost line: '||coalesce(r->>'code',''));
  r:=public.manage_work_order_actual_cost(wo,null,'{"operation":"confirm"}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'confirm costing: '||coalesce(r->>'code',''));
  reset role;
  path:='evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/after.jpg';
  insert into storage.objects(bucket_id,name) values('field-evidence',path);
  set local role authenticated;
  r:=public.register_evidence_item('work_order',wo,'after.jpg','image/jpeg',10,'after','After repair',path);
  perform pg_temp.assert_true((r->>'ok')::boolean,'After evidence: '||coalesce(r->>'code',''));
  -- D-11: the Technician enters the actual work times.
  r:=public.set_work_order_actual_times(wo,pg_catalog.now()-interval '3 hours',pg_catalog.now()-interval '1 hour');
  perform pg_temp.assert_true((r->>'ok')::boolean,'actual work times: '||coalesce(r->>'code',''));
  r:=public.submit_physical_completion(wo,'{"completion_notes":"Replaced bearing and realigned coupling.","actual_labour_hours":3}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='completed','submit for review: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
end;$$;

-- D-11/D-20: a second Technician endorses the work, final cost and any variation order before the review.
create function pg_temp.endorse(wo uuid) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform pg_temp.act(pg_temp.u(2)); set local role authenticated;
  r:=public.endorse_work_order(wo,'Checked on site: work and final cost as recorded.');
  reset role; return r;
end;$$;

-- D-08: the contractor's final quotation for the work actually performed (final-cost document).
create function pg_temp.final_doc(wo uuid) returns void language plpgsql security definer as $fd$
begin
  insert into public.work_order_final_cost_documents(final_cost_submission_id,work_order_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
  select fc.id,wo,(select assigned_technician_id from public.work_orders where id=wo),'final-quotation.pdf','application/pdf',100,'commercial/work-order/'||wo::text||'/final-quotation.pdf'
  from public.work_order_final_cost_submissions fc where fc.work_order_id=wo;
end;$fd$;
create function pg_temp.final_cost(wo uuid, tech uuid, amount numeric) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform pg_temp.act(tech); set local role authenticated;
  r:=public.save_work_order_final_cost(wo,jsonb_build_object('final_contractor_amount',amount,'comments','Final contractor account',
    'variation_order',amount is distinct from (select coalesce(c.approved_budget,c.quoted_cost) from public.work_order_financial_controls c where c.work_order_id=wo),
    'variation_justification','Contractor revised the final account'));
  reset role; return r;
end;$$;

-- Normal Work Order: create, quote S$650, approve, execute at S$620.
do $setup$ declare r jsonb; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.create_work_order(jsonb_build_object('title','Pump bearing','location','Plant room','facility_id',(select facility_id from f),
    'description','Pump bearing noise and rising vibration.','copied_party_ids',jsonb_build_array(pg_temp.u(11))));
  insert into ids values('wo',(r->'work_order'->>'id')::uuid); perform pg_temp.site((r->'work_order'->>'id')::uuid);
  reset role;
end;$setup$;
select pg_temp.quote((select id from ids where name='wo'),pg_temp.u(1),650);
do $approve$ begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  perform pg_temp.assert_true(public.transition_work_order((select id from ids where name='wo'),'submit')->'work_order'->>'status'='submitted','submitted');
  perform pg_temp.act(pg_temp.u(3));
  perform pg_temp.assert_true((public.transition_work_order((select id from ids where name='wo'),'approve')->>'ok')::boolean,'approved');
  reset role;
end;$approve$;
select pg_temp.execute((select id from ids where name='wo'),pg_temp.u(1),620);

do $test$
declare r jsonb; wo uuid:=(select id from ids where name='wo');
begin
  set local role authenticated;
  -- Review gates ---------------------------------------------------------------------
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{}')->>'code'='ENDORSEMENT_REQUIRED','review needs the endorsement, which waits for the final cost');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.endorse_work_order(wo,'Checked on site: work done as recorded.')->>'code'='FINAL_COST_REQUIRED','D-20 no endorsement before the final cost');
  perform pg_temp.assert_true(public.work_order_endorsement_status(wo)->'blocked'->>'code'='FINAL_COST_REQUIRED','D-20 status explains the wait');
  perform pg_temp.act(pg_temp.u(13));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{}')->>'code'='ACCESS_DENIED','other-facility Supervisor cannot review (facility gap closed)');
  perform pg_temp.act(pg_temp.u(10));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{}')->>'code'='ACCESS_DENIED','non-member Approver cannot review');
  perform pg_temp.act(pg_temp.u(12));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{}')->>'code'='ACCESS_DENIED','Finance cannot review');
  reset role;
end;$test$;
-- D-19: the Technician must state whether there was a variation order.
do $d19$
declare r jsonb; wo uuid:=(select id from ids where name='wo');
begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.save_work_order_final_cost(wo,'{"final_contractor_amount":650,"comments":"Final account"}');
  perform pg_temp.assert_true(r->>'code'='VARIATION_CONFIRMATION_REQUIRED','D-19 variation answer required: '||coalesce(r->>'code',''));
  r:=public.save_work_order_final_cost(wo,'{"final_contractor_amount":620,"comments":"Final account","variation_order":false}');
  perform pg_temp.assert_true(r->>'code'='PRICE_UNCHANGED_MISMATCH','D-19 unchanged price must equal the approved quotation: '||coalesce(r->>'code',''));
  r:=public.save_work_order_final_cost(wo,'{"final_contractor_amount":650,"comments":"Final account","variation_order":false}');
  perform pg_temp.assert_true((r->>'ok')::boolean and (r->'final_cost'->>'variation_order')::boolean = false,'D-19 price unchanged saved: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
  perform pg_temp.assert_true((select fc.final_quotation_id = q.id from public.work_order_final_cost_submissions fc
    join public.contractor_quotations q on q.work_order_id=fc.work_order_id and q.status='approved' where fc.work_order_id=wo),'D-19 approved quotation carried forward as the final quotation');
  perform pg_temp.assert_true(not public.work_order_final_quotation_missing(wo),'D-19 no revised quotation needed when the price is unchanged');
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.save_work_order_final_cost(wo,'{"final_contractor_amount":650,"comments":"Final account","variation_order":true}');
  perform pg_temp.assert_true(r->>'code'='VARIATION_JUSTIFICATION_REQUIRED','D-19 variation needs a justification: '||coalesce(r->>'code',''));
  r:=public.save_work_order_final_cost(wo,'{"final_contractor_amount":650,"comments":"Final account","variation_order":true,"variation_justification":"Extra gasket set found on site"}');
  reset role;
  perform pg_temp.assert_true((r->>'ok')::boolean and public.work_order_final_quotation_missing(wo),'D-19 variation order needs the revised quotation even at the same amount');
end;$d19$;
select pg_temp.assert_true((pg_temp.final_cost((select id from ids where name='wo'),pg_temp.u(1),620)->>'ok')::boolean,'Technician enters final cost S$620');

do $test$
declare r jsonb; wo uuid:=(select id from ids where name='wo'); path text; p jsonb;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{}')->>'code'='ACCESS_DENIED','Technician cannot review own work');
  -- The old transition 'review' path is routed to the v2 review (same rules).
  perform pg_temp.assert_true(public.transition_work_order(wo,'review','{}')->>'code'='ACCESS_DENIED','transition review routed to v2 review');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{"note":"x"}')->>'code'='ENDORSEMENT_REQUIRED','review needs the second Technician endorsement');
  perform pg_temp.assert_true(public.work_order_verification_readiness(wo)->'missing_requirements' @> '["Final quotation for the work actually performed (final cost differs from the approved quotation)"]','readiness lists the final quotation');
  reset role;
  r:=pg_temp.endorse(wo);
  perform pg_temp.assert_true(r->>'code'='FINAL_QUOTATION_REQUIRED','D-20 endorsement waits for the revised quotation: '||coalesce(r->>'code',''));
  perform pg_temp.final_doc(wo);
  r:=pg_temp.endorse(wo);
  perform pg_temp.assert_true((r->>'ok')::boolean and r->'endorsement'->>'final_cost_fingerprint' is not null,'D-20 second Technician endorses the final cost: '||coalesce(r->>'code',''));
  -- D-20: a change to the final cost after the endorsement cancels it.
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.save_work_order_final_cost(wo,'{"final_contractor_amount":620,"comments":"Final account","variation_order":true,"variation_justification":"Contractor reduced labour after site check"}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'Technician revises the justification: '||coalesce(r->>'code',''));
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true((public.work_order_endorsement_status(wo)->>'superseded')::boolean and (public.work_order_endorsement_status(wo)->>'due')::boolean,'D-20 endorsement superseded by the change');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{"note":"x"}')->>'code'='ENDORSEMENT_REQUIRED','D-20 review refused until re-endorsed');
  reset role;
  perform pg_temp.assert_true((pg_temp.endorse(wo)->>'ok')::boolean,'D-20 second Technician endorses again');
  -- D-21: a cost typed in by mistake is corrected while Submitted for Review, without Reject & Reopen.
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.manage_work_order_actual_cost(wo,(select c.id from public.work_order_cost_lines c where c.work_order_id=wo and c.cost_phase='actual' limit 1),
    '{"cost_type":"service","description":"Contractor repair","unit":"job","quantity":1020,"unit_rate":620}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'D-21 Technician corrects a cost line before the review: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
  perform pg_temp.assert_true((select status='draft' from public.work_order_final_cost_submissions where work_order_id=wo),'D-21 saved final cost reset by the correction');
  perform pg_temp.assert_true(public.work_order_endorsement_missing(wo,'review'),'D-21 endorsement no longer counts');
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.manage_work_order_actual_cost(wo,(select c.id from public.work_order_cost_lines c where c.work_order_id=wo and c.cost_phase='actual' limit 1),
    '{"cost_type":"service","description":"Contractor repair","unit":"job","quantity":1,"unit_rate":620}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'D-21 cost line back to S$620');
  perform pg_temp.assert_true((public.manage_work_order_actual_cost(wo,null,'{"operation":"confirm"}')->>'ok')::boolean,'D-21 costing confirmed again');
  r:=public.save_work_order_final_cost(wo,'{"final_contractor_amount":620,"comments":"Final account","variation_order":true,"variation_justification":"Contractor reduced labour after site check"}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'D-21 final cost saved again: '||coalesce(r->>'code',''));
  reset role;
  perform pg_temp.assert_true((pg_temp.endorse(wo)->>'ok')::boolean,'D-21 second Technician endorses the corrected cost');
  set local role authenticated; perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(not (public.work_order_verification_readiness(wo)->'missing_requirements' @> '["Final quotation for the work actually performed (final cost differs from the approved quotation)"]'),'final quotation attached');
  r:=public.verify_completed_work(wo,'{"note":"Work, cost and documents verified."}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='reviewed','Supervisor approves Completed: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  perform pg_temp.assert_true((r->'payment'->>'assessed_amount')::numeric=620 and r->'payment'->>'status'='approved_for_payment','approved payable S$620');
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{}')->>'code'='NO_CHANGE','repeat review is NO_CHANGE');
  perform pg_temp.act(pg_temp.u(1));
  r:=pg_temp.final_cost(wo,pg_temp.u(1),700); perform pg_temp.assert_true(r->>'code'='ACCESS_DENIED','final cost locked after review: '||coalesce(r::text,'null'));
  perform pg_temp.act(pg_temp.u(1));

  -- Invoice ------------------------------------------------------------------------------
  reset role;
  path:='commercial/work-order/'||wo::text||'/invoice-620.pdf';
  insert into storage.objects(bucket_id,name) values('field-evidence',path);
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.register_work_order_invoice(wo,path,'inv.pdf','application/pdf',100,'INV-1',620)->>'code'='ACCESS_DENIED','other Technician cannot upload invoice');
  perform pg_temp.act(pg_temp.u(12));
  perform pg_temp.assert_true(public.mark_work_order_invoice_received(wo)->>'code'='INVOICE_REQUIRED','Finance waits for the invoice');
  perform pg_temp.act(pg_temp.u(1));
  r:=public.register_work_order_invoice(wo,path,'inv.pdf','application/pdf',100,'INV-1',650);
  perform pg_temp.assert_true(r->>'code'='INVOICE_AMOUNT_MISMATCH','invoice must equal approved S$620, not the S$650 quotation');
  r:=public.register_work_order_invoice(wo,path,'inv.pdf','application/pdf',100,'INV-1',620);
  perform pg_temp.assert_true((r->>'ok')::boolean,'Technician uploads matching invoice');
  reset role;
  perform pg_temp.assert_true((select count(*) from public.notification_outbox where work_order_id=wo and event_type='work_order_invoice_uploaded' and recipient_profile_id in (pg_temp.u(7),pg_temp.u(12),pg_temp.u(11),pg_temp.u(4)))=4,'Finance users, copied party and reviewer notified of invoice');
  set local role authenticated;

  -- Finance -------------------------------------------------------------------------------
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(public.mark_work_order_invoice_received(wo)->>'code'='ACCESS_DENIED','Administrator cannot confirm invoice receipt');
  perform pg_temp.assert_true(public.record_work_order_finance_payment(wo,'{"paid_amount":620,"payment_reference":"PAY-1","payment_note":"x"}')->>'code'='ACCESS_DENIED','Administrator cannot record payment');
  perform pg_temp.act(pg_temp.u(12));
  perform pg_temp.assert_true(public.record_work_order_finance_payment(wo,'{"paid_amount":620,"payment_reference":"PAY-1","payment_note":"x"}')->>'code'='INVOICE_NOT_RECEIVED','payment needs invoice receipt');
  perform pg_temp.assert_true(public.mark_work_order_invoice_received(wo,((now() at time zone 'Asia/Singapore')::date+1))->>'code'='VALIDATION_ERROR','received date cannot be in the future');
  r:=public.mark_work_order_invoice_received(wo);
  perform pg_temp.assert_true((r->>'ok')::boolean and r->'payment'->>'payment_due_at' is not null,'Finance confirms receipt; due date set');
  perform pg_temp.assert_true(exists(select 1 from public.work_order_finance_tracker() t where t.work_order_id=wo and t.payment_status='invoice_received'),'tracker shows invoice received');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(not exists(select 1 from public.work_order_finance_tracker()),'tracker hidden from non-Finance roles');
  perform pg_temp.act(pg_temp.u(12));
  perform pg_temp.assert_true(public.record_work_order_finance_payment(wo,'{"paid_amount":650,"payment_reference":"PAY-1","payment_note":"x"}')->>'code'='PAYMENT_RECONCILIATION_REQUIRED','payment must equal approved amount');
  r:=public.record_work_order_finance_payment(wo,'{"paid_amount":620,"payment_reference":"PAY-1","payment_note":"Paid per terms"}');
  perform pg_temp.assert_true((r->>'ok')::boolean and (r->>'work_order_closed')::boolean,'Finance records payment; Work Order closes');
  perform pg_temp.assert_true((select status='closed' from public.work_orders where id=wo),'Work Order Closed');
  reset role;
end;$test$;

-- Over-limit review and Approver reject & reopen on a second Work Order (S$900, final S$1,200).
do $setup$ declare r jsonb; v uuid; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.create_work_order(jsonb_build_object('title','Valve leak','location','Riser','facility_id',(select facility_id from f),'description','Isolation valve leaking at gland.'));
  insert into ids values('wo2',(r->'work_order'->>'id')::uuid); perform pg_temp.site((r->'work_order'->>'id')::uuid);
  reset role;
end;$setup$;
select pg_temp.quote((select id from ids where name='wo2'),pg_temp.u(1),900);
do $t$ declare wo uuid:=(select id from ids where name='wo2'); r jsonb; v uuid; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->'work_order'->>'status'='submitted','wo2 submitted');
  perform pg_temp.act(pg_temp.u(5));
  perform pg_temp.assert_true((public.transition_work_order(wo,'approve')->>'ok')::boolean,'wo2 approved by FM');
  reset role;
end;$t$;
select pg_temp.execute((select id from ids where name='wo2'),pg_temp.u(1),1200);
select pg_temp.assert_true((pg_temp.final_cost((select id from ids where name='wo2'),pg_temp.u(1),1200)->>'final_cost')::jsonb->>'status'='variance_pending','final cost above approval is a variance');
select pg_temp.final_doc((select id from ids where name='wo2'));
select pg_temp.assert_true((pg_temp.endorse((select id from ids where name='wo2'))->>'ok')::boolean,'wo2 endorsed');
do $t$ declare wo uuid:=(select id from ids where name='wo2'); r jsonb; v uuid; begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(6));
  select version_id into v from public.work_order_approval_limit_policy;
  perform pg_temp.assert_true((public.change_work_order_approval_limits('{"approver":1000,"supervisor":250000,"facility_manager":500000}','LC2 review limit test',v)->>'ok')::boolean,'Administrator lowers Approver limit to S$1,000');
  perform pg_temp.act(pg_temp.u(3));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{}')->>'code'='VARIANCE_NOTE_REQUIRED','variance needs a note');
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{"note":"Additional seal kit required."}')->>'code'='APPROVAL_AUTHORITY_EXCEEDED','Approver over limit on final cost');
  r:=public.transition_work_order(wo,'return_for_rework','{"reason":"Attach photo of replaced seal."}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='in_progress','Approver rejects & reopens: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
end;$t$;

-- Emergency: review approves the after-the-fact quotation; no-payment closes automatically.
do $setup$ declare r jsonb; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.create_work_order(jsonb_build_object('title','Burst pipe','location','Level 3','facility_id',(select facility_id from f),'emergency_work',true,'description','Burst pipe flooding corridor; repair now.'));
  insert into ids values('em',(r->'work_order'->>'id')::uuid); perform pg_temp.site((r->'work_order'->>'id')::uuid);
  perform pg_temp.assert_true(public.transition_work_order((r->'work_order'->>'id')::uuid,'submit')->'work_order'->>'status'='in_progress','emergency started');
  reset role;
end;$setup$;
select pg_temp.execute((select id from ids where name='em'),pg_temp.u(1),880);
select pg_temp.assert_true((pg_temp.final_cost((select id from ids where name='em'),pg_temp.u(1),880)->>'ok')::boolean,'emergency final cost entered');
select pg_temp.assert_true((pg_temp.endorse((select id from ids where name='em'))->>'ok')::boolean,'em endorsed');
do $t$ declare wo uuid:=(select id from ids where name='em'); begin
  set local role authenticated; perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.verify_completed_work(wo,'{"note":"Emergency"}')->>'code'='QUOTATION_REQUIRED','emergency review needs the after-the-fact quotation');
  reset role;
end;$t$;
select pg_temp.quote((select id from ids where name='em'),pg_temp.u(1),880);
do $t$ declare wo uuid:=(select id from ids where name='em'); r jsonb; begin
  set local role authenticated; perform pg_temp.act(pg_temp.u(4));
  r:=public.verify_completed_work(wo,'{"note":"Emergency repair verified against contract rates."}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='reviewed','emergency reviewed to Completed: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
  perform pg_temp.assert_true((select cost_status='approved' and approved_budget=880 and financial_approved_by=pg_temp.u(4) from public.work_order_financial_controls where work_order_id=wo),'review approved the emergency quotation');
  -- Switch to a no-payment outcome (warranty) to exercise automatic closure.
  delete from public.contractor_payment_assessments where work_order_id=wo;
  set local role authenticated; perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true((public.propose_work_order_no_payment(wo,'warranty','Covered by contractor warranty.')->>'ok')::boolean,'Technician proposes no payment');
  perform pg_temp.act(pg_temp.u(10));
  perform pg_temp.assert_true(public.approve_work_order_no_payment(wo,'Approve')->>'code'='ACCESS_DENIED','non-member Approver cannot approve no-payment');
  perform pg_temp.act(pg_temp.u(5));
  perform pg_temp.assert_true((public.approve_work_order_no_payment(wo,'Warranty confirmed.')->>'ok')::boolean,'Facility Manager approves no payment');
  reset role;
  perform pg_temp.assert_true((select status='closed' from public.work_orders where id=wo),'approved no-payment closes the Completed Work Order');
end;$t$;
select pg_temp.assert_true(not has_function_privilege('authenticated','public.work_order_close_if_settled(uuid,uuid,text)','EXECUTE'),'close helper not exposed');
rollback;

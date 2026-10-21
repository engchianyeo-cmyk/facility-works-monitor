\set ON_ERROR_STOP on
begin;
create function pg_temp.actor_id(p_email text) returns uuid language sql stable security definer set search_path=pg_catalog as $$ select id from public.profiles where email=p_email $$;
-- Isolated, rollback-only financial state; no Preview identities or live records.
-- LC2: synthetic Finance identity (payment recording is Finance-only, D-03.2).
insert into auth.users(id,email,raw_user_meta_data) values('f1a00000-0000-4000-8000-000000000001','wp2a.finance@example.test','{"display_name":"WP2A Finance"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='finance',is_active=true,password_change_required=false where id='f1a00000-0000-4000-8000-000000000001';
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
update public.work_orders set assigned_technician_id=pg_temp.actor_id('pilot.technician@example.test'),
 status='reviewed',completed_at=now(),reviewed_at=now(),completion_notes='Synthetic physical work completed',actual_labour_hours=1.25,
 actual_costs_confirmed_at=now(),actual_costs_confirmed_by=pg_temp.actor_id('pilot.technician@example.test')
where id='08000000-0000-4000-8000-000000000012';
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select w.facility_id,p.id,p.role,pg_temp.actor_id('pilot.admin@example.test') from public.work_orders w cross join public.profiles p
where w.id='08000000-0000-4000-8000-000000000012' and p.email in ('pilot.technician@example.test','pilot.supervisor@example.test') on conflict do nothing;
insert into public.work_order_financial_controls(work_order_id,estimated_cost,quoted_cost,approved_budget,cost_status)
values('08000000-0000-4000-8000-000000000012',650,650,650,'approved');
insert into public.work_order_cost_lines(work_order_id,cost_type,description,quantity,unit,unit_rate,entered_by,cost_phase)
values('08000000-0000-4000-8000-000000000012','service','Synthetic repair',1,'job',620,pg_temp.actor_id('pilot.technician@example.test'),'actual');
insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,approved_by,approved_at,invoice_reference,invoice_amount,invoice_uploaded_at)
select id,assigned_vendor_id,'approved_for_payment',620,pg_temp.actor_id('pilot.supervisor@example.test'),now(),'INV-WP2A-620',620,now() from public.work_orders where id='08000000-0000-4000-8000-000000000012';
insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
values('work_order','08000000-0000-4000-8000-000000000012',pg_temp.actor_id('pilot.technician@example.test'),'after.jpg','image/jpeg',10,'after','evidence/work-order/08000000-0000-4000-8000-000000000012/aa000000-0000-4000-8000-000000000012/after.jpg');


create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $assert$
begin
  if not coalesce(p_condition,false) then
    raise exception 'WP-2A regression failed: %',p_message;
  end if;
end;
$assert$;

-- Release-gate identities are synthetic Release-1 actors. Every data mutation in this
-- regression is transaction-scoped and rolled back at the end.
select pg_temp.assert_true(
  exists(select 1 from public.work_orders where id='08000000-0000-4000-8000-000000000012' and work_order_number='WO-TEST-012'),
  'WO-TEST-012 fixture is required'
);
select pg_temp.assert_true(
  (select approved_budget from public.work_order_financial_controls where work_order_id='08000000-0000-4000-8000-000000000012')=650,
  'WO-TEST-012 approved quotation remains S$650'
);
select pg_temp.assert_true(
  (select sum(amount) from public.work_order_cost_lines where work_order_id='08000000-0000-4000-8000-000000000012' and cost_phase='actual')=620,
  'WO-TEST-012 actual cost ledger remains S$620'
);

savepoint payment_path;
select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor_id('pilot.admin@example.test'),'role','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('request.jwt.claims')::jsonb->>'sub',true);
set local role authenticated;
select pg_temp.assert_true(
  public.transition_work_order('08000000-0000-4000-8000-000000000012','close','{}'::jsonb)->>'code'='FINANCIAL_DISPOSITION_REQUIRED',
  'reviewed Work Order cannot close while payment is unresolved'
);
select pg_temp.assert_true(
  public.record_work_order_finance_payment('08000000-0000-4000-8000-000000000012','{"paid_amount":620,"payment_reference":"WP2A-ADMIN","payment_note":"Administrator attempt."}'::jsonb)->>'code'='ACCESS_DENIED',
  'Administrator cannot record payment; Finance only (D-03.2)'
);
select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub','f1a00000-0000-4000-8000-000000000001','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','f1a00000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(
  public.record_work_order_finance_payment('08000000-0000-4000-8000-000000000012','{"paid_amount":620,"payment_reference":"WP2A-EARLY","payment_note":"Before receipt."}'::jsonb)->>'code'='INVOICE_NOT_RECEIVED',
  'payment cannot be recorded before Finance receives the invoice'
);
select pg_temp.assert_true(
  (public.mark_work_order_invoice_received('08000000-0000-4000-8000-000000000012')->>'ok')::boolean,
  'Finance confirms invoice receipt'
);
reset role;
select pg_temp.assert_true(
  (select payment_due_at=invoice_received_at+make_interval(days=>v.payment_terms_days) from public.contractor_payment_assessments p join public.vendors v on v.id=p.vendor_id where p.work_order_id='08000000-0000-4000-8000-000000000012'),
  'payment due date = invoice received + contractor payment terms (D-05.3)'
);
set local role authenticated;
select pg_temp.assert_true(
  public.record_work_order_finance_payment('08000000-0000-4000-8000-000000000012','{"paid_amount":650,"payment_reference":"WP2A-WRONG","payment_note":"Must not pay quotation instead of actual."}'::jsonb)->>'code'='PAYMENT_RECONCILIATION_REQUIRED',
  'quotation amount cannot be recorded as payment when approved actual is S$620'
);
select pg_temp.assert_true(
  (public.record_work_order_finance_payment('08000000-0000-4000-8000-000000000012','{"paid_amount":620,"payment_reference":"WP2A-620","payment_note":"Rollback-only reconciliation test."}'::jsonb)->>'ok')::boolean,
  'recorded payment accepts the independently approved S$620 actual amount'
);
select pg_temp.assert_true(
  (select status='closed' from public.work_orders where id='08000000-0000-4000-8000-000000000012'),
  'recorded and reconciled payment closes the Completed Work Order automatically'
);
reset role;
rollback to payment_path;

-- Exercise physical completion with no final-cost submission or final invoice.
delete from public.work_order_commercial_documents where work_order_id='08000000-0000-4000-8000-000000000012' and document_type='invoice';
delete from public.contractor_payment_assessments where work_order_id='08000000-0000-4000-8000-000000000012';
delete from public.work_order_final_cost_documents where work_order_id='08000000-0000-4000-8000-000000000012';
delete from public.work_order_final_cost_submissions where work_order_id='08000000-0000-4000-8000-000000000012';
delete from public.work_order_financial_dispositions where work_order_id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('fmworks.status_transition','on',true);
update public.work_orders set status='in_progress',completed_at=null,reviewed_at=null,closed_at=null where id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('fmworks.status_transition','off',true);

select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor_id('pilot.technician@example.test'),'role','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('request.jwt.claims')::jsonb->>'sub',true);
set local role authenticated;
select pg_temp.assert_true(
  (public.submit_physical_completion('08000000-0000-4000-8000-000000000012','{}'::jsonb)->>'ok')::boolean,
  'assigned Technician can submit physical completion without a final invoice'
);
select pg_temp.assert_true(
  (select status='completed' and completed_at is not null from public.work_orders where id='08000000-0000-4000-8000-000000000012'),
  'physical completion records the completion state and timestamp'
);

-- An unauthorized Technician cannot approve the financial disposition they proposed.
select pg_temp.assert_true(
  (public.propose_work_order_no_payment('08000000-0000-4000-8000-000000000012','warranty','Covered by contractor warranty; no payment is due.')->>'ok')::boolean,
  'assigned Technician can propose a governed no-payment disposition'
);
select pg_temp.assert_true(
  public.approve_work_order_no_payment('08000000-0000-4000-8000-000000000012','Attempted self approval')->>'code'='ACCESS_DENIED',
  'Technician cannot approve their own no-payment disposition'
);

select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor_id('pilot.supervisor@example.test'),'role','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('request.jwt.claims')::jsonb->>'sub',true);
select pg_temp.assert_true(
  (public.approve_work_order_no_payment('08000000-0000-4000-8000-000000000012','Independent warranty disposition approval.')->>'ok')::boolean,
  'independent Supervisor can approve no payment required'
);
reset role;

-- Preserve the verified physical-completion history while advancing to reviewed for closure.
select pg_catalog.set_config('fmworks.status_transition','on',true);
update public.work_orders set status='reviewed',reviewed_at=pg_catalog.now() where id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('fmworks.status_transition','off',true);
select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor_id('pilot.admin@example.test'),'role','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('request.jwt.claims')::jsonb->>'sub',true);
set local role authenticated;
select pg_temp.assert_true(
  (public.work_order_closure_readiness('08000000-0000-4000-8000-000000000012')->>'ready')::boolean,
  'approved no-payment disposition permits closure without fabricated payment'
);
select pg_temp.assert_true(
  (public.transition_work_order('08000000-0000-4000-8000-000000000012','close','{}'::jsonb)->>'ok')::boolean,
  'authorized no-payment disposition permits governed closure'
);
reset role;

-- Reconcile actual cost independently of the S$650 quotation (LC2: before the review), then the
-- single review approves work + final cost and creates the S$620 payable; the invoice follows.
select pg_catalog.set_config('fmworks.admin_correction','on',true);
update public.work_orders set status='completed',closed_at=null,reviewed_at=null where id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('fmworks.admin_correction','off',true);
delete from public.work_order_financial_dispositions where work_order_id='08000000-0000-4000-8000-000000000012';
delete from public.contractor_payment_assessments where work_order_id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor_id('pilot.technician@example.test'),'role','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('request.jwt.claims')::jsonb->>'sub',true);
set local role authenticated;
select pg_temp.assert_true(
  (public.save_work_order_final_cost('08000000-0000-4000-8000-000000000012','{"final_contractor_amount":620,"confirmed_actual_cost":620,"comments":"Reconciled rollback-only test."}'::jsonb)->'final_cost'->>'confirmed_actual_cost')::numeric=620,
  'final-cost snapshot derives S$620 actual rather than adding the S$650 quotation'
);
select pg_temp.assert_true(
  public.verify_completed_work('08000000-0000-4000-8000-000000000012','{}'::jsonb)->>'code'='ACCESS_DENIED',
  'Technician cannot review their own work'
);
-- D-08: S$620 differs from the S$650 quotation, so the contractor's final quotation must be attached.
reset role;
insert into public.work_order_final_cost_documents(final_cost_submission_id,work_order_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
select fc.id,w.id,w.assigned_technician_id,'final-quotation.pdf','application/pdf',100,'commercial/work-order/'||w.id::text||'/final-quotation-d08.pdf'
from public.work_orders w join public.work_order_final_cost_submissions fc on fc.work_order_id=w.id where w.id='08000000-0000-4000-8000-000000000012';
set local role authenticated;
select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor_id('pilot.supervisor@example.test'),'role','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('request.jwt.claims')::jsonb->>'sub',true);
select pg_temp.assert_true(
  ((public.verify_completed_work('08000000-0000-4000-8000-000000000012','{"note":"Work, S$620 cost and documents verified."}'::jsonb)->'payment'->>'assessed_amount')::numeric)=620,
  'review to Completed approves the S$620 actual (not the S$650 quotation) as the payable'
);
reset role;
select pg_temp.assert_true(
  (select status='approved_for_payment' and invoice_received_at is null and payment_due_at is null from public.contractor_payment_assessments where work_order_id='08000000-0000-4000-8000-000000000012'),
  'payable awaits invoice; payment terms not started at completion (D-05.3)'
);
select pg_temp.assert_true(
  (select status='reviewed' from public.work_orders where id='08000000-0000-4000-8000-000000000012'),
  'Work Order is Completed after review'
);
select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub','f1a00000-0000-4000-8000-000000000001','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','f1a00000-0000-4000-8000-000000000001',true);
set local role authenticated;
select pg_temp.assert_true(
  public.mark_work_order_invoice_received('08000000-0000-4000-8000-000000000012')->>'code'='INVOICE_REQUIRED',
  'Finance cannot confirm receipt before the Technician uploads the invoice'
);
reset role;

rollback;

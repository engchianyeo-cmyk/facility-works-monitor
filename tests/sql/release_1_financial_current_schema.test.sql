\set ON_ERROR_STOP on
begin;
create function pg_temp.actor_id(p_email text) returns uuid language sql stable security definer set search_path=pg_catalog as $$ select id from public.profiles where email=p_email $$;
-- Isolated, rollback-only financial state; no Preview identities or live records.
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
insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,approved_by,approved_at)
select id,assigned_vendor_id,'approved_for_payment',620,pg_temp.actor_id('pilot.supervisor@example.test'),now() from public.work_orders where id='08000000-0000-4000-8000-000000000012';
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
  public.record_work_order_finance_payment('08000000-0000-4000-8000-000000000012','{"paid_amount":650,"payment_reference":"WP2A-WRONG","payment_note":"Must not pay quotation instead of actual."}'::jsonb)->>'code'='PAYMENT_RECONCILIATION_REQUIRED',
  'quotation amount cannot be recorded as payment when approved actual is S$620'
);
select pg_temp.assert_true(
  (public.record_work_order_finance_payment('08000000-0000-4000-8000-000000000012','{"paid_amount":620,"payment_reference":"WP2A-620","payment_note":"Rollback-only reconciliation test."}'::jsonb)->>'ok')::boolean,
  'recorded payment accepts the independently approved S$620 actual amount'
);
select pg_temp.assert_true(
  (public.work_order_closure_readiness('08000000-0000-4000-8000-000000000012')->>'ready')::boolean,
  'recorded and reconciled payment makes closure ready'
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

-- Reconcile actual cost independently of the S$650 quotation and retain the later invoice gate.
select pg_catalog.set_config('fmworks.admin_correction','on',true);
update public.work_orders set status='reviewed',closed_at=null,reviewed_at=pg_catalog.now() where id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('fmworks.admin_correction','off',true);
delete from public.work_order_financial_dispositions where work_order_id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.actor_id('pilot.technician@example.test'),'role','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('request.jwt.claims')::jsonb->>'sub',true);
set local role authenticated;
select pg_temp.assert_true(
  (public.save_work_order_final_cost('08000000-0000-4000-8000-000000000012','{"final_contractor_amount":620,"confirmed_actual_cost":620,"comments":"Reconciled rollback-only test."}'::jsonb)->'final_cost'->>'confirmed_actual_cost')::numeric=620,
  'final-cost snapshot derives S$620 actual rather than adding the S$650 quotation'
);
select pg_temp.assert_true(
  (public.save_work_order_payment_proposal('08000000-0000-4000-8000-000000000012','{"recommendation_note":"Pay reconciled actual only."}'::jsonb)->'payment'->>'assessed_amount')::numeric=620,
  'payment proposal is S$620'
);
select pg_temp.assert_true(
  public.submit_work_order_payment_proposal('08000000-0000-4000-8000-000000000012',null)->>'code'='INVOICE_REQUIRED',
  'missing invoice remains blocked at payment-proposal submission'
);
reset role;

rollback;

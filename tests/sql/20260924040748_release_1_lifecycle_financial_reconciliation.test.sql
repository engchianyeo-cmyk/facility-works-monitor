begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $assert$
begin
  if not coalesce(p_condition,false) then
    raise exception 'WP-2A regression failed: %',p_message;
  end if;
end;
$assert$;

-- Preview fixture identities are synthetic Release-1 actors. Every data mutation in this
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
select pg_catalog.set_config('request.jwt.claims','{"sub":"4a8bf9d9-d7f0-482b-8b1c-1d76897bdd50","role":"authenticated"}',true);
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

select pg_catalog.set_config('request.jwt.claims','{"sub":"f2007b69-cc4c-40b5-9be1-7678450eb83a","role":"authenticated"}',true);
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

select pg_catalog.set_config('request.jwt.claims','{"sub":"826e5c86-8734-4ae6-9e25-e72d8c7f23d5","role":"authenticated"}',true);
select pg_temp.assert_true(
  (public.approve_work_order_no_payment('08000000-0000-4000-8000-000000000012','Independent warranty disposition approval.')->>'ok')::boolean,
  'independent Approver can approve no payment required'
);
reset role;

-- Preserve the verified physical-completion history while advancing to reviewed for closure.
select pg_catalog.set_config('fmworks.status_transition','on',true);
update public.work_orders set status='reviewed',reviewed_at=pg_catalog.now() where id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('fmworks.status_transition','off',true);
select pg_catalog.set_config('request.jwt.claims','{"sub":"4a8bf9d9-d7f0-482b-8b1c-1d76897bdd50","role":"authenticated"}',true);
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
select pg_catalog.set_config('request.jwt.claims','{"sub":"f2007b69-cc4c-40b5-9be1-7678450eb83a","role":"authenticated"}',true);
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

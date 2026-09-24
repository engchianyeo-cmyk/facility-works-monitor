-- WP-2A: separate physical completion, financial reconciliation, payment and closure.
begin;

create table public.work_order_financial_dispositions (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null unique references public.work_orders(id) on delete restrict,
  disposition_type text not null check (disposition_type = 'no_payment_required'),
  reason_code text not null check (reason_code in ('in_house','warranty','goodwill','zero_cost','other')),
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  status text not null default 'proposed' check (status in ('proposed','approved','rejected')),
  proposed_by uuid not null references public.profiles(id) on delete restrict,
  proposed_at timestamptz not null default now(),
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  approval_note text,
  updated_at timestamptz not null default now(),
  check (approved_by is null or approved_by is distinct from proposed_by),
  check (
    (status = 'approved' and approved_by is not null and approved_at is not null and approval_note is not null)
    or (status <> 'approved' and approved_by is null and approved_at is null)
  )
);

alter table public.work_order_financial_dispositions enable row level security;
revoke all on public.work_order_financial_dispositions from public, anon, authenticated;
grant select on public.work_order_financial_dispositions to authenticated;
create policy work_order_financial_dispositions_read
on public.work_order_financial_dispositions for select to authenticated
using (exists(select 1 from public.work_orders w where w.id=work_order_id));

create or replace function public.work_order_financial_documentation_readiness(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; final_cost public.work_order_final_cost_submissions%rowtype;
  payment public.contractor_payment_assessments%rowtype; invoice_present boolean:=false; final_invoice_present boolean:=false;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  select * into final_cost from public.work_order_final_cost_submissions where work_order_id=w.id;
  select * into payment from public.contractor_payment_assessments where work_order_id=w.id;
  if final_cost.id is not null then
    select exists(select 1 from public.work_order_final_cost_documents d where d.final_cost_submission_id=final_cost.id and d.deleted_at is null) into final_invoice_present;
  end if;
  if payment.id is not null then
    select exists(select 1 from public.work_order_commercial_documents d where d.payment_assessment_id=payment.id and d.document_type='invoice' and d.deleted_at is null) into invoice_present;
  end if;
  return pg_catalog.jsonb_build_object(
    'ok',true,'physical_completion_status',w.status,
    'actual_costs_confirmed',w.actual_costs_confirmed_at is not null,
    'final_cost_status',final_cost.status,'final_invoice_present',final_invoice_present,
    'payment_status',payment.status,'payment_invoice_present',invoice_present,
    'payment_proposal_ready',w.status in ('reviewed','closed') and final_cost.status in ('confirmed','variance_approved') and invoice_present
  );
end;$function$;

create or replace function public.work_order_closure_readiness(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; payment public.contractor_payment_assessments%rowtype;
  disposition public.work_order_financial_dispositions%rowtype; resolved boolean:=false; resolution text; missing text[]:=array[]::text[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  select * into payment from public.contractor_payment_assessments where work_order_id=w.id;
  select * into disposition from public.work_order_financial_dispositions where work_order_id=w.id;
  if payment.status='paid' and payment.paid_at is not null and payment.paid_amount=payment.assessed_amount then resolved:=true; resolution:='paid';
  elsif disposition.status='approved' and disposition.disposition_type='no_payment_required' then resolved:=true; resolution:='no_payment_required'; end if;
  if w.status<>'reviewed' then missing:=array_append(missing,'verified_completion'); end if;
  if not resolved then missing:=array_append(missing,'resolved_financial_disposition'); end if;
  return pg_catalog.jsonb_build_object('ok',true,'ready',w.status='reviewed' and resolved,'work_order_status',w.status,
    'resolution',resolution,'payment_status',payment.status,'no_payment_status',disposition.status,'missing_requirements',pg_catalog.to_jsonb(missing));
end;$function$;

create or replace function public.propose_work_order_no_payment(p_work_order_id uuid,p_reason_code text,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_financial_dispositions%rowtype;
  code text:=pg_catalog.lower(coalesce(p_reason_code,'')); reason_text text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may propose no payment.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational financial disposition authority is required.'); end if;
  if w.status not in ('completed','reviewed') then return public.work_order_result_error('INVALID_TRANSITION','No-payment disposition is available after physical completion.'); end if;
  if code not in ('in_house','warranty','goodwill','zero_cost','other') or reason_text is null or length(reason_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A valid no-payment reason and bounded explanation are required.'); end if;
  if exists(select 1 from public.contractor_payment_assessments p where p.work_order_id=w.id and p.status<>'returned') then return public.work_order_result_error('PAYMENT_ALREADY_RECORDED','An active or recorded payment process must be returned before no payment required can be proposed.'); end if;
  insert into public.work_order_financial_dispositions(work_order_id,disposition_type,reason_code,reason,status,proposed_by)
  values(w.id,'no_payment_required',code,reason_text,'proposed',actor_id)
  on conflict(work_order_id) do update set disposition_type='no_payment_required',reason_code=excluded.reason_code,reason=excluded.reason,status='proposed',proposed_by=actor_id,proposed_at=pg_catalog.now(),approved_by=null,approved_at=null,approval_note=null,updated_at=pg_catalog.now()
  returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_no_payment_proposed',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('disposition_id',result.id,'reason_code',code,'reason',reason_text,'proposed_by',actor_id)::text);
  return pg_catalog.jsonb_build_object('ok',true,'disposition',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.approve_work_order_no_payment(p_work_order_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_financial_dispositions%rowtype;
  note_text text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent no-payment approval authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  select * into result from public.work_order_financial_dispositions where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Proposed no-payment disposition was not found.'); end if;
  if result.status<>'proposed' then return public.work_order_result_error('INVALID_TRANSITION','Only a proposed no-payment disposition may be approved.'); end if;
  if result.proposed_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The proposer cannot approve their own no-payment disposition.'); end if;
  if exists(select 1 from public.contractor_payment_assessments p where p.work_order_id=w.id and p.status<>'returned') then return public.work_order_result_error('PAYMENT_ALREADY_RECORDED','No payment required cannot be approved while a payment process is active or recorded.'); end if;
  if note_text is null or length(note_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A bounded independent approval note is required.'); end if;
  update public.work_order_financial_dispositions set status='approved',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=note_text,updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_no_payment_independently_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('disposition_id',result.id,'reason_code',result.reason_code,'proposed_by',result.proposed_by,'approved_by',actor_id,'self_approval',false,'approval_note',note_text)::text);
  return pg_catalog.jsonb_build_object('ok',true,'disposition',pg_catalog.to_jsonb(result));
end;$function$;

-- Physical completion remains an operational event. Execution cost-line confirmation is
-- required, but final reconciliation, invoice receipt and variance approval may follow later.
create or replace function public.submit_physical_completion(p_work_order_id uuid,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.actual_costs_confirmed_at is null or w.actual_costs_confirmed_by is distinct from (actor->>'id')::uuid then
    return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Confirm the execution cost ledger, including a genuine zero-cost result, before physical completion.');
  end if;
  return public.submit_physical_completion_20260921_core(p_work_order_id,p_payload);
end;$function$;

-- The final-cost submission is the authoritative reconciliation snapshot. Labour comes from
-- physical completion and total actual expenditure is derived from actual cost lines.
create or replace function public.save_work_order_final_cost(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_final_cost_submissions%rowtype;
  contractor numeric; derived_actual numeric; claimed_actual numeric; approved numeric; note text; next_status text; payment_status text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or w.status not in ('assigned','in_progress','completed','reviewed') or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may reconcile final costs before closure.'); end if;
  if w.actual_costs_confirmed_at is null or w.actual_labour_hours is null then return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Physical labour and the execution cost ledger must be confirmed before final reconciliation.'); end if;
  select p.status into payment_status from public.contractor_payment_assessments p where p.work_order_id=w.id;
  if payment_status in ('awaiting_approval','approved_for_payment','paid') then return public.work_order_result_error('FINANCIAL_RECORD_IMMUTABLE','Final cost cannot change after the payment proposal is submitted.'); end if;
  begin contractor:=(p_payload->>'final_contractor_amount')::numeric; claimed_actual:=nullif(p_payload->>'confirmed_actual_cost','')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Final contractor amount or claimed actual cost is invalid.'); end;
  select coalesce(pg_catalog.sum(c.amount),0) into derived_actual from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
  note:=nullif(pg_catalog.btrim(coalesce(p_payload->>'comments','')),'');
  if contractor is null or contractor<0 or note is null or length(note)>2000 then return public.work_order_result_error('VALIDATION_ERROR','Final contractor amount and comments are required.'); end if;
  if claimed_actual is not null and claimed_actual<>derived_actual then return public.work_order_result_error('ACTUAL_COST_MISMATCH','Confirmed actual cost must equal the execution cost ledger total.'); end if;
  select approved_budget into approved from public.work_order_financial_controls where work_order_id=w.id;
  next_status:=case when derived_actual>coalesce(approved,0) then 'variance_pending' else 'confirmed' end;
  insert into public.work_order_final_cost_submissions(work_order_id,status,actual_labour_hours,final_contractor_amount,confirmed_actual_cost,comments,submitted_by,submitted_at)
  values(w.id,next_status,w.actual_labour_hours,contractor,derived_actual,note,actor_id,pg_catalog.now())
  on conflict(work_order_id) do update set status=excluded.status,actual_labour_hours=excluded.actual_labour_hours,final_contractor_amount=excluded.final_contractor_amount,confirmed_actual_cost=excluded.confirmed_actual_cost,comments=excluded.comments,submitted_by=excluded.submitted_by,submitted_at=excluded.submitted_at,variance_approved_by=null,variance_approved_at=null,variance_approval_note=null,updated_at=pg_catalog.now() returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_cost_reconciled',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('submission_id',result.id,'approved_quotation',approved,'actual_contractor_charge',contractor,'actual_repair_cost',derived_actual,'actual_labour_hours',w.actual_labour_hours,'variance',derived_actual-coalesce(approved,0),'quotation_excluded_from_actual_total',true,'status',next_status)::text);
  return pg_catalog.jsonb_build_object('ok',true,'final_cost',pg_catalog.to_jsonb(result),'approved_quotation',approved,'actual_repair_cost',derived_actual,'variance',derived_actual-coalesce(approved,0));
end;$function$;

create or replace function public.save_work_order_payment_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; final_cost public.work_order_final_cost_submissions%rowtype;
  result public.contractor_payment_assessments%rowtype; note_text text; invoice_ref text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into final_cost from public.work_order_final_cost_submissions where work_order_id=p_work_order_id;
  if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','An assigned contractor record is required.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare the final account.'); end if;
  if w.status not in ('reviewed','closed') or w.reviewed_at is null then return public.work_order_result_error('APPROVAL_NOT_READY','Verified completion is required before preparing the final account.'); end if;
  if final_cost.id is null or final_cost.status not in ('confirmed','variance_approved') then return public.work_order_result_error('FINAL_COST_REQUIRED','A reconciled final cost and any required variance approval are required.'); end if;
  if exists(select 1 from public.work_order_financial_dispositions d where d.work_order_id=w.id and d.status in ('proposed','approved')) then return public.work_order_result_error('FINANCIAL_DISPOSITION_REQUIRED','Return or reject the no-payment disposition before preparing a payment proposal.'); end if;
  note_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'recommendation_note','')),''); invoice_ref:=nullif(pg_catalog.btrim(coalesce(p_payload->>'invoice_reference','')),'');
  if note_text is null or length(note_text)>1000 or coalesce(length(invoice_ref),0)>120 then return public.work_order_result_error('VALIDATION_ERROR','A bounded payment recommendation note is required.'); end if;
  insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,invoice_reference,recommendation_note,payment_term_started_at,payment_due_at)
  values(w.id,w.assigned_vendor_id,'draft',final_cost.confirmed_actual_cost,w.reviewed_at,invoice_ref,note_text,w.reviewed_at,w.reviewed_at+interval '30 days')
  on conflict(work_order_id) do update set status='draft',vendor_id=excluded.vendor_id,assessed_amount=excluded.assessed_amount,completed_work_accepted_at=excluded.completed_work_accepted_at,invoice_reference=excluded.invoice_reference,recommendation_note=excluded.recommendation_note,payment_term_started_at=excluded.payment_term_started_at,payment_due_at=excluded.payment_due_at,recommended_by=null,recommended_at=null,approved_by=null,approved_at=null,approval_note=null,completion_notified_at=null,paid_at=null,paid_amount=null,payment_reference=null,paid_by=null,payment_note=null,updated_at=pg_catalog.now() returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_final_account_draft_saved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_quotation',(select approved_budget from public.work_order_financial_controls where work_order_id=w.id),'actual_repair_cost',final_cost.confirmed_actual_cost,'recommended_payment',result.assessed_amount,'quotation_excluded_from_payment_total',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.register_work_order_final_cost_document(p_work_order_id uuid,p_submission_id uuid,p_original_filename text,p_content_type text,p_byte_size bigint,p_storage_path text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; submission public.work_order_final_cost_submissions%rowtype; result public.work_order_final_cost_documents%rowtype; old_ids uuid[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into submission from public.work_order_final_cost_submissions where id=p_submission_id and work_order_id=p_work_order_id;
  if w.id is null or submission.id is null then return public.work_order_result_error('NOT_FOUND','Final-cost submission was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) or w.status not in ('assigned','in_progress','completed','reviewed') then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may attach a final invoice before closure.'); end if;
  if exists(select 1 from public.contractor_payment_assessments p where p.work_order_id=w.id and p.status in ('awaiting_approval','approved_for_payment','paid')) then return public.work_order_result_error('FINANCIAL_RECORD_IMMUTABLE','Final-cost documents cannot change after the payment proposal is submitted.'); end if;
  if p_content_type not in ('image/jpeg','image/png','image/webp','application/pdf') or p_byte_size not between 1 and 10485760 or p_storage_path not like 'commercial/work-order/'||w.id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return public.work_order_result_error('INVALID_STORAGE_OBJECT','Final invoice storage could not be verified.'); end if;
  select pg_catalog.array_agg(id) into old_ids from public.work_order_final_cost_documents where final_cost_submission_id=submission.id and deleted_at is null;
  insert into public.work_order_final_cost_documents(final_cost_submission_id,work_order_id,uploaded_by,original_filename,content_type,byte_size,storage_path) values(submission.id,w.id,actor_id,p_original_filename,p_content_type,p_byte_size,p_storage_path) returning * into result;
  if old_ids is not null then update public.work_order_final_cost_documents set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason='Replaced by a controlled financial-document revision',superseded_by=result.id where id=any(old_ids); end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_invoice_attached',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',result.id,'submission_id',submission.id,'filename',result.original_filename,'physical_completion_timestamp_unchanged',true,'replaced_document_ids',coalesce(pg_catalog.to_jsonb(old_ids),'[]'::jsonb))::text);
  return pg_catalog.jsonb_build_object('ok',true,'document',pg_catalog.to_jsonb(result)-'storage_path');
end;$function$;

create or replace function public.record_work_order_finance_payment(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype; amount numeric; reference text; note_text text; paid_time timestamptz;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  if actor->>'role'<>'administrator' then return public.work_order_result_error('ACCESS_DENIED','Finance payment recording is restricted to an Administrator.'); end if;
  select * into w from public.work_orders where id=p_work_order_id; select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Approved payment proposal was not found.'); end if;
  if result.status<>'approved_for_payment' then return public.work_order_result_error('INVALID_TRANSITION','Independent payment approval is required before Finance records payment.'); end if;
  if result.approved_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The payment approver cannot also record the Finance payment.'); end if;
  begin amount:=(p_payload->>'paid_amount')::numeric; paid_time:=coalesce(nullif(p_payload->>'paid_at','')::timestamptz,pg_catalog.now()); exception when others then return public.work_order_result_error('VALIDATION_ERROR','Paid amount or payment date is invalid.'); end;
  reference:=nullif(pg_catalog.btrim(coalesce(p_payload->>'payment_reference','')),''); note_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'payment_note','')),'');
  if amount is null or amount<>result.assessed_amount or reference is null or note_text is null then return public.work_order_result_error('PAYMENT_RECONCILIATION_REQUIRED','Recorded payment must equal the independently approved payment proposal and include a reference and Finance note.'); end if;
  update public.contractor_payment_assessments set status='paid',paid_amount=amount,payment_reference=reference,paid_by=actor_id,paid_at=paid_time,payment_note=note_text,updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_payment_recorded_by_finance',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_payment',result.assessed_amount,'paid_amount',result.paid_amount,'payment_reference',result.payment_reference,'paid_at',result.paid_at,'reconciled',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$;

alter function public.transition_work_order(uuid,text,jsonb) rename to transition_work_order_20260924_core;
create or replace function public.transition_work_order(p_work_order_id uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare action text:=pg_catalog.lower(coalesce(p_action,'')); readiness jsonb;
begin
  if action<>'close' then return public.transition_work_order_20260924_core(p_work_order_id,p_action,p_payload); end if;
  readiness:=public.work_order_closure_readiness(p_work_order_id);
  if not coalesce((readiness->>'ready')::boolean,false) then return public.work_order_result_error('FINANCIAL_DISPOSITION_REQUIRED','Payment must be recorded or an independent no-payment-required disposition must be approved before closure.'); end if;
  return public.transition_work_order_20260924_core(p_work_order_id,p_action,p_payload);
end;$function$;

revoke all on function public.work_order_financial_documentation_readiness(uuid),public.work_order_closure_readiness(uuid),public.propose_work_order_no_payment(uuid,text,text),public.approve_work_order_no_payment(uuid,text),public.submit_physical_completion(uuid,jsonb),public.save_work_order_final_cost(uuid,jsonb),public.save_work_order_payment_proposal(uuid,jsonb),public.register_work_order_final_cost_document(uuid,uuid,text,text,bigint,text),public.record_work_order_finance_payment(uuid,jsonb),public.transition_work_order(uuid,text,jsonb),public.transition_work_order_20260924_core(uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.work_order_financial_documentation_readiness(uuid),public.work_order_closure_readiness(uuid),public.propose_work_order_no_payment(uuid,text,text),public.approve_work_order_no_payment(uuid,text),public.submit_physical_completion(uuid,jsonb),public.save_work_order_final_cost(uuid,jsonb),public.save_work_order_payment_proposal(uuid,jsonb),public.register_work_order_final_cost_document(uuid,uuid,text,text,bigint,text),public.record_work_order_finance_payment(uuid,jsonb),public.transition_work_order(uuid,text,jsonb) to authenticated;

do $postconditions$
declare object_name text; config text[];
begin
  foreach object_name in array array[
    'public.work_order_financial_documentation_readiness(uuid)','public.work_order_closure_readiness(uuid)',
    'public.propose_work_order_no_payment(uuid,text,text)','public.approve_work_order_no_payment(uuid,text)',
    'public.submit_physical_completion(uuid,jsonb)','public.save_work_order_final_cost(uuid,jsonb)',
    'public.save_work_order_payment_proposal(uuid,jsonb)','public.register_work_order_final_cost_document(uuid,uuid,text,text,bigint,text)','public.record_work_order_finance_payment(uuid,jsonb)',
    'public.transition_work_order(uuid,text,jsonb)'
  ] loop
    select p.proconfig into config from pg_catalog.pg_proc p where p.oid=object_name::regprocedure and p.prosecdef;
    if config is null or config<>array['search_path=pg_catalog'] then raise exception 'WP-2A function security postcondition failed: %',object_name; end if;
    if not pg_catalog.has_function_privilege('authenticated',object_name,'EXECUTE') or pg_catalog.has_function_privilege('anon',object_name,'EXECUTE') or pg_catalog.has_function_privilege('service_role',object_name,'EXECUTE') then raise exception 'WP-2A function grant postcondition failed: %',object_name; end if;
  end loop;
  if pg_catalog.has_function_privilege('authenticated','public.transition_work_order_20260924_core(uuid,text,jsonb)','EXECUTE') then raise exception 'WP-2A core transition must not be directly executable'; end if;
end;$postconditions$;

commit;

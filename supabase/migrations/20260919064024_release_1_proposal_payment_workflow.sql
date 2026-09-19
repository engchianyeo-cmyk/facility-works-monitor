begin;

alter table public.contractor_quotations
  alter column quotation_ref drop not null,
  alter column quotation_date drop not null,
  alter column submitted_by drop not null,
  alter column submitted_at drop not null,
  add column if not exists prepared_by uuid references public.profiles(id) on delete restrict,
  add column if not exists prepared_at timestamptz,
  add column if not exists draft_saved_at timestamptz,
  add column if not exists scope_summary text,
  add column if not exists contractor_legal_name text,
  add column if not exists gst_treatment text,
  add column if not exists itemization_note text,
  add column if not exists submission_note text;

do $constraints$
declare constraint_name text;
begin
  for constraint_name in
    select c.conname
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=any(c.conkey)
    where c.conrelid='public.contractor_quotations'::regclass and c.contype='c' and a.attname='status'
  loop
    execute pg_catalog.format('alter table public.contractor_quotations drop constraint %I',constraint_name);
  end loop;
  alter table public.contractor_quotations
    add constraint contractor_quotations_status_check
    check(status in ('draft','submitted','approved','returned','rejected','superseded'));

  for constraint_name in
    select c.conname
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=any(c.conkey)
    where c.conrelid='public.contractor_payment_assessments'::regclass and c.contype='c' and a.attname='status'
  loop
    execute pg_catalog.format('alter table public.contractor_payment_assessments drop constraint %I',constraint_name);
  end loop;
  alter table public.contractor_payment_assessments
    add constraint contractor_payment_assessments_status_check
    check(status in ('draft','awaiting_approval','approved_for_payment','paid','returned'));
end;
$constraints$;

alter table public.contractor_payment_assessments
  add column if not exists invoice_reference text,
  add column if not exists recommendation_note text,
  add column if not exists recommended_by uuid references public.profiles(id) on delete restrict,
  add column if not exists recommended_at timestamptz,
  add column if not exists approval_note text,
  add column if not exists payment_term_started_at timestamptz,
  add column if not exists completion_notified_at timestamptz,
  add column if not exists paid_amount numeric(14,2) check(paid_amount is null or paid_amount>=0),
  add column if not exists payment_reference text,
  add column if not exists paid_by uuid references public.profiles(id) on delete restrict,
  add column if not exists payment_note text;

create table public.work_order_commercial_documents(
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete restrict,
  document_type text not null check(document_type in ('quotation','invoice')),
  quotation_id uuid references public.contractor_quotations(id) on delete restrict,
  payment_assessment_id uuid references public.contractor_payment_assessments(id) on delete restrict,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  original_filename text not null check(length(original_filename) between 1 and 255),
  content_type text not null check(content_type in ('image/jpeg','image/png','image/webp','application/pdf')),
  byte_size bigint not null check(byte_size between 1 and 10485760),
  storage_path text not null unique,
  uploaded_at timestamptz not null default now(),
  deleted_at timestamptz,
  check(
    (document_type='quotation' and quotation_id is not null and payment_assessment_id is null)
    or (document_type='invoice' and quotation_id is null and payment_assessment_id is not null)
  )
);
create index work_order_commercial_documents_active_idx
  on public.work_order_commercial_documents(work_order_id,document_type,uploaded_at desc)
  where deleted_at is null;
alter table public.work_order_commercial_documents enable row level security;
revoke all on public.work_order_commercial_documents from public,anon,authenticated;
grant select on public.work_order_commercial_documents to authenticated;
create policy work_order_commercial_documents_read on public.work_order_commercial_documents
for select to authenticated using(
  exists(select 1 from public.work_orders w where w.id=work_order_commercial_documents.work_order_id)
);

create or replace function public.save_work_order_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare
  actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype;
  q public.contractor_quotations%rowtype; amount numeric; scope_text text;
  quote_ref text; quote_date date; legal_name text; gst text; itemization text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','An assigned contractor record is required.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare this proposal.');
  end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Proposal preparation authority is required.'); end if;
  if w.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE','A terminal Work Order cannot receive a proposal.'); end if;
  begin amount:=(p_payload->>'proposed_amount')::numeric; quote_date:=nullif(p_payload->>'quotation_date','')::date; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Proposed amount or quotation date is invalid.'); end;
  scope_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'scope_summary','')),'');
  quote_ref:=nullif(pg_catalog.btrim(coalesce(p_payload->>'quotation_ref','')),'');
  legal_name:=nullif(pg_catalog.btrim(coalesce(p_payload->>'contractor_legal_name','')),'');
  gst:=nullif(pg_catalog.btrim(coalesce(p_payload->>'gst_treatment','')),'');
  itemization:=nullif(pg_catalog.btrim(coalesce(p_payload->>'itemization_note','')),'');
  if amount is null or amount<0 or scope_text is null or length(scope_text)>1000 or coalesce(length(quote_ref),0)>120 or coalesce(length(legal_name),0)>200 or coalesce(length(gst),0)>120 or coalesce(length(itemization),0)>2000 then
    return public.work_order_result_error('VALIDATION_ERROR','A valid proposal amount and repair scope are required.');
  end if;
  select * into q from public.contractor_quotations
  where work_order_id=w.id and status in ('draft','returned') order by updated_at desc limit 1 for update;
  if q.id is null then
    insert into public.contractor_quotations(work_order_id,vendor_id,quotation_ref,quotation_date,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary,contractor_legal_name,gst_treatment,itemization_note)
    values(w.id,w.assigned_vendor_id,quote_ref,quote_date,coalesce((select max(version_no)+1 from public.contractor_quotations where work_order_id=w.id),1),'draft','SGD',amount,actor_id,pg_catalog.now(),pg_catalog.now(),scope_text,legal_name,gst,itemization)
    returning * into q;
  else
    update public.contractor_quotations set vendor_id=w.assigned_vendor_id,quotation_ref=quote_ref,quotation_date=quote_date,total_amount=amount,status='draft',prepared_by=actor_id,prepared_at=coalesce(prepared_at,pg_catalog.now()),draft_saved_at=pg_catalog.now(),scope_summary=scope_text,contractor_legal_name=legal_name,gst_treatment=gst,itemization_note=itemization,submitted_by=null,submitted_at=null,approved_by=null,approved_at=null,approval_note=null,updated_at=pg_catalog.now()
    where id=q.id returning * into q;
  end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_proposal_draft_saved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'proposed_amount',q.total_amount,'quotation_reference_recorded',q.quotation_ref is not null,'quotation_date_recorded',q.quotation_date is not null,'contractor_legal_name_recorded',q.contractor_legal_name is not null,'gst_treatment_recorded',q.gst_treatment is not null,'itemization_recorded',q.itemization_note is not null)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$;

create or replace function public.submit_work_order_proposal(p_work_order_id uuid,p_quotation_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype; required_count integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Draft proposal was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or q.prepared_by is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician who prepared the draft may submit it.'); end if;
  if q.status not in ('draft','returned') then return public.work_order_result_error('INVALID_TRANSITION','Only a draft or returned proposal may be submitted.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  if coalesce(required_count,1)<>1 or q.total_amount>=1000 then return public.work_order_result_error('APPROVAL_NOT_READY','This Release-1 path is limited to the configured below-S$1,000 one-quotation rule.'); end if;
  update public.contractor_quotations set status='submitted',submitted_by=actor_id,submitted_at=pg_catalog.now(),submission_note=nullif(pg_catalog.btrim(coalesce(p_note,'')),''),updated_at=pg_catalog.now() where id=q.id returning * into q;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,cost_status='recommended',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=coalesce(nullif(pg_catalog.btrim(coalesce(p_note,'')),''),'Submitted for independent approval under the configured one-quotation rule.'),financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,approved_budget=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_proposal_submitted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'proposed_amount',q.total_amount,'required_quotations',required_count,'authentic_details_pending',pg_catalog.jsonb_build_array(case when q.quotation_ref is null then 'quotation_reference' end,case when q.quotation_date is null then 'quotation_date' end,case when q.contractor_legal_name is null then 'contractor_legal_name' end,case when q.itemization_note is null then 'itemization' end,case when q.gst_treatment is null then 'gst_treatment' end))::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$;

create or replace function public.approve_work_order_proposal(p_work_order_id uuid,p_quotation_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Submitted proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent financial approval authority is required.'); end if;
  if q.submitted_by=actor_id or q.prepared_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','A proposal preparer cannot approve the same expenditure.'); end if;
  if q.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only a submitted proposal may be approved.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('VALIDATION_ERROR','An independent approval note is required.'); end if;
  update public.contractor_quotations set status='approved',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=pg_catalog.btrim(p_note),updated_at=pg_catalog.now() where id=q.id returning * into q;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,approved_budget=q.total_amount,cost_status='approved',financial_approved_by=actor_id,financial_approved_at=pg_catalog.now(),financial_approval_note=pg_catalog.btrim(p_note),updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_proposal_independently_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'approved_amount',q.total_amount,'prepared_by',q.prepared_by,'approved_by',actor_id,'self_approval',false)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$;

create or replace function public.save_work_order_payment_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype; actual_total numeric; note_text text; invoice_ref text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','An assigned contractor record is required.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare the final account.'); end if;
  if w.status not in ('reviewed','closed') or w.reviewed_at is null then return public.work_order_result_error('APPROVAL_NOT_READY','Verified completion is required before preparing the final account.'); end if;
  if w.actual_costs_confirmed_at is null then return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Confirmed actual costing is required.'); end if;
  select coalesce(sum(amount),0) into actual_total from public.work_order_cost_lines where work_order_id=w.id and cost_phase='actual';
  note_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'recommendation_note','')),'');
  invoice_ref:=nullif(pg_catalog.btrim(coalesce(p_payload->>'invoice_reference','')),'');
  if note_text is null or length(note_text)>1000 or coalesce(length(invoice_ref),0)>120 then return public.work_order_result_error('VALIDATION_ERROR','A bounded payment recommendation note is required.'); end if;
  insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,invoice_reference,recommendation_note,payment_term_started_at,payment_due_at)
  values(w.id,w.assigned_vendor_id,'draft',actual_total,w.reviewed_at,invoice_ref,note_text,w.reviewed_at,w.reviewed_at+interval '30 days')
  on conflict(work_order_id) do update set status='draft',vendor_id=excluded.vendor_id,assessed_amount=excluded.assessed_amount,completed_work_accepted_at=excluded.completed_work_accepted_at,invoice_reference=excluded.invoice_reference,recommendation_note=excluded.recommendation_note,payment_term_started_at=excluded.payment_term_started_at,payment_due_at=excluded.payment_due_at,recommended_by=null,recommended_at=null,approved_by=null,approved_at=null,approval_note=null,completion_notified_at=null,paid_at=null,paid_amount=null,payment_reference=null,paid_by=null,payment_note=null,updated_at=pg_catalog.now()
  returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'contractor_final_account_draft_saved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'recommended_payment',actual_total,'payment_term_started_at',result.payment_term_started_at,'payment_due_at',result.payment_due_at,'invoice_reference_recorded',result.invoice_reference is not null)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.submit_work_order_payment_proposal(p_work_order_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Final account draft was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may submit the payment proposal.'); end if;
  if result.status not in ('draft','returned') then return public.work_order_result_error('INVALID_TRANSITION','Only a draft or returned payment proposal may be submitted.'); end if;
  if not exists(select 1 from public.work_order_commercial_documents d where d.work_order_id=w.id and d.payment_assessment_id=result.id and d.document_type='invoice' and d.deleted_at is null) then return public.work_order_result_error('INVOICE_REQUIRED','Attach the contractor invoice before submitting the payment proposal.'); end if;
  update public.contractor_payment_assessments set status='awaiting_approval',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=coalesce(nullif(pg_catalog.btrim(coalesce(p_note,'')),''),recommendation_note),completion_notified_at=pg_catalog.now(),updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
  select w.id,'contractor_final_account_submitted','work_order:'||w.id::text||':payment-proposal:'||result.id::text||':submitted',p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',w.id,'payment_assessment_id',result.id,'recommended_payment',result.assessed_amount,'payment_due_at',result.payment_due_at),'pending'
  from public.profiles p where p.is_active and p.deleted_at is null and p.role in ('approver','administrator') and p.id<>actor_id on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'contractor_final_account_submitted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'recommended_payment',result.assessed_amount,'invoice_attached',true,'completion_notification_queued',true,'payment_term_started_at',result.payment_term_started_at,'payment_due_at',result.payment_due_at)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.approve_work_order_payment(p_work_order_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Submitted payment proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent payment approval authority is required.'); end if;
  if result.recommended_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The payment recommender cannot approve the same payment.'); end if;
  if result.status<>'awaiting_approval' then return public.work_order_result_error('INVALID_TRANSITION','Only a submitted payment proposal may be approved.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('VALIDATION_ERROR','An independent payment approval note is required.'); end if;
  update public.contractor_payment_assessments set status='approved_for_payment',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=pg_catalog.btrim(p_note),updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
  select w.id,'contractor_payment_approved','work_order:'||w.id::text||':payment-proposal:'||result.id::text||':approved',p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',w.id,'approved_payment',result.assessed_amount,'payment_due_at',result.payment_due_at),'pending'
  from public.profiles p where p.id=w.assigned_technician_id and p.is_active and p.deleted_at is null on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'contractor_payment_independently_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_payment',result.assessed_amount,'recommended_by',result.recommended_by,'approved_by',actor_id,'self_approval',false,'finance_payment_recorded',false)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.record_work_order_finance_payment(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype; amount numeric; reference text; note_text text; paid_time timestamptz;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  if actor->>'role'<>'administrator' then return public.work_order_result_error('ACCESS_DENIED','Finance payment recording is restricted to an Administrator.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Approved payment proposal was not found.'); end if;
  if result.status<>'approved_for_payment' then return public.work_order_result_error('INVALID_TRANSITION','Independent payment approval is required before Finance records payment.'); end if;
  begin amount:=(p_payload->>'paid_amount')::numeric; paid_time:=coalesce(nullif(p_payload->>'paid_at','')::timestamptz,pg_catalog.now()); exception when others then return public.work_order_result_error('VALIDATION_ERROR','Paid amount or payment date is invalid.'); end;
  reference:=nullif(pg_catalog.btrim(coalesce(p_payload->>'payment_reference','')),''); note_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'payment_note','')),'');
  if amount is null or amount<0 or reference is null or note_text is null then return public.work_order_result_error('VALIDATION_ERROR','Payment reference, amount and Finance note are required.'); end if;
  update public.contractor_payment_assessments set status='paid',paid_amount=amount,payment_reference=reference,paid_by=actor_id,paid_at=paid_time,payment_note=note_text,updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'contractor_payment_recorded_by_finance',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_payment',result.assessed_amount,'paid_amount',result.paid_amount,'payment_reference',result.payment_reference,'paid_at',result.paid_at)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.register_work_order_commercial_document(p_work_order_id uuid,p_document_type text,p_record_id uuid,p_original_filename text,p_content_type text,p_byte_size bigint,p_storage_path text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_commercial_documents%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may attach commercial documents.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Commercial document authority is required.'); end if;
  if p_document_type='quotation' and not exists(select 1 from public.contractor_quotations q where q.id=p_record_id and q.work_order_id=w.id and q.status in ('draft','submitted','approved','returned')) then return public.work_order_result_error('NOT_FOUND','Proposal record was not found.'); end if;
  if p_document_type='invoice' and not exists(select 1 from public.contractor_payment_assessments p where p.id=p_record_id and p.work_order_id=w.id and p.status in ('draft','awaiting_approval','approved_for_payment','returned')) then return public.work_order_result_error('NOT_FOUND','Final account record was not found.'); end if;
  if p_document_type not in ('quotation','invoice') or p_storage_path not like 'commercial/work-order/'||w.id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return public.work_order_result_error('INVALID_STORAGE_OBJECT','Commercial document storage could not be verified.'); end if;
  insert into public.work_order_commercial_documents(work_order_id,document_type,quotation_id,payment_assessment_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
  values(w.id,p_document_type,case when p_document_type='quotation' then p_record_id end,case when p_document_type='invoice' then p_record_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_storage_path) returning * into result;
  if p_document_type='invoice' then
    update public.contractor_payment_assessments set invoice_received_at=coalesce(invoice_received_at,pg_catalog.now()),updated_at=pg_catalog.now() where id=p_record_id;
  end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_commercial_document_attached',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',result.id,'document_type',result.document_type,'record_id',p_record_id,'filename',result.original_filename)::text);
  return pg_catalog.jsonb_build_object('ok',true,'document',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or foreign_key_violation or unique_violation then return public.work_order_result_error('VALIDATION_ERROR','Commercial document metadata is invalid.');
end;$function$;

create or replace function public.work_order_contractor_quotations(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); facility uuid; result jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select facility_id into facility from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if not public.field_work_facility_permitted(facility) and actor->>'role' not in ('approver','administrator') then return public.work_order_result_error('ACCESS_DENIED','Work Order quotation access is denied.'); end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',q.id,'quotation_ref',q.quotation_ref,'quotation_date',q.quotation_date,'version_no',q.version_no,'status',q.status,'currency',q.currency,'total_amount',q.total_amount,'vendor_id',q.vendor_id,'source_filename',q.source_filename,'prepared_by',q.prepared_by,'prepared_at',q.prepared_at,'draft_saved_at',q.draft_saved_at,'scope_summary',q.scope_summary,'contractor_legal_name',q.contractor_legal_name,'gst_treatment',q.gst_treatment,'itemization_note',q.itemization_note,'submitted_by',q.submitted_by,'submitted_at',q.submitted_at,'approved_by',q.approved_by,'approved_at',q.approved_at,'approval_note',q.approval_note,'lines',(select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(l)-'quotation_id' order by l.line_no),'[]'::jsonb) from public.contractor_quotation_lines l where l.quotation_id=q.id)) order by q.created_at desc,q.version_no desc),'[]'::jsonb) into result from public.contractor_quotations q where q.work_order_id=p_work_order_id;
  return pg_catalog.jsonb_build_object('ok',true,'quotations',result);
end;$function$;

revoke all on function public.save_work_order_proposal(uuid,jsonb),public.submit_work_order_proposal(uuid,uuid,text),public.approve_work_order_proposal(uuid,uuid,text),public.save_work_order_payment_proposal(uuid,jsonb),public.submit_work_order_payment_proposal(uuid,text),public.approve_work_order_payment(uuid,text),public.record_work_order_finance_payment(uuid,jsonb),public.register_work_order_commercial_document(uuid,text,uuid,text,text,bigint,text) from public,anon,service_role;
grant execute on function public.save_work_order_proposal(uuid,jsonb),public.submit_work_order_proposal(uuid,uuid,text),public.approve_work_order_proposal(uuid,uuid,text),public.save_work_order_payment_proposal(uuid,jsonb),public.submit_work_order_payment_proposal(uuid,text),public.approve_work_order_payment(uuid,text),public.record_work_order_finance_payment(uuid,jsonb),public.register_work_order_commercial_document(uuid,text,uuid,text,text,bigint,text) to authenticated;
revoke all on function public.work_order_contractor_quotations(uuid) from public,anon,service_role;
grant execute on function public.work_order_contractor_quotations(uuid) to authenticated;

do $uat$
declare w public.work_orders%rowtype; q public.contractor_quotations%rowtype; yang uuid;
begin
  select * into w from public.work_orders where work_order_number='WO-TEST-012';
  select id into yang from public.profiles where email='koi.kpr@gmail.com' and role='technician' and is_active and deleted_at is null;
  if w.id is null or yang is null then raise exception 'WO-TEST-012 proposal/payment UAT prerequisite missing'; end if;
  select * into q from public.contractor_quotations where work_order_id=w.id order by created_at limit 1;
  if q.id is null then
    insert into public.contractor_quotations(work_order_id,vendor_id,quotation_ref,quotation_date,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary)
    values(w.id,w.assigned_vendor_id,null,null,1,'draft','SGD',650,yang,pg_catalog.now(),pg_catalog.now(),'Repair and test RS-01 - Loading Bay Roller Shutter No. 1') returning * into q;
  else
    delete from public.contractor_quotation_lines where quotation_id=q.id;
    update public.contractor_quotations set quotation_ref=null,quotation_date=null,status='draft',total_amount=650,source_filename=null,source_sha256=null,submitted_by=null,submitted_at=null,approved_by=null,approved_at=null,approval_note=null,prepared_by=yang,prepared_at=pg_catalog.now(),draft_saved_at=pg_catalog.now(),scope_summary='Repair and test RS-01 - Loading Bay Roller Shutter No. 1',contractor_legal_name=null,gst_treatment=null,itemization_note=null,submission_note=null,updated_at=pg_catalog.now() where id=q.id returning * into q;
  end if;
  update public.work_order_financial_controls set estimated_cost=650,quoted_cost=null,approved_budget=null,cost_status='draft',recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,payment_term_started_at,payment_due_at,recommendation_note)
  values(w.id,w.assigned_vendor_id,'draft',620,w.reviewed_at,w.reviewed_at,w.reviewed_at+interval '30 days','Recommend payment of the confirmed actual cost after verified completion.')
  on conflict(work_order_id) do update set status='draft',assessed_amount=620,completed_work_accepted_at=w.reviewed_at,invoice_received_at=null,invoice_reference=null,payment_term_started_at=w.reviewed_at,payment_due_at=w.reviewed_at+interval '30 days',recommendation_note='Recommend payment of the confirmed actual cost after verified completion.',recommended_by=null,recommended_at=null,approved_by=null,approved_at=null,approval_note=null,completion_notified_at=null,paid_at=null,paid_amount=null,payment_reference=null,paid_by=null,payment_note=null,updated_at=pg_catalog.now();
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(yang,w.id,'release_1_commercial_workflow_rebased',w.status,w.status,'Preview UAT remediation',pg_catalog.jsonb_build_object('proposal_amount',650,'actual_cost_preserved',620,'invented_quotation_details_removed',true,'payment_term_days',30,'rs01_markup_unchanged',true,'evidence_unchanged',true)::text);
end;$uat$;

commit;

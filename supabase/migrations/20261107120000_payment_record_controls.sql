begin;
-- D-41 (7 Nov 2026): payment record controls, after WO-TEST-007 was saved with Voltquay's invoice number and payment
-- reference (browser autofill) and a payment time 8 hours late (the form sent Singapore time without a time zone).
--   * An invoice number already recorded on another Work Order is refused (any contractor), with where it is used.
--   * A payment reference already recorded on another payment is refused.
--   * The payment date cannot be later than now (5 minutes' grace), instead of up to a day ahead.
--   * Finance must open the contractor invoice before confirming receipt; opening it is recorded.
--   * Work Orders marked as test data are left out of Finance's lists and totals (still visible on their own page).

alter table public.contractor_payment_assessments
  add column if not exists invoice_opened_at timestamptz,
  add column if not exists invoice_opened_by uuid references public.profiles(id) on delete restrict;
-- Test-data marks are kept beside the Work Order: closed Work Orders cannot be changed.
create table if not exists public.work_order_test_data (
  work_order_id uuid primary key references public.work_orders(id) on delete restrict,
  reason text not null check (char_length(btrim(reason)) between 5 and 500),
  marked_by uuid references public.profiles(id) on delete restrict,
  marked_at timestamptz not null default now()
);
alter table public.work_order_test_data enable row level security;
drop policy if exists work_order_test_data_read on public.work_order_test_data;
create policy work_order_test_data_read on public.work_order_test_data for select to authenticated using (public.pilot_account_ready());
revoke all on public.work_order_test_data from anon, authenticated;
grant select on public.work_order_test_data to authenticated;

-- Finance opens the invoice (from the document access route); the latest opening is kept and logged.
create or replace function public.record_invoice_opened(p_work_order_id uuid, p_document_id uuid)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb := public.work_order_actor(); d public.work_order_commercial_documents%rowtype; p public.contractor_payment_assessments%rowtype;
begin
  if actor is null or actor ->> 'role' <> 'finance' then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NOT_FINANCE'); end if;
  select * into d from public.work_order_commercial_documents where id = p_document_id and work_order_id = p_work_order_id and deleted_at is null;
  if not found or d.document_type <> 'invoice' then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NOT_AN_INVOICE'); end if;
  update public.contractor_payment_assessments set invoice_opened_at = now(), invoice_opened_by = (actor ->> 'id')::uuid
  where id = d.payment_assessment_id returning * into p;
  insert into public.activity_logs(user_id, work_order_id, action, actor, note)
  values ((actor ->> 'id')::uuid, p_work_order_id, 'work_order_invoice_opened_by_finance', coalesce(actor ->> 'display_name', 'Finance'),
    pg_catalog.jsonb_build_object('document_id', d.id, 'payment_assessment_id', p.id)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'invoice_opened_at', p.invoice_opened_at);
end;
$function$;
revoke all on function public.record_invoice_opened(uuid, uuid) from public, anon, service_role;
grant execute on function public.record_invoice_opened(uuid, uuid) to authenticated;

create or replace function public.register_work_order_invoice(p_work_order_id uuid, p_storage_path text, p_original_filename text, p_content_type text, p_byte_size bigint, p_invoice_reference text, p_invoice_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; p public.contractor_payment_assessments%rowtype;
  doc public.work_order_commercial_documents%rowtype; reference text:=nullif(pg_catalog.btrim(coalesce(p_invoice_reference,'')),''); stamp text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned Technician uploads the contractor invoice.'); end if;
  if w.status<>'reviewed' then return public.work_order_result_error('INVALID_TRANSITION','The invoice is uploaded after the Work Order is Completed.'); end if;
  select * into p from public.contractor_payment_assessments where work_order_id=w.id for update;
  if p.id is null or p.status<>'approved_for_payment' then return public.work_order_result_error('NOT_FOUND','No approved payable exists for this Work Order.'); end if;
  if p.invoice_received_at is not null then return public.work_order_result_error('INVOICE_ALREADY_RECEIVED','Finance has already received the invoice.'); end if;
  if reference is null or pg_catalog.length(reference)>100 then return public.work_order_result_error('VALIDATION_ERROR','The invoice number is required.'); end if;
  if exists(select 1 from public.contractor_payment_assessments x where x.id<>p.id and pg_catalog.upper(pg_catalog.btrim(x.invoice_reference))=pg_catalog.upper(reference)) then
    return public.work_order_result_error('DUPLICATE_INVOICE_NUMBER','Invoice number '||reference||' is already recorded on '||
      (select string_agg(coalesce(xw.work_order_number,'another Work Order')||' ('||coalesce(xv.name,'another contractor')||')',', ')
       from public.contractor_payment_assessments x join public.work_orders xw on xw.id=x.work_order_id left join public.vendors xv on xv.id=x.vendor_id
       where x.id<>p.id and pg_catalog.upper(pg_catalog.btrim(x.invoice_reference))=pg_catalog.upper(reference))||'. Enter the number printed on this contractor''s invoice.'); end if;
  if p_invoice_amount is null or p_invoice_amount::text in ('NaN','Infinity','-Infinity') or p_invoice_amount<0 then
    return public.work_order_result_error('VALIDATION_ERROR','A valid invoice amount is required.'); end if;
  if p_invoice_amount<>p.assessed_amount then
    return public.work_order_result_error('INVOICE_AMOUNT_MISMATCH','The invoice amount must equal the approved amount of S$'||pg_catalog.to_char(p.assessed_amount,'FM999,999,999,990.00')||'. Obtain a corrected invoice.'); end if;
  if p_storage_path is null or p_storage_path not like 'commercial/work-order/'||w.id::text||'/%'
    or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then
    return public.work_order_result_error('INVALID_STORAGE_OBJECT','Invoice storage could not be verified.'); end if;
  update public.work_order_commercial_documents set deleted_at=pg_catalog.now(),superseded_at=pg_catalog.now(),superseded_by_user=actor_id
    where payment_assessment_id=p.id and document_type='invoice' and deleted_at is null;
  insert into public.work_order_commercial_documents(work_order_id,document_type,payment_assessment_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
  values(w.id,'invoice',p.id,actor_id,p_original_filename,p_content_type,p_byte_size,p_storage_path) returning * into doc;
  update public.contractor_payment_assessments set invoice_reference=reference,invoice_amount=p_invoice_amount,invoice_uploaded_at=pg_catalog.now(),
    invoice_uploaded_by=actor_id,updated_at=pg_catalog.now() where id=p.id returning * into p;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_invoice_uploaded',w.status,w.status,coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('payment_assessment_id',p.id,'document_id',doc.id,'invoice_reference',reference,'invoice_amount',p_invoice_amount)::text);
  stamp:=pg_catalog.to_char(pg_catalog.clock_timestamp(),'YYYYMMDDHH24MISSUS');
  insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
  select w.id,'work_order_invoice_uploaded','work_order:'||w.id::text||':invoice:'||stamp,x.id,x.id,x.email,'email',
    pg_catalog.jsonb_build_object('work_order_id',w.id,'work_order_number',w.work_order_number,'invoice_reference',reference,'invoice_amount',p_invoice_amount),'pending'
  from public.profiles x where x.is_active and x.deleted_at is null and x.id<>actor_id and (x.role='finance' or x.id=p.approved_by)
  on conflict do nothing;
  perform public.work_order_notify(w.id,'work_order_invoice_uploaded',false,false,actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(p),'document',pg_catalog.to_jsonb(doc)-'storage_path');
exception when check_violation or foreign_key_violation or unique_violation then
  return public.work_order_result_error('VALIDATION_ERROR','Invoice metadata is invalid.');
end;$function$;

create or replace function public.mark_work_order_invoice_received(p_work_order_id uuid, p_received_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; p public.contractor_payment_assessments%rowtype; terms integer; received date;
begin
  if actor is null or actor->>'role'<>'finance' then return public.work_order_result_error('ACCESS_DENIED','Only Finance confirms receipt of invoices.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  select * into p from public.contractor_payment_assessments where work_order_id=w.id for update;
  if p.id is null or p.status<>'approved_for_payment' then return public.work_order_result_error('NOT_FOUND','No approved payable exists for this Work Order.'); end if;
  if p.invoice_uploaded_at is null then return public.work_order_result_error('INVOICE_REQUIRED','The Technician has not uploaded the contractor invoice.'); end if;
  if p.invoice_received_at is not null then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','payment',pg_catalog.to_jsonb(p)); end if;
  if p.invoice_opened_at is null or p.invoice_opened_at<p.invoice_uploaded_at then
    return public.work_order_result_error('INVOICE_NOT_OPENED','Open the contractor invoice and check it against the approved amount before confirming receipt.'); end if;
  received:=coalesce(p_received_on,(pg_catalog.now() at time zone 'Asia/Singapore')::date);
  if received>(pg_catalog.now() at time zone 'Asia/Singapore')::date or received<(p.invoice_uploaded_at at time zone 'Asia/Singapore')::date then
    return public.work_order_result_error('VALIDATION_ERROR','The received date must be between the upload date and today.'); end if;
  select v.payment_terms_days into terms from public.vendors v where v.id=p.vendor_id;
  update public.contractor_payment_assessments set invoice_received_at=(received::timestamp at time zone 'Asia/Singapore'),invoice_received_by=(actor->>'id')::uuid,
    payment_term_started_at=(received::timestamp at time zone 'Asia/Singapore'),
    payment_due_at=((received+coalesce(terms,30))::timestamp at time zone 'Asia/Singapore'),updated_at=pg_catalog.now()
    where id=p.id returning * into p;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values((actor->>'id')::uuid,w.id,'work_order_invoice_received_by_finance',w.status,w.status,coalesce(actor->>'display_name','Finance'),
    pg_catalog.jsonb_build_object('payment_assessment_id',p.id,'received_on',received,'payment_terms_days',coalesce(terms,30),'payment_due_at',p.payment_due_at)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(p));
end;$function$;

create or replace function public.record_work_order_finance_payment_r1_scope_core(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype; amount numeric; reference text; note_text text; paid_time timestamptz; closed boolean;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  if actor->>'role'<>'finance' then return public.work_order_result_error('ACCESS_DENIED','Payment recording is restricted to Finance.'); end if;
  select * into w from public.work_orders where id=p_work_order_id; select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Approved payable was not found.'); end if;
  if result.status<>'approved_for_payment' then return public.work_order_result_error('INVALID_TRANSITION','Payment can be recorded only for an approved payable.'); end if;
  if result.invoice_received_at is null then return public.work_order_result_error('INVOICE_NOT_RECEIVED','Confirm receipt of the contractor invoice before recording payment.'); end if;
  if result.approved_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The payment approver cannot also record the Finance payment.'); end if;
  begin amount:=(p_payload->>'paid_amount')::numeric; paid_time:=coalesce(nullif(p_payload->>'paid_at','')::timestamptz,pg_catalog.now()); exception when others then return public.work_order_result_error('VALIDATION_ERROR','Paid amount or payment date is invalid.'); end;
  reference:=nullif(pg_catalog.btrim(coalesce(p_payload->>'payment_reference','')),''); note_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'payment_note','')),'');
  if amount is null or amount<>result.assessed_amount or reference is null or note_text is null then return public.work_order_result_error('PAYMENT_RECONCILIATION_REQUIRED','Recorded payment must equal the approved amount and include a reference and Finance note.'); end if;
  if paid_time<result.invoice_received_at or paid_time>pg_catalog.now()+interval '5 minutes' then return public.work_order_result_error('VALIDATION_ERROR','The payment date must be on or after the invoice received date and not later than now.'); end if;
  if exists(select 1 from public.contractor_payment_assessments x join public.work_orders xw on xw.id=x.work_order_id
            where x.id<>result.id and pg_catalog.upper(pg_catalog.btrim(x.payment_reference))=pg_catalog.upper(reference)) then
    return public.work_order_result_error('DUPLICATE_PAYMENT_REFERENCE','Payment reference '||reference||' is already recorded on '||
      (select string_agg(coalesce(xw.work_order_number,'another Work Order'),', ') from public.contractor_payment_assessments x join public.work_orders xw on xw.id=x.work_order_id
       where x.id<>result.id and pg_catalog.upper(pg_catalog.btrim(x.payment_reference))=pg_catalog.upper(reference))||'. Check the bank reference for this payment.'); end if;
  update public.contractor_payment_assessments set status='paid',paid_amount=amount,payment_reference=reference,paid_by=actor_id,paid_at=paid_time,payment_note=note_text,updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_payment_recorded_by_finance',w.status,w.status,coalesce(actor->>'display_name','Finance'),
    pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_payment',result.assessed_amount,'paid_amount',amount,'payment_reference',reference,'paid_at',paid_time,
      'invoice_received_at',result.invoice_received_at,'payment_due_at',result.payment_due_at,'paid_late',paid_time>result.payment_due_at)::text);
  closed:=public.work_order_close_if_settled(w.id,actor_id,coalesce(actor->>'display_name','Finance'));
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result),'work_order_closed',closed);
end;$function$;

create or replace function public.work_order_finance_tracker()
 RETURNS TABLE(work_order_id uuid, work_order_number text, title text, facility_id uuid, vendor_id uuid, vendor_name text, approved_amount numeric, completed_at timestamp with time zone, invoice_reference text, invoice_amount numeric, invoice_uploaded_at timestamp with time zone, invoice_received_at timestamp with time zone, payment_due_at timestamp with time zone, paid_at timestamp with time zone, paid_amount numeric, payment_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select w.id,w.work_order_number,w.title,w.facility_id,p.vendor_id,v.name,p.assessed_amount,w.reviewed_at,p.invoice_reference,p.invoice_amount,
    p.invoice_uploaded_at,p.invoice_received_at,p.payment_due_at,p.paid_at,p.paid_amount,
    case when p.status='paid' then 'paid'
         when p.invoice_received_at is not null and p.payment_due_at<pg_catalog.now() then 'overdue'
         when p.invoice_received_at is not null then 'invoice_received'
         when p.invoice_uploaded_at is not null then 'invoice_uploaded'
         else 'awaiting_invoice' end
  from public.contractor_payment_assessments p
  join public.work_orders w on w.id=p.work_order_id
  left join public.vendors v on v.id=p.vendor_id
  where public.current_user_role() in ('finance','administrator') and p.status in ('approved_for_payment','paid') and not exists(select 1 from public.work_order_test_data td where td.work_order_id=w.id)
  order by case when p.status='paid' then 1 else 0 end, p.payment_due_at nulls last, w.reviewed_at
$function$;

create or replace function public.finance_completed_work_register(p_work_order_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(work_order_id uuid, work_order_number text, title text, facility_name text, status text, in_house_work boolean, emergency_work boolean, contractor_name text, technician_name text, approved_by_name text, approved_at timestamp with time zone, completed_by_name text, completed_at timestamp with time zone, closed_at timestamp with time zone, work_performed text, actual_labour_hours numeric, actual_work_started_at timestamp with time zone, actual_work_ended_at timestamp with time zone, approved_amount numeric, final_amount numeric, invoice_reference text, invoice_amount numeric, invoice_uploaded_at timestamp with time zone, invoice_received_at timestamp with time zone, payment_due_at timestamp with time zone, payment_terms_days integer, paid_at timestamp with time zone, paid_amount numeric, payment_reference text, register_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select w.id, w.work_order_number, w.title, s.name, w.status, coalesce(w.in_house_work, false), coalesce(w.emergency_work, false),
    v.name, t.display_name, ap.actor, ap.created_at, cp.actor, coalesce(cp.created_at, w.reviewed_at), w.closed_at,
    w.completion_notes, w.actual_labour_hours, w.actual_work_started_at, w.actual_work_ended_at,
    fc.approved_budget,
    case when coalesce(w.in_house_work, false)
         then (select coalesce(sum(c.amount), 0) from public.work_order_cost_lines c where c.work_order_id = w.id and c.cost_phase = 'actual')
         else p.assessed_amount end,
    p.invoice_reference, p.invoice_amount, p.invoice_uploaded_at, p.invoice_received_at, p.payment_due_at, v.payment_terms_days,
    p.paid_at, p.paid_amount, p.payment_reference,
    case when coalesce(w.in_house_work, false) then 'in_house'
         when p.status = 'paid' or p.paid_at is not null then 'paid'
         when p.invoice_received_at is not null and p.payment_due_at < now() then 'overdue'
         when p.invoice_received_at is not null then 'invoice_received'
         when p.invoice_uploaded_at is not null then 'invoice_uploaded'
         when w.status = 'closed' then 'closed_no_payment'
         else 'awaiting_invoice' end
  from public.work_orders w
  left join public.sites s on s.id = w.facility_id
  left join public.contractor_payment_assessments p on p.work_order_id = w.id
  left join public.vendors v on v.id = coalesce(p.vendor_id, w.assigned_vendor_id)
  left join public.profiles t on t.id = w.assigned_technician_id
  left join public.work_order_financial_controls fc on fc.work_order_id = w.id
  left join lateral (select a.actor, a.created_at from public.activity_logs a
    where a.work_order_id = w.id and a.from_status = 'submitted' and a.to_status in ('approved', 'assigned', 'in_progress')
    order by a.created_at desc limit 1) ap on true
  left join lateral (select a.actor, a.created_at from public.activity_logs a
    where a.work_order_id = w.id and a.action = 'work_order_review' and a.to_status = 'reviewed'
    order by a.created_at desc limit 1) cp on true
  where public.current_user_role() in ('finance', 'administrator') and public.pilot_account_ready(auth.uid())
    and w.status in ('reviewed', 'closed') and (p_work_order_id is null or w.id = p_work_order_id) and (p_work_order_id is not null or not exists (select 1 from public.work_order_test_data td where td.work_order_id = w.id))
  order by coalesce(cp.created_at, w.reviewed_at) desc nulls last
$function$;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.register_work_order_invoice(uuid,text,text,text,bigint,text,numeric)'::regprocedure), 'DUPLICATE_INVOICE_NUMBER') = 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.record_work_order_finance_payment_r1_scope_core(uuid,jsonb)'::regprocedure), 'DUPLICATE_PAYMENT_REFERENCE') = 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.mark_work_order_invoice_received(uuid,date)'::regprocedure), 'INVOICE_NOT_OPENED') = 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.work_order_finance_tracker()'::regprocedure), 'work_order_test_data') = 0 then
    raise exception 'D-41 payment controls were not installed';
  end if;
end;$postcheck$;
commit;

-- WP-LC2-M3: Work Order Lifecycle v2 — review to "Completed", invoice, Finance, closure.
-- Design §3.4–3.5 (approved 2026-10-20); decisions D-01.4/5, D-03.1/2, D-05.3.
--
-- * Physical completion is unchanged (R1-001). The final cost — and, for emergency work,
--   the after-the-fact quotation — must be in before the review can approve "Completed".
--   Any assigned field owner (0040) may enter the final cost.
-- * One review (verify_completed_work) approves work + final cost + documents within the
--   reviewer's limit, with facility scope and independence -> status 'reviewed' ("Completed").
--   It creates the approved payable. Closes the facility-scope gap in the 20260921 version.
-- * The Technician uploads the contractor invoice after "Completed"; its amount must equal
--   the approved final cost. Finance and copied parties are notified.
-- * Finance marks the invoice received: due date = received + contractor payment terms.
-- * Finance records payment; the Work Order closes automatically. An approved no-payment
--   disposition also closes a Completed Work Order.

do $preflight$
begin
  if current_user <> 'postgres' then raise exception 'LC2-M3 must be applied as postgres'; end if;
  if pg_catalog.to_regprocedure('public.work_order_preparer_permitted(uuid)') is null then raise exception 'LC2-M3 requires LC2-M2'; end if;
  if pg_catalog.to_regprocedure('public.register_work_order_invoice(uuid,text,text,text,bigint,text,numeric)') is not null
    or exists(select 1 from information_schema.columns where table_schema='public' and table_name='contractor_payment_assessments' and column_name='invoice_amount') then
    raise exception 'LC2-M3 conflicting or partial state already exists'; end if;
end;$preflight$;

alter table public.contractor_payment_assessments
  add column invoice_amount numeric(14,2) check (invoice_amount is null or (invoice_amount >= 0 and invoice_amount::text not in ('NaN','Infinity','-Infinity'))),
  add column invoice_uploaded_at timestamptz,
  add column invoice_uploaded_by uuid references public.profiles(id) on delete restrict,
  add column invoice_received_by uuid references public.profiles(id) on delete restrict;

-- Close a Completed ('reviewed') Work Order once payment is recorded in full or an
-- approved no-payment disposition exists. Internal helper (not granted).
create function public.work_order_close_if_settled(p_work_order_id uuid, p_actor_id uuid, p_actor_name text)
returns boolean language plpgsql security definer set search_path=pg_catalog as $function$
declare w public.work_orders%rowtype; p public.contractor_payment_assessments%rowtype; d public.work_order_financial_dispositions%rowtype; resolution text;
begin
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found or w.status<>'reviewed' then return false; end if;
  select * into p from public.contractor_payment_assessments where work_order_id=w.id;
  select * into d from public.work_order_financial_dispositions where work_order_id=w.id;
  if p.status='paid' and p.paid_amount=p.assessed_amount then resolution:='paid';
  elsif d.status='approved' and d.disposition_type='no_payment_required' then resolution:='no_payment_required';
  else return false; end if;
  update public.work_orders set status='closed',closed_at=pg_catalog.now(),updated_at=pg_catalog.now() where id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(p_actor_id,w.id,'work_order_closed_settled','reviewed','closed',coalesce(p_actor_name,'System'),
    pg_catalog.jsonb_build_object('resolution',resolution,'payment_assessment_id',p.id,'paid_amount',p.paid_amount,'disposition_id',d.id)::text);
  perform public.work_order_notify(w.id,'work_order_closed',false,true,p_actor_id);
  return true;
end;$function$;

-- The single review to "Completed" (design §3.4).
create or replace function public.verify_completed_work(p_work_order_id uuid, p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  previous public.work_orders%rowtype; result public.work_orders%rowtype;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  completion_activity_id uuid; completion_actor_id uuid; cycle_number integer;
  fc public.work_order_final_cost_submissions%rowtype; control public.work_order_financial_controls%rowtype;
  q public.contractor_quotations%rowtype; amount numeric(14,2); approved numeric(14,2); variance boolean; authority jsonb;
  vendor uuid; payable public.contractor_payment_assessments%rowtype; self_override boolean := false;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := coalesce(actor ->> 'display_name', 'Unknown user'); actor_role := actor ->> 'role';
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if actor_role not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Approval authority is required to review completed work.'); end if;
  if not public.approval_facility_permitted(previous.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Active same-facility approval membership is required.'); end if;
  if previous.status = 'reviewed' then
    return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE', 'work_order', pg_catalog.to_jsonb(previous)); end if;
  if previous.status <> 'completed' then
    return public.work_order_result_error('INVALID_TRANSITION', 'Only work submitted for review can be approved as Completed.'); end if;

  select l.id, l.user_id into completion_activity_id, completion_actor_id from public.activity_logs l
  where l.work_order_id = previous.id and l.action = 'work_order_complete' order by l.created_at desc, l.id desc limit 1;
  if completion_activity_id is null then
    return public.work_order_result_error('COMPLETION_AUDIT_REQUIRED', 'The latest completion submission record could not be found.'); end if;
  if not exists(select 1 from public.evidence_items e where e.work_order_id=previous.id and e.category='after' and e.deleted_at is null) then
    return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED', 'At least one active After evidence item is required.'); end if;

  select * into fc from public.work_order_final_cost_submissions where work_order_id = previous.id for update;
  if fc.id is null or fc.status not in ('confirmed','variance_pending','variance_approved') then
    return public.work_order_result_error('FINAL_COST_REQUIRED', 'The Technician has not entered the final cost.'); end if;
  amount := fc.confirmed_actual_cost;
  select * into control from public.work_order_financial_controls where work_order_id = previous.id for update;
  approved := control.approved_budget;
  if previous.emergency_work and (control.work_order_id is null or control.cost_status not in ('recommended','approved') or control.quoted_cost is null) then
    return public.work_order_result_error('QUOTATION_REQUIRED', 'The after-the-fact emergency quotation has not been submitted.'); end if;
  variance := amount > coalesce(approved, control.quoted_cost, 0);
  if variance and reason is null then
    return public.work_order_result_error('VARIANCE_NOTE_REQUIRED', 'The final cost exceeds the approved amount; record why it is accepted.'); end if;

  -- Monetary limit applies to the final cost; independence from requester and assigned Technician.
  authority := public.work_order_approval_authority(previous.id, amount, reason);
  if authority is not null then return authority; end if;
  if actor_id = completion_actor_id then
    if actor_role <> 'administrator' then return public.work_order_result_error('SELF_REVIEW_DENIED', 'Completed work must be reviewed by another authorised person.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-review requires an audited reason.'); end if;
  end if;
  self_override := actor_id in (completion_actor_id, previous.requested_by, previous.assigned_technician_id);

  -- Emergency: the review approves the after-the-fact quotation.
  if control.work_order_id is not null and control.cost_status = 'recommended' then
    select * into q from public.contractor_quotations where work_order_id = previous.id and vendor_id = previous.recommended_vendor_id and status = 'submitted' order by version_no desc limit 1;
    if q.id is not null then
      update public.contractor_quotations set status='superseded',updated_at=pg_catalog.now() where work_order_id=previous.id and id<>q.id and status='approved';
      update public.contractor_quotations set status='approved',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=coalesce(reason,'Approved at review'),updated_at=pg_catalog.now() where id=q.id;
      update public.work_order_financial_controls set approved_budget=q.total_amount,cost_status='approved',financial_approved_by=actor_id,financial_approved_at=pg_catalog.now(),
        financial_approval_note=coalesce(reason,'Approved at review'),updated_at=pg_catalog.now() where work_order_id=previous.id;
      vendor := q.vendor_id;
    end if;
  end if;
  if fc.status = 'variance_pending' then
    update public.work_order_final_cost_submissions set status='variance_approved',variance_approved_by=actor_id,variance_approved_at=pg_catalog.now(),
      variance_approval_note=coalesce(reason,'Approved at review'),updated_at=pg_catalog.now() where id=fc.id;
  end if;

  select pg_catalog.count(*) + 1 into cycle_number from public.activity_logs l where l.work_order_id = previous.id and l.action = 'work_order_returned_for_rework';
  update public.work_orders set status='reviewed', reviewed_at=pg_catalog.now(), updated_at=pg_catalog.now() where id=previous.id returning * into result;

  -- Approved payable for the contractor; the invoice follows (§3.5).
  vendor := coalesce(vendor, result.assigned_vendor_id, result.recommended_vendor_id);
  if vendor is not null and amount > 0 then
    insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,approved_by,approved_at,approval_note)
    values(result.id,vendor,'approved_for_payment',amount,result.reviewed_at,actor_id,pg_catalog.now(),coalesce(reason,'Approved at review to Completed'))
    on conflict(work_order_id) do update set vendor_id=excluded.vendor_id,status='approved_for_payment',assessed_amount=excluded.assessed_amount,
      completed_work_accepted_at=excluded.completed_work_accepted_at,approved_by=excluded.approved_by,approved_at=excluded.approved_at,approval_note=excluded.approval_note,
      recommended_by=null,recommended_at=null,invoice_reference=null,invoice_amount=null,invoice_uploaded_at=null,invoice_uploaded_by=null,
      invoice_received_at=null,invoice_received_by=null,payment_term_started_at=null,payment_due_at=null,
      paid_at=null,paid_amount=null,payment_reference=null,paid_by=null,payment_note=null,updated_at=pg_catalog.now()
    returning * into payable;
  end if;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,result.id,'work_order_review','completed','reviewed',actor_name,
    pg_catalog.jsonb_build_object('cycle',cycle_number,'decision','approved_completed','approved_final_cost',amount,'approved_budget',approved,
      'variance',variance,'reason',reason,'reviewer_role',actor_role,'emergency_work',result.emergency_work,
      'completion_activity_id',completion_activity_id,'payment_assessment_id',payable.id,
      'administrator_override',self_override and actor_role='administrator','verified_at',pg_catalog.now())::text);
  perform public.work_order_notify(result.id,'work_order_completed',false,true,actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle_number,
    'approved_final_cost',amount,'payment',pg_catalog.to_jsonb(payable),'notification_status','queued');
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Review data is invalid.');
end;
$function$;


-- readiness: Approver included; facility through the approval rule
CREATE OR REPLACE FUNCTION public.work_order_verification_readiness(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; event_id uuid; event_actor uuid; missing jsonb:='[]'::jsonb; same_actor boolean;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Completed Work verification authority is required.'); end if;
  if not public.approval_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Active same-facility approval membership is required.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  if w.status<>'completed' then missing:=missing||'"completed_awaiting_verification_status"'::jsonb; end if;
  select l.id,l.user_id into event_id,event_actor from public.activity_logs l where l.work_order_id=w.id and l.action='work_order_complete' order by l.created_at desc,l.id desc limit 1;
  if event_id is null then missing:=missing||'"authoritative_completion_submission_event"'::jsonb; end if;
  same_actor:=event_actor=(actor->>'id')::uuid;
  if same_actor and actor->>'role'<>'administrator' then missing:=missing||'"independent_authorised_verifier"'::jsonb; end if;
  return pg_catalog.jsonb_build_object('ok',true,'verification_ready',pg_catalog.jsonb_array_length(missing)=0,
    'missing_requirements',missing,'completion_event_found',event_id is not null,'completion_event_id',event_id,
    'legacy_completion_record',w.status='completed' and event_id is null,
    'self_verification_reason_required',same_actor and actor->>'role'='administrator');
end;$function$;

-- core: Approver has Supervisor powers for reject & reopen and close (D-04)
CREATE OR REPLACE FUNCTION public.transition_work_order_0034_core(p_work_order_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  previous public.work_orders%rowtype;
  result public.work_orders%rowtype;
  action text := pg_catalog.lower(coalesce(p_action, ''));
  target_status text;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  cycle_number integer;
  evidence_ids jsonb := '[]'::jsonb;
  transition_activity_id uuid;
  completion_activity_id uuid;
  completion_actor_id uuid;
  completion_note_text text;
  completion_note jsonb := '{}'::jsonb;
  prior_hours numeric;
  requested_hours numeric;
  direct_completed_from_assigned boolean := false;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'name', actor ->> 'display_name', 'Unknown user');
  actor_role := actor ->> 'role';

  select * into previous from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;

  if (action='complete' and previous.status='completed')
    or (action='review' and previous.status='reviewed')
    or (action='return_for_rework' and previous.status='in_progress' and exists(
      select 1 from public.activity_logs l where l.work_order_id=previous.id
        and l.action='work_order_returned_for_rework'
        and not exists(select 1 from public.activity_logs later where later.work_order_id=previous.id and later.created_at>l.created_at and later.action='work_order_complete')
    )) then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(previous));
  end if;

  if previous.status in ('closed','cancelled') then
    return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Closed and cancelled work orders are immutable.');
  end if;

  target_status := case action
    when 'submit' then 'submitted'
    when 'approve' then 'approved'
    when 'accept' then 'assigned'
    when 'start' then 'in_progress'
    when 'complete' then 'completed'
    when 'return_for_rework' then 'in_progress'
    when 'review' then 'reviewed'
    when 'close' then 'closed'
    when 'cancel' then 'cancelled'
    else null
  end;

  if target_status is null or not (
    (action='submit' and previous.status='draft')
    or (action='approve' and previous.status='submitted')
    or (action='accept' and previous.status='assigned' and previous.accepted_at is null)
    or (action='start' and previous.status='assigned')
    or (action='complete' and previous.status in ('assigned','in_progress'))
    or (action='return_for_rework' and previous.status='completed')
    or (action='review' and previous.status='completed')
    or (action='close' and previous.status='reviewed')
    or (action='cancel' and previous.status in ('draft','submitted','approved','assigned','in_progress','completed','reviewed'))
  ) then
    return public.work_order_result_error('INVALID_TRANSITION', 'The requested workflow transition is not allowed.');
  end if;

  if action='submit'
    and not (actor_id=previous.requested_by and actor_role in ('reviewer','initiator','approver','supervisor','facility_manager'))
    and actor_role<>'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the requester may submit this work order.');
  elsif action='approve' and actor_role not in ('approver','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Approver, Facility Manager or Administrator authority is required.');
  elsif action='approve' and actor_id=previous.requested_by then
    if actor_role<>'administrator' then return public.work_order_result_error('SELF_APPROVAL_DENIED', 'Requesters cannot approve their own work orders.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-approval requires an override reason.'); end if;
  elsif action in ('review','return_for_rework','close') and actor_role not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Supervisor, Facility Manager or Administrator authority is required.');
  elsif action in ('accept','start','complete') and actor_role<>'administrator'
    and not (actor_role='technician' and actor_id=previous.assigned_technician_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the assigned Technician-in-Charge or an Administrator may perform this action.');
  elsif action='cancel' and actor_role not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot cancel work orders.');
  end if;

  if action='cancel' and reason is null then
    return public.work_order_result_error('CANCELLATION_REASON_REQUIRED', 'A cancellation reason is required.');
  end if;
  if action='return_for_rework' and reason is null then
    return public.work_order_result_error('REWORK_REASON_REQUIRED', 'A rework reason is required.');
  end if;
  if action='return_for_rework' and not exists(
    select 1 from public.profiles p where p.id=previous.assigned_technician_id
      and p.role='technician' and p.is_active and p.deleted_at is null
  ) then
    return public.work_order_result_error('INVALID_ASSIGNMENT', 'Return for rework requires an active assigned Technician.');
  end if;

  if action='complete' then
    begin requested_hours := nullif(p_payload ->> 'actual_labour_hours','')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      return public.work_order_result_error('COMPLETED_DETAILS_REQUIRED', 'Work performed statement and cumulative non-negative labour hours are required.');
    end;
    if nullif(pg_catalog.btrim(coalesce(p_payload ->> 'completion_notes','')),'') is null
      or requested_hours is null or requested_hours<0 then
      return public.work_order_result_error('COMPLETED_DETAILS_REQUIRED', 'Work performed statement and cumulative non-negative labour hours are required.');
    end if;
    if not exists(select 1 from public.evidence_items e where e.work_order_id=previous.id and e.category='after') then
      return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED', 'Upload After photo or PDF evidence before marking this Work Order Completed.');
    end if;
    select count(*)+1 into cycle_number from public.activity_logs l
      where l.work_order_id=previous.id and l.action='work_order_returned_for_rework';
    prior_hours := previous.actual_labour_hours;
    if cycle_number>1 and prior_hours is not null and requested_hours<prior_hours then
      return public.work_order_result_error('CUMULATIVE_LABOUR_REQUIRED', 'Resubmitted labour hours must be the cumulative total and cannot be lower than the previous submission.');
    end if;
    select coalesce(pg_catalog.jsonb_agg(e.id order by e.uploaded_at,e.id),'[]'::jsonb)
      into evidence_ids from public.evidence_items e where e.work_order_id=previous.id;
    direct_completed_from_assigned := previous.status='assigned';
  end if;

  if action in ('review','return_for_rework') then
    select count(*)+1 into cycle_number from public.activity_logs l
      where l.work_order_id=previous.id and l.action='work_order_returned_for_rework';
    select l.id,l.user_id,l.note
      into completion_activity_id,completion_actor_id,completion_note_text
    from public.activity_logs l
    where l.work_order_id=previous.id and l.action='work_order_complete'
    order by l.created_at desc,l.id desc limit 1;
    begin completion_note := coalesce(nullif(completion_note_text,'')::jsonb,'{}'::jsonb);
    exception when invalid_text_representation then completion_note := '{}'::jsonb; end;
    evidence_ids := case when pg_catalog.jsonb_typeof(completion_note -> 'evidence_ids')='array'
      then completion_note -> 'evidence_ids' else '[]'::jsonb end;
  end if;

  if action='review' and actor_id=completion_actor_id then
    return public.work_order_result_error('SELF_REVIEW_DENIED', 'Completed Work must be accepted by a different Supervisor, Facility Manager or Administrator.');
  end if;

  begin
    if action='return_for_rework' then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,previous.id,'work_order_returned_for_rework','completed','in_progress',actor_name,
        pg_catalog.jsonb_build_object('cycle',cycle_number,'reason',reason,'previous_completion_activity_id',completion_activity_id,
          'previous_completion',pg_catalog.jsonb_build_object('completion_notes',previous.completion_notes,'cumulative_labour_hours',previous.actual_labour_hours,'completed_at',previous.completed_at,'evidence_ids',evidence_ids,'actor_id',completion_actor_id,'activity_note',completion_note),
          'returned_by',actor_id,'returned_at',pg_catalog.now())::text)
      returning id into transition_activity_id;
    end if;

    update public.work_orders set
      status=target_status,
      submitted_at=case when action='submit' then pg_catalog.now() else submitted_at end,
      approved_at=case when action='approve' then pg_catalog.now() else approved_at end,
      accepted_at=case when action='accept' then pg_catalog.now() else accepted_at end,
      started_at=case when action='start' then pg_catalog.now() when action='complete' and started_at is null then pg_catalog.now() else started_at end,
      completed_at=case when action='complete' then pg_catalog.now() when action='return_for_rework' then null else completed_at end,
      reviewed_at=case when action='review' then pg_catalog.now() else reviewed_at end,
      closed_at=case when action='close' then pg_catalog.now() else closed_at end,
      cancelled_at=case when action='cancel' then pg_catalog.now() else cancelled_at end,
      completion_notes=case when action='complete' then pg_catalog.btrim(p_payload ->> 'completion_notes') else completion_notes end,
      actual_labour_hours=case when action='complete' then requested_hours else actual_labour_hours end,
      cancellation_reason=case when action='cancel' then reason else cancellation_reason end,
      updated_at=pg_catalog.now()
    where id=previous.id returning * into result;

    if action<>'return_for_rework' then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,result.id,'work_order_'||action,previous.status,result.status,actor_name,
        case when action='complete' then pg_catalog.jsonb_build_object(
          'cycle',cycle_number,'completion_notes',result.completion_notes,'cumulative_labour_hours',result.actual_labour_hours,
          'completed_at',result.completed_at,'evidence_ids',evidence_ids,'submitted_by',actor_id,'submitted_at',pg_catalog.now(),
          'resubmission',cycle_number>1,'direct_completed_from_assigned',direct_completed_from_assigned)
        when action='review' then pg_catalog.jsonb_build_object('cycle',cycle_number,'decision','accepted','reason',reason,'completion_activity_id',completion_activity_id,'independent_review',true)
        else pg_catalog.jsonb_build_object('reason',reason,'payload',p_payload,'administrator_override',action='approve' and actor_id=previous.requested_by and actor_role='administrator') end::text)
      returning id into transition_activity_id;
    end if;

    if action='complete' then
      with primary_recipients as (
        select p.id,p.email from public.profiles p where p.is_active and p.deleted_at is null
          and p.role in ('supervisor','facility_manager') and p.id<>actor_id
      ), recipients as (
        select * from primary_recipients
        union all
        select p.id,p.email from public.profiles p where p.is_active and p.deleted_at is null
          and p.role='administrator' and p.id<>actor_id and not exists(select 1 from primary_recipients)
      )
      insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
      select result.id,case when cycle_number=1 then 'work_order_completion_submitted' else 'work_order_completion_resubmitted' end,
        'work_order:'||result.id::text||':completion:'||cycle_number::text||':submitted',r.id,r.id,r.email,'email',
        pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),'pending'
      from recipients r on conflict do nothing;
    elsif action='return_for_rework' then
      insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
      select result.id,'work_order_completion_returned_for_rework','work_order:'||result.id::text||':completion:'||cycle_number::text||':returned',p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),'pending'
      from public.profiles p where p.id=result.assigned_technician_id on conflict do nothing;
    elsif action='review' then
      if result.assigned_technician_id is not null then
        insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
        select result.id,'work_order_completion_accepted','work_order:'||result.id::text||':completion:'||cycle_number::text||':accepted',p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),'pending'
        from public.profiles p where p.id=result.assigned_technician_id and p.is_active and p.deleted_at is null on conflict do nothing;
      end if;
      if result.assigned_vendor_id is not null then
        insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,payment_due_at)
        values(result.id,result.assigned_vendor_id,'awaiting_approval',coalesce((select sum(amount) from public.work_order_cost_lines where work_order_id=result.id),0),pg_catalog.now(),pg_catalog.now()+interval '30 days')
        on conflict(work_order_id) do update set status='awaiting_approval',assessed_amount=excluded.assessed_amount,completed_work_accepted_at=excluded.completed_work_accepted_at,payment_due_at=excluded.payment_due_at,updated_at=pg_catalog.now();
      end if;
    end if;

    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',case when action in ('complete','return_for_rework','review') then cycle_number else null end,'notification_status',case when action in ('complete','return_for_rework','review') then 'queued' else null end);
  exception when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order transition failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more transition values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order transition failed.');
end;
$function$;

-- no-payment approval: approval rule (facility), proposer independence kept; auto-close when Completed
CREATE OR REPLACE FUNCTION public.approve_work_order_no_payment_r1_scope_core(p_work_order_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_financial_dispositions%rowtype;
  note_text text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),''); authority jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent no-payment approval authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  select * into result from public.work_order_financial_dispositions where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Proposed no-payment disposition was not found.'); end if;
  authority:=public.work_order_approval_authority(w.id,0,note_text);
  if authority is not null then return authority; end if;
  if result.status<>'proposed' then return public.work_order_result_error('INVALID_TRANSITION','Only a proposed no-payment disposition may be approved.'); end if;
  if result.proposed_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The proposer cannot approve their own no-payment disposition.'); end if;
  if exists(select 1 from public.contractor_payment_assessments p where p.work_order_id=w.id and p.status<>'returned') then return public.work_order_result_error('PAYMENT_ALREADY_RECORDED','No payment required cannot be approved while a payment process is active or recorded.'); end if;
  if note_text is null or length(note_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A bounded independent approval note is required.'); end if;
  update public.work_order_financial_dispositions set status='approved',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=note_text,updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_no_payment_independently_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('disposition_id',result.id,'reason_code',result.reason_code,'proposed_by',result.proposed_by,'approved_by',actor_id,'self_approval',false,'approval_note',note_text)::text);
  perform public.work_order_close_if_settled(w.id,actor_id,actor->>'name');
  return pg_catalog.jsonb_build_object('ok',true,'disposition',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.transition_work_order(p_work_order_id uuid, p_action text, p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare
  actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; role text;
  action text:=pg_catalog.lower(coalesce(p_action,'')); payload jsonb:=coalesce(p_payload,'{}'::jsonb);
  reason text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'reason','')),'');
  w public.work_orders%rowtype; result public.work_orders%rowtype; control public.work_order_financial_controls%rowtype;
  q public.contractor_quotations%rowtype; required_count integer; collected_count integer; amount numeric; authority jsonb; r jsonb;
  limit_version uuid; note_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; role:=actor->>'role'; actor_name:=coalesce(actor->>'display_name','Unknown user');
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;

  -- LC2-M3: the only path to Completed is the v2 review (work + cost + documents within limit).
  if action='review' then return public.verify_completed_work(p_work_order_id,p_payload); end if;

  if action not in ('submit','approve','return') then
    if role='approver' and not public.approver_facility_permitted(w.facility_id) then
      return public.work_order_result_error('ACCESS_DENIED','Active same-facility Approver membership is required.'); end if;
    return public.transition_work_order_20261020_core(p_work_order_id,p_action,p_payload);
  end if;

  if action='submit' then
    if w.status='submitted' or (w.emergency_work and w.status='in_progress' and w.submitted_at is not null) then
      return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
    if w.status<>'draft' then return public.work_order_result_error('INVALID_TRANSITION','Only a Draft may be submitted.'); end if;
    if not public.work_order_preparer_permitted(w.id) then
      return public.work_order_result_error('ACCESS_DENIED','Only the Work Order preparer may submit it.'); end if;
    if w.assigned_technician_id is null then
      return public.work_order_result_error('TECHNICIAN_REQUIRED','Assign the Technician who will witness the work before submitting.'); end if;
    if pg_catalog.length(pg_catalog.btrim(coalesce(w.description,'')))<10 then
      return public.work_order_result_error('JUSTIFICATION_REQUIRED','Explain why the work is needed (at least 10 characters) before submitting.'); end if;
    if w.emergency_work then
      update public.work_orders set status='in_progress',submitted_at=pg_catalog.now(),submitted_by=actor_name,
        accepted_at=coalesce(accepted_at,pg_catalog.now()),started_at=coalesce(started_at,pg_catalog.now()),updated_at=pg_catalog.now()
        where id=w.id returning * into result;
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,w.id,'work_order_emergency_started','draft','in_progress',actor_name,
        pg_catalog.jsonb_build_object('emergency_work',true,'quotation','to_follow_after_work','reason',reason)::text);
      perform public.work_order_notify(w.id,'work_order_emergency_started',true,true,actor_id);
      return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'emergency',true);
    end if;
    select * into control from public.work_order_financial_controls where work_order_id=w.id;
    select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
    select pg_catalog.count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
    if control.work_order_id is null or control.cost_status<>'recommended' or control.quoted_cost is null or w.recommended_vendor_id is null then
      return public.work_order_result_error('QUOTATION_REQUIRED','Submit and recommend the contractor quotation before submitting the Work Order.'); end if;
    if collected_count<coalesce(required_count,1) then
      return public.work_order_result_error('INSUFFICIENT_QUOTATIONS','The company quotation count has not been met.'); end if;
    update public.work_orders set status='submitted',submitted_at=pg_catalog.now(),submitted_by=actor_name,updated_at=pg_catalog.now()
      where id=w.id returning * into result;
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_submit','draft','submitted',actor_name,
      pg_catalog.jsonb_build_object('quoted_cost',control.quoted_cost,'recommended_vendor_id',w.recommended_vendor_id,
        'quotations',collected_count,'required_quotations',coalesce(required_count,1))::text);
    perform public.work_order_notify(w.id,'work_order_submitted_for_approval',true,false,actor_id);
    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
  end if;

  if action='return' then
    if w.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only a Work Order awaiting approval may be returned.'); end if;
    authority:=public.work_order_approval_authority(w.id,0,reason);
    if authority is not null then return authority; end if;
    if reason is null or pg_catalog.length(reason)>2000 then return public.work_order_result_error('VALIDATION_ERROR','A reason for returning the Work Order is required.'); end if;
    update public.contractor_quotations set status='returned',approval_note=reason,updated_at=pg_catalog.now() where work_order_id=w.id and status='submitted';
    update public.work_order_financial_controls set cost_status='returned',financial_approved_by=null,financial_approved_at=null,financial_approval_note=reason,updated_at=pg_catalog.now() where work_order_id=w.id;
    update public.work_orders set status='draft',updated_at=pg_catalog.now() where id=w.id returning * into result;
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_returned_to_draft','submitted','draft',actor_name,pg_catalog.jsonb_build_object('reason',reason)::text);
    perform public.work_order_notify(w.id,'work_order_returned_to_draft',false,true,actor_id);
    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
  end if;

  -- approve
  if w.status='assigned' and w.approved_at is not null then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
  if w.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only a Work Order awaiting approval may be approved.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id;
  select * into q from public.contractor_quotations where work_order_id=w.id and vendor_id=w.recommended_vendor_id and status='submitted'
    order by version_no desc limit 1;
  if control.work_order_id is null or control.cost_status<>'recommended' or q.id is null or control.quoted_cost is distinct from q.total_amount then
    return public.work_order_result_error('APPROVAL_NOT_READY','The recommended quotation is not ready for approval.'); end if;
  amount:=q.total_amount;
  authority:=public.work_order_approval_authority(w.id,amount,reason);
  if authority is not null then return authority; end if;
  if amount>1000000 and (nullif(pg_catalog.btrim(coalesce(payload->>'board_approval_reference','')),'') is null
    or nullif(payload->>'board_approval_date','') is null) then
    return public.work_order_result_error('BOARD_APPROVAL_REQUIRED','Board approval reference and date are required above S$1,000,000.'); end if;
  note_text:=coalesce(nullif(pg_catalog.btrim(coalesce(payload->>'note','')),''),reason,'Approved to proceed with the recommended quotation.');
  r:=public.approve_work_order_proposal(w.id,q.id,note_text);
  if not coalesce((r->>'ok')::boolean,false) then return r; end if;
  select version_id into limit_version from public.work_order_approval_limit_policy where singleton;
  update public.work_orders set status='assigned',approved_at=pg_catalog.now(),
      assigned_vendor_id=coalesce(assigned_vendor_id,q.vendor_id),assigned_at=coalesce(assigned_at,pg_catalog.now()),
      accepted_at=case when assigned_technician_id=requested_by then coalesce(accepted_at,pg_catalog.now()) else accepted_at end,
      approval_limit_version_id=limit_version,updated_at=pg_catalog.now()
    where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_approve','submitted','assigned',actor_name,
    pg_catalog.jsonb_build_object('decision','approved_to_proceed','approved_amount',amount,'quotation_id',q.id,'vendor_id',q.vendor_id,
      'approval_limit_version_id',limit_version,'approver_role',role,'reason',reason,
      'board_approval_reference',payload->>'board_approval_reference','board_approval_date',payload->>'board_approval_date',
      'administrator_override',(actor_id=w.requested_by or actor_id=w.assigned_technician_id) and role='administrator')::text);
  perform public.work_order_notify(w.id,'work_order_approved',false,true,actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'approved_amount',amount);
exception when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow or invalid_datetime_format then
  return public.work_order_result_error('VALIDATION_ERROR','Transition data is invalid.');
end;$function$;

-- emergency: the after-the-fact quotation may also follow the submission for review (D-01.6)
CREATE OR REPLACE FUNCTION public.prepare_work_order_proposal_r1_scope_core(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
  control public.work_order_financial_controls%rowtype; vendor uuid; amount numeric; governed_estimate numeric; scope_text text; rule uuid;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if not public.work_order_preparer_permitted(w.id) then return public.work_order_result_error('ACCESS_DENIED','Only the Work Order preparer may prepare a quotation.'); end if;
  if w.status not in ('draft','assigned','in_progress') and not (w.emergency_work and w.status='completed') then return public.work_order_result_error('INVALID_TRANSITION','Quotations are prepared in Draft, or during work for emergency and variation.'); end if;
  begin vendor:=(p_payload->>'vendor_id')::uuid; amount:=(p_payload->>'proposed_amount')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Eligible contractor and proposed amount are required.'); end;
  scope_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'scope_summary','')),'');
  if amount is null or amount<0 or scope_text is null or length(scope_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','Repair scope and non-negative proposed amount are required.'); end if;
  if not exists(select 1 from public.vendor_facility_eligibility e join public.vendors v on v.id=e.vendor_id where e.vendor_id=vendor and e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and v.active and v.deleted_at is null) then return public.work_order_result_error('CONTRACTOR_INELIGIBLE','Select a Procurement-prequalified, Facility-confirmed contractor.'); end if;
  if exists(select 1 from public.contractor_quotations x where x.work_order_id=w.id and x.vendor_id=vendor and x.status in ('draft','submitted','approved')) then return public.work_order_result_error('DUPLICATE_CONTRACTOR_QUOTATION','A current quotation for this contractor already exists.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  governed_estimate:=greatest(coalesce(control.estimated_cost,0),amount);
  select id into rule from public.commercial_approval_rules where policy_version_id=coalesce(control.policy_version_id,(select version_id from public.procurement_company_policy where singleton)) and active and governed_estimate>=minimum_amount and (maximum_amount is null or governed_estimate<maximum_amount) order by minimum_amount desc limit 1;
  if rule is null then return public.work_order_result_error('COMMERCIAL_RULE_REQUIRED','No commercial approval rule covers this amount.'); end if;
  insert into public.work_order_financial_controls(work_order_id,estimated_cost,rule_id,cost_status)
  values(w.id,governed_estimate,rule,'draft') on conflict(work_order_id) do update set estimated_cost=governed_estimate,rule_id=rule,cost_status='draft',quoted_cost=null,approved_budget=null,recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now();
  insert into public.contractor_quotations(work_order_id,vendor_id,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary)
  values(w.id,vendor,coalesce((select max(version_no)+1 from public.contractor_quotations where work_order_id=w.id),1),'draft','SGD',amount,actor_id,pg_catalog.now(),pg_catalog.now(),scope_text) returning * into q;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_competing_quotation_prepared',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('vendor_id',vendor,'quotation_id',q.id,'quoted_amount',amount,'governed_estimate',governed_estimate,'decision_pending',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$;

-- final cost: any assigned same-facility field owner (0040); fixed once the review approves it
CREATE OR REPLACE FUNCTION public.save_work_order_final_cost_r1_scope_core(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_final_cost_submissions%rowtype;
  contractor numeric; derived_actual numeric; claimed_actual numeric; approved numeric; note text; next_status text; payment_status text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.assigned_technician_id is distinct from actor_id or w.status not in ('assigned','in_progress','completed') or not public.field_work_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may reconcile final costs before closure.'); end if;
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

-- commercial documents: uploading an invoice no longer marks it received; Finance does (D-05.3)
CREATE OR REPLACE FUNCTION public.register_work_order_commercial_document_r1_scope_core(p_work_order_id uuid, p_document_type text, p_record_id uuid, p_original_filename text, p_content_type text, p_byte_size bigint, p_storage_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_commercial_documents%rowtype; replaced_ids uuid[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if not public.work_order_preparer_permitted(w.id) then return public.work_order_result_error('ACCESS_DENIED','Only the Work Order preparer may attach commercial documents.'); end if;
  if p_document_type='quotation' and not exists(select 1 from public.contractor_quotations q where q.id=p_record_id and q.work_order_id=w.id and q.status in ('draft','returned')) then return public.work_order_result_error('APPROVED_DOCUMENT_IMMUTABLE','Only a draft or returned quotation revision can receive a replacement document.'); end if;
  if p_document_type='invoice' and not exists(select 1 from public.contractor_payment_assessments p where p.id=p_record_id and p.work_order_id=w.id and p.status in ('draft','awaiting_approval','approved_for_payment','returned')) then return public.work_order_result_error('NOT_FOUND','Final account record was not found.'); end if;
  if p_document_type not in ('quotation','invoice') or p_storage_path not like 'commercial/work-order/'||w.id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return public.work_order_result_error('INVALID_STORAGE_OBJECT','Commercial document storage could not be verified.'); end if;
  if p_document_type='quotation' then select pg_catalog.array_agg(id) into replaced_ids from public.work_order_commercial_documents where quotation_id=p_record_id and deleted_at is null; end if;
  insert into public.work_order_commercial_documents(work_order_id,document_type,quotation_id,payment_assessment_id,uploaded_by,original_filename,content_type,byte_size,storage_path) values(w.id,p_document_type,case when p_document_type='quotation' then p_record_id end,case when p_document_type='invoice' then p_record_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_storage_path) returning * into result;
  if p_document_type='quotation' and replaced_ids is not null then update public.work_order_commercial_documents set deleted_at=pg_catalog.now(),superseded_at=pg_catalog.now(),superseded_by=result.id,superseded_by_user=actor_id where id=any(replaced_ids); end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,case when replaced_ids is null then 'work_order_commercial_document_attached' else 'draft_quotation_document_replaced' end,w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',result.id,'document_type',result.document_type,'record_id',p_record_id,'filename',result.original_filename,'replaced_document_ids',coalesce(pg_catalog.to_jsonb(replaced_ids),'[]'::jsonb))::text);
  return pg_catalog.jsonb_build_object('ok',true,'document',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or foreign_key_violation or unique_violation then return public.work_order_result_error('VALIDATION_ERROR','Commercial document metadata is invalid.'); end;$function$;


-- Invoice upload by the assigned Technician after "Completed"; amount must equal the
-- approved final cost. Notifies Finance, the reviewer, copied parties and the Technician.
create function public.register_work_order_invoice(p_work_order_id uuid, p_storage_path text, p_original_filename text, p_content_type text,
  p_byte_size bigint, p_invoice_reference text, p_invoice_amount numeric)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
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

-- Finance confirms receipt of the invoice; payment terms run from this date.
create function public.mark_work_order_invoice_received(p_work_order_id uuid, p_received_on date default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; p public.contractor_payment_assessments%rowtype; terms integer; received date;
begin
  if actor is null or actor->>'role'<>'finance' then return public.work_order_result_error('ACCESS_DENIED','Only Finance confirms receipt of invoices.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  select * into p from public.contractor_payment_assessments where work_order_id=w.id for update;
  if p.id is null or p.status<>'approved_for_payment' then return public.work_order_result_error('NOT_FOUND','No approved payable exists for this Work Order.'); end if;
  if p.invoice_uploaded_at is null then return public.work_order_result_error('INVOICE_REQUIRED','The Technician has not uploaded the contractor invoice.'); end if;
  if p.invoice_received_at is not null then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','payment',pg_catalog.to_jsonb(p)); end if;
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

-- Finance records payment (Finance role, not Administrator); closes the Work Order when settled.
create or replace function public.record_work_order_finance_payment_r1_scope_core(p_work_order_id uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
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
  if paid_time<result.invoice_received_at or paid_time>pg_catalog.now()+interval '1 day' then return public.work_order_result_error('VALIDATION_ERROR','The payment date must be on or after the invoice received date and not in the future.'); end if;
  update public.contractor_payment_assessments set status='paid',paid_amount=amount,payment_reference=reference,paid_by=actor_id,paid_at=paid_time,payment_note=note_text,updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_payment_recorded_by_finance',w.status,w.status,coalesce(actor->>'display_name','Finance'),
    pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_payment',result.assessed_amount,'paid_amount',amount,'payment_reference',reference,'paid_at',paid_time,
      'invoice_received_at',result.invoice_received_at,'payment_due_at',result.payment_due_at,'paid_late',paid_time>result.payment_due_at)::text);
  closed:=public.work_order_close_if_settled(w.id,actor_id,coalesce(actor->>'display_name','Finance'));
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result),'work_order_closed',closed);
end;$function$;

-- Finance payment tracker (Finance and Administrator).
create function public.work_order_finance_tracker()
returns table(work_order_id uuid, work_order_number text, title text, facility_id uuid, vendor_id uuid, vendor_name text, approved_amount numeric,
  completed_at timestamptz, invoice_reference text, invoice_amount numeric, invoice_uploaded_at timestamptz, invoice_received_at timestamptz,
  payment_due_at timestamptz, paid_at timestamptz, paid_amount numeric, payment_status text)
language sql stable security definer set search_path=pg_catalog as $function$
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
  where public.current_user_role() in ('finance','administrator') and p.status in ('approved_for_payment','paid')
  order by case when p.status='paid' then 1 else 0 end, p.payment_due_at nulls last, w.reviewed_at
$function$;

-- Privileges ----------------------------------------------------------------------
revoke all on function public.work_order_close_if_settled(uuid,uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.register_work_order_invoice(uuid,text,text,text,bigint,text,numeric) from public, anon, service_role;
revoke all on function public.mark_work_order_invoice_received(uuid,date) from public, anon, service_role;
revoke all on function public.work_order_finance_tracker() from public, anon, service_role;
revoke all on function public.record_work_order_finance_payment_r1_scope_core(uuid,jsonb) from public, anon, authenticated, service_role;
grant execute on function public.register_work_order_invoice(uuid,text,text,text,bigint,text,numeric) to authenticated;
grant execute on function public.mark_work_order_invoice_received(uuid,date) to authenticated;
grant execute on function public.work_order_finance_tracker() to authenticated;

do $post$
begin
  if not exists(select 1 from pg_catalog.pg_proc where oid='public.verify_completed_work(uuid,jsonb)'::regprocedure and prosrc like '%approval_facility_permitted(previous.facility_id)%') then
    raise exception 'LC2-M3 review facility scope missing'; end if;
  if has_function_privilege('authenticated','public.work_order_close_if_settled(uuid,uuid,text)','EXECUTE') then raise exception 'LC2-M3 close helper exposed'; end if;
  if not exists(select 1 from pg_catalog.pg_proc where oid='public.transition_work_order(uuid,text,jsonb)'::regprocedure and prosrc like '%if action=''review'' then return public.verify_completed_work%') then
    raise exception 'LC2-M3 review routing missing'; end if;
end;$post$;

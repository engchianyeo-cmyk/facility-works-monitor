begin;
-- D-22 (28 Oct 2026): for contractor work the actual cost is taken from the final contractor charge entered in
-- Final Cost Reconciliation (the attached quotation is the official breakdown). The Actual Cost lines become an
-- optional itemised record and no longer have to repeat the quotation. In-house work keeps the cost ledger.
-- D-23 (28 Oct 2026): the field owner may delete their own uncertified actual-cost line, with an audit entry.
-- D-24 (28 Oct 2026): contractor work is submitted for review with the official (final) quotation.

CREATE OR REPLACE FUNCTION public.save_work_order_final_cost_r1_scope_core(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_final_cost_submissions%rowtype;
  contractor numeric; derived_actual numeric; claimed_actual numeric; approved numeric; agreed numeric; note text; next_status text; payment_status text;
  variation boolean; final_quote uuid; final_ref text; justification text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.assigned_technician_id is distinct from actor_id or w.status not in ('assigned','in_progress','completed') or not public.field_work_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may reconcile final costs before closure.'); end if;
  -- D-22: contractor work needs the labour hours; the cost ledger is an optional itemised record.
  if w.actual_labour_hours is null or (w.in_house_work and w.actual_costs_confirmed_at is null) then return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Physical labour and the execution cost ledger must be confirmed before final reconciliation.'); end if;
  select p.status into payment_status from public.contractor_payment_assessments p where p.work_order_id=w.id;
  if payment_status in ('awaiting_approval','approved_for_payment','paid') then return public.work_order_result_error('FINANCIAL_RECORD_IMMUTABLE','Final cost cannot change after the payment proposal is submitted.'); end if;
  begin contractor:=(p_payload->>'final_contractor_amount')::numeric; claimed_actual:=nullif(p_payload->>'confirmed_actual_cost','')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Final contractor amount or claimed actual cost is invalid.'); end;
  -- D-22: for contractor work the actual cost IS the final contractor charge; in-house work keeps the ledger total.
  if w.in_house_work then
    select coalesce(pg_catalog.sum(c.amount),0) into derived_actual from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
  end if;
  note:=nullif(pg_catalog.btrim(coalesce(p_payload->>'comments','')),'');
  if contractor is null or contractor<0 or note is null or length(note)>2000 then return public.work_order_result_error('VALIDATION_ERROR','Final contractor amount and comments are required.'); end if;
  if not w.in_house_work then derived_actual:=contractor;
  elsif claimed_actual is not null and claimed_actual<>derived_actual then return public.work_order_result_error('ACTUAL_COST_MISMATCH','Confirmed actual cost must equal the execution cost ledger total.'); end if;
  select approved_budget, coalesce(approved_budget, quoted_cost) into approved, agreed from public.work_order_financial_controls where work_order_id=w.id;
  -- D-19: contractor work with a quotation must state whether there was a variation order. In-house work has no
  -- quotation, and an emergency job's after-the-fact quotation may not exist yet.
  if not w.in_house_work and agreed is not null then
    if coalesce(p_payload->>'variation_order','') not in ('true','false') then
      return public.work_order_result_error('VARIATION_CONFIRMATION_REQUIRED','State whether there was a variation order: price unchanged, or a revised quotation from the contractor.'); end if;
    variation:=(p_payload->>'variation_order')::boolean;
    justification:=nullif(pg_catalog.btrim(coalesce(p_payload->>'variation_justification','')),'');
    if variation and (justification is null or pg_catalog.length(justification) not between 10 and 2000) then
      return public.work_order_result_error('VARIATION_JUSTIFICATION_REQUIRED','Explain why the price changed (the variation order justification, at least 10 characters).'); end if;
    if not variation then justification:=null; end if;
  end if;
  if variation is false then
    select q.id, q.quotation_ref into final_quote, final_ref from public.contractor_quotations q
    where q.work_order_id=w.id and (q.status='approved' or (q.status='submitted' and q.vendor_id=w.recommended_vendor_id))
    order by (q.status='approved') desc, q.version_no desc, q.created_at desc limit 1;
    if final_quote is null then
      return public.work_order_result_error('APPROVED_QUOTATION_REQUIRED','No approved quotation was found to carry forward as the final quotation.'); end if;
    if contractor<>agreed then
      return public.work_order_result_error('PRICE_UNCHANGED_MISMATCH','You stated the price is unchanged, so the final contractor charge must equal the approved quotation of S$'||pg_catalog.to_char(agreed,'FM999,999,990.00')||'. Choose "variation order" if the contractor revised the price.'); end if;
  end if;
  next_status:=case when derived_actual>coalesce(approved,0) then 'variance_pending' else 'confirmed' end;
  insert into public.work_order_final_cost_submissions(work_order_id,status,actual_labour_hours,final_contractor_amount,confirmed_actual_cost,comments,submitted_by,submitted_at,variation_order,final_quotation_id,variation_justification)
  values(w.id,next_status,w.actual_labour_hours,contractor,derived_actual,note,actor_id,pg_catalog.now(),variation,final_quote,justification)
  on conflict(work_order_id) do update set status=excluded.status,actual_labour_hours=excluded.actual_labour_hours,final_contractor_amount=excluded.final_contractor_amount,confirmed_actual_cost=excluded.confirmed_actual_cost,comments=excluded.comments,submitted_by=excluded.submitted_by,submitted_at=excluded.submitted_at,variation_order=excluded.variation_order,final_quotation_id=excluded.final_quotation_id,variation_justification=excluded.variation_justification,variance_approved_by=null,variance_approved_at=null,variance_approval_note=null,updated_at=pg_catalog.now() returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_cost_reconciled',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('submission_id',result.id,'approved_quotation',approved,'actual_contractor_charge',contractor,'actual_repair_cost',derived_actual,'actual_labour_hours',w.actual_labour_hours,'variance',derived_actual-coalesce(approved,0),'quotation_excluded_from_actual_total',true,'actual_cost_source',case when w.in_house_work then 'cost ledger' else 'final contractor charge' end,'status',next_status,
    'variation_order',variation,'variation_justification',justification,'final_quotation',case when variation then 'revised quotation to be attached' when variation is false then coalesce(final_ref,'approved quotation') end)::text);
  return pg_catalog.jsonb_build_object('ok',true,'final_cost',pg_catalog.to_jsonb(result),'approved_quotation',approved,'actual_repair_cost',derived_actual,'variance',derived_actual-coalesce(approved,0));
end;$function$;

create or replace function public.manage_work_order_actual_cost(
  p_work_order_id uuid,
  p_cost_line_id uuid,
  p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare
  actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; w public.work_orders%rowtype;
  operation text:=pg_catalog.lower(coalesce(p_payload->>'operation','upsert'));
  kind text; detail text; measure text; worker text; quantity_value numeric; rate_value numeric;
  existing public.work_order_cost_lines%rowtype; result public.work_order_cost_lines%rowtype;
  previous_value jsonb; actual_count bigint; actual_total numeric;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name','Unknown user');
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Assigned field-owner authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  -- D-21: the assigned Technician may also correct costs while Submitted for Review, before the review.
  if w.status not in ('assigned','in_progress','completed') then return public.work_order_result_error('ACTUAL_COST_READ_ONLY','Actual execution costs are read-only after the review.'); end if;
  if w.assigned_technician_id is null or w.assigned_technician_id<>actor_id
    or not public.field_work_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility assigned field-owner responsibility is required.');
  end if;

  if operation='confirm' then
    if p_cost_line_id is not null then return public.work_order_result_error('VALIDATION_ERROR','Cost-line identity is not accepted when confirming actual costing.'); end if;
    update public.work_orders set actual_costs_confirmed_at=pg_catalog.now(),actual_costs_confirmed_by=actor_id,updated_at=pg_catalog.now()
      where id=w.id;
    select pg_catalog.count(*),coalesce(pg_catalog.sum(c.amount),0) into actual_count,actual_total
      from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_actual_costing_confirmed',w.status,w.status,actor_name,
      pg_catalog.jsonb_build_object('facility_id',w.facility_id,'actual_line_count',actual_count,'actual_total',actual_total,
        'confirmed_at',pg_catalog.now())::text);
    return pg_catalog.jsonb_build_object('ok',true,'confirmed',true,'actual_line_count',actual_count,'actual_total',actual_total);
  end if;
  -- D-23: the field owner may delete their own uncertified, unapproved line (e.g. one typed in by mistake); audited.
  if operation='delete' then
    select * into existing from public.work_order_cost_lines c where c.id=p_cost_line_id and c.work_order_id=w.id for update;
    if not found then return public.work_order_result_error('NOT_FOUND','Actual cost line not found.'); end if;
    if existing.cost_phase is distinct from 'actual' then return public.work_order_result_error('PROPOSED_COST_PROTECTED','Proposed or legacy cost lines cannot be changed through actual-cost recording.'); end if;
    if existing.entered_by<>actor_id then return public.work_order_result_error('ACCESS_DENIED','A field owner may delete only their own actual-cost line.'); end if;
    if existing.technician_certified_at is not null or existing.approved_at is not null then
      return public.work_order_result_error('ACTUAL_COST_LOCKED','Certified or approved actual-cost lines cannot be deleted.'); end if;
    delete from public.work_order_cost_lines where id=existing.id;
    update public.work_orders set actual_costs_confirmed_at=null,actual_costs_confirmed_by=null,updated_at=pg_catalog.now() where id=w.id;
    if w.in_house_work then
      update public.work_order_final_cost_submissions set status='draft',updated_at=pg_catalog.now() where work_order_id=w.id and status<>'draft';
    end if;
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_actual_cost_deleted',w.status,w.status,actor_name,
      pg_catalog.jsonb_build_object('facility_id',w.facility_id,'cost_line_id',existing.id,'deleted_line',pg_catalog.to_jsonb(existing))::text);
    return pg_catalog.jsonb_build_object('ok',true,'deleted',existing.id,'actual_costing_confirmed',false);
  end if;
  if operation<>'upsert' then return public.work_order_result_error('VALIDATION_ERROR','Actual-cost operation is invalid.'); end if;

  kind:=pg_catalog.lower(coalesce(p_payload->>'cost_type',''));
  detail:=nullif(pg_catalog.btrim(coalesce(p_payload->>'description','')),'');
  measure:=nullif(pg_catalog.btrim(coalesce(p_payload->>'unit','')),'');
  worker:=nullif(pg_catalog.btrim(coalesce(p_payload->>'worker_name','')),'');
  begin quantity_value:=(p_payload->>'quantity')::numeric; exception when others then quantity_value:=null; end;
  begin rate_value:=(p_payload->>'unit_rate')::numeric; exception when others then rate_value:=null; end;
  if kind not in ('labour','material','equipment','service','callout') or detail is null or measure is null
    or quantity_value is null or quantity_value<0 or rate_value is null or rate_value<0 then
    return public.work_order_result_error('VALIDATION_ERROR','Cost type, description, non-negative quantity, unit and non-negative unit rate are required.');
  end if;
  if pg_catalog.length(detail)>1000 or pg_catalog.length(measure)>100 or pg_catalog.length(coalesce(worker,''))>200 then
    return public.work_order_result_error('VALIDATION_ERROR','Actual-cost text exceeds the permitted length.');
  end if;

  if p_cost_line_id is null then
    insert into public.work_order_cost_lines(work_order_id,vendor_id,worker_name,cost_type,description,quantity,unit,unit_rate,entered_by,cost_phase)
    values(w.id,case when kind in ('service','callout') then w.assigned_vendor_id end,worker,kind,detail,quantity_value,measure,rate_value,actor_id,'actual')
    returning * into result;
  else
    select * into existing from public.work_order_cost_lines c where c.id=p_cost_line_id and c.work_order_id=w.id for update;
    if not found then return public.work_order_result_error('NOT_FOUND','Actual cost line not found.'); end if;
    if existing.cost_phase is distinct from 'actual' then return public.work_order_result_error('PROPOSED_COST_PROTECTED','Proposed or legacy cost lines cannot be changed through actual-cost recording.'); end if;
    if existing.entered_by<>actor_id then return public.work_order_result_error('ACCESS_DENIED','A field owner may update only their own active actual-cost line.'); end if;
    if existing.technician_certified_at is not null or existing.approved_at is not null then
      return public.work_order_result_error('ACTUAL_COST_LOCKED','Certified or approved actual-cost lines are read-only.');
    end if;
    previous_value:=pg_catalog.to_jsonb(existing);
    update public.work_order_cost_lines set
      vendor_id=case when kind in ('service','callout') then w.assigned_vendor_id end,
      worker_name=worker,cost_type=kind,description=detail,quantity=quantity_value,unit=measure,unit_rate=rate_value
    where id=existing.id returning * into result;
  end if;

  update public.work_orders set actual_costs_confirmed_at=null,actual_costs_confirmed_by=null,updated_at=pg_catalog.now() where id=w.id;
  -- D-22: in-house work only - its actual cost is the ledger, so a saved final cost must be saved again.
  if w.in_house_work then
    update public.work_order_final_cost_submissions set status='draft',updated_at=pg_catalog.now() where work_order_id=w.id and status<>'draft';
  end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,case when p_cost_line_id is null then 'work_order_actual_cost_created' else 'work_order_actual_cost_updated' end,
    w.status,w.status,actor_name,pg_catalog.jsonb_build_object('facility_id',w.facility_id,'cost_line_id',result.id,
      'previous',previous_value,'new',pg_catalog.to_jsonb(result),'recorded_at',pg_catalog.now())::text);
  return pg_catalog.jsonb_build_object('ok',true,'cost_line',pg_catalog.to_jsonb(result),'actual_costing_confirmed',false);
exception
  when check_violation or foreign_key_violation or invalid_text_representation or numeric_value_out_of_range then
    return public.work_order_result_error('VALIDATION_ERROR','Actual cost data is invalid.');
  when others then return public.work_order_result_error('INTERNAL_ERROR','Actual cost could not be recorded.');
end;$function$;
-- D-24 (28 Oct 2026): for contractor work with an approved quotation, the work is submitted for review together
-- with the official quotation: the final cost must be saved (price unchanged = the approved quotation; variation =
-- the contractor's revised quotation attached). Emergency work keeps its after-the-fact quotation route.
create or replace function public.submit_physical_completion(p_work_order_id uuid,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; agreed numeric;
begin
  if actor is null or actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Active field execution authority is required.');
  end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.assigned_technician_id is distinct from (actor->>'id')::uuid or not public.field_work_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility field owner may submit physical completion.');
  end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Physical completion requires active assigned work.'); end if;
  if w.actual_costs_confirmed_at is null or w.actual_costs_confirmed_by is distinct from (actor->>'id')::uuid then
    return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Confirm the execution cost ledger, including a genuine zero-cost result, before physical completion.');
  end if;
  select c.approved_budget into agreed from public.work_order_financial_controls c where c.work_order_id=w.id;
  if not w.in_house_work and not w.emergency_work and agreed is not null then
    if not exists(select 1 from public.work_order_final_cost_submissions fc where fc.work_order_id=w.id and fc.status<>'draft') then
      return public.work_order_result_error('FINAL_COST_REQUIRED','Save the Final Cost Reconciliation first: price unchanged (the approved quotation), or a variation order with the contractor''s revised quotation.');
    end if;
    if public.work_order_final_quotation_missing(w.id) then
      return public.work_order_result_error('FINAL_QUOTATION_REQUIRED','Attach the contractor''s revised quotation for the variation order before submitting the work.');
    end if;
  end if;
  return public.submit_physical_completion_20260921_core(p_work_order_id,p_payload);
end;$function$;


do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.save_work_order_final_cost_r1_scope_core(uuid,jsonb)'::regprocedure), 'derived_actual:=contractor') = 0 then
    raise exception 'D-22 actual cost from the final contractor charge was not installed';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.manage_work_order_actual_cost(uuid,uuid,jsonb)'::regprocedure), 'work_order_actual_cost_deleted') = 0 then
    raise exception 'D-23 cost-line deletion was not installed';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.submit_physical_completion(uuid,jsonb)'::regprocedure), 'FINAL_QUOTATION_REQUIRED') = 0 then
    raise exception 'D-24 submission with the official quotation was not installed';
  end if;
end;$postcheck$;
commit;

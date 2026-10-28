begin;
-- D-21 (28 Oct 2026): the assigned Technician may correct an actual-cost line typed in by mistake while the
-- Work Order is Submitted for Review (before the review), without a Reject & Reopen. Any correction clears the
-- costing confirmation and the saved final cost; both must be confirmed and saved again, and the second
-- Technician's endorsement no longer counts until given again.

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
  -- D-21: a saved final cost no longer matches the ledger; it must be saved again (and re-endorsed, D-20).
  update public.work_order_final_cost_submissions set status='draft',updated_at=pg_catalog.now() where work_order_id=w.id and status<>'draft';
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

-- The endorsement fingerprint also covers the confirmed actual cost and the final-cost status.
create or replace function public.work_order_final_cost_fingerprint(p_work_order_id uuid) returns text
language sql stable security definer set search_path = pg_catalog as $function$
  select pg_catalog.md5(pg_catalog.concat_ws('|', fc.final_contractor_amount::text, fc.variation_order::text, fc.variation_justification,
    fc.confirmed_actual_cost::text, fc.status,
    (select pg_catalog.string_agg(d.id::text, ',' order by d.id) from public.work_order_final_cost_documents d
      where d.final_cost_submission_id = fc.id and d.deleted_at is null)))
  from public.work_order_final_cost_submissions fc where fc.work_order_id = p_work_order_id
$function$;

-- A final cost reset to draft by a cost correction must be saved again before the endorsement.
create or replace function public.work_order_review_endorsement_block(p_work_order_id uuid) returns jsonb
language sql stable security definer set search_path = pg_catalog as $function$
  select case
    when w.in_house_work then null
    when not exists(select 1 from public.work_order_final_cost_submissions fc where fc.work_order_id = w.id and fc.status <> 'draft') then
      pg_catalog.jsonb_build_object('code','FINAL_COST_REQUIRED','message','The responsible Technician must save the final cost before the second Technician endorses.')
    when public.work_order_final_quotation_missing(w.id) then
      pg_catalog.jsonb_build_object('code','FINAL_QUOTATION_REQUIRED','message','The contractor''s revised quotation for the variation order must be attached before the second Technician endorses.')
    else null end
  from public.work_orders w where w.id = p_work_order_id
$function$;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.manage_work_order_actual_cost(uuid,uuid,jsonb)'::regprocedure), 'read-only after the review') = 0
    or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.work_order_final_cost_fingerprint(uuid)'::regprocedure), 'confirmed_actual_cost') = 0 then
    raise exception 'D-21 actual-cost correction was not installed';
  end if;
end;$postcheck$;
commit;

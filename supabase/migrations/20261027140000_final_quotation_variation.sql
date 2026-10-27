begin;
-- D-19 and D-20 (27 Oct 2026): after the work, the Technician must state whether there was a variation order.
-- No variation: the approved quotation is recorded as the final quotation and the final charge must equal it.
-- Variation: the contractor's revised quotation must be attached before the review.

alter table public.work_order_final_cost_submissions
  add column if not exists variation_order boolean,
  add column if not exists final_quotation_id uuid references public.contractor_quotations(id) on delete restrict,
  add column if not exists variation_justification text check (variation_justification is null or pg_catalog.length(variation_justification) between 10 and 2000);

comment on column public.work_order_final_cost_submissions.variation_order is
  'D-19: false = price unchanged (final_quotation_id = the approved quotation); true = variation order, revised quotation attached as a final-cost document; null = saved before D-19.';

-- The scope wrapper public.save_work_order_final_cost calls this core (20261003043000).
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
  if w.actual_costs_confirmed_at is null or w.actual_labour_hours is null then return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Physical labour and the execution cost ledger must be confirmed before final reconciliation.'); end if;
  select p.status into payment_status from public.contractor_payment_assessments p where p.work_order_id=w.id;
  if payment_status in ('awaiting_approval','approved_for_payment','paid') then return public.work_order_result_error('FINANCIAL_RECORD_IMMUTABLE','Final cost cannot change after the payment proposal is submitted.'); end if;
  begin contractor:=(p_payload->>'final_contractor_amount')::numeric; claimed_actual:=nullif(p_payload->>'confirmed_actual_cost','')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Final contractor amount or claimed actual cost is invalid.'); end;
  select coalesce(pg_catalog.sum(c.amount),0) into derived_actual from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
  note:=nullif(pg_catalog.btrim(coalesce(p_payload->>'comments','')),'');
  if contractor is null or contractor<0 or note is null or length(note)>2000 then return public.work_order_result_error('VALIDATION_ERROR','Final contractor amount and comments are required.'); end if;
  if claimed_actual is not null and claimed_actual<>derived_actual then return public.work_order_result_error('ACTUAL_COST_MISMATCH','Confirmed actual cost must equal the execution cost ledger total.'); end if;
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
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_cost_reconciled',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('submission_id',result.id,'approved_quotation',approved,'actual_contractor_charge',contractor,'actual_repair_cost',derived_actual,'actual_labour_hours',w.actual_labour_hours,'variance',derived_actual-coalesce(approved,0),'quotation_excluded_from_actual_total',true,'status',next_status,
    'variation_order',variation,'variation_justification',justification,'final_quotation',case when variation then 'revised quotation to be attached' when variation is false then coalesce(final_ref,'approved quotation') end)::text);
  return pg_catalog.jsonb_build_object('ok',true,'final_cost',pg_catalog.to_jsonb(result),'approved_quotation',approved,'actual_repair_cost',derived_actual,'variance',derived_actual-coalesce(approved,0));
end;$function$;

-- Missing final quotation: a variation order without the revised quotation attached; for costs saved
-- before D-19, the old rule (final cost differs from the approved quotation and nothing attached).
create or replace function public.work_order_final_quotation_missing(p_work_order_id uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $function$
  select coalesce((
    select not exists(select 1 from public.work_order_final_cost_documents d where d.final_cost_submission_id=fc.id and d.deleted_at is null)
      and (fc.variation_order is true
        or (fc.variation_order is null and fc.confirmed_actual_cost is not null
            and coalesce(c.approved_budget,c.quoted_cost) is not null
            and fc.confirmed_actual_cost <> coalesce(c.approved_budget,c.quoted_cost)))
    from public.work_orders w
    join public.work_order_final_cost_submissions fc on fc.work_order_id=w.id
    left join public.work_order_financial_controls c on c.work_order_id=w.id
    where w.id=p_work_order_id and not w.in_house_work), false)
$function$;
revoke all on function public.work_order_final_quotation_missing(uuid) from public, anon, authenticated, service_role;

-- D-20 (27 Oct 2026): the second Technician's review endorsement covers the final cost and any variation order.
-- It can be given only once the final cost (and the revised quotation, for a variation) is in place, and it
-- stops counting if the final charge, the variation answer, the justification or the attached quotation change.
alter table public.work_order_endorsements add column if not exists final_cost_fingerprint text;

create function public.work_order_final_cost_fingerprint(p_work_order_id uuid) returns text
language sql stable security definer set search_path = pg_catalog as $function$
  select pg_catalog.md5(pg_catalog.concat_ws('|', fc.final_contractor_amount::text, fc.variation_order::text, fc.variation_justification,
    (select pg_catalog.string_agg(d.id::text, ',' order by d.id) from public.work_order_final_cost_documents d
      where d.final_cost_submission_id = fc.id and d.deleted_at is null)))
  from public.work_order_final_cost_submissions fc where fc.work_order_id = p_work_order_id
$function$;
revoke all on function public.work_order_final_cost_fingerprint(uuid) from public, anon, authenticated, service_role;

-- What blocks a review endorsement right now (null = nothing): contractor work needs the final cost first,
-- and a variation order needs the revised quotation attached.
create function public.work_order_review_endorsement_block(p_work_order_id uuid) returns jsonb
language sql stable security definer set search_path = pg_catalog as $function$
  select case
    when w.in_house_work then null
    when not exists(select 1 from public.work_order_final_cost_submissions fc where fc.work_order_id = w.id) then
      pg_catalog.jsonb_build_object('code','FINAL_COST_REQUIRED','message','The responsible Technician must save the final cost before the second Technician endorses.')
    when public.work_order_final_quotation_missing(w.id) then
      pg_catalog.jsonb_build_object('code','FINAL_QUOTATION_REQUIRED','message','The contractor''s revised quotation for the variation order must be attached before the second Technician endorses.')
    else null end
  from public.work_orders w where w.id = p_work_order_id
$function$;
revoke all on function public.work_order_review_endorsement_block(uuid) from public, anon, authenticated, service_role;

create or replace function public.work_order_endorsement_missing(p_work_order_id uuid, p_stage text) returns boolean
language sql stable security definer set search_path = pg_catalog as $function$
  with w as (select wo.*, public.work_order_endorsement_stage(wo.facility_id) as setting from public.work_orders wo where wo.id = p_work_order_id)
  select coalesce((select case
      when p_stage = 'submission' then not w.emergency_work and w.setting in ('before_submission','both')
      when p_stage = 'review' then w.setting in ('before_review','both') or (w.emergency_work and w.setting = 'before_submission')
      else false end
    and not exists(select 1 from public.work_order_endorsements e where e.work_order_id = w.id and e.stage = p_stage
      and e.cycle = public.work_order_endorsement_cycle(w.id, p_stage)
      and (p_stage = 'submission' or e.final_cost_fingerprint is not distinct from public.work_order_final_cost_fingerprint(w.id))) from w), false)
$function$;

create or replace function public.endorse_work_order(p_work_order_id uuid, p_statement text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; stage text; result public.work_order_endorsements%rowtype; block jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id := (actor->>'id')::uuid;
  if not public.release1_work_order_visible(p_work_order_id) then return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.'); end if;
  select * into w from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role' <> 'technician' or not public.technician_facility_read_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Only a Technician of this facility may endorse a Work Order.'); end if;
  if actor_id = w.assigned_technician_id or actor_id = w.requested_by then
    return public.work_order_result_error('ACCESS_DENIED','A second Technician, not the one responsible for this Work Order, must endorse it.'); end if;
  stage := case w.status when 'draft' then 'submission' when 'completed' then 'review' else null end;
  if stage is null then return public.work_order_result_error('INVALID_TRANSITION','Endorsement is given while the Work Order is a Draft or Submitted for Review.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_statement,''))) < 10 then
    return public.work_order_result_error('VALIDATION_ERROR','State what you checked (at least 10 characters).'); end if;
  if not public.work_order_endorsement_missing(w.id, stage) then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','message','No endorsement is required at this stage, or it has already been given.'); end if;
  if stage = 'review' then
    block := public.work_order_review_endorsement_block(w.id);
    if block is not null then return public.work_order_result_error(block->>'code', block->>'message'); end if;
  end if;
  insert into public.work_order_endorsements(work_order_id, stage, endorsed_by, statement, cycle, final_cost_fingerprint)
  values (w.id, stage, actor_id, pg_catalog.btrim(p_statement), public.work_order_endorsement_cycle(w.id, stage),
    case when stage = 'review' then public.work_order_final_cost_fingerprint(w.id) end) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values (actor_id, w.id, 'work_order_endorsed', w.status, w.status, coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('endorsement_id',result.id,'stage',stage,'statement',result.statement,
      'final_cost', case when stage = 'review' then (select pg_catalog.jsonb_build_object('final_contractor_amount',fc.final_contractor_amount,
        'variation_order',fc.variation_order,'variation_justification',fc.variation_justification)
        from public.work_order_final_cost_submissions fc where fc.work_order_id = w.id) end)::text);
  perform public.work_order_notify(w.id, 'work_order_endorsed', false, true, actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'endorsement',pg_catalog.to_jsonb(result));
end;$function$;

-- Endorsement status for anyone who can see the Work Order (drives the endorsement panel).
create function public.work_order_endorsement_status(p_work_order_id uuid) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog as $function$
declare w public.work_orders%rowtype; stage text; fc public.work_order_final_cost_submissions%rowtype; superseded boolean := false;
begin
  if public.work_order_actor() is null or not public.release1_work_order_visible(p_work_order_id) then
    return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.'); end if;
  select * into w from public.work_orders where id = p_work_order_id;
  stage := case w.status when 'draft' then 'submission' when 'completed' then 'review' else null end;
  select * into fc from public.work_order_final_cost_submissions where work_order_id = w.id;
  if stage = 'review' then
    superseded := exists(select 1 from public.work_order_endorsements e where e.work_order_id = w.id and e.stage = 'review'
      and e.cycle = public.work_order_endorsement_cycle(w.id, 'review')
      and e.final_cost_fingerprint is distinct from public.work_order_final_cost_fingerprint(w.id));
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'stage', stage,
    'due', stage is not null and public.work_order_endorsement_missing(w.id, stage),
    'blocked', case when stage = 'review' then public.work_order_review_endorsement_block(w.id) end,
    'superseded', superseded and public.work_order_endorsement_missing(w.id, 'review'),
    'final_cost', case when fc.id is null then null else pg_catalog.jsonb_build_object('final_contractor_amount', fc.final_contractor_amount,
      'variation_order', fc.variation_order, 'variation_justification', fc.variation_justification,
      'documents', (select pg_catalog.count(*) from public.work_order_final_cost_documents d where d.final_cost_submission_id = fc.id and d.deleted_at is null)) end);
end;$function$;
revoke all on function public.work_order_endorsement_status(uuid) from public, anon, service_role;
grant execute on function public.work_order_endorsement_status(uuid) to authenticated;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.save_work_order_final_cost_r1_scope_core(uuid,jsonb)'::regprocedure), 'VARIATION_CONFIRMATION_REQUIRED') = 0
    or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.work_order_final_quotation_missing(uuid)'::regprocedure), 'variation_order is true') = 0 then
    raise exception 'D-19 final quotation rule was not installed';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.work_order_endorsement_missing(uuid,text)'::regprocedure), 'final_cost_fingerprint') = 0 then
    raise exception 'D-20 endorsement rule was not installed';
  end if;
end;$postcheck$;
commit;

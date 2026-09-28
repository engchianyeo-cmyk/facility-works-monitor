-- Release-1 quotation threshold control: one quote below S$1,000 and three
-- distinct eligible-contractor quotes at or above S$1,000.
begin;

create or replace function public.prepare_work_order_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
  control public.work_order_financial_controls%rowtype; vendor uuid; amount numeric; governed_estimate numeric; scope_text text; rule uuid;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare a proposal.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Proposal preparation requires active assigned work.'); end if;
  begin vendor:=(p_payload->>'vendor_id')::uuid; amount:=(p_payload->>'proposed_amount')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Eligible contractor and proposed amount are required.'); end;
  scope_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'scope_summary','')),'');
  if amount is null or amount<0 or scope_text is null or length(scope_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','Repair scope and non-negative proposed amount are required.'); end if;
  if not exists(select 1 from public.vendor_facility_eligibility e join public.vendors v on v.id=e.vendor_id where e.vendor_id=vendor and e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and v.active and v.deleted_at is null) then return public.work_order_result_error('CONTRACTOR_INELIGIBLE','Select a Procurement-prequalified, Facility-confirmed contractor.'); end if;
  if exists(select 1 from public.contractor_quotations x where x.work_order_id=w.id and x.vendor_id=vendor and x.status in ('draft','submitted','approved')) then return public.work_order_result_error('DUPLICATE_CONTRACTOR_QUOTATION','A current quotation for this contractor already exists.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  governed_estimate:=greatest(coalesce(control.estimated_cost,0),amount);
  select id into rule from public.commercial_approval_rules where active and governed_estimate>=minimum_amount and (maximum_amount is null or governed_estimate<maximum_amount) order by minimum_amount desc limit 1;
  if rule is null then return public.work_order_result_error('COMMERCIAL_RULE_REQUIRED','No commercial approval rule covers this amount.'); end if;
  insert into public.work_order_financial_controls(work_order_id,estimated_cost,rule_id,cost_status)
  values(w.id,governed_estimate,rule,'draft') on conflict(work_order_id) do update set estimated_cost=governed_estimate,rule_id=rule,cost_status='draft',quoted_cost=null,approved_budget=null,recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now();
  insert into public.contractor_quotations(work_order_id,vendor_id,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary)
  values(w.id,vendor,coalesce((select max(version_no)+1 from public.contractor_quotations where work_order_id=w.id),1),'draft','SGD',amount,actor_id,pg_catalog.now(),pg_catalog.now(),scope_text) returning * into q;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_competing_quotation_prepared',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('vendor_id',vendor,'quotation_id',q.id,'quoted_amount',amount,'governed_estimate',governed_estimate,'decision_pending',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$;

create or replace function public.submit_work_order_proposal(p_work_order_id uuid,p_quotation_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype;
  required_count integer; collected_count integer; note_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Draft proposal was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or q.prepared_by is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician who prepared the draft may submit it.'); end if;
  if q.status not in ('draft','returned') then return public.work_order_result_error('INVALID_TRANSITION','Only a draft or returned proposal may be submitted.'); end if;
  if not exists(select 1 from public.work_order_commercial_documents d where d.quotation_id=q.id and d.document_type='quotation' and d.deleted_at is null) then return public.work_order_result_error('QUOTATION_DOCUMENT_REQUIRED','Attach the authentic contractor quotation before submission.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  update public.contractor_quotations set status='submitted',submitted_by=actor_id,submitted_at=pg_catalog.now(),submission_note=nullif(pg_catalog.btrim(coalesce(p_note,'')),''),updated_at=pg_catalog.now() where id=q.id returning * into q;
  select count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  note_text:=coalesce(nullif(pg_catalog.btrim(coalesce(p_note,'')),''),'Authentic quotation submitted for governed comparison.');
  if coalesce(required_count,1)=1 then
    update public.work_orders set recommended_vendor_id=q.vendor_id,updated_at=pg_catalog.now() where id=w.id;
    update public.work_order_financial_controls set quoted_cost=q.total_amount,cost_status='recommended',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=note_text,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,approved_budget=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  else
    update public.work_order_financial_controls set cost_status='quotation_recorded',quoted_cost=null,recommended_by=null,recommended_at=null,recommendation_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_quotation_submitted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'vendor_id',q.vendor_id,'quoted_amount',q.total_amount,'required_quotations',required_count,'distinct_quotations_collected',collected_count,'ready_for_selection',collected_count>=coalesce(required_count,1))::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q),'required_quotations',required_count,'collected_quotations',collected_count,'ready_for_selection',collected_count>=coalesce(required_count,1));
end;$function$;

create or replace function public.recommend_work_order_quotation(p_work_order_id uuid,p_quotation_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer; note_text text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id and status='submitted'; select * into control from public.work_order_financial_controls where work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null or control.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Submitted quotation collection was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may recommend a quotation.'); end if;
  if note_text is null or length(note_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A bounded selection rationale is required.'); end if;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  select count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  if collected_count<coalesce(required_count,1) then return public.work_order_result_error('INSUFFICIENT_QUOTATIONS','Collect the required number of distinct eligible-contractor quotations before recommendation.'); end if;
  update public.work_orders set recommended_vendor_id=q.vendor_id,updated_at=pg_catalog.now() where id=w.id;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,cost_status='recommended',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=note_text,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,approved_budget=null,updated_at=pg_catalog.now() where work_order_id=w.id returning * into control;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_quotation_recommended',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'vendor_id',q.vendor_id,'quoted_amount',q.total_amount,'governed_estimate',control.estimated_cost,'required_quotations',required_count,'collected_quotations',collected_count,'selection_rationale',note_text)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q),'financial',pg_catalog.to_jsonb(control));
end;$function$;

-- Add the collection/readiness checks to the existing independent approval function.
alter function public.approve_work_order_proposal(uuid,uuid,text) rename to approve_work_order_proposal_20260924_core;
create or replace function public.approve_work_order_proposal(p_work_order_id uuid,p_quotation_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id; select * into control from public.work_order_financial_controls where work_order_id=p_work_order_id;
  if w.id is null or q.id is null or control.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Recommended quotation was not found.'); end if;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active; select count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  if control.cost_status<>'recommended' or w.recommended_vendor_id is distinct from q.vendor_id or control.quoted_cost is distinct from q.total_amount then return public.work_order_result_error('APPROVAL_NOT_READY','Select and justify the recommended quotation before approval.'); end if;
  if collected_count<coalesce(required_count,1) then return public.work_order_result_error('INSUFFICIENT_QUOTATIONS','The configured quotation count has not been met.'); end if;
  return public.approve_work_order_proposal_20260924_core(p_work_order_id,p_quotation_id,p_note);
end;$function$;

revoke all on function public.prepare_work_order_proposal(uuid,jsonb),public.submit_work_order_proposal(uuid,uuid,text),public.recommend_work_order_quotation(uuid,uuid,text),public.approve_work_order_proposal(uuid,uuid,text),public.approve_work_order_proposal_20260924_core(uuid,uuid,text) from public,anon,service_role,authenticated;
grant execute on function public.prepare_work_order_proposal(uuid,jsonb),public.submit_work_order_proposal(uuid,uuid,text),public.recommend_work_order_quotation(uuid,uuid,text),public.approve_work_order_proposal(uuid,uuid,text) to authenticated;

do $postconditions$
begin
  if pg_catalog.has_function_privilege('authenticated','public.approve_work_order_proposal_20260924_core(uuid,uuid,text)','EXECUTE') then raise exception 'Three-quotation approval core must remain private'; end if;
end;$postconditions$;

commit;

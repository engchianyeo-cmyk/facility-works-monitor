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

revoke all on function public.prepare_work_order_proposal(uuid,jsonb) from public,anon,service_role;
grant execute on function public.prepare_work_order_proposal(uuid,jsonb) to authenticated;

commit;

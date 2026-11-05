begin;
-- UAT 5 Nov 2026 (WO-TEST-005): approving a contractor quotation failed with "workflow service temporarily
-- unavailable". The Work Order still carried an in-house team assignment (from imported test data), and a Work
-- Order may be assigned to a team or a contractor, not both (work_orders_primary_assignment_check). Approving the
-- contractor's quotation now releases any in-house team assignment; the released team is kept in the approval's
-- activity record. Only the core function changes; the public wrappers are untouched.

create or replace function public.approve_work_order_proposal_20260924_core(p_work_order_id uuid, p_quotation_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Submitted proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent financial approval authority is required.'); end if;
  if q.submitted_by=actor_id or q.prepared_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','A proposal preparer cannot approve the same expenditure.'); end if;
  if q.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only a submitted proposal may be approved.'); end if;
  if nullif(btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('VALIDATION_ERROR','An independent approval note is required.'); end if;
  if not exists(select 1 from public.work_order_commercial_documents d where d.quotation_id=q.id and d.document_type='quotation' and d.deleted_at is null) then return public.work_order_result_error('QUOTATION_DOCUMENT_REQUIRED','The supporting quotation document is required for approval.'); end if;
  if not exists(select 1 from public.vendor_facility_eligibility e where e.vendor_id=q.vendor_id and e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed) then return public.work_order_result_error('CONTRACTOR_INELIGIBLE','The recommended contractor is no longer eligible.'); end if;
  update public.contractor_quotations set status='superseded',updated_at=now() where work_order_id=w.id and id<>q.id and status='approved';
  update public.contractor_quotations set status='approved',approved_by=actor_id,approved_at=now(),approval_note=btrim(p_note),updated_at=now() where id=q.id returning * into q;
  update public.work_orders set assigned_vendor_id=q.vendor_id,recommended_vendor_id=q.vendor_id,assigned_team_id=null,updated_at=now() where id=w.id;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,approved_budget=q.total_amount,cost_status='approved',financial_approved_by=actor_id,financial_approved_at=now(),financial_approval_note=btrim(p_note),updated_at=now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_independently_approved',w.status,w.status,actor->>'name',jsonb_build_object('quotation_id',q.id,'version_no',q.version_no,'approved_amount',q.total_amount,'selected_vendor_id',q.vendor_id,'supporting_document_locked',true,'prepared_by',q.prepared_by,'approved_by',actor_id,'self_approval',false,'released_team_id',w.assigned_team_id)::text);
  return jsonb_build_object('ok',true,'quotation',to_jsonb(q));
end;$function$;


do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.approve_work_order_proposal_20260924_core(uuid,uuid,text)'::regprocedure),
       'assigned_team_id=null') = 0 then
    raise exception 'Contractor approval does not release the in-house team assignment';
  end if;
end;$postcheck$;
commit;

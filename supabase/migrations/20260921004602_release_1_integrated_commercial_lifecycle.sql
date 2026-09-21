begin;

insert into public.commercial_approval_rules(rule_code,minimum_amount,maximum_amount,minimum_quotations)
values('SGD_1000_AND_ABOVE_THREE_QUOTES',1000,null,3)
on conflict(rule_code) do update set minimum_amount=excluded.minimum_amount,maximum_amount=excluded.maximum_amount,minimum_quotations=excluded.minimum_quotations,active=true;

alter table public.work_orders
  add column if not exists recommended_vendor_id uuid references public.vendors(id) on delete restrict;

create table public.vendor_facility_eligibility(
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  facility_id uuid not null references public.sites(id) on delete restrict,
  procurement_prequalified boolean not null default false,
  facility_confirmed boolean not null default false,
  confirmation_basis text not null,
  confirmed_by uuid references public.profiles(id) on delete restrict,
  confirmed_at timestamptz not null default now(),
  active boolean not null default true,
  primary key(vendor_id,facility_id),
  check(length(btrim(confirmation_basis)) between 1 and 1000)
);
alter table public.vendor_facility_eligibility enable row level security;
revoke all on public.vendor_facility_eligibility from public,anon,authenticated;
grant select on public.vendor_facility_eligibility to authenticated;
create policy vendor_facility_eligibility_read on public.vendor_facility_eligibility
for select to authenticated using(public.pilot_account_ready());

insert into public.vendor_facility_eligibility(vendor_id,facility_id,procurement_prequalified,facility_confirmed,confirmation_basis)
select distinct w.assigned_vendor_id,w.facility_id,true,true,'Existing governed Work Order contractor relationship'
from public.work_orders w
where w.work_order_number='WO-TEST-012' and w.assigned_vendor_id is not null and w.facility_id is not null
on conflict(vendor_id,facility_id) do nothing;

create or replace function public.work_order_eligible_contractors(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may review eligible contractors.');
  end if;
  if actor->>'role' not in ('technician','approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Commercial access is required.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'trade',v.trade,'payment_terms_days',v.payment_terms_days) order by v.name),'[]'::jsonb)
  into result from public.vendor_facility_eligibility e join public.vendors v on v.id=e.vendor_id
  where e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and v.active and v.deleted_at is null;
  return jsonb_build_object('ok',true,'contractors',result);
end;$function$;

create or replace function public.prepare_work_order_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; vendor uuid; amount numeric; scope_text text; rule uuid;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare a proposal.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Proposal preparation requires active assigned work.'); end if;
  begin vendor:=(p_payload->>'vendor_id')::uuid; amount:=(p_payload->>'proposed_amount')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Eligible contractor and proposed amount are required.'); end;
  scope_text:=nullif(btrim(coalesce(p_payload->>'scope_summary','')),'');
  if amount is null or amount<0 or scope_text is null then return public.work_order_result_error('VALIDATION_ERROR','Repair scope and non-negative proposed amount are required.'); end if;
  if not exists(select 1 from public.vendor_facility_eligibility e join public.vendors v on v.id=e.vendor_id where e.vendor_id=vendor and e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and v.active and v.deleted_at is null) then return public.work_order_result_error('CONTRACTOR_INELIGIBLE','Select a Procurement-prequalified, Facility-confirmed contractor.'); end if;
  select id into rule from public.commercial_approval_rules where active and amount>=minimum_amount and (maximum_amount is null or amount<maximum_amount) order by minimum_amount desc limit 1;
  if rule is null then return public.work_order_result_error('COMMERCIAL_RULE_REQUIRED','No commercial approval rule covers this amount.'); end if;
  update public.work_orders set recommended_vendor_id=vendor,updated_at=now() where id=w.id;
  insert into public.work_order_financial_controls(work_order_id,estimated_cost,rule_id,cost_status)
  values(w.id,amount,rule,'draft') on conflict(work_order_id) do update set estimated_cost=excluded.estimated_cost,rule_id=excluded.rule_id,cost_status='draft',quoted_cost=null,approved_budget=null,recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=now();
  insert into public.contractor_quotations(work_order_id,vendor_id,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary)
  values(w.id,vendor,coalesce((select max(version_no)+1 from public.contractor_quotations where work_order_id=w.id),1),'draft','SGD',amount,actor_id,now(),now(),scope_text) returning * into q;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_contractor_recommended',w.status,w.status,actor->>'name',jsonb_build_object('vendor_id',vendor,'quotation_id',q.id,'proposed_amount',amount,'decision_pending_independent_approval',true)::text);
  return jsonb_build_object('ok',true,'quotation',to_jsonb(q));
end;$function$;

create or replace function public.save_work_order_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; amount numeric; scope_text text; quote_ref text; quote_date date; legal_name text; gst text; itemization text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare this proposal.'); end if;
  select * into q from public.contractor_quotations where work_order_id=w.id and status in ('draft','returned') order by updated_at desc limit 1 for update;
  if q.id is null then return public.work_order_result_error('PROPOSAL_REQUIRED','Prepare a governed contractor proposal first.'); end if;
  begin amount:=(p_payload->>'proposed_amount')::numeric; quote_date:=nullif(p_payload->>'quotation_date','')::date; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Proposed amount or quotation date is invalid.'); end;
  scope_text:=nullif(btrim(coalesce(p_payload->>'scope_summary','')),''); quote_ref:=nullif(btrim(coalesce(p_payload->>'quotation_ref','')),''); legal_name:=nullif(btrim(coalesce(p_payload->>'contractor_legal_name','')),''); gst:=nullif(btrim(coalesce(p_payload->>'gst_treatment','')),''); itemization:=nullif(btrim(coalesce(p_payload->>'itemization_note','')),'');
  if amount is null or amount<0 or scope_text is null then return public.work_order_result_error('VALIDATION_ERROR','A valid proposal amount and repair scope are required.'); end if;
  update public.contractor_quotations set quotation_ref=quote_ref,quotation_date=quote_date,total_amount=amount,status='draft',prepared_by=actor_id,prepared_at=coalesce(prepared_at,now()),draft_saved_at=now(),scope_summary=scope_text,contractor_legal_name=legal_name,gst_treatment=gst,itemization_note=itemization,submitted_by=null,submitted_at=null,approved_by=null,approved_at=null,approval_note=null,updated_at=now() where id=q.id returning * into q;
  update public.work_order_financial_controls set estimated_cost=amount,updated_at=now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_draft_saved',w.status,w.status,actor->>'name',jsonb_build_object('quotation_id',q.id,'proposed_amount',amount)::text);
  return jsonb_build_object('ok',true,'quotation',to_jsonb(q));
end;$function$;

create or replace function public.return_work_order_proposal(p_work_order_id uuid,p_quotation_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Submitted proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent approval authority is required.'); end if;
  if q.status<>'submitted' or nullif(btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('INVALID_TRANSITION','A submitted proposal and return reason are required.'); end if;
  update public.contractor_quotations set status='returned',approval_note=btrim(p_note),updated_at=now() where id=q.id returning * into q;
  update public.work_order_financial_controls set cost_status='returned',financial_approved_by=null,financial_approved_at=null,financial_approval_note=btrim(p_note),updated_at=now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_returned',w.status,w.status,actor->>'name',jsonb_build_object('quotation_id',q.id,'reason',btrim(p_note))::text);
  return jsonb_build_object('ok',true,'quotation',to_jsonb(q));
end;$function$;

create or replace function public.return_work_order_payment(p_work_order_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Payment proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent payment authority is required.'); end if;
  if result.status<>'awaiting_approval' or nullif(btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('INVALID_TRANSITION','An awaiting-approval payment proposal and return reason are required.'); end if;
  update public.contractor_payment_assessments set status='returned',approval_note=btrim(p_note),updated_at=now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_payment_proposal_returned',w.status,w.status,actor->>'name',jsonb_build_object('payment_assessment_id',result.id,'reason',btrim(p_note))::text);
  return jsonb_build_object('ok',true,'payment',to_jsonb(result));
end;$function$;

create or replace function public.approve_work_order_proposal(p_work_order_id uuid,p_quotation_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
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
  update public.work_orders set assigned_vendor_id=q.vendor_id,recommended_vendor_id=q.vendor_id,updated_at=now() where id=w.id;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,approved_budget=q.total_amount,cost_status='approved',financial_approved_by=actor_id,financial_approved_at=now(),financial_approval_note=btrim(p_note),updated_at=now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_independently_approved',w.status,w.status,actor->>'name',jsonb_build_object('quotation_id',q.id,'version_no',q.version_no,'approved_amount',q.total_amount,'selected_vendor_id',q.vendor_id,'supporting_document_locked',true,'prepared_by',q.prepared_by,'approved_by',actor_id,'self_approval',false)::text);
  return jsonb_build_object('ok',true,'quotation',to_jsonb(q));
end;$function$;

revoke all on function public.work_order_eligible_contractors(uuid),public.prepare_work_order_proposal(uuid,jsonb),public.return_work_order_proposal(uuid,uuid,text),public.return_work_order_payment(uuid,text) from public,anon,service_role;
grant execute on function public.work_order_eligible_contractors(uuid),public.prepare_work_order_proposal(uuid,jsonb),public.return_work_order_proposal(uuid,uuid,text),public.return_work_order_payment(uuid,text) to authenticated;

commit;

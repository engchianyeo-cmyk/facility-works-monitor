-- WP-LC2-M2: Work Order Lifecycle v2 — creation, Draft quotation, single approval,
-- return to Draft, emergency start. Design §3.1–3.3, §3.6, §4 (approved 2026-10-20).
--
-- * Technicians create Work Orders and are auto-assigned; a superior (Approver,
--   Supervisor, Facility Manager, Administrator) may create one when the Technician is
--   unavailable and assigns a Technician. Initiator, Reviewer and Finance cannot create.
-- * The preparer (assigned Technician, or the creating superior while Draft/Submitted)
--   attaches evidence and prepares quotations in Draft.
-- * submit: Draft -> Awaiting Approval with justification and a recommended quotation
--   meeting the company quotation count; emergency Work Orders start immediately.
-- * approve: one approval of the Work Order and its quotation under the single
--   approval-authority rule; the Work Order goes straight to Assigned.
-- * return: an approval authority returns a submitted Work Order to Draft with a reason.
-- Existing functions are replaced in full below with only the commented changes.

do $preflight$
begin
  if current_user <> 'postgres' then raise exception 'LC2-M2 must be applied as postgres'; end if;
  if pg_catalog.to_regprocedure('public.work_order_approval_authority(uuid,numeric,text)') is null then
    raise exception 'LC2-M2 requires LC2-M1'; end if;
  if pg_catalog.to_regprocedure('public.work_order_preparer_permitted(uuid)') is not null
    or pg_catalog.to_regprocedure('public.transition_work_order_20261020_core(uuid,text,jsonb)') is not null then
    raise exception 'LC2-M2 conflicting or partial state already exists'; end if;
end;$preflight$;

-- Preparer: the assigned same-facility Technician; or the superior who created the
-- Work Order, while it is still Draft or Awaiting Approval.
create function public.work_order_preparer_permitted(p_work_order_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and exists (
    select 1 from public.work_orders w where w.id=p_work_order_id and (
      (public.current_user_role()='technician' and w.assigned_technician_id=auth.uid()
        and public.technician_facility_read_permitted(w.facility_id))
      or (w.requested_by=auth.uid() and w.status in ('draft','submitted')
        and public.current_user_role() in ('approver','supervisor','facility_manager','administrator')
        and public.approval_facility_permitted(w.facility_id))
    )
  )
$function$;

-- Recipients: approval authorities for the facility (Administrators, and Approver /
-- Supervisor / Facility Manager members), copied parties, and the assigned Technician.
create function public.work_order_notify(p_work_order_id uuid, p_event text, p_include_approvers boolean, p_include_technician boolean, p_exclude uuid default null)
returns integer language plpgsql security definer set search_path=pg_catalog as $function$
declare w public.work_orders%rowtype; n integer; stamp text:=pg_catalog.to_char(pg_catalog.clock_timestamp(),'YYYYMMDDHH24MISSUS');
begin
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return 0; end if;
  insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
  select w.id,p_event,'work_order:'||w.id::text||':'||p_event||':'||stamp,p.id,p.id,p.email,'email',
    pg_catalog.jsonb_build_object('work_order_id',w.id,'work_order_number',w.work_order_number,'status',w.status,'event',p_event),'pending'
  from public.profiles p
  where p.is_active and p.deleted_at is null and p.id is distinct from p_exclude and (
    (p_include_approvers and (p.role='administrator' or exists(
      select 1 from public.facility_memberships fm where fm.profile_id=p.id and fm.facility_id=w.facility_id and fm.active
        and fm.membership_role in ('approver','supervisor','facility_manager') and fm.membership_role=p.role
        and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now()))))
    or exists(select 1 from public.work_order_copied_parties c where c.work_order_id=w.id and c.profile_id=p.id)
    or (p_include_technician and p.id=w.assigned_technician_id)
  )
  on conflict do nothing;
  get diagnostics n=row_count;
  return n;
end;$function$;


-- prepare: preparer rule; allowed in Draft (v2) and during work (emergency, legacy in-flight)
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
  if w.status not in ('draft','assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Quotations are prepared in Draft, or during work for emergency and variation.'); end if;
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

CREATE OR REPLACE FUNCTION public.save_work_order_proposal_20260924_core(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; amount numeric; scope_text text; quote_ref text; quote_date date; legal_name text; gst text; itemization text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if not public.work_order_preparer_permitted(w.id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare this proposal.'); end if;
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

CREATE OR REPLACE FUNCTION public.submit_work_order_proposal_r1_scope_core(p_work_order_id uuid, p_quotation_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype;
  required_count integer; collected_count integer; note_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Draft proposal was not found.'); end if;
  if not public.work_order_preparer_permitted(w.id) or q.prepared_by is distinct from actor_id then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician who prepared the draft may submit it.'); end if;
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

CREATE OR REPLACE FUNCTION public.recommend_work_order_quotation_r1_scope_core(p_work_order_id uuid, p_quotation_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer; note_text text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id and status='submitted'; select * into control from public.work_order_financial_controls where work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null or control.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Submitted quotation collection was not found.'); end if;
  if not public.work_order_preparer_permitted(w.id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may recommend a quotation.'); end if;
  if note_text is null or length(note_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A bounded selection rationale is required.'); end if;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  select count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  if collected_count<coalesce(required_count,1) then return public.work_order_result_error('INSUFFICIENT_QUOTATIONS','Collect the required number of distinct eligible-contractor quotations before recommendation.'); end if;
  update public.work_orders set recommended_vendor_id=q.vendor_id,updated_at=pg_catalog.now() where id=w.id;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,cost_status='recommended',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=note_text,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,approved_budget=null,updated_at=pg_catalog.now() where work_order_id=w.id returning * into control;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_quotation_recommended',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'vendor_id',q.vendor_id,'quoted_amount',q.total_amount,'governed_estimate',control.estimated_cost,'required_quotations',required_count,'collected_quotations',collected_count,'selection_rationale',note_text)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q),'financial',pg_catalog.to_jsonb(control));
end;$function$;

CREATE OR REPLACE FUNCTION public.start_work_order_quotation_revision_r1_scope_core(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; prior public.contractor_quotations%rowtype; result public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if not public.work_order_preparer_permitted(w.id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare a quotation revision.'); end if;
  if w.status in ('completed','reviewed','closed') and not exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open') then return public.work_order_result_error('CORRECTION_REQUIRED','Authorized management must open a supporting-document correction first.'); end if;
  if exists(select 1 from public.contractor_quotations q where q.work_order_id=w.id and q.status in ('draft','returned','submitted')) then return public.work_order_result_error('REVISION_ALREADY_ACTIVE','A quotation revision is already active.'); end if;
  select * into prior from public.contractor_quotations where work_order_id=w.id and status in ('approved','superseded') order by version_no desc limit 1;
  if prior.id is null then return public.work_order_result_error('NOT_FOUND','An approved quotation was not found.'); end if;
  insert into public.contractor_quotations(work_order_id,vendor_id,quotation_ref,quotation_date,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary,contractor_legal_name,gst_treatment,itemization_note)
  values(w.id,w.assigned_vendor_id,prior.quotation_ref,prior.quotation_date,prior.version_no+1,'draft',prior.currency,prior.total_amount,actor_id,pg_catalog.now(),pg_catalog.now(),prior.scope_summary,prior.contractor_legal_name,prior.gst_treatment,prior.itemization_note) returning * into result;
  update public.work_order_financial_controls set cost_status='draft',recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_quotation_revision_started',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('prior_quotation_id',prior.id,'revision_quotation_id',result.id,'version_no',result.version_no,'prior_approved_document_preserved',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(result));
end;$function$;

CREATE OR REPLACE FUNCTION public.void_work_order_supporting_document_r1_scope_core(p_work_order_id uuid, p_document_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; commercial public.work_order_commercial_documents%rowtype;
  final_doc public.work_order_final_cost_documents%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); record_editable boolean:=false;
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into w from public.work_orders where id=p_work_order_id for update;
 if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
 if reason is null or length(reason)>500 then return public.work_order_result_error('VALIDATION_ERROR','A bounded removal reason is required.'); end if;
 if not public.work_order_preparer_permitted(w.id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may remove editable supporting documents.'); end if;
 select * into commercial from public.work_order_commercial_documents where id=p_document_id and work_order_id=w.id and deleted_at is null for update;
 if commercial.id is not null then
   if commercial.document_type='quotation' then record_editable:=exists(select 1 from public.contractor_quotations q where q.id=commercial.quotation_id and q.status in ('draft','returned'));
   elsif commercial.document_type='invoice' then record_editable:=exists(select 1 from public.contractor_payment_assessments p where p.id=commercial.payment_assessment_id and p.status in ('draft','returned'));
   end if;
   if not record_editable then return public.work_order_result_error('APPROVED_DOCUMENT_IMMUTABLE','Submitted or approved supporting documents require a controlled revision.'); end if;
   update public.work_order_commercial_documents set deleted_at=pg_catalog.now(),superseded_by_user=actor_id where id=commercial.id;
 else
   select * into final_doc from public.work_order_final_cost_documents where id=p_document_id and work_order_id=w.id and deleted_at is null for update;
   if final_doc.id is null then return public.work_order_result_error('NOT_FOUND','Supporting document was not found.'); end if;
   if w.status not in ('assigned','in_progress') and not exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open') then return public.work_order_result_error('CORRECTION_REQUIRED','Authorized document correction is required.'); end if;
   update public.work_order_final_cost_documents set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason=reason where id=final_doc.id;
 end if;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_supporting_document_voided',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',p_document_id,'reason',reason,'soft_deleted',true)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$;

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
  if p_document_type='invoice' then update public.contractor_payment_assessments set invoice_received_at=coalesce(invoice_received_at,pg_catalog.now()),updated_at=pg_catalog.now() where id=p_record_id; end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,case when replaced_ids is null then 'work_order_commercial_document_attached' else 'draft_quotation_document_replaced' end,w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',result.id,'document_type',result.document_type,'record_id',p_record_id,'filename',result.original_filename,'replaced_document_ids',coalesce(pg_catalog.to_jsonb(replaced_ids),'[]'::jsonb))::text);
  return pg_catalog.jsonb_build_object('ok',true,'document',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or foreign_key_violation or unique_violation then return public.work_order_result_error('VALIDATION_ERROR','Commercial document metadata is invalid.'); end;$function$;

CREATE OR REPLACE FUNCTION public.record_contractor_quotation(p_work_order_id uuid, p_quotation_ref text, p_quotation_date date, p_lines jsonb, p_source_filename text DEFAULT NULL::text, p_source_sha256 text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
  line jsonb; item public.contractor_rate_items%rowtype; qty numeric; quoted numeric; agreed numeric; line_number integer:=0; total numeric:=0; next_version integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','Assign a contractor before recording a quotation.'); end if;
  if w.status not in ('draft','submitted','approved','assigned','in_progress') then return public.work_order_result_error('QUOTATION_READ_ONLY','Quotations are read-only outside planning and active execution.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or w.status not in ('draft','assigned','in_progress') or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may record this quotation.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Quotation recording authority is required.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_quotation_ref,'')),'') is null or p_quotation_date is null or p_lines is null or pg_catalog.jsonb_typeof(p_lines)<>'array' or pg_catalog.jsonb_array_length(p_lines)=0 then return public.work_order_result_error('VALIDATION_ERROR','Quotation reference, date and at least one line are required.'); end if;
  select coalesce(pg_catalog.max(version_no),0)+1 into next_version from public.contractor_quotations where work_order_id=w.id and quotation_ref=pg_catalog.btrim(p_quotation_ref);
  update public.contractor_quotations set status='superseded',updated_at=pg_catalog.now() where work_order_id=w.id and vendor_id=w.assigned_vendor_id and status='submitted';
  insert into public.contractor_quotations(work_order_id,vendor_id,quotation_ref,quotation_date,version_no,status,currency,source_filename,source_sha256,submitted_by)
  values(w.id,w.assigned_vendor_id,pg_catalog.btrim(p_quotation_ref),p_quotation_date,next_version,'submitted','SGD',nullif(pg_catalog.btrim(coalesce(p_source_filename,'')),''),nullif(pg_catalog.btrim(coalesce(p_source_sha256,'')),''),actor_id) returning * into q;
  for line in select value from pg_catalog.jsonb_array_elements(p_lines) loop
    line_number:=line_number+1;
    begin qty:=(line->>'quantity')::numeric; quoted:=(line->>'quoted_unit_rate')::numeric; exception when others then qty:=null; quoted:=null; end;
    select * into item from public.contractor_rate_items where id=(line->>'rate_item_id')::uuid and vendor_id=w.assigned_vendor_id and active and effective_from<=p_quotation_date and (effective_to is null or effective_to>=p_quotation_date);
    if item.id is null or qty is null or qty<=0 or quoted is null or quoted<0 then raise exception using errcode='22023',message='Quotation line is invalid.'; end if;
    agreed:=case when w.emergency_work and item.emergency_unit_rate is not null then item.emergency_unit_rate else item.normal_unit_rate end;
    if quoted<>agreed and nullif(pg_catalog.btrim(coalesce(line->>'exception_reason','')),'') is null then raise exception using errcode='22023',message='A rate exception reason is required.'; end if;
    insert into public.contractor_quotation_lines(quotation_id,line_no,rate_item_id,cost_type,item_code,description,unit,quantity,agreed_unit_rate,quoted_unit_rate,rate_exception,exception_reason,worker_name,remarks)
    values(q.id,line_number,item.id,item.cost_type,item.item_code,item.description,item.unit,qty,agreed,quoted,quoted<>agreed,case when quoted<>agreed then pg_catalog.btrim(line->>'exception_reason') end,nullif(pg_catalog.btrim(coalesce(line->>'worker_name','')),''),nullif(pg_catalog.btrim(coalesce(line->>'remarks','')),''));
    total:=total+pg_catalog.round(qty*quoted,2);
  end loop;
  update public.contractor_quotations set total_amount=total,updated_at=pg_catalog.now() where id=q.id returning * into q;
  update public.work_order_financial_controls set quoted_cost=total,cost_status='quotation_recorded',recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_quotation_recorded',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'quotation_ref',q.quotation_ref,'total_amount',total,'recorded_by_role',actor->>'role')::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q),'line_count',line_number);
exception when invalid_text_representation or check_violation or foreign_key_violation or numeric_value_out_of_range or sqlstate '22023' then return public.work_order_result_error('VALIDATION_ERROR',sqlerrm); when unique_violation then return public.work_order_result_error('DUPLICATE_QUOTATION','That quotation version already exists.'); when others then return public.work_order_result_error('INTERNAL_ERROR','Contractor quotation could not be recorded.'); end;$function$;

CREATE OR REPLACE FUNCTION public.register_evidence_item(p_parent_type text, p_parent_id uuid, p_original_filename text, p_content_type text, p_byte_size bigint, p_category text, p_description text, p_storage_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor_id uuid:=auth.uid(); actor_name text; actor_role text; result public.evidence_items;
begin
  if actor_id is null then return pg_catalog.jsonb_build_object('ok',false,'code','AUTHENTICATION_REQUIRED'); end if;
  if not public.pilot_account_ready(actor_id) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  select display_name,role into actor_name,actor_role from public.profiles where id=actor_id;
  if p_parent_type='work_order' then
    if not exists(
      select 1 from public.work_orders w where w.id=p_parent_id and (
        (actor_role in ('technician','supervisor','facility_manager','administrator')
          and w.assigned_technician_id=actor_id and public.field_work_facility_permitted(w.facility_id)
          and (w.status in ('assigned','in_progress') or (w.status in ('completed','reviewed','closed')
            and exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open'))))
        -- LC2: the preparer attaches supporting photos/video/voice while drafting.
        or (w.status in ('draft','submitted') and public.work_order_preparer_permitted(w.id))
      )
    ) then return pg_catalog.jsonb_build_object('ok',false,'code','EVIDENCE_READ_ONLY'); end if;
  elsif p_parent_type='incident' then
    -- Serialize evidence registration with terminal transitions/removal.
    perform 1 from public.incidents i where i.id=p_parent_id for update;
    if not public.incident_evidence_mutation_permitted(p_parent_id,actor_id) then
      return pg_catalog.jsonb_build_object('ok',false,'code','EVIDENCE_READ_ONLY');
    end if;
  else return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;
  if p_category not in ('before','after') or p_storage_path not like 'evidence/'||pg_catalog.replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return pg_catalog.jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT'); end if;
  insert into public.evidence_items(parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path) values(p_parent_type,case when p_parent_type='work_order' then p_parent_id end,case when p_parent_type='incident' then p_parent_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_category,nullif(pg_catalog.btrim(p_description),''),p_storage_path) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note) values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,pg_catalog.jsonb_build_object('evidence_id',result.id,'category',result.category,'parent_type',result.parent_type,'document_correction',exists(select 1 from public.work_order_document_corrections c where c.work_order_id=result.work_order_id and c.status='open'))::text);
  return pg_catalog.jsonb_build_object('ok',true,'evidence',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or invalid_text_representation then return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); when unique_violation then return pg_catalog.jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE'); when others then return pg_catalog.jsonb_build_object('ok',false,'code','INTERNAL_ERROR'); end;
$function$;

CREATE OR REPLACE FUNCTION public.assign_work_order(p_work_order_id uuid, p_assignment_type text, p_assignee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  previous public.work_orders%rowtype; result public.work_orders%rowtype; assignee_name text;
  mode text := pg_catalog.lower(coalesce(p_assignment_type, ''));
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  if actor_role not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot assign work orders.'); end if;
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if not public.approval_facility_permitted(previous.facility_id) then return public.work_order_result_error('ACCESS_DENIED', 'Active same-facility approval membership is required.'); end if;
  if previous.status not in ('approved','assigned') then return public.work_order_result_error('INVALID_TRANSITION', 'Assignment is allowed only after approval.'); end if;
  if mode = 'technician' then
    select display_name into assignee_name from public.profiles where id = p_assignee_id and role = 'technician' and is_active = true and deleted_at is null;
  elsif mode = 'vendor' then
    select name into assignee_name from public.vendors where id = p_assignee_id and active = true and deleted_at is null;
  elsif mode = 'team' then
    select name into assignee_name from public.maintenance_teams where id = p_assignee_id and is_active = true and deleted_at is null;
  else return public.work_order_result_error('INVALID_ASSIGNMENT', 'Assignment type is invalid.');
  end if;
  if assignee_name is null then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected assignee is unavailable.'); end if;
  if previous.status = 'assigned' and (
    (mode = 'technician' and previous.assigned_technician_id = p_assignee_id and previous.assigned_vendor_id is null and previous.assigned_team_id is null)
    or (mode = 'vendor' and previous.assigned_vendor_id = p_assignee_id and previous.assigned_technician_id is null and previous.assigned_team_id is null)
    or (mode = 'team' and previous.assigned_team_id = p_assignee_id and previous.assigned_technician_id is null and previous.assigned_vendor_id is null)
  ) then
    return pg_catalog.jsonb_build_object(
      'ok', true,
      'code', 'NO_CHANGE',
      'message', 'The work order is already assigned to this assignee.',
      'work_order', pg_catalog.to_jsonb(previous)
    );
  end if;
  begin
    update public.work_orders set
      assigned_technician_id = case when mode = 'technician' then p_assignee_id else null end,
      assigned_vendor_id = case when mode = 'vendor' then p_assignee_id else null end,
      assigned_team_id = case when mode = 'team' then p_assignee_id else null end,
      assigned_to = assignee_name, assigned_by = actor_name, assigned_by_user_id = actor_id,
      assigned_at = pg_catalog.now(), accepted_at = null, status = 'assigned', updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, result.id, case when previous.status = 'assigned' then 'work_order_reassigned' else 'work_order_assigned' end,
      previous.status, result.status, actor_name,
      pg_catalog.jsonb_build_object('assignment_type', mode, 'assignee_id', p_assignee_id, 'assignee_name', assignee_name)::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Work-order assignment failed.'); end;
end;
$function$;

CREATE OR REPLACE FUNCTION public.approve_work_order_proposal_r1_scope_core(p_work_order_id uuid, p_quotation_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer; authority jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id; select * into control from public.work_order_financial_controls where work_order_id=p_work_order_id;
  if w.id is null or q.id is null or control.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Recommended quotation was not found.'); end if;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active; select count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  if control.cost_status<>'recommended' or w.recommended_vendor_id is distinct from q.vendor_id or control.quoted_cost is distinct from q.total_amount then return public.work_order_result_error('APPROVAL_NOT_READY','Select and justify the recommended quotation before approval.'); end if;
  if collected_count<coalesce(required_count,1) then return public.work_order_result_error('INSUFFICIENT_QUOTATIONS','The configured quotation count has not been met.'); end if;
  -- LC2: single approval-authority rule (role, facility, monetary limit, independence).
  authority:=public.work_order_approval_authority(w.id,q.total_amount,p_note);
  if authority is not null then return authority; end if;
  return public.approve_work_order_proposal_20260924_core(p_work_order_id,p_quotation_id,p_note);
end;$function$;

-- edit: the preparer edits Drafts (v2); Administrator unchanged
CREATE OR REPLACE FUNCTION public.update_work_order(p_work_order_id uuid, p_payload jsonb)
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
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Closed and cancelled work orders are immutable.'); end if;
  if actor_role not in ('facility_manager','administrator') and not (previous.status = 'draft' and public.work_order_preparer_permitted(previous.id)) then
    return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot edit this work order.');
  end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', previous.title))) < 3
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'location', previous.location))) = 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'Title and location are required.'); end if;
  if nullif(p_payload ->> 'department_id', '') is not null and not exists (
    select 1 from public.departments where id = (p_payload ->> 'department_id')::uuid and is_active = true and deleted_at is null
  ) then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected department is unavailable.'); end if;

  begin
    update public.work_orders set
      title = pg_catalog.btrim(coalesce(p_payload ->> 'title', title)),
      description = case when p_payload ? 'description' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'description', '')), '') else description end,
      location = pg_catalog.btrim(coalesce(p_payload ->> 'location', location)),
      site = case when p_payload ? 'site' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'site', '')), '') else site end,
      category_id = case when p_payload ? 'category_id' then nullif(p_payload ->> 'category_id', '')::uuid else category_id end,
      priority = case when p_payload ? 'priority' then pg_catalog.lower(p_payload ->> 'priority') else priority end,
      source = case when p_payload ? 'source' then pg_catalog.lower(p_payload ->> 'source') else source end,
      department_id = case when p_payload ? 'department_id' then nullif(p_payload ->> 'department_id', '')::uuid else department_id end,
      asset_id = case when p_payload ? 'asset_id' then nullif(p_payload ->> 'asset_id', '')::uuid else asset_id end,
      source_reference = case when p_payload ? 'source_reference' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'source_reference', '')), '') else source_reference end,
      alert_id = case when p_payload ? 'alert_id' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'alert_id', '')), '') else alert_id end,
      prediction_reference = case when p_payload ? 'prediction_reference' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'prediction_reference', '')), '') else prediction_reference end,
      health_score_at_creation = case when p_payload ? 'health_score_at_creation' then nullif(p_payload ->> 'health_score_at_creation', '')::numeric else health_score_at_creation end,
      failure_probability = case when p_payload ? 'failure_probability' then nullif(p_payload ->> 'failure_probability', '')::numeric else failure_probability end,
      predicted_failure_date = case when p_payload ? 'predicted_failure_date' then nullif(p_payload ->> 'predicted_failure_date', '')::date else predicted_failure_date end,
      recommended_action = case when p_payload ? 'recommended_action' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'recommended_action', '')), '') else recommended_action end,
      confidence_score = case when p_payload ? 'confidence_score' then nullif(p_payload ->> 'confidence_score', '')::numeric else confidence_score end,
      due_date = case when p_payload ? 'due_date' then nullif(p_payload ->> 'due_date', '')::date else due_date end,
      estimated_hours = case when p_payload ? 'estimated_hours' then nullif(p_payload ->> 'estimated_hours', '')::numeric else estimated_hours end,
      internal_notes = case when p_payload ? 'internal_notes' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'internal_notes', '')), '') else internal_notes end,
      contact_number = case when p_payload ? 'contact_number' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'contact_number', '')), '') else contact_number end,
      updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, actor, note)
    values (actor_id, result.id, 'work_order_updated', actor_name,
      pg_catalog.jsonb_build_object('before', pg_catalog.to_jsonb(previous), 'after', pg_catalog.to_jsonb(result))::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when check_violation or invalid_text_representation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order update failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order update failed.');
end;
$function$;


-- Creation (D-01.1, D-05.2 amended): Technician, or a superior when the Technician is
-- unavailable. New Work Orders always start as Draft; submission uses transition 'submit'.
create or replace function public.create_work_order(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid; actor_name text; actor_role text;
  requested_status text := pg_catalog.lower(coalesce(p_payload ->> 'status', 'draft'));
  requested_source text := pg_catalog.lower(coalesce(p_payload ->> 'source', 'manual'));
  technician uuid; party uuid; result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := coalesce(actor ->> 'display_name', actor ->> 'name'); actor_role := actor ->> 'role';
  if actor_role not in ('technician','approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Only a Technician, or a superior when the Technician is unavailable, may create Work Orders.');
  end if;
  if requested_status <> 'draft' then return public.work_order_result_error('VALIDATION_ERROR', 'Create the Work Order as Draft, then submit it for approval.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', ''))) < 3
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', ''))) > 200
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'location', ''))) = 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'Title and location are required.'); end if;
  if pg_catalog.lower(coalesce(p_payload ->> 'priority', 'medium')) not in ('low','medium','high','critical')
    or requested_source not in ('manual','reactive','preventive','inspection','condition_based','predictive')
  then return public.work_order_result_error('VALIDATION_ERROR', 'Priority or source is invalid.'); end if;
  if p_payload ? 'estimated_hours' and (p_payload ->> 'estimated_hours')::numeric < 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'A numeric work-order value is outside its allowed range.'); end if;
  if nullif(p_payload ->> 'department_id', '') is not null and not exists (
    select 1 from public.departments where id = (p_payload ->> 'department_id')::uuid and is_active = true and deleted_at is null
  ) then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected department is unavailable.'); end if;
  technician := case when actor_role = 'technician' then actor_id else nullif(p_payload ->> 'assigned_technician_id', '')::uuid end;

  begin
    insert into public.work_orders (
      user_id, requested_by, title, description, location, site, category_id, priority, status, source, source_reference,
      asset_id, facility_id, facility_area_id, department_id, due_date, estimated_hours, internal_notes, contact_number,
      emergency_work, assigned_technician_id, assigned_at
    ) values (
      actor_id, actor_id,
      pg_catalog.btrim(p_payload ->> 'title'),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'description', '')), ''),
      pg_catalog.btrim(p_payload ->> 'location'),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'site', '')), ''),
      nullif(p_payload ->> 'category_id', '')::uuid,
      pg_catalog.lower(coalesce(p_payload ->> 'priority', 'medium')),
      'draft', requested_source,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'source_reference', '')), ''),
      nullif(p_payload ->> 'asset_id', '')::uuid,
      nullif(p_payload ->> 'facility_id', '')::uuid,
      nullif(p_payload ->> 'facility_area_id', '')::uuid,
      nullif(p_payload ->> 'department_id', '')::uuid,
      nullif(p_payload ->> 'due_date', '')::date,
      nullif(p_payload ->> 'estimated_hours', '')::numeric,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'internal_notes', '')), ''),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'contact_number', '')), ''),
      coalesce(nullif(p_payload ->> 'emergency_work', '')::boolean, false),
      technician, case when technician is not null then pg_catalog.now() end
    ) returning * into result;

    -- Facility scope: Technicians create only at their own facility; superiors only where they hold approval membership.
    if actor_role = 'technician' and not public.technician_facility_read_permitted(result.facility_id) then
      raise exception using errcode = '42501', message = 'TECHNICIAN_FACILITY';
    end if;
    if actor_role <> 'technician' and not public.approval_facility_permitted(result.facility_id) then
      raise exception using errcode = '42501', message = 'APPROVAL_FACILITY';
    end if;
    if technician is not null and actor_role <> 'technician' and not exists (
      select 1 from public.profiles p join public.facility_memberships fm on fm.profile_id = p.id
      where p.id = technician and p.role = 'technician' and p.is_active and p.deleted_at is null and not p.password_change_required
        and fm.facility_id = result.facility_id and fm.membership_role = 'technician' and fm.active
        and fm.effective_from <= pg_catalog.now() and (fm.effective_to is null or fm.effective_to > pg_catalog.now())
    ) then raise exception using errcode = '23514', message = 'TECHNICIAN_UNAVAILABLE'; end if;

    if pg_catalog.jsonb_typeof(p_payload -> 'copied_party_ids') = 'array' then
      for party in select (x #>> '{}')::uuid from pg_catalog.jsonb_array_elements(p_payload -> 'copied_party_ids') x loop
        if not public.pilot_account_ready(party) then raise exception using errcode = '23514', message = 'COPIED_PARTY_UNAVAILABLE'; end if;
        insert into public.work_order_copied_parties(work_order_id, profile_id, added_by) values (result.id, party, actor_id) on conflict do nothing;
      end loop;
    end if;

    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, result.id, 'work_order_created', null, result.status, actor_name,
      pg_catalog.jsonb_build_object('source', result.source, 'created_by_role', actor_role, 'assigned_technician_id', technician,
        'emergency_work', result.emergency_work, 'superior_created', actor_role <> 'technician')::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception
    when insufficient_privilege then
      return public.work_order_result_error('ACCESS_DENIED', 'You can create Work Orders only for a facility you belong to.');
    when check_violation then
      if sqlerrm = 'TECHNICIAN_UNAVAILABLE' then return public.work_order_result_error('INACTIVE_REFERENCE', 'Assign an active Technician who belongs to this facility.'); end if;
      if sqlerrm = 'COPIED_PARTY_UNAVAILABLE' then return public.work_order_result_error('INACTIVE_REFERENCE', 'A copied party is not an active user.'); end if;
      return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
    when invalid_text_representation or numeric_value_out_of_range or foreign_key_violation then
      return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
    when others then
      return public.work_order_result_error('INTERNAL_ERROR', 'Work-order creation failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order creation failed.');
end;
$function$;

-- Assign the field-witness Technician while Draft / Awaiting Approval (superior-created
-- and system-generated Work Orders). After approval, assign_work_order is used.
create function public.set_work_order_technician(p_work_order_id uuid, p_technician_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Approval authority is required to assign a Technician.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not public.approval_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility approval membership is required.'); end if;
  if w.status not in ('draft','submitted') then
    return public.work_order_result_error('INVALID_TRANSITION','Use assignment after approval.'); end if;
  if not exists (
    select 1 from public.profiles p join public.facility_memberships fm on fm.profile_id=p.id
    where p.id=p_technician_id and p.role='technician' and p.is_active and p.deleted_at is null and not p.password_change_required
      and fm.facility_id=w.facility_id and fm.membership_role='technician' and fm.active
      and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
  ) then return public.work_order_result_error('INACTIVE_REFERENCE','Assign an active Technician who belongs to this facility.'); end if;
  if w.assigned_technician_id=p_technician_id then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
  update public.work_orders set assigned_technician_id=p_technician_id,assigned_at=pg_catalog.now(),accepted_at=null,updated_at=pg_catalog.now()
    where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values((actor->>'id')::uuid,w.id,'work_order_technician_set',w.status,w.status,coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('previous_technician_id',w.assigned_technician_id,'technician_id',p_technician_id)::text);
  perform public.work_order_notify(w.id,'work_order_technician_assigned',false,true,(actor->>'id')::uuid);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
end;$function$;

-- Copied parties: set by the preparer or an approval authority before closure.
create function public.set_work_order_copied_parties(p_work_order_id uuid, p_profile_ids uuid[])
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; party uuid; previous uuid[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE','Closed and cancelled work orders are immutable.'); end if;
  if not (public.work_order_preparer_permitted(w.id)
    or (actor->>'role' in ('approver','supervisor','facility_manager','administrator') and public.approval_facility_permitted(w.facility_id))) then
    return public.work_order_result_error('ACCESS_DENIED','Only the preparer or an approval authority may change copied parties.'); end if;
  if coalesce(pg_catalog.array_length(p_profile_ids,1),0)>50 then return public.work_order_result_error('VALIDATION_ERROR','At most 50 copied parties.'); end if;
  foreach party in array coalesce(p_profile_ids,'{}'::uuid[]) loop
    if not public.pilot_account_ready(party) then return public.work_order_result_error('INACTIVE_REFERENCE','A copied party is not an active user.'); end if;
  end loop;
  select pg_catalog.array_agg(profile_id order by profile_id) into previous from public.work_order_copied_parties where work_order_id=w.id;
  delete from public.work_order_copied_parties where work_order_id=w.id and not (profile_id = any(coalesce(p_profile_ids,'{}'::uuid[])));
  insert into public.work_order_copied_parties(work_order_id,profile_id,added_by)
    select w.id,x,(actor->>'id')::uuid from pg_catalog.unnest(coalesce(p_profile_ids,'{}'::uuid[])) x on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values((actor->>'id')::uuid,w.id,'work_order_copied_parties_changed',w.status,w.status,coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('previous',previous,'copied_party_ids',p_profile_ids)::text);
  return pg_catalog.jsonb_build_object('ok',true,'copied_party_ids',to_jsonb(coalesce(p_profile_ids,'{}'::uuid[])));
end;$function$;

-- Lifecycle v2 transition layer: submit, approve and return are handled here; every
-- other action keeps its existing governed path (with Approver facility scope added).
alter function public.transition_work_order(uuid,text,jsonb) rename to transition_work_order_20261020_core;
revoke all on function public.transition_work_order_20261020_core(uuid,text,jsonb) from public, anon, authenticated, service_role;

create function public.transition_work_order(p_work_order_id uuid, p_action text, p_payload jsonb default '{}'::jsonb)
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

-- Privileges --------------------------------------------------------------------
revoke all on function public.work_order_preparer_permitted(uuid) from public, anon, service_role;
revoke all on function public.work_order_notify(uuid,text,boolean,boolean,uuid) from public, anon, authenticated, service_role;
revoke all on function public.set_work_order_technician(uuid,uuid) from public, anon, service_role;
revoke all on function public.set_work_order_copied_parties(uuid,uuid[]) from public, anon, service_role;
revoke all on function public.transition_work_order(uuid,text,jsonb) from public, anon, service_role;
grant execute on function public.work_order_preparer_permitted(uuid) to authenticated;
grant execute on function public.set_work_order_technician(uuid,uuid) to authenticated;
grant execute on function public.set_work_order_copied_parties(uuid,uuid[]) to authenticated;
grant execute on function public.transition_work_order(uuid,text,jsonb) to authenticated;

do $post$
begin
  if exists(select 1 from pg_catalog.pg_proc where oid='public.create_work_order(jsonb)'::regprocedure and prosrc like '%actor_role = ''technician'' then return public.work_order_result_error(''ACCESS_DENIED''%') then
    raise exception 'LC2-M2 Technician creation still denied'; end if;
  if has_function_privilege('authenticated','public.transition_work_order_20261020_core(uuid,text,jsonb)','EXECUTE') then
    raise exception 'LC2-M2 core transition exposed'; end if;
  if has_function_privilege('authenticated','public.work_order_notify(uuid,text,boolean,boolean,uuid)','EXECUTE') then
    raise exception 'LC2-M2 notification helper exposed'; end if;
end;$post$;

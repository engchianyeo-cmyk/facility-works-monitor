-- WP-LC2-M8 (D-14, owner 27 Oct 2026 15:59): "Other supporting document" as a field evidence category.
-- Stored as the existing evidence_items category 'document' (already allowed by the table constraint).
-- It does not count as Before or After evidence; those requirements are unchanged.
-- D-15 (27 Oct 2026, UAT WO-TEST-010): a Draft whose due date has passed is listed in the readiness and
-- refused at submission with DUE_DATE_PASSED, instead of failing on work_orders_due_date_check.
begin;
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
  if p_category not in ('before','after','document') or p_storage_path not like 'evidence/'||pg_catalog.replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return pg_catalog.jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT'); end if;
  insert into public.evidence_items(parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path) values(p_parent_type,case when p_parent_type='work_order' then p_parent_id end,case when p_parent_type='incident' then p_parent_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_category,nullif(pg_catalog.btrim(p_description),''),p_storage_path) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note) values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,pg_catalog.jsonb_build_object('evidence_id',result.id,'category',result.category,'parent_type',result.parent_type,'document_correction',exists(select 1 from public.work_order_document_corrections c where c.work_order_id=result.work_order_id and c.status='open'))::text);
  return pg_catalog.jsonb_build_object('ok',true,'evidence',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or invalid_text_representation then return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); when unique_violation then return pg_catalog.jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE'); when others then return pg_catalog.jsonb_build_object('ok',false,'code','INTERNAL_ERROR'); end;
$function$;

-- D-15: readiness lists a passed due date
CREATE OR REPLACE FUNCTION public.work_order_approval_summary(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare w public.work_orders%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer;
  amount numeric; level text; authority jsonb; missing jsonb:='[]'::jsonb;
begin
  if not public.release1_work_order_visible(p_work_order_id) then
    return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into control from public.work_order_financial_controls where work_order_id=w.id;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id;
  select pg_catalog.count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  amount:=control.quoted_cost;
  if pg_catalog.length(pg_catalog.btrim(coalesce(w.description,'')))<10 then missing:=missing||'"Reason the work is needed"'::jsonb; end if;
  -- D-15: a due date earlier than the submission date is refused by work_orders_due_date_check.
  if w.status='draft' and w.due_date is not null and w.pm_occurrence_id is null and w.due_date<(pg_catalog.now())::date then missing:=missing||'"Due date has passed — update the due date"'::jsonb; end if;
  if w.assigned_technician_id is null then missing:=missing||'"Field-witness Technician"'::jsonb; end if;
  if not w.emergency_work then
    if not public.work_order_location_marked(w.id) then missing:=missing||'"Location marked on the layout plan"'::jsonb; end if;
    if not public.work_order_before_evidence_present(w.id) then missing:=missing||'"Before photo, video or voice note of the site"'::jsonb; end if;
  end if;
  if public.work_order_endorsement_missing(w.id,'submission') then missing:=missing||'"Second Technician endorsement"'::jsonb; end if;
  if not w.emergency_work and not w.in_house_work then
    if collected_count<coalesce(required_count,1) then missing:=missing||pg_catalog.to_jsonb(pg_catalog.format('Quotations: %s of %s submitted',collected_count,coalesce(required_count,1))); end if;
    if control.work_order_id is null or control.cost_status<>'recommended' or amount is null then missing:=missing||'"Recommended contractor quotation"'::jsonb; end if;
  end if;
  select l.role into level from public.work_order_approval_limits l join public.work_order_approval_limit_policy p on p.version_id=l.version_id
    where amount is not null and (l.maximum_amount is null or l.maximum_amount>=amount)
    order by l.maximum_amount nulls last, case l.role when 'approver' then 1 when 'supervisor' then 2 when 'facility_manager' then 3 else 4 end limit 1;
  if w.status='submitted' and (amount is not null or w.in_house_work) then authority:=public.work_order_approval_authority(w.id,coalesce(amount,0),null); end if;
  return pg_catalog.jsonb_build_object('ok',true,'status',w.status,'emergency_work',w.emergency_work,'in_house_work',w.in_house_work,
    'quoted_cost',amount,'approved_budget',control.approved_budget,'cost_status',control.cost_status,
    'required_quotations',coalesce(required_count,1),'collected_quotations',collected_count,
    'missing_requirements',missing,'ready',pg_catalog.jsonb_array_length(missing)=0,
    'lowest_authority',level,'board_approval_required',coalesce(amount,0)>1000000,
    'can_approve',w.status='submitted' and (amount is not null or w.in_house_work) and authority is null,
    'approval_blocker',authority->>'code','approval_blocker_message',authority->>'message');
end;$function$;

-- D-15: submission refuses a passed due date with a clear reason
CREATE OR REPLACE FUNCTION public.transition_work_order(p_work_order_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
    if w.due_date is not null and w.pm_occurrence_id is null and w.due_date<(pg_catalog.now())::date then
      return public.work_order_result_error('DUE_DATE_PASSED','The due date has passed. Edit the Work Order and set a new due date before submitting.'); end if;
    if w.assigned_technician_id is null then
      return public.work_order_result_error('TECHNICIAN_REQUIRED','Assign the Technician who will witness the work before submitting.'); end if;
    if pg_catalog.length(pg_catalog.btrim(coalesce(w.description,'')))<10 then
      return public.work_order_result_error('JUSTIFICATION_REQUIRED','Explain why the work is needed (at least 10 characters) before submitting.'); end if;
    if not w.emergency_work and not public.work_order_location_marked(w.id) then
      return public.work_order_result_error('LOCATION_MARKUP_REQUIRED','Mark the work location on the layout plan before submitting.'); end if;
    if not w.emergency_work and not public.work_order_before_evidence_present(w.id) then
      return public.work_order_result_error('BEFORE_EVIDENCE_REQUIRED','Add at least one Before photo, video or voice note of the site before submitting.'); end if;
    if public.work_order_endorsement_missing(w.id,'submission') then
      return public.work_order_result_error('ENDORSEMENT_REQUIRED','A second Technician of this facility must endorse the Work Order as authentic before it is submitted.'); end if;
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
    if w.in_house_work then
      update public.work_orders set status='submitted',submitted_at=pg_catalog.now(),submitted_by=actor_name,updated_at=pg_catalog.now()
        where id=w.id returning * into result;
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,w.id,'work_order_submit','draft','submitted',actor_name,pg_catalog.jsonb_build_object('in_house_work',true,'pricing','waived')::text);
      perform public.work_order_notify(w.id,'work_order_submitted_for_approval',true,false,actor_id);
      return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
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
  if w.in_house_work then
    -- D-07: in-house services, pricing waived; same authority rule at S$0.
    authority:=public.work_order_approval_authority(w.id,0,reason);
    if authority is not null then return authority; end if;
    select version_id into limit_version from public.work_order_approval_limit_policy where singleton;
    update public.work_orders set status='assigned',approved_at=pg_catalog.now(),assigned_at=coalesce(assigned_at,pg_catalog.now()),
        accepted_at=case when assigned_technician_id=requested_by then coalesce(accepted_at,pg_catalog.now()) else accepted_at end,
        approval_limit_version_id=limit_version,updated_at=pg_catalog.now()
      where id=w.id returning * into result;
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_approve','submitted','assigned',actor_name,
      pg_catalog.jsonb_build_object('decision','approved_to_proceed','in_house_work',true,'approved_amount',0,'approval_limit_version_id',limit_version,
        'approver_role',role,'reason',reason,'administrator_override',(actor_id=w.requested_by or actor_id=w.assigned_technician_id) and role='administrator')::text);
    perform public.work_order_notify(w.id,'work_order_approved',false,true,actor_id);
    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'approved_amount',0);
  end if;
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

do $postcheck$
declare definition text;
begin
  select pg_catalog.pg_get_functiondef('public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'::regprocedure) into definition;
  if definition not like '%p_category not in (''before'',''after'',''document'')%' then raise exception 'LC2-M8 evidence category postcondition failed'; end if;
  if pg_catalog.pg_get_functiondef('public.transition_work_order(uuid,text,jsonb)'::regprocedure) not like '%DUE_DATE_PASSED%' then raise exception 'LC2-M8 due date postcondition failed'; end if;
  if not exists(select 1 from pg_catalog.pg_constraint c where c.conname='evidence_items_category_check'
                and pg_catalog.pg_get_constraintdef(c.oid) like '%document%') then raise exception 'LC2-M8 table constraint does not allow document'; end if;
end;$postcheck$;
commit;

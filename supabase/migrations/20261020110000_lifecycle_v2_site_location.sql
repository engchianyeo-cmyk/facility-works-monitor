-- WP-LC2-M6: site location and documentation requirements (owner decision D-08, 20 October 2026).
-- 1. The location must be marked on the facility layout plan: before submission for normal and
--    in-house work, and before the review to "Completed" for emergency work. The preparer may mark
--    the layout while the Work Order is Draft or Awaiting Approval; the assigned field owner may
--    also mark it during the work and while awaiting review.
--    Choosing an area already placed on the layout plan highlights it automatically and counts.
-- 2. At least one active Before photo, video, voice note or PDF is required before submission;
--    for emergency work (which starts on submission) before the review.
-- 3. Where the final cost differs from the approved (or emergency) quotation, the contractor's final
--    quotation for the work actually performed must be attached before the review; the reviewer
--    approves it together with the work (variation approved at review).

begin;

do $preflight$
begin
  if current_user <> 'postgres' then raise exception 'LC2-M6 must be applied as postgres'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_orders' and column_name='in_house_work') then
    raise exception 'LC2-M6 requires LC2-M5'; end if;
  if pg_catalog.to_regprocedure('public.work_order_location_marked(uuid)') is not null then
    raise exception 'LC2-M6 conflicting or partial state already exists'; end if;
end;$preflight$;

create function public.work_order_location_marked(p_work_order_id uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $function$
  -- Marked when the chosen area is already placed on a layout plan (highlighted automatically),
  -- or when a markup has been drawn on the plan.
  select exists(select 1 from public.work_order_markups m where m.work_order_id=p_work_order_id and m.deleted_at is null)
    or exists(select 1 from public.work_orders w join public.facility_areas a on a.id=w.facility_area_id
              where w.id=p_work_order_id and nullif(pg_catalog.btrim(a.drawing_reference),'') is not null
                and a.map_x is not null and a.map_y is not null)
$function$;
create function public.work_order_before_evidence_present(p_work_order_id uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $function$
  select exists(select 1 from public.evidence_items e where e.work_order_id=p_work_order_id and e.category='before' and e.deleted_at is null)
$function$;
-- True when the final cost differs from the approved/emergency quotation and no final quotation is attached.
create function public.work_order_final_quotation_missing(p_work_order_id uuid) returns boolean
language sql stable security definer set search_path = pg_catalog as $function$
  select coalesce((
    select fc.confirmed_actual_cost is not null
      and coalesce(c.approved_budget,c.quoted_cost) is not null
      and fc.confirmed_actual_cost <> coalesce(c.approved_budget,c.quoted_cost)
      and not exists(select 1 from public.work_order_final_cost_documents d where d.final_cost_submission_id=fc.id and d.deleted_at is null)
    from public.work_orders w
    join public.work_order_final_cost_submissions fc on fc.work_order_id=w.id
    left join public.work_order_financial_controls c on c.work_order_id=w.id
    where w.id=p_work_order_id and not w.in_house_work), false)
$function$;
revoke all on function public.work_order_location_marked(uuid), public.work_order_before_evidence_present(uuid),
  public.work_order_final_quotation_missing(uuid) from public, anon, authenticated, service_role;

-- create: area must belong to the facility
CREATE OR REPLACE FUNCTION public.create_work_order(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
      emergency_work, in_house_work, assigned_technician_id, assigned_at
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
      coalesce(nullif(p_payload ->> 'in_house_work', '')::boolean, false),
      technician, case when technician is not null then pg_catalog.now() end
    ) returning * into result;

    -- D-08: the chosen area must belong to the Work Order's facility.
    if result.facility_area_id is not null and exists(select 1 from public.facility_areas a where a.id=result.facility_area_id
        and (not a.active or (a.facility_id is not null and a.facility_id is distinct from result.facility_id))) then
      raise exception using errcode = '23514', message = 'AREA_FACILITY_MISMATCH';
    end if;
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
        'emergency_work', result.emergency_work, 'in_house_work', result.in_house_work, 'superior_created', actor_role <> 'technician')::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception
    when insufficient_privilege then
      return public.work_order_result_error('ACCESS_DENIED', 'You can create Work Orders only for a facility you belong to.');
    when check_violation then
      if sqlerrm = 'TECHNICIAN_UNAVAILABLE' then return public.work_order_result_error('INACTIVE_REFERENCE', 'Assign an active Technician who belongs to this facility.'); end if;
      if sqlerrm = 'AREA_FACILITY_MISMATCH' then return public.work_order_result_error('VALIDATION_ERROR', 'Choose an active area of this facility.'); end if;
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

-- markup: preparer marks the layout while drafting
CREATE OR REPLACE FUNCTION public.record_work_order_markup_r1_scope_core(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_order_markups%rowtype;
  source_kind text:=pg_catalog.lower(coalesce(p_payload->>'source_type','drawing'));
  source_ref text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'source_reference','')),'');
  revision text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'drawing_revision','')),'');
  annotation text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'note','')),'');
  kind text:=pg_catalog.lower(coalesce(p_payload->>'annotation_type',''));
  shape jsonb:=p_payload->'geometry'; first_point jsonb; x numeric; y numeric; page integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status in ('draft','submitted') then
    if not public.work_order_preparer_permitted(w.id) then return public.work_order_result_error('ACCESS_DENIED','Only the Work Order preparer may mark the location while it is drafted or awaiting approval.'); end if;
  elsif w.status not in ('assigned','in_progress','completed') then return public.work_order_result_error('MARKUP_READ_ONLY','Markup is editable while drafting, during the work, or before the review.');
  elsif actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may add field markup.');
  elsif actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Supervisor authority is required.');
  elsif actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Facility Manager authority is required.');
  elsif actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational markup authority is required.'); end if;
  if shape is null or pg_catalog.jsonb_typeof(shape)<>'object' or pg_catalog.jsonb_typeof(shape->'points')<>'array' or pg_catalog.jsonb_array_length(shape->'points')=0 or pg_catalog.octet_length(shape::text)>20000 then return public.work_order_result_error('VALIDATION_ERROR','Markup geometry is invalid.'); end if;
  first_point:=shape->'points'->0;
  begin x:=(first_point->>'x')::numeric; y:=(first_point->>'y')::numeric; page:=nullif(p_payload->>'page_number','')::integer; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Markup coordinates or page are invalid.'); end;
  if source_kind not in ('drawing','pdf') or source_ref is null or revision is null or annotation is null or kind not in ('marker','arrow','circle','rectangle','freehand','text') or x not between 0 and 100 or y not between 0 and 100 then return public.work_order_result_error('VALIDATION_ERROR','Drawing revision, annotation, note and calibrated geometry are required.'); end if;
  insert into public.work_order_markups(work_order_id,source_type,source_reference,drawing_revision,page_number,x_percent,y_percent,annotation_type,geometry,note,created_by)
  values(w.id,source_kind,source_ref,revision,page,x,y,kind,shape,annotation,(actor->>'id')::uuid) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_markup_recorded',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('markup_id',result.id,'drawing',source_ref,'revision',revision,'annotation_type',kind)::text);
  return pg_catalog.jsonb_build_object('ok',true,'markup',pg_catalog.to_jsonb(result));
exception when others then return public.work_order_result_error('INTERNAL_ERROR','Markup could not be recorded.'); end;$function$;

-- markup deletion: preparer removes own markup while drafting
CREATE OR REPLACE FUNCTION public.delete_work_order_markup(p_work_order_id uuid, p_markup_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; m public.work_order_markups%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into m from public.work_order_markups where id=p_markup_id and work_order_id=p_work_order_id and deleted_at is null;
  if w.id is null or m.id is null then return public.work_order_result_error('NOT_FOUND','Markup not found.'); end if;
  if w.status in ('draft','submitted') then
    if not public.work_order_preparer_permitted(w.id) or m.created_by is distinct from (actor->>'id')::uuid then return public.work_order_result_error('ACCESS_DENIED','Only the preparer may remove their own location markup while drafting.'); end if;
  elsif w.status not in ('assigned','in_progress','completed') then return public.work_order_result_error('MARKUP_READ_ONLY','Markup is editable while drafting, during the work, or before the review.');
  elsif actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or m.created_by is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Technicians may delete only their own active-assignment markup.');
  elsif actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational markup authority is required.'); end if;
  update public.work_order_markups set deleted_at=pg_catalog.now(),deleted_by=(actor->>'id')::uuid where id=m.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_markup_deleted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('markup_id',m.id,'drawing',m.source_reference,'revision',m.drawing_revision)::text);
  return pg_catalog.jsonb_build_object('ok',true,'markup_id',m.id);
end;$function$;

-- approval summary: location and Before evidence
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
  if w.assigned_technician_id is null then missing:=missing||'"Field-witness Technician"'::jsonb; end if;
  if not w.emergency_work then
    if not public.work_order_location_marked(w.id) then missing:=missing||'"Location marked on the layout plan"'::jsonb; end if;
    if not public.work_order_before_evidence_present(w.id) then missing:=missing||'"Before photo, video or voice note of the site"'::jsonb; end if;
  end if;
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

-- transition: submission requires location markup and Before evidence (emergency exempt)
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
    if w.assigned_technician_id is null then
      return public.work_order_result_error('TECHNICIAN_REQUIRED','Assign the Technician who will witness the work before submitting.'); end if;
    if pg_catalog.length(pg_catalog.btrim(coalesce(w.description,'')))<10 then
      return public.work_order_result_error('JUSTIFICATION_REQUIRED','Explain why the work is needed (at least 10 characters) before submitting.'); end if;
    if not w.emergency_work and not public.work_order_location_marked(w.id) then
      return public.work_order_result_error('LOCATION_MARKUP_REQUIRED','Mark the work location on the layout plan before submitting.'); end if;
    if not w.emergency_work and not public.work_order_before_evidence_present(w.id) then
      return public.work_order_result_error('BEFORE_EVIDENCE_REQUIRED','Add at least one Before photo, video or voice note of the site before submitting.'); end if;
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

-- review: location markup and final (revised) quotation
CREATE OR REPLACE FUNCTION public.verify_completed_work(p_work_order_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  previous public.work_orders%rowtype; result public.work_orders%rowtype;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  completion_activity_id uuid; completion_actor_id uuid; cycle_number integer;
  fc public.work_order_final_cost_submissions%rowtype; control public.work_order_financial_controls%rowtype;
  q public.contractor_quotations%rowtype; amount numeric(14,2); approved numeric(14,2); variance boolean; authority jsonb;
  vendor uuid; payable public.contractor_payment_assessments%rowtype; self_override boolean := false; proposer uuid; closed boolean := false;
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
  -- Normal and in-house work were checked at submission; emergency work is marked before the review.
  if previous.emergency_work and not public.work_order_location_marked(previous.id) then
    return public.work_order_result_error('LOCATION_MARKUP_REQUIRED', 'Mark the work location on the layout plan before the review.'); end if;
  if previous.emergency_work and not public.work_order_before_evidence_present(previous.id) then
    return public.work_order_result_error('BEFORE_EVIDENCE_REQUIRED', 'Add the Before photo, video or voice note of the site before the review.'); end if;

  select * into fc from public.work_order_final_cost_submissions where work_order_id = previous.id for update;
  if not previous.in_house_work and (fc.id is null or fc.status not in ('confirmed','variance_pending','variance_approved')) then
    return public.work_order_result_error('FINAL_COST_REQUIRED', 'The Technician has not entered the final cost.'); end if;
  amount := case when previous.in_house_work then 0 else fc.confirmed_actual_cost end;
  select * into control from public.work_order_financial_controls where work_order_id = previous.id for update;
  approved := control.approved_budget;
  if previous.emergency_work and not previous.in_house_work and (control.work_order_id is null or control.cost_status not in ('recommended','approved') or control.quoted_cost is null) then
    return public.work_order_result_error('QUOTATION_REQUIRED', 'The after-the-fact emergency quotation has not been submitted.'); end if;
  variance := amount > coalesce(approved, control.quoted_cost, 0);
  if variance and reason is null then
    return public.work_order_result_error('VARIANCE_NOTE_REQUIRED', 'The final cost exceeds the approved amount; record why it is accepted.'); end if;
  if public.work_order_final_quotation_missing(previous.id) then
    return public.work_order_result_error('FINAL_QUOTATION_REQUIRED', 'The final cost differs from the approved quotation; attach the contractor''s final quotation for the work actually performed.'); end if;

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

  -- D-07: in-house work has no payable; record the audited in-house no-payment disposition.
  if result.in_house_work then
    proposer := case when completion_actor_id is distinct from actor_id then completion_actor_id
                     when result.requested_by is distinct from actor_id then result.requested_by
                     else result.assigned_technician_id end;
    if proposer is not null and proposer is distinct from actor_id then
      insert into public.work_order_financial_dispositions(work_order_id,disposition_type,reason_code,reason,status,proposed_by,approved_by,approved_at,approval_note)
      values(result.id,'no_payment_required','in_house','Services provided in-house; pricing waived (D-07).','approved',proposer,actor_id,pg_catalog.now(),
        coalesce(reason,'In-house work approved as Completed.'))
      on conflict(work_order_id) do update set disposition_type='no_payment_required',reason_code='in_house',reason=excluded.reason,status='approved',
        proposed_by=excluded.proposed_by,approved_by=excluded.approved_by,approved_at=excluded.approved_at,approval_note=excluded.approval_note,updated_at=pg_catalog.now();
    end if;
  end if;

  -- Approved payable for the contractor; the invoice follows (§3.5).
  vendor := coalesce(vendor, result.assigned_vendor_id, result.recommended_vendor_id);
  if vendor is not null and amount > 0 and not result.in_house_work then
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
  if result.in_house_work then closed := public.work_order_close_if_settled(result.id,actor_id,actor_name); end if;
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle_number,
    'approved_final_cost',amount,'payment',pg_catalog.to_jsonb(payable),'work_order_closed',closed,'notification_status','queued');
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Review data is invalid.');
end;
$function$;

-- verification readiness: location markup and final quotation
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
  if w.emergency_work and not public.work_order_location_marked(w.id) then missing:=missing||'"Location marked on the layout plan"'::jsonb; end if;
  if w.emergency_work and not public.work_order_before_evidence_present(w.id) then missing:=missing||'"Before photo, video or voice note of the site"'::jsonb; end if;
  if public.work_order_final_quotation_missing(w.id) then missing:=missing||'"Final quotation for the work actually performed (final cost differs from the approved quotation)"'::jsonb; end if;
  select l.id,l.user_id into event_id,event_actor from public.activity_logs l where l.work_order_id=w.id and l.action='work_order_complete' order by l.created_at desc,l.id desc limit 1;
  if event_id is null then missing:=missing||'"authoritative_completion_submission_event"'::jsonb; end if;
  same_actor:=event_actor=(actor->>'id')::uuid;
  if same_actor and actor->>'role'<>'administrator' then missing:=missing||'"independent_authorised_verifier"'::jsonb; end if;
  return pg_catalog.jsonb_build_object('ok',true,'verification_ready',pg_catalog.jsonb_array_length(missing)=0,
    'missing_requirements',missing,'completion_event_found',event_id is not null,'completion_event_id',event_id,
    'legacy_completion_record',w.status='completed' and event_id is null,
    'self_verification_reason_required',same_actor and actor->>'role'='administrator');
end;$function$;

commit;

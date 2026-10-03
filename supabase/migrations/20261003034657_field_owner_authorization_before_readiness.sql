-- Preserve the four-role field-owner contract and reject cross-owner requests
-- before exposing costing/evidence readiness. Keep lifecycle and audit in the core.
begin;
create or replace function public.submit_physical_completion(p_work_order_id uuid,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype;
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
  return public.submit_physical_completion_20260921_core(p_work_order_id,p_payload);
end;$function$;
revoke all on function public.submit_physical_completion(uuid,jsonb) from public,anon,service_role;
grant execute on function public.submit_physical_completion(uuid,jsonb) to authenticated;

create or replace function public.register_evidence_item(p_parent_type text,p_parent_id uuid,p_original_filename text,p_content_type text,p_byte_size bigint,p_category text,p_description text,p_storage_path text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor_id uuid:=auth.uid(); actor_name text; actor_role text; result public.evidence_items;
begin
  if actor_id is null then return pg_catalog.jsonb_build_object('ok',false,'code','AUTHENTICATION_REQUIRED'); end if;
  if not public.pilot_account_ready(actor_id) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  select display_name,role into actor_name,actor_role from public.profiles where id=actor_id;
  if p_parent_type='work_order' then
    if actor_role not in ('technician','supervisor','facility_manager','administrator') or not exists(
      select 1 from public.work_orders w where w.id=p_parent_id
        and w.assigned_technician_id=actor_id and public.field_work_facility_permitted(w.facility_id)
        and (w.status in ('assigned','in_progress') or (w.status in ('completed','reviewed','closed')
          and exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open')))
    ) then return pg_catalog.jsonb_build_object('ok',false,'code','EVIDENCE_READ_ONLY'); end if;
  elsif p_parent_type='incident' then
    if not exists(select 1 from public.incidents i where i.id=p_parent_id and (actor_role in ('approver','supervisor','administrator') or i.reported_by=actor_id or i.assigned_technician_id=actor_id or (i.assigned_team_id is not null and exists(select 1 from public.maintenance_team_members m where m.team_id=i.assigned_team_id and m.profile_id=actor_id and m.is_active)))) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  else return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;
  if p_category not in ('before','after') or p_storage_path not like 'evidence/'||pg_catalog.replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return pg_catalog.jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT'); end if;
  insert into public.evidence_items(parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path) values(p_parent_type,case when p_parent_type='work_order' then p_parent_id end,case when p_parent_type='incident' then p_parent_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_category,nullif(pg_catalog.btrim(p_description),''),p_storage_path) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note) values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,pg_catalog.jsonb_build_object('evidence_id',result.id,'category',result.category,'parent_type',result.parent_type,'document_correction',exists(select 1 from public.work_order_document_corrections c where c.work_order_id=result.work_order_id and c.status='open'))::text);
  return pg_catalog.jsonb_build_object('ok',true,'evidence',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or invalid_text_representation then return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); when unique_violation then return pg_catalog.jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE'); when others then return pg_catalog.jsonb_build_object('ok',false,'code','INTERNAL_ERROR'); end;$function$;


revoke all on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) from public,anon,service_role;
grant execute on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) to authenticated;

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
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('ACTUAL_COST_READ_ONLY','Actual execution costs are read-only outside active assigned work.'); end if;
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


revoke all on function public.manage_work_order_actual_cost(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function public.manage_work_order_actual_cost(uuid,uuid,jsonb) to authenticated;

create or replace function public.void_work_order_evidence(p_evidence_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; item public.evidence_items%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into item from public.evidence_items where id=p_evidence_id and deleted_at is null for update; if item.id is null or item.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Active Work Order evidence was not found.'); end if;
 select * into w from public.work_orders where id=item.work_order_id for update;
 if reason is null or length(reason)>500 then return public.work_order_result_error('VALIDATION_ERROR','A bounded removal reason is required.'); end if;
 if (w.assigned_technician_id is distinct from actor_id or not public.field_work_facility_permitted(w.facility_id) or not (w.status in ('assigned','in_progress') or exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open'))) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned field owner may remove evidence while the record is editable.'); end if;
 if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Evidence removal authority is required.'); end if;
 if item.category='after' and w.status in ('completed','reviewed','closed') and not exists(select 1 from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null and e.id<>item.id) then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','Upload replacement After evidence before removing the last mandatory item.'); end if;
 update public.evidence_items set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason=reason where id=item.id;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'evidence_voided',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('evidence_id',item.id,'filename',item.original_filename,'original_category',item.category,'reason',reason)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$;


revoke all on function public.void_work_order_evidence(uuid,text) from public,anon,service_role;
grant execute on function public.void_work_order_evidence(uuid,text) to authenticated;
commit;

create or replace function public.field_work_facility_permitted(p_facility_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select public.pilot_account_ready(auth.uid())
    and exists (
      select 1 from public.sites s where s.id=p_facility_id and s.is_active
    )
    and (
      public.current_user_role()='administrator'
      or exists (
        select 1
        from public.facility_memberships fm
        where fm.profile_id=auth.uid()
          and fm.facility_id=p_facility_id
          and fm.membership_role=public.current_user_role()
          and fm.membership_role in ('technician','supervisor','facility_manager')
          and fm.active
          and fm.effective_from<=pg_catalog.now()
          and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
      )
    )
$function$;

create or replace function public.accept_work_responsibility(p_work_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  actor jsonb:=public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  w public.work_orders%rowtype;
  result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  actor_name:=coalesce(actor->>'display_name',actor->>'name','Unknown user');
  actor_role:=actor->>'role';
  if actor_role not in ('technician','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Field execution authority is required.');
  end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('approved','assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Responsibility may be accepted only for approved or active work.'); end if;
  if not public.field_work_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Active facility authority is required for this work order.'); end if;
  if w.assigned_technician_id is not null and w.assigned_technician_id<>actor_id then return public.work_order_result_error('ASSIGNMENT_CONFLICT','Another field-responsible person already owns this work order.'); end if;
  if w.assigned_technician_id=actor_id then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;

  update public.work_orders
  set assigned_technician_id=actor_id,
      assigned_to=actor_name,
      assigned_at=coalesce(assigned_at,pg_catalog.now()),
      accepted_at=pg_catalog.now(),
      status=case when status='approved' then 'assigned' else status end,
      updated_at=pg_catalog.now()
  where id=w.id
  returning * into result;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_responsibility_accepted',w.status,result.status,actor_name,
    pg_catalog.jsonb_build_object(
      'responsible_field_profile_id',actor_id,
      'responsible_field_role',actor_role,
      'facility_id',w.facility_id,
      'assigned_vendor_id',w.assigned_vendor_id,
      'accepted_at',pg_catalog.now()
    )::text);

  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
exception
  when check_violation or foreign_key_violation then return public.work_order_result_error('VALIDATION_ERROR','Responsibility could not be accepted.');
  when others then return public.work_order_result_error('INTERNAL_ERROR','Responsibility acceptance failed.');
end;
$function$;

create or replace function public.submit_physical_completion(p_work_order_id uuid, p_payload jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  actor jsonb:=public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  w public.work_orders%rowtype;
  result public.work_orders%rowtype;
  statement text;
  hours numeric;
  evidence_ids jsonb;
  cycle integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  actor_name:=coalesce(actor->>'display_name',actor->>'name','Unknown user');
  actor_role:=actor->>'role';
  if actor_role not in ('technician','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Field execution authority is required.');
  end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Only active assigned work may be submitted as physically complete.'); end if;
  if w.assigned_technician_id is null or w.assigned_technician_id<>actor_id or not public.field_work_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','The active field-responsible person for this facility is required.');
  end if;

  statement:=nullif(pg_catalog.btrim(coalesce(p_payload->>'completion_notes',w.completion_notes,'')),'');
  begin hours:=coalesce(nullif(p_payload->>'actual_labour_hours','')::numeric,w.actual_labour_hours); exception when others then hours:=null; end;
  if statement is null then return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED','A work-performed statement is required.'); end if;
  if hours is null or hours<0 then return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED','Cumulative non-negative labour hours are required.'); end if;
  if w.actual_labour_hours is not null and hours<w.actual_labour_hours then return public.work_order_result_error('CUMULATIVE_LABOUR_REQUIRED','Cumulative labour hours cannot decrease.'); end if;

  select coalesce(pg_catalog.jsonb_agg(e.id order by e.uploaded_at,e.id),'[]'::jsonb) into evidence_ids
  from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null;
  if pg_catalog.jsonb_array_length(evidence_ids)=0 then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','At least one active After evidence item is required.'); end if;

  select pg_catalog.count(*)+1 into cycle from public.activity_logs l where l.work_order_id=w.id and l.action='work_order_returned_for_rework';
  update public.work_orders
  set status='completed',completion_notes=statement,actual_labour_hours=hours,
      started_at=coalesce(started_at,pg_catalog.now()),completed_at=pg_catalog.now(),updated_at=pg_catalog.now()
  where id=w.id returning * into result;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_complete',w.status,'completed',actor_name,
    pg_catalog.jsonb_build_object(
      'cycle',cycle,
      'completion_notes',statement,
      'cumulative_labour_hours',hours,
      'completed_at',result.completed_at,
      'evidence_ids',evidence_ids,
      'submitted_by',actor_id,
      'submitted_role',actor_role,
      'submitted_at',pg_catalog.now(),
      'submission_type','field_physical_completion'
    )::text);

  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle);
exception
  when check_violation or invalid_text_representation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Physical completion data is invalid.');
  when others then return public.work_order_result_error('INTERNAL_ERROR','Physical completion submission failed.');
end;
$function$;

create or replace function public.register_evidence_item(
  p_parent_type text,
  p_parent_id uuid,
  p_original_filename text,
  p_content_type text,
  p_byte_size bigint,
  p_category text,
  p_description text,
  p_storage_path text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_name text;
  actor_role text;
  result public.evidence_items;
begin
  if actor_id is null then return pg_catalog.jsonb_build_object('ok',false,'code','AUTHENTICATION_REQUIRED'); end if;
  if not public.pilot_account_ready(actor_id) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;

  select display_name,role into actor_name,actor_role from public.profiles where id=actor_id;

  if p_parent_type='work_order' then
    if actor_role not in ('technician','supervisor','facility_manager','administrator') then
      return pg_catalog.jsonb_build_object('ok',false,'code','EVIDENCE_READ_ONLY');
    end if;
    if not exists(
      select 1 from public.work_orders w
      where w.id=p_parent_id
        and w.assigned_technician_id=actor_id
        and w.status in ('assigned','in_progress')
        and public.field_work_facility_permitted(w.facility_id)
    ) then
      return pg_catalog.jsonb_build_object('ok',false,'code','EVIDENCE_READ_ONLY');
    end if;
  elsif p_parent_type='incident' then
    if not exists(
      select 1 from public.incidents i
      where i.id=p_parent_id and (
        actor_role in ('approver','supervisor','administrator')
        or i.reported_by=actor_id
        or i.assigned_technician_id=actor_id
        or (
          i.assigned_team_id is not null and exists(
            select 1 from public.maintenance_team_members m
            where m.team_id=i.assigned_team_id and m.profile_id=actor_id and m.is_active
          )
        )
      )
    ) then
      return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED');
    end if;
  else
    return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  end if;

  if p_storage_path not like 'evidence/'||pg_catalog.replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%'
    or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path)
  then
    return pg_catalog.jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT');
  end if;

  insert into public.evidence_items(
    parent_type,work_order_id,incident_id,uploaded_by,original_filename,
    content_type,byte_size,category,description,storage_path
  ) values(
    p_parent_type,
    case when p_parent_type='work_order' then p_parent_id end,
    case when p_parent_type='incident' then p_parent_id end,
    actor_id,p_original_filename,p_content_type,p_byte_size,p_category,
    nullif(pg_catalog.btrim(p_description),''),p_storage_path
  ) returning * into result;

  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note)
  values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,
    pg_catalog.jsonb_build_object(
      'evidence_id',result.id,
      'category',result.category,
      'parent_type',result.parent_type,
      'field_role',actor_role
    )::text);

  return pg_catalog.jsonb_build_object('ok',true,'evidence',pg_catalog.to_jsonb(result)-'storage_path');
exception
  when check_violation or invalid_text_representation then return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  when unique_violation then return pg_catalog.jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE');
  when others then return pg_catalog.jsonb_build_object('ok',false,'code','INTERNAL_ERROR');
end;
$function$;

revoke all on function public.field_work_facility_permitted(uuid) from public, anon, service_role;
revoke all on function public.accept_work_responsibility(uuid) from public, anon, service_role;
revoke all on function public.submit_physical_completion(uuid,jsonb) from public, anon, service_role;
revoke all on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) from public, anon, service_role;
grant execute on function public.field_work_facility_permitted(uuid) to authenticated;
grant execute on function public.accept_work_responsibility(uuid) to authenticated;
grant execute on function public.submit_physical_completion(uuid,jsonb) to authenticated;
grant execute on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) to authenticated;

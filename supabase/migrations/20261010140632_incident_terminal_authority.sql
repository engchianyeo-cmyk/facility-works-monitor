-- Responders progress through Recovery; terminal authority remains with management.
begin;

create or replace function public.transition_incident(p_incident_id uuid, p_action text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $fn$
declare actor_id uuid := auth.uid(); actor_role text := public.current_user_role(); previous public.incidents; incident public.incidents; target text; authorized boolean := false;
begin
  if actor_id is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if not public.pilot_account_ready(actor_id) then return public.incident_result_error('ACCESS_DENIED','An active ready profile is required.'); end if;
  select * into previous from public.incidents where id=p_incident_id for update;
  if previous.id is null then return public.incident_result_error('NOT_FOUND','Incident was not found.'); end if;
  target := case pg_catalog.lower(p_action)
    when 'acknowledge' then 'acknowledged' when 'mobilise' then 'mobilising'
    when 'arrive' then 'on_site' when 'start_rescue' then 'rescue_in_progress'
    when 'make_safe' then 'safe' when 'start_recovery' then 'recovery'
    when 'close' then 'closed' when 'cancel' then 'cancelled' end;
  if target is null then return public.incident_result_error('INVALID_TRANSITION','The incident transition is not allowed.'); end if;
  if not ((previous.status='reported' and target='acknowledged') or (previous.status='acknowledged' and target='mobilising')
    or (previous.status='mobilising' and target='on_site') or (previous.status='on_site' and target='rescue_in_progress')
    or (previous.status='rescue_in_progress' and target='safe') or (previous.status='safe' and target='recovery')
    or (previous.status='recovery' and target='closed') or (target='cancelled' and previous.status not in ('closed','cancelled'))) then
    return public.incident_result_error('INVALID_TRANSITION','The incident transition is not allowed.');
  end if;
  authorized := actor_role='administrator'
    or (actor_role='supervisor' and target in ('closed','cancelled'))
    or (target not in ('closed','cancelled') and actor_role='technician' and actor_id=previous.assigned_technician_id)
    or (target not in ('closed','cancelled') and actor_role='technician' and previous.assigned_team_id is not null and exists(
      select 1 from public.maintenance_team_members m where m.team_id=previous.assigned_team_id and m.profile_id=actor_id and m.is_active));
  if not authorized then return public.incident_result_error('ACCESS_DENIED','You cannot update this incident.'); end if;
  update public.incidents set status=target,
    acknowledged_at=case when target='acknowledged' then pg_catalog.now() else acknowledged_at end,
    mobilising_at=case when target='mobilising' then pg_catalog.now() else mobilising_at end,
    on_site_at=case when target='on_site' then pg_catalog.now() else on_site_at end,
    rescue_started_at=case when target='rescue_in_progress' then pg_catalog.now() else rescue_started_at end,
    safe_at=case when target='safe' then pg_catalog.now() else safe_at end,
    recovery_started_at=case when target='recovery' then pg_catalog.now() else recovery_started_at end,
    closed_at=case when target='closed' then pg_catalog.now() else closed_at end
    where id=p_incident_id returning * into incident;
  insert into public.activity_logs(user_id,incident_id,action,from_status,to_status,actor)
    select actor_id,incident.id,'incident_'||pg_catalog.lower(p_action),previous.status,target,p.display_name from public.profiles p where p.id=actor_id;
  return pg_catalog.jsonb_build_object('ok',true,'incident',pg_catalog.to_jsonb(incident));
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The incident transition could not be completed.');
end;
$fn$;


revoke all on function public.transition_incident(uuid,text) from public,anon,service_role;
grant execute on function public.transition_incident(uuid,text) to authenticated;

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

revoke all on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) from public,anon,service_role;
grant execute on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) to authenticated;


commit;

-- Keep Incident evidence editable only while the response record is active and
-- provide the audited soft-removal path exposed by the Evidence panel.
begin;

create or replace function public.incident_evidence_mutation_permitted(p_incident_id uuid, p_actor_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select exists(
    select 1
    from public.incidents i
    join public.profiles p on p.id=p_actor_id
    where i.id=p_incident_id
      and public.pilot_account_ready(p_actor_id)
      and i.status not in ('closed','cancelled')
      and (
        p.role in ('approver','supervisor','administrator')
        or i.reported_by=p_actor_id
        or i.assigned_technician_id=p_actor_id
        or (i.assigned_team_id is not null and exists(
          select 1 from public.maintenance_team_members m
          where m.team_id=i.assigned_team_id and m.profile_id=p_actor_id and m.is_active
        ))
      )
  );
$function$;

revoke all on function public.incident_evidence_mutation_permitted(uuid,uuid) from public,anon,authenticated,service_role;

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

create or replace function public.void_incident_evidence(p_evidence_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor_id uuid:=auth.uid(); item public.evidence_items%rowtype; incident public.incidents%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); actor_name text;
begin
  if actor_id is null or not public.pilot_account_ready(actor_id) then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into item from public.evidence_items where id=p_evidence_id and deleted_at is null for update;
  if item.id is null or item.incident_id is null then return public.work_order_result_error('NOT_FOUND','Active Incident evidence was not found.'); end if;
  select * into incident from public.incidents where id=item.incident_id for update;
  if reason is null or pg_catalog.length(reason)>500 then return public.work_order_result_error('VALIDATION_ERROR','A bounded removal reason is required.'); end if;
  if not public.incident_evidence_mutation_permitted(incident.id,actor_id) then return public.work_order_result_error('ACCESS_DENIED','Incident evidence is read-only or the caller lacks response authority.'); end if;
  select display_name into actor_name from public.profiles where id=actor_id;
  update public.evidence_items set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason=reason where id=item.id;
  insert into public.activity_logs(user_id,incident_id,action,from_status,to_status,actor,note)
  values(actor_id,incident.id,'incident_evidence_voided',incident.status,incident.status,actor_name,
    pg_catalog.jsonb_build_object('evidence_id',item.id,'filename',item.original_filename,'original_category',item.category,'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true);
end;
$function$;

revoke all on function public.void_incident_evidence(uuid,text) from public,anon,service_role;
grant execute on function public.void_incident_evidence(uuid,text) to authenticated;

commit;

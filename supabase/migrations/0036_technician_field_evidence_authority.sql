begin;

create or replace function public.register_evidence_item(
  p_parent_type text,p_parent_id uuid,p_original_filename text,p_content_type text,
  p_byte_size bigint,p_category text,p_description text,p_storage_path text
) returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor_id uuid:=auth.uid(); actor_name text; actor_role text; result public.evidence_items;
begin
  if actor_id is null then return pg_catalog.jsonb_build_object('ok',false,'code','AUTHENTICATION_REQUIRED'); end if;
  if not public.pilot_account_ready(actor_id) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  select display_name,role into actor_name,actor_role from public.profiles where id=actor_id;
  if p_parent_type='work_order' then
    if actor_role='technician' then
      if not exists(
        select 1 from public.work_orders w
        where w.id=p_parent_id
          and w.assigned_technician_id=actor_id
          and w.status in ('assigned','in_progress')
          and exists (
            select 1 from public.facility_memberships fm
            join public.sites s on s.id=fm.facility_id
            where fm.profile_id=actor_id
              and fm.facility_id=w.facility_id
              and fm.membership_role='technician'
              and fm.active
              and fm.effective_from<=pg_catalog.now()
              and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
              and s.is_active
          )
      ) then return pg_catalog.jsonb_build_object('ok',false,'code','EVIDENCE_READ_ONLY'); end if;
    elsif not exists(select 1 from public.work_orders w where w.id=p_parent_id and (
      actor_role in ('approver','supervisor','administrator') or w.user_id=actor_id or w.requested_by=actor_id
    )) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  elsif p_parent_type='incident' then
    if not exists(select 1 from public.incidents i where i.id=p_parent_id and (
      actor_role in ('approver','supervisor','administrator') or i.reported_by=actor_id or i.assigned_technician_id=actor_id
      or (i.assigned_team_id is not null and exists(select 1 from public.maintenance_team_members m where m.team_id=i.assigned_team_id and m.profile_id=actor_id and m.is_active))
    )) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  else return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;
  if p_storage_path not like 'evidence/'||pg_catalog.replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%'
    or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path)
  then return pg_catalog.jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT'); end if;
  insert into public.evidence_items(parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path)
  values(p_parent_type,case when p_parent_type='work_order' then p_parent_id end,case when p_parent_type='incident' then p_parent_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_category,nullif(pg_catalog.btrim(p_description),''),p_storage_path)
  returning * into result;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note)
  values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,
    pg_catalog.jsonb_build_object('evidence_id',result.id,'category',result.category,'parent_type',result.parent_type)::text);
  return pg_catalog.jsonb_build_object('ok',true,'evidence',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or invalid_text_representation then return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
when unique_violation then return pg_catalog.jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE');
when others then return pg_catalog.jsonb_build_object('ok',false,'code','INTERNAL_ERROR'); end;
$function$;

revoke all on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) from public,anon,service_role;
grant execute on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) to authenticated;

do $$
declare definition text; secured boolean; config text[];
begin
  select pg_catalog.pg_get_functiondef(p.oid),p.prosecdef,p.proconfig into definition,secured,config
  from pg_catalog.pg_proc p where p.oid='public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'::regprocedure;
  if not secured or config<>array['search_path=pg_catalog']
    or definition !~ 'actor_role\s*=\s*''technician'''
    or definition !~ 'w\.assigned_technician_id\s*=\s*actor_id'
    or definition !~ 'fm\.profile_id\s*=\s*actor_id'
    or definition !~ 'fm\.facility_id\s*=\s*w\.facility_id'
    or definition !~ 'fm\.membership_role\s*=\s*''technician'''
    or definition !~ 'fm\.active'
    or definition !~ 'fm\.effective_from\s*<=\s*pg_catalog\.now\(\)'
    or definition !~ 'fm\.effective_to\s+is\s+null\s+or\s+fm\.effective_to\s*>\s*pg_catalog\.now\(\)'
    or definition !~ 's\.is_active'
    or definition !~ 'w\.status\s+in\s*\(''assigned'',\s*''in_progress''\)'
    or definition !~ 'actor_role\s+in\s*\(''approver'',\s*''supervisor'',\s*''administrator''\)'
    or definition !~ 'w\.user_id\s*=\s*actor_id'
    or definition !~ 'w\.requested_by\s*=\s*actor_id'
    or definition ~ '''facility_manager'''
    or definition ~* 'trade_discipline|electrical|mechanical' then
    raise exception '0036 postcondition failed: field-evidence authorization contract mismatch';
  end if;
end$$;

commit;

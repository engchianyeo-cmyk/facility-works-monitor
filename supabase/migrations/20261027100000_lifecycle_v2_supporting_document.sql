-- WP-LC2-M8 (D-14, owner 27 Oct 2026 15:59): "Other supporting document" as a field evidence category.
-- Stored as the existing evidence_items category 'document' (already allowed by the table constraint).
-- It does not count as Before or After evidence; those requirements are unchanged.
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

do $postcheck$
declare definition text;
begin
  select pg_catalog.pg_get_functiondef('public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'::regprocedure) into definition;
  if definition not like '%p_category not in (''before'',''after'',''document'')%' then raise exception 'LC2-M8 evidence category postcondition failed'; end if;
  if not exists(select 1 from pg_catalog.pg_constraint c where c.conname='evidence_items_category_check'
                and pg_catalog.pg_get_constraintdef(c.oid) like '%document%') then raise exception 'LC2-M8 table constraint does not allow document'; end if;
end;$postcheck$;
commit;

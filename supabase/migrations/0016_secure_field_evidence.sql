begin;

create table public.evidence_items (
  id uuid primary key default gen_random_uuid(),
  parent_type text not null check (parent_type in ('work_order','incident')),
  work_order_id uuid references public.work_orders(id) on delete cascade,
  incident_id uuid references public.incidents(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  original_filename text not null check (length(original_filename) between 1 and 255),
  content_type text not null check (content_type in ('image/jpeg','image/png','image/webp','application/pdf')),
  byte_size bigint not null check (byte_size between 1 and 10485760),
  category text not null check (category in ('before','after','completion','document','other')),
  description text check (description is null or length(description) <= 500),
  storage_path text not null unique,
  uploaded_at timestamptz not null default now(),
  constraint evidence_parent_exactly_one check (
    (parent_type='work_order' and work_order_id is not null and incident_id is null)
    or (parent_type='incident' and incident_id is not null and work_order_id is null)
  ),
  constraint evidence_storage_path_check check (
    storage_path ~ '^evidence/(work-order|incident)/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[^/]+$'
  )
);

create index evidence_work_order_idx on public.evidence_items(work_order_id,uploaded_at desc) where work_order_id is not null;
create index evidence_incident_idx on public.evidence_items(incident_id,uploaded_at desc) where incident_id is not null;

alter table public.evidence_items enable row level security;
create policy evidence_parent_authorized_read on public.evidence_items for select to authenticated using (
  (work_order_id is not null and exists(select 1 from public.work_orders w where w.id=work_order_id))
  or (incident_id is not null and exists(select 1 from public.incidents i where i.id=incident_id))
);
revoke all on table public.evidence_items from public,anon,authenticated;
grant select on public.evidence_items to authenticated;

create or replace function public.register_evidence_item(
  p_parent_type text,p_parent_id uuid,p_original_filename text,p_content_type text,
  p_byte_size bigint,p_category text,p_description text,p_storage_path text
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $fn$
declare actor_id uuid:=auth.uid(); actor_name text; result public.evidence_items;
begin
  if actor_id is null then return jsonb_build_object('ok',false,'code','AUTHENTICATION_REQUIRED'); end if;
  select display_name into actor_name from public.profiles where id=actor_id and is_active and deleted_at is null;
  if actor_name is null then return jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  if p_parent_type='work_order' then
    if not exists(select 1 from public.work_orders w where w.id=p_parent_id and (
      public.current_user_role() in ('approver','supervisor','administrator') or w.user_id=actor_id or w.requested_by=actor_id or w.assigned_technician_id=actor_id
    )) then return jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  elsif p_parent_type='incident' then
    if not exists(select 1 from public.incidents i where i.id=p_parent_id and (
      public.current_user_role() in ('approver','supervisor','administrator') or i.reported_by=actor_id or i.assigned_technician_id=actor_id
      or (i.assigned_team_id is not null and exists(select 1 from public.maintenance_team_members m where m.team_id=i.assigned_team_id and m.profile_id=actor_id and m.is_active))
    )) then return jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  else return jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;

  if p_storage_path not like 'evidence/'||replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%'
    or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path)
  then return jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT'); end if;

  insert into public.evidence_items(parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path)
  values(p_parent_type,case when p_parent_type='work_order' then p_parent_id end,case when p_parent_type='incident' then p_parent_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_category,nullif(btrim(p_description),''),p_storage_path)
  returning * into result;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note)
  values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,
    jsonb_build_object('evidence_id',result.id,'category',result.category,'parent_type',result.parent_type)::text);
  return jsonb_build_object('ok',true,'evidence',to_jsonb(result)-'storage_path');
exception when check_violation or invalid_text_representation then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
when unique_violation then return jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE');
when others then return jsonb_build_object('ok',false,'code','INTERNAL_ERROR'); end;
$fn$;

revoke all on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) from public,anon,service_role;
grant execute on function public.register_evidence_item(text,uuid,text,text,bigint,text,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('field-evidence','field-evidence',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']::text[])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- No storage.objects policies are created. Protected server routes validate the
-- authenticated parent record, then use the server-only service role for object
-- upload and five-minute signed access. Browser clients never receive service credentials.
commit;

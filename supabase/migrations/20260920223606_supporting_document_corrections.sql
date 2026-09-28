begin;

create table public.work_order_document_corrections(
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete restrict,
  original_status text not null,
  status text not null default 'open' check(status in ('open','closed')),
  reason text not null check(length(reason) between 3 and 1000),
  opened_by uuid not null references public.profiles(id) on delete restrict,
  opened_at timestamptz not null default now(),
  closed_by uuid references public.profiles(id) on delete restrict,
  closed_at timestamptz,
  closure_note text,
  created_at timestamptz not null default now()
);
create unique index work_order_document_corrections_one_open_idx on public.work_order_document_corrections(work_order_id) where status='open';
alter table public.work_order_document_corrections enable row level security;
revoke all on public.work_order_document_corrections from public,anon,authenticated;
grant select on public.work_order_document_corrections to authenticated;
create policy work_order_document_corrections_read on public.work_order_document_corrections for select to authenticated using(
  exists(select 1 from public.work_orders w where w.id=work_order_document_corrections.work_order_id)
);

alter table public.work_order_commercial_documents
  add column if not exists superseded_by uuid references public.work_order_commercial_documents(id) on delete restrict,
  add column if not exists superseded_at timestamptz,
  add column if not exists superseded_by_user uuid references public.profiles(id) on delete restrict;

create or replace function public.open_work_order_document_correction(p_work_order_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_document_corrections%rowtype; reason_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; reason_text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Authorized management approval is required to open a document correction.'); end if;
  if w.status not in ('completed','reviewed','closed') then return public.work_order_result_error('INVALID_TRANSITION','Document correction is only available after physical completion.'); end if;
  if w.assigned_technician_id is null then return public.work_order_result_error('INVALID_ASSIGNMENT','An assigned Technician is required.'); end if;
  if reason_text is null or length(reason_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A correction reason is required.'); end if;
  if exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open') then return public.work_order_result_error('CORRECTION_ALREADY_OPEN','A supporting-document correction is already open.'); end if;
  insert into public.work_order_document_corrections(work_order_id,original_status,reason,opened_by) values(w.id,w.status,reason_text,actor_id) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'supporting_document_correction_opened',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('correction_id',result.id,'reason',reason_text,'work_order_status_preserved',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'correction',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.start_work_order_quotation_revision(p_work_order_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; prior public.contractor_quotations%rowtype; result public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare a quotation revision.'); end if;
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

create or replace function public.close_work_order_document_correction(p_work_order_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; correction public.work_order_document_corrections%rowtype; note_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; note_text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),''); select * into w from public.work_orders where id=p_work_order_id;
  select * into correction from public.work_order_document_corrections where work_order_id=p_work_order_id and status='open' for update;
  if w.id is null or correction.id is null then return public.work_order_result_error('NOT_FOUND','An open supporting-document correction was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Authorized management verification is required to close a document correction.'); end if;
  if note_text is null or length(note_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A correction verification note is required.'); end if;
  if not exists(select 1 from public.evidence_items e where e.work_order_id=w.id and e.category='before' and e.deleted_at is null) then return public.work_order_result_error('BEFORE_EVIDENCE_REQUIRED','Active Before evidence is required.'); end if;
  if not exists(select 1 from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null) then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','Active After evidence is required.'); end if;
  if exists(select 1 from public.contractor_quotations q where q.work_order_id=w.id and q.status in ('draft','returned','submitted')) then return public.work_order_result_error('QUOTATION_APPROVAL_REQUIRED','The active quotation revision must be independently approved.'); end if;
  if not exists(select 1 from public.contractor_quotations q join public.work_order_commercial_documents d on d.quotation_id=q.id and d.deleted_at is null where q.work_order_id=w.id and q.status='approved') then return public.work_order_result_error('QUOTATION_DOCUMENT_REQUIRED','An approved quotation supporting document is required.'); end if;
  update public.work_order_document_corrections set status='closed',closed_by=actor_id,closed_at=pg_catalog.now(),closure_note=note_text where id=correction.id returning * into correction;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'supporting_document_correction_verified',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('correction_id',correction.id,'before_evidence_present',true,'after_evidence_present',true,'approved_quotation_document_present',true,'note',note_text,'original_history_preserved',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'correction',pg_catalog.to_jsonb(correction));
end;$function$;

create or replace function public.register_evidence_item(p_parent_type text,p_parent_id uuid,p_original_filename text,p_content_type text,p_byte_size bigint,p_category text,p_description text,p_storage_path text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor_id uuid:=auth.uid(); actor_name text; actor_role text; result public.evidence_items;
begin
  if actor_id is null then return pg_catalog.jsonb_build_object('ok',false,'code','AUTHENTICATION_REQUIRED'); end if;
  if not public.pilot_account_ready(actor_id) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  select display_name,role into actor_name,actor_role from public.profiles where id=actor_id;
  if p_parent_type='work_order' then
    if actor_role='technician' then
      if not exists(select 1 from public.work_orders w where w.id=p_parent_id and w.assigned_technician_id=actor_id and (w.status in ('assigned','in_progress') or (w.status in ('completed','reviewed','closed') and exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open'))) and exists(select 1 from public.facility_memberships fm join public.sites s on s.id=fm.facility_id where fm.profile_id=actor_id and fm.facility_id=w.facility_id and fm.membership_role='technician' and fm.active and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now()) and s.is_active)) then return pg_catalog.jsonb_build_object('ok',false,'code','EVIDENCE_READ_ONLY'); end if;
    elsif not exists(select 1 from public.work_orders w where w.id=p_parent_id and (actor_role in ('approver','supervisor','administrator') or w.user_id=actor_id or w.requested_by=actor_id)) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  elsif p_parent_type='incident' then
    if not exists(select 1 from public.incidents i where i.id=p_parent_id and (actor_role in ('approver','supervisor','administrator') or i.reported_by=actor_id or i.assigned_technician_id=actor_id or (i.assigned_team_id is not null and exists(select 1 from public.maintenance_team_members m where m.team_id=i.assigned_team_id and m.profile_id=actor_id and m.is_active)))) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  else return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;
  if p_category not in ('before','after') or p_storage_path not like 'evidence/'||pg_catalog.replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return pg_catalog.jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT'); end if;
  insert into public.evidence_items(parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path) values(p_parent_type,case when p_parent_type='work_order' then p_parent_id end,case when p_parent_type='incident' then p_parent_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_category,nullif(pg_catalog.btrim(p_description),''),p_storage_path) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note) values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,pg_catalog.jsonb_build_object('evidence_id',result.id,'category',result.category,'parent_type',result.parent_type,'document_correction',exists(select 1 from public.work_order_document_corrections c where c.work_order_id=result.work_order_id and c.status='open'))::text);
  return pg_catalog.jsonb_build_object('ok',true,'evidence',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or invalid_text_representation then return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); when unique_violation then return pg_catalog.jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE'); when others then return pg_catalog.jsonb_build_object('ok',false,'code','INTERNAL_ERROR'); end;$function$;

create or replace function public.register_work_order_commercial_document(p_work_order_id uuid,p_document_type text,p_record_id uuid,p_original_filename text,p_content_type text,p_byte_size bigint,p_storage_path text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_commercial_documents%rowtype; replaced_ids uuid[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may attach commercial documents.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Commercial document authority is required.'); end if;
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

create or replace function public.submit_work_order_proposal(p_work_order_id uuid,p_quotation_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype; required_count integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Draft proposal was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or q.prepared_by is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician who prepared the draft may submit it.'); end if;
  if q.status not in ('draft','returned') then return public.work_order_result_error('INVALID_TRANSITION','Only a draft or returned proposal may be submitted.'); end if;
  if not exists(select 1 from public.work_order_commercial_documents d where d.quotation_id=q.id and d.document_type='quotation' and d.deleted_at is null) then return public.work_order_result_error('QUOTATION_DOCUMENT_REQUIRED','Attach the contractor quotation before submitting for approval.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update; select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  if coalesce(required_count,1)<>1 or q.total_amount>=1000 then return public.work_order_result_error('APPROVAL_NOT_READY','This Release-1 path is limited to the configured below-S$1,000 one-quotation rule.'); end if;
  update public.contractor_quotations set status='submitted',submitted_by=actor_id,submitted_at=pg_catalog.now(),submission_note=nullif(pg_catalog.btrim(coalesce(p_note,'')),''),updated_at=pg_catalog.now() where id=q.id returning * into q;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,cost_status='recommended',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=coalesce(nullif(pg_catalog.btrim(coalesce(p_note,'')),''),'Submitted for independent approval under the configured one-quotation rule.'),financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_submitted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'version_no',q.version_no,'proposed_amount',q.total_amount,'quotation_document_attached',true,'required_quotations',required_count)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$;

create or replace function public.approve_work_order_proposal(p_work_order_id uuid,p_quotation_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Submitted proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent financial approval authority is required.'); end if;
  if q.submitted_by=actor_id or q.prepared_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','A proposal preparer cannot approve the same expenditure.'); end if;
  if q.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only a submitted proposal may be approved.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('VALIDATION_ERROR','An independent approval note is required.'); end if;
  if not exists(select 1 from public.work_order_commercial_documents d where d.quotation_id=q.id and d.document_type='quotation' and d.deleted_at is null) then return public.work_order_result_error('QUOTATION_DOCUMENT_REQUIRED','The supporting quotation document is required for approval.'); end if;
  update public.contractor_quotations set status='superseded',updated_at=pg_catalog.now() where work_order_id=w.id and id<>q.id and status='approved';
  update public.contractor_quotations set status='approved',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=pg_catalog.btrim(p_note),updated_at=pg_catalog.now() where id=q.id returning * into q;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,approved_budget=q.total_amount,cost_status='approved',financial_approved_by=actor_id,financial_approved_at=pg_catalog.now(),financial_approval_note=pg_catalog.btrim(p_note),updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_independently_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'version_no',q.version_no,'approved_amount',q.total_amount,'supporting_document_locked',true,'prepared_by',q.prepared_by,'approved_by',actor_id,'self_approval',false)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$;

revoke all on function public.open_work_order_document_correction(uuid,text),public.close_work_order_document_correction(uuid,text),public.start_work_order_quotation_revision(uuid) from public,anon,service_role;
grant execute on function public.open_work_order_document_correction(uuid,text),public.close_work_order_document_correction(uuid,text),public.start_work_order_quotation_revision(uuid) to authenticated;

commit;

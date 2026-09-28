begin;

do $constraints$
declare item record;
begin
  for item in select conname from pg_catalog.pg_constraint where conrelid='public.evidence_items'::regclass and contype='c'
    and pg_catalog.pg_get_constraintdef(oid) ilike '%content_type%' loop execute pg_catalog.format('alter table public.evidence_items drop constraint %I',item.conname); end loop;
  for item in select conname from pg_catalog.pg_constraint where conrelid='public.evidence_items'::regclass and contype='c'
    and pg_catalog.pg_get_constraintdef(oid) ilike '%byte_size%' loop execute pg_catalog.format('alter table public.evidence_items drop constraint %I',item.conname); end loop;
end;$constraints$;
alter table public.evidence_items add constraint evidence_items_content_type_check check(content_type in ('image/jpeg','image/png','image/webp','video/mp4','video/webm','application/pdf'));
alter table public.evidence_items add constraint evidence_items_byte_size_check check(byte_size between 1 and 52428800);

create table public.work_order_final_cost_submissions(
  id uuid primary key default gen_random_uuid(), work_order_id uuid not null unique references public.work_orders(id) on delete restrict,
  status text not null default 'draft' check(status in ('draft','confirmed','variance_pending','variance_approved')),
  actual_labour_hours numeric(12,2) not null check(actual_labour_hours>=0), final_contractor_amount numeric(14,2) not null check(final_contractor_amount>=0),
  confirmed_actual_cost numeric(14,2) not null check(confirmed_actual_cost>=0), comments text not null check(length(comments) between 3 and 2000),
  submitted_by uuid not null references public.profiles(id) on delete restrict, submitted_at timestamptz,
  variance_approved_by uuid references public.profiles(id) on delete restrict, variance_approved_at timestamptz, variance_approval_note text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.work_order_final_cost_documents(
  id uuid primary key default gen_random_uuid(), final_cost_submission_id uuid not null references public.work_order_final_cost_submissions(id) on delete restrict,
  work_order_id uuid not null references public.work_orders(id) on delete restrict, uploaded_by uuid not null references public.profiles(id) on delete restrict,
  original_filename text not null, content_type text not null check(content_type in ('image/jpeg','image/png','image/webp','application/pdf')),
  byte_size bigint not null check(byte_size between 1 and 10485760), storage_path text not null unique, uploaded_at timestamptz not null default now(),
  deleted_at timestamptz, deleted_by uuid references public.profiles(id) on delete restrict, deletion_reason text,
  superseded_by uuid references public.work_order_final_cost_documents(id) on delete restrict
);
alter table public.work_order_final_cost_submissions enable row level security;
alter table public.work_order_final_cost_documents enable row level security;
revoke all on public.work_order_final_cost_submissions,public.work_order_final_cost_documents from public,anon,authenticated;
grant select on public.work_order_final_cost_submissions,public.work_order_final_cost_documents to authenticated;
create policy final_cost_read on public.work_order_final_cost_submissions for select to authenticated using(exists(select 1 from public.work_orders w where w.id=work_order_id));
create policy final_cost_documents_read on public.work_order_final_cost_documents for select to authenticated using(exists(select 1 from public.work_orders w where w.id=work_order_id));

create or replace function public.save_work_order_final_cost(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_final_cost_submissions%rowtype;
  labour numeric; contractor numeric; actual numeric; approved numeric; note text; next_status text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or w.status not in ('assigned','in_progress') or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may submit final costs for active work.'); end if;
  begin labour:=(p_payload->>'actual_labour_hours')::numeric; contractor:=(p_payload->>'final_contractor_amount')::numeric; actual:=(p_payload->>'confirmed_actual_cost')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Final cost amounts are invalid.'); end;
  note:=nullif(pg_catalog.btrim(coalesce(p_payload->>'comments','')),'');
  if labour<0 or contractor<0 or actual<0 or note is null or length(note)>2000 then return public.work_order_result_error('VALIDATION_ERROR','Labour hours, final contractor amount, confirmed actual cost and comments are required.'); end if;
  select approved_budget into approved from public.work_order_financial_controls where work_order_id=w.id;
  next_status:=case when actual>coalesce(approved,0) then 'variance_pending' else 'confirmed' end;
  insert into public.work_order_final_cost_submissions(work_order_id,status,actual_labour_hours,final_contractor_amount,confirmed_actual_cost,comments,submitted_by,submitted_at)
  values(w.id,next_status,labour,contractor,actual,note,actor_id,pg_catalog.now())
  on conflict(work_order_id) do update set status=excluded.status,actual_labour_hours=excluded.actual_labour_hours,final_contractor_amount=excluded.final_contractor_amount,
    confirmed_actual_cost=excluded.confirmed_actual_cost,comments=excluded.comments,submitted_by=excluded.submitted_by,submitted_at=excluded.submitted_at,
    variance_approved_by=null,variance_approved_at=null,variance_approval_note=null,updated_at=pg_catalog.now() returning * into result;
  update public.work_orders set actual_labour_hours=labour,actual_costs_confirmed_at=pg_catalog.now(),actual_costs_confirmed_by=actor_id,updated_at=pg_catalog.now() where id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_cost_submitted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('submission_id',result.id,'approved_expenditure',approved,'final_contractor_amount',contractor,'confirmed_actual_cost',actual,'variance',actual-coalesce(approved,0),'status',next_status)::text);
  return pg_catalog.jsonb_build_object('ok',true,'final_cost',pg_catalog.to_jsonb(result),'approved_expenditure',approved,'variance',actual-coalesce(approved,0));
end;$function$;

create or replace function public.approve_work_order_final_cost_variance(p_work_order_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_final_cost_submissions%rowtype; note text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),'');
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 if actor->>'role' not in ('approver','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent expenditure authority is required.'); end if;
 select * into w from public.work_orders where id=p_work_order_id; select * into result from public.work_order_final_cost_submissions where work_order_id=p_work_order_id for update;
 if result.id is null or result.status<>'variance_pending' then return public.work_order_result_error('INVALID_TRANSITION','A pending final-cost variance was not found.'); end if;
 if result.submitted_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The Technician cannot approve their own final-cost variance.'); end if;
 if note is null then return public.work_order_result_error('VALIDATION_ERROR','An approval note is required.'); end if;
 update public.work_order_final_cost_submissions set status='variance_approved',variance_approved_by=actor_id,variance_approved_at=pg_catalog.now(),variance_approval_note=note,updated_at=pg_catalog.now() where id=result.id returning * into result;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_cost_variance_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('submission_id',result.id,'confirmed_actual_cost',result.confirmed_actual_cost,'approval_note',note)::text);
 return pg_catalog.jsonb_build_object('ok',true,'final_cost',pg_catalog.to_jsonb(result));
end;$function$;

create or replace function public.register_work_order_final_cost_document(p_work_order_id uuid,p_submission_id uuid,p_original_filename text,p_content_type text,p_byte_size bigint,p_storage_path text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; submission public.work_order_final_cost_submissions%rowtype; result public.work_order_final_cost_documents%rowtype; old_ids uuid[];
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into w from public.work_orders where id=p_work_order_id; select * into submission from public.work_order_final_cost_submissions where id=p_submission_id and work_order_id=p_work_order_id;
 if w.id is null or submission.id is null then return public.work_order_result_error('NOT_FOUND','Final-cost submission was not found.'); end if;
 if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) or not (w.status in ('assigned','in_progress') or exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open')) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned Technician may attach a final invoice while the record is editable.'); end if;
 if p_storage_path not like 'commercial/work-order/'||w.id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return public.work_order_result_error('INVALID_STORAGE_OBJECT','Final invoice storage could not be verified.'); end if;
 select pg_catalog.array_agg(id) into old_ids from public.work_order_final_cost_documents where final_cost_submission_id=submission.id and deleted_at is null;
 insert into public.work_order_final_cost_documents(final_cost_submission_id,work_order_id,uploaded_by,original_filename,content_type,byte_size,storage_path) values(submission.id,w.id,actor_id,p_original_filename,p_content_type,p_byte_size,p_storage_path) returning * into result;
 if old_ids is not null then update public.work_order_final_cost_documents set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason='Replaced by a controlled revision',superseded_by=result.id where id=any(old_ids); end if;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_invoice_attached',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',result.id,'submission_id',submission.id,'filename',result.original_filename,'replaced_document_ids',coalesce(pg_catalog.to_jsonb(old_ids),'[]'::jsonb))::text);
 return pg_catalog.jsonb_build_object('ok',true,'document',pg_catalog.to_jsonb(result)-'storage_path');
end;$function$;

create or replace function public.void_work_order_evidence(p_evidence_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; item public.evidence_items%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into item from public.evidence_items where id=p_evidence_id and deleted_at is null for update; if item.id is null or item.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Active Work Order evidence was not found.'); end if;
 select * into w from public.work_orders where id=item.work_order_id for update;
 if reason is null or length(reason)>500 then return public.work_order_result_error('VALIDATION_ERROR','A bounded removal reason is required.'); end if;
 if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) or not (w.status in ('assigned','in_progress') or exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open'))) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned Technician may remove evidence while the record is editable.'); end if;
 if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Evidence removal authority is required.'); end if;
 if item.category='after' and w.status in ('completed','reviewed','closed') and not exists(select 1 from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null and e.id<>item.id) then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','Upload replacement After evidence before removing the last mandatory item.'); end if;
 update public.evidence_items set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason=reason where id=item.id;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'evidence_voided',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('evidence_id',item.id,'filename',item.original_filename,'original_category',item.category,'reason',reason)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$;

create or replace function public.withdraw_physical_completion(p_work_order_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into w from public.work_orders where id=p_work_order_id for update;
 if w.status<>'completed' then return public.work_order_result_error('INVALID_TRANSITION','Only an unverified completion submission may be withdrawn.'); end if;
 if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned Technician may withdraw their unverified completion submission.'); end if;
 if reason is null then return public.work_order_result_error('VALIDATION_ERROR','A withdrawal reason is required.'); end if;
 update public.work_orders set status='in_progress',completed_at=null,updated_at=pg_catalog.now() where id=w.id;
 update public.work_order_final_cost_submissions set status='draft',variance_approved_by=null,variance_approved_at=null,variance_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'physical_completion_withdrawn','completed','in_progress',actor->>'name',pg_catalog.jsonb_build_object('reason',reason,'prior_completed_at',w.completed_at,'physical_history_preserved',true)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$;

alter function public.submit_physical_completion(uuid,jsonb) rename to submit_physical_completion_20260921_core;
create function public.submit_physical_completion(p_work_order_id uuid,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare result public.work_order_final_cost_submissions%rowtype;
begin
 select * into result from public.work_order_final_cost_submissions where work_order_id=p_work_order_id;
 if result.id is null or result.status not in ('confirmed','variance_approved') then return public.work_order_result_error('FINAL_COST_REQUIRED','Submit final labour, contractor amount, confirmed actual cost and any required variance approval before physical completion.'); end if;
 if not exists(select 1 from public.work_order_final_cost_documents d where d.final_cost_submission_id=result.id and d.deleted_at is null) then return public.work_order_result_error('FINAL_INVOICE_REQUIRED','Attach the supporting final invoice before physical completion.'); end if;
 return public.submit_physical_completion_20260921_core(p_work_order_id,p_payload);
end;$function$;

revoke all on function public.save_work_order_final_cost(uuid,jsonb),public.approve_work_order_final_cost_variance(uuid,text),public.register_work_order_final_cost_document(uuid,uuid,text,text,bigint,text),public.void_work_order_evidence(uuid,text),public.withdraw_physical_completion(uuid,text),public.submit_physical_completion(uuid,jsonb),public.submit_physical_completion_20260921_core(uuid,jsonb) from public,anon,service_role;
grant execute on function public.save_work_order_final_cost(uuid,jsonb),public.approve_work_order_final_cost_variance(uuid,text),public.register_work_order_final_cost_document(uuid,uuid,text,text,bigint,text),public.void_work_order_evidence(uuid,text),public.withdraw_physical_completion(uuid,text),public.submit_physical_completion(uuid,jsonb) to authenticated;

commit;

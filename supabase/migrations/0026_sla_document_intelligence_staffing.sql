-- WP-FMW-010: governed SLA document intelligence and advisory staffing analysis.
begin;

do $preflight$ begin
 if to_regclass('public.sla_extraction_proposals') is null or to_regprocedure('public.approve_sla_version(uuid,text)') is null then
  raise exception '0026 prerequisite missing: WP-FMW-009 SLA foundation';
 end if;
end $preflight$;

create table public.sla_documents(
 id uuid primary key default gen_random_uuid(), agreement_id uuid references public.sla_agreements(id),
 title text not null, client_owner text, service_provider text, maintenance_model text not null check(maintenance_model in ('IN_HOUSE','OUTSOURCED','HYBRID')),
 agreement_reference text not null, version_label text not null, effective_date date, expiry_date date,
 original_filename text not null, media_type text not null check(media_type in ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','text/plain')),
 byte_size integer not null check(byte_size between 1 and 10485760), content_sha256 text not null check(content_sha256~'^[0-9a-f]{64}$'),
 storage_provider text not null default 'PILOT_DATABASE' check(storage_provider in ('PILOT_DATABASE','FUTURE_APPROVED_PROVIDER')),
 storage_key text not null unique, extracted_text text, review_status text not null default 'NOT_EXTRACTED' check(review_status in ('NOT_EXTRACTED','EXTRACTED','IN_REVIEW','REVIEWED','REJECTED')),
 approval_status text not null default 'DRAFT' check(approval_status in ('DRAFT','PENDING_APPROVAL','APPROVED','REJECTED')),
 superseded_at timestamptz, notes text, uploaded_by uuid not null references public.profiles(id), uploaded_at timestamptz not null default now(),
 check(expiry_date is null or effective_date is null or expiry_date>=effective_date), unique(agreement_reference,version_label)
);

alter table public.sla_extraction_proposals add column document_id uuid references public.sla_documents(id) on delete restrict;
alter table public.sla_extraction_proposals add column source_excerpt text;
alter table public.sla_extraction_proposals add column provider_model text;
alter table public.sla_extraction_proposals add column extraction_payload jsonb not null default '{}'::jsonb;
alter table public.sla_extraction_proposals add column extraction_warnings text[] not null default '{}';
alter table public.sla_extraction_proposals add column modifications jsonb not null default '[]'::jsonb;
alter table public.sla_extraction_proposals add column approved_rule_id uuid references public.sla_rules(id);
alter table public.sla_extraction_proposals add column approved_by uuid references public.profiles(id);
alter table public.sla_extraction_proposals add column approved_at timestamptz;

create table public.staffing_assessments(
 id uuid primary key default gen_random_uuid(), name text not null, operating_model text not null check(operating_model in ('IN_HOUSE','OUTSOURCED','HYBRID')),
 scope jsonb not null default '{}'::jsonb, facility_inputs jsonb not null default '{}'::jsonb, asset_inputs jsonb not null default '{}'::jsonb,
 service_inputs jsonb not null default '{}'::jsonb, workforce_inputs jsonb not null default '{}'::jsonb,
 proposed_organization jsonb not null default '[]'::jsonb, status text not null default 'DRAFT' check(status in ('DRAFT','ANALYSED','REVIEWED','ARCHIVED')),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.staffing_recommendations(
 id uuid primary key default gen_random_uuid(), assessment_id uuid not null references public.staffing_assessments(id) on delete cascade,
 provider_key text not null, provider_model text not null, recommendation jsonb not null, assumptions jsonb not null default '[]'::jsonb,
 unknown_inputs text[] not null default '{}', coverage_gaps jsonb not null default '[]'::jsonb, confidence numeric(5,4) check(confidence between 0 and 1),
 advisory_only boolean not null default true, generated_by uuid not null references public.profiles(id), generated_at timestamptz not null default now()
);

create or replace function public.create_sla_document(p_payload jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); result public.sla_documents;
begin
 if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management document authority is required.'); end if;
 if length(btrim(coalesce(p_payload->>'title','')))<3 or coalesce(p_payload->>'maintenance_model','') not in ('IN_HOUSE','OUTSOURCED','HYBRID') then return public.work_order_result_error('VALIDATION_ERROR','Valid title and maintenance model are required.'); end if;
 insert into public.sla_documents(agreement_id,title,client_owner,service_provider,maintenance_model,agreement_reference,version_label,effective_date,expiry_date,original_filename,media_type,byte_size,content_sha256,storage_key,extracted_text,notes,uploaded_by)
 values(nullif(p_payload->>'agreement_id','')::uuid,btrim(p_payload->>'title'),nullif(btrim(coalesce(p_payload->>'client_owner','')),''),nullif(btrim(coalesce(p_payload->>'service_provider','')),''),p_payload->>'maintenance_model',btrim(p_payload->>'agreement_reference'),btrim(p_payload->>'version_label'),nullif(p_payload->>'effective_date','')::date,nullif(p_payload->>'expiry_date','')::date,p_payload->>'original_filename',p_payload->>'media_type',(p_payload->>'byte_size')::integer,p_payload->>'content_sha256',p_payload->>'storage_key',nullif(p_payload->>'extracted_text',''),nullif(p_payload->>'notes',''),(actor->>'id')::uuid) returning * into result;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_document_ingested',actor->>'name',jsonb_build_object('document_id',result.id,'reference',result.agreement_reference,'version',result.version_label,'sha256',result.content_sha256)::text);
 return jsonb_build_object('ok',true,'document',to_jsonb(result)-'extracted_text');
exception when check_violation or unique_violation or invalid_text_representation then return public.work_order_result_error('VALIDATION_ERROR','Document metadata is invalid or this version already exists.'); end $fn$;

create or replace function public.record_sla_extraction(p_document_id uuid,p_provider_key text,p_provider_model text,p_candidates jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); candidate jsonb; proposal public.sla_extraction_proposals; ids jsonb:='[]'::jsonb;
begin
 if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management extraction authority is required.'); end if;
 if p_provider_key not in ('mock','disabled') or jsonb_typeof(p_candidates)<>'array' then return public.work_order_result_error('VALIDATION_ERROR','Provider or candidate output is invalid.'); end if;
 if not exists(select 1 from public.sla_documents where id=p_document_id and superseded_at is null) then return public.work_order_result_error('NOT_FOUND','SLA document is unavailable.'); end if;
 for candidate in select value from jsonb_array_elements(p_candidates) loop
  if coalesce(candidate->>'sourceClause','')='' or coalesce(candidate->>'extractedObligation','')='' or jsonb_typeof(candidate->'proposedRule')<>'object' or coalesce((candidate->>'confidence')::numeric,-1) not between 0 and 1 then return public.work_order_result_error('MALFORMED_AI_OUTPUT','Every candidate requires source, obligation, rule and confidence.'); end if;
  insert into public.sla_extraction_proposals(document_id,source_page,source_section,source_clause,source_excerpt,extracted_obligation,proposed_rule,confidence,ambiguity_warning,provider_key,provider_model,extraction_payload,extraction_warnings,created_by)
  values(p_document_id,candidate->>'sourcePage',candidate->>'sourceSection',candidate->>'sourceClause',candidate->>'sourceExcerpt',candidate->>'extractedObligation',candidate->'proposedRule',(candidate->>'confidence')::numeric,candidate->>'ambiguityWarning',p_provider_key,p_provider_model,candidate,coalesce(array(select jsonb_array_elements_text(coalesce(candidate->'warnings','[]'::jsonb))),'{}'),(actor->>'id')::uuid) returning * into proposal;
  ids:=ids||to_jsonb(proposal.id);
 end loop;
 update public.sla_documents set review_status='EXTRACTED' where id=p_document_id;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_document_extracted',actor->>'name',jsonb_build_object('document_id',p_document_id,'provider',p_provider_key,'model',p_provider_model,'candidate_count',jsonb_array_length(ids))::text);
 return jsonb_build_object('ok',true,'proposal_ids',ids,'human_approval_required',true);
end $fn$;

create or replace function public.review_sla_extraction(p_proposal_id uuid,p_decision text,p_changes jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); result public.sla_extraction_proposals;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Facility Manager or Administrator review is required.'); end if;
 if p_decision not in ('approved_for_draft','rejected') then return public.work_order_result_error('VALIDATION_ERROR','Review decision is invalid.'); end if;
 update public.sla_extraction_proposals set proposed_rule=case when p_decision='approved_for_draft' then proposed_rule||coalesce(p_changes,'{}'::jsonb) else proposed_rule end,human_approval_state=p_decision,reviewed_by=(actor->>'id')::uuid,reviewed_at=now(),modifications=modifications||jsonb_build_array(jsonb_build_object('at',now(),'by',actor->>'id','changes',coalesce(p_changes,'{}'::jsonb))) where id=p_proposal_id and human_approval_state='pending' returning * into result;
 if not found then return public.work_order_result_error('INVALID_STATE','Only pending proposals can be reviewed.'); end if;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_extraction_reviewed',actor->>'name',jsonb_build_object('proposal_id',result.id,'decision',p_decision,'changes',p_changes)::text);
 return jsonb_build_object('ok',true,'proposal',to_jsonb(result));
end $fn$;

create or replace function public.approve_reviewed_sla_clause(p_proposal_id uuid,p_version_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); p public.sla_extraction_proposals; rule public.sla_rules; category_id uuid; payload jsonb;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Facility Manager or Administrator approval is required.'); end if;
 select * into p from public.sla_extraction_proposals where id=p_proposal_id and human_approval_state='approved_for_draft' and approved_rule_id is null for update;
 if not found then return public.work_order_result_error('INVALID_STATE','A reviewed, unapproved proposal is required.'); end if; payload:=p.proposed_rule;
 select id into category_id from public.service_categories where code=coalesce(payload->>'serviceCategoryCode','GENERAL') and is_active; if category_id is null then return public.work_order_result_error('VALIDATION_ERROR','Service category is unavailable.'); end if;
 insert into public.sla_rules(version_id,service_category_id,priority_class,work_order_priority,acknowledgement_minutes,response_minutes,attendance_minutes,make_safe_minutes,rectification_minutes,kpi_target_percent,source_clause)
 values(p_version_id,category_id,payload->>'priorityClass',payload->>'workOrderPriority',nullif(payload->>'acknowledgementMinutes','')::integer,nullif(payload->>'responseMinutes','')::integer,nullif(payload->>'attendanceMinutes','')::integer,nullif(payload->>'makeSafeMinutes','')::integer,(payload->>'rectificationMinutes')::integer,(payload->>'kpiTargetPercent')::numeric,p.source_clause) returning * into rule;
 update public.sla_extraction_proposals set approved_rule_id=rule.id,approved_by=(actor->>'id')::uuid,approved_at=now() where id=p.id;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_clause_approved',actor->>'name',jsonb_build_object('proposal_id',p.id,'rule_id',rule.id,'document_id',p.document_id,'source_clause',p.source_clause)::text);
 return jsonb_build_object('ok',true,'rule',to_jsonb(rule),'lineage',jsonb_build_object('document_id',p.document_id,'proposal_id',p.id,'source_clause',p.source_clause));
exception when check_violation or unique_violation or invalid_text_representation then return public.work_order_result_error('VALIDATION_ERROR','Reviewed structured rule is incomplete or conflicts with this version.'); end $fn$;

create or replace function public.create_staffing_assessment(p_payload jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); result public.staffing_assessments;
begin
 if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management staffing authority is required.'); end if;
 if coalesce(p_payload->>'operating_model','') not in ('IN_HOUSE','OUTSOURCED','HYBRID') then return public.work_order_result_error('VALIDATION_ERROR','Operating model is invalid.'); end if;
 insert into public.staffing_assessments(name,operating_model,scope,facility_inputs,asset_inputs,service_inputs,workforce_inputs,proposed_organization,created_by)
 values(btrim(p_payload->>'name'),p_payload->>'operating_model',coalesce(p_payload->'scope','{}'),coalesce(p_payload->'facility_inputs','{}'),coalesce(p_payload->'asset_inputs','{}'),coalesce(p_payload->'service_inputs','{}'),coalesce(p_payload->'workforce_inputs','{}'),coalesce(p_payload->'proposed_organization','[]'),(actor->>'id')::uuid) returning * into result;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'staffing_assessment_created',actor->>'name',jsonb_build_object('assessment_id',result.id,'operating_model',result.operating_model)::text);
 return jsonb_build_object('ok',true,'assessment',to_jsonb(result));
end $fn$;

alter table public.sla_documents enable row level security; alter table public.staffing_assessments enable row level security; alter table public.staffing_recommendations enable row level security;
create policy sla_documents_management_read on public.sla_documents for select to authenticated using(public.current_user_role() in ('approver','supervisor','administrator'));
create policy staffing_assessments_management_read on public.staffing_assessments for select to authenticated using(public.current_user_role() in ('approver','supervisor','administrator'));
create policy staffing_recommendations_management_read on public.staffing_recommendations for select to authenticated using(public.current_user_role() in ('approver','supervisor','administrator'));
revoke insert,update,delete on public.sla_documents,public.staffing_assessments,public.staffing_recommendations from authenticated;
grant select on public.sla_documents,public.staffing_assessments,public.staffing_recommendations to authenticated;
revoke all on function public.create_sla_document(jsonb),public.record_sla_extraction(uuid,text,text,jsonb),public.review_sla_extraction(uuid,text,jsonb),public.approve_reviewed_sla_clause(uuid,uuid),public.create_staffing_assessment(jsonb) from public,anon,service_role;
grant execute on function public.create_sla_document(jsonb),public.record_sla_extraction(uuid,text,text,jsonb),public.review_sla_extraction(uuid,text,jsonb),public.approve_reviewed_sla_clause(uuid,uuid),public.create_staffing_assessment(jsonb) to authenticated;
commit;

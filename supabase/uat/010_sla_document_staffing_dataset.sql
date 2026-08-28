-- Synthetic Preview/UAT-only WP-FMW-010 document and staffing profile. Never a real client agreement.
begin;
do $uat$ declare actor_id uuid; begin
 select id into actor_id from public.profiles where role='administrator' and is_active and deleted_at is null order by created_at limit 1;
 if actor_id is null then raise exception 'Synthetic WP-FMW-010 UAT data requires an active Administrator profile'; end if;
 if not exists(select 1 from public.sla_documents where agreement_reference='FMW-UAT-SLA-010' and version_label='1') then
  insert into public.sla_documents(title,client_owner,service_provider,maintenance_model,agreement_reference,version_label,effective_date,expiry_date,original_filename,media_type,byte_size,content_sha256,storage_key,extracted_text,review_status,approval_status,notes,uploaded_by)
  values('FMWorks Pilot Facility Maintenance SLA','Synthetic Building Owner','Synthetic FM Service Team','HYBRID','FMW-UAT-SLA-010','1',current_date,current_date+365,'FMWorks-Pilot-SLA.txt','text/plain',512,repeat('b',64),'pilot-db://fmw-uat-sla-010-v1','P1 critical: acknowledge 15 minutes, attend 30 minutes, make safe 120 minutes, rectify 240 minutes. P2 high, P3 medium and P4 low require reviewed targets. PM compliance target 95 percent. Emergency coverage and monthly reporting required.','NOT_EXTRACTED','DRAFT','SYNTHETIC UAT ONLY - not a real client agreement',actor_id);
 end if;
 if not exists(select 1 from public.staffing_assessments where name='FMWorks Synthetic Pilot Hybrid Staffing Profile') then
  insert into public.staffing_assessments(name,operating_model,scope,facility_inputs,asset_inputs,service_inputs,workforce_inputs,proposed_organization,status,created_by)
  values('FMWorks Synthetic Pilot Hybrid Staffing Profile','HYBRID',jsonb_build_object('site','Synthetic Pilot Site'),jsonb_build_object('building_type','Mixed-use','operating_hours',24),jsonb_build_object('asset_count',160,'critical_assets',10),jsonb_build_object('emergency_coverage',true,'monthly_reporting',true),jsonb_build_object('shifts_per_day',3,'utilization',.75),jsonb_build_array(jsonb_build_object('role','Maintenance Supervisor','fte',1,'coverage','day only')),'DRAFT',actor_id);
 end if;
end $uat$;
commit;

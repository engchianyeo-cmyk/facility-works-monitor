\set ON_ERROR_STOP on
-- M41b: the Facility Manager sees the management views a Supervisor sees. Rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Facility Manager views regression: %',message; end if; end;$$;
select pg_temp.assert_true((select count(*) from pg_policies where schemaname='public' and policyname in ('sla_documents_management_read','incidents_authenticated_read','assets_authenticated_read','maintenance_requirements_read','pm_occurrences_read','report_runs_management_read','work_order_sla_clocks_management_read') and coalesce(qual,'') like '%facility_manager%')=7,'the SLA, incident, asset, maintenance and report read rules include the Facility Manager');
select pg_temp.assert_true(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname<>'create_staffing_assessment' and replace(p.prosrc,' ','') like '%''approver'',''supervisor'',''administrator''%'),'no management function leaves the Facility Manager out (Staffing aside)');
-- Behaviour: a Facility Manager reads an incident he did not report.
insert into auth.users(id,email,raw_user_meta_data) values ('1d420000-0000-4000-8000-000000000001','m41b.fm@example.test','{"display_name":"M41b FM"}'),('1d420000-0000-4000-8000-000000000002','m41b.sup@example.test','{"display_name":"M41b Sup"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='facility_manager',is_active=true,password_change_required=false where id='1d420000-0000-4000-8000-000000000001';
update public.profiles set role='supervisor',is_active=true,password_change_required=false where id='1d420000-0000-4000-8000-000000000002';
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.incidents(incident_type,severity,location,description,reported_by,acknowledgement_deadline) values ('flood','high','M41b','Water','1d420000-0000-4000-8000-000000000002',now()+interval '5 minutes');
select set_config('request.jwt.claim.sub','1d420000-0000-4000-8000-000000000001',true), set_config('request.jwt.claims','{"sub":"1d420000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.assert_true(exists(select 1 from public.incidents where location='M41b'),'the Facility Manager sees the incident');
reset role;
select 'facility_manager_views tests passed' as result;
rollback;

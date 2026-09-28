\set ON_ERROR_STOP on
begin;
set transaction read only;
select count(*) as work_order_count from public.work_orders;
select count(distinct work_order_number) as distinct_work_order_references,encode(digest(coalesce(string_agg(work_order_number,'|' order by work_order_number),''),'sha256'),'hex') as work_order_reference_fingerprint from public.work_orders;
select encode(digest(coalesce(string_agg(id::text||':'||status,'|' order by id),''),'sha256'),'hex') as canonical_status_fingerprint from public.work_orders;
select to_regclass('public.incidents') is not null as incidents_exist,to_regclass('public.emergency_response_roster') is not null as roster_exists;
select c.relname,c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('incidents','emergency_response_roster','notification_outbox');
select p.proname,p.prosecdef,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('create_incident','assign_incident','transition_incident','record_incident_notification_result','link_work_order_to_incident','get_incident_operations','get_emergency_roster','upsert_emergency_roster');
select has_function_privilege('anon','public.create_incident(jsonb)','EXECUTE') as anon_create_incident,has_function_privilege('authenticated','public.create_incident(jsonb)','EXECUTE') as authenticated_create_incident;
select count(*)=0 as no_orphan_links from public.work_orders w left join public.incidents i on i.id=w.incident_id where w.incident_id is not null and i.id is null;
select count(*)=0 as no_invalid_roster_rows from public.emergency_response_roster r left join public.profiles p on p.id=r.profile_id left join public.maintenance_teams t on t.id=r.team_id where ((r.profile_id is null)::int+(r.team_id is null)::int)<>1 or (r.profile_id is not null and (p.id is null or not p.is_active or p.deleted_at is not null)) or (r.team_id is not null and (t.id is null or not t.is_active or t.deleted_at is not null)) or (r.active_to is not null and r.active_from is not null and r.active_to<=r.active_from);
select is_nullable='YES' as work_orders_incident_nullable from information_schema.columns where table_schema='public' and table_name='work_orders' and column_name='incident_id';
select count(*) filter(where channel='sms') as sms_rows,count(*) filter(where channel='whatsapp') as whatsapp_rows from public.notification_outbox where incident_id is not null;
select pg_get_functiondef('public.create_incident(jsonb)'::regprocedure) like '%administrator%supervisor%' as mandatory_recipient_rule_present;
select p.proname,p.prosecdef,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('create_work_order','assign_work_order','transition_work_order','create_department','update_department');
rollback;

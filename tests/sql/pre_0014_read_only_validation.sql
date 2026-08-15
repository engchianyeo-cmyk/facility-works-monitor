\set ON_ERROR_STOP on
begin;
set transaction read only;
select count(*) as work_order_count from public.work_orders;
select count(distinct work_order_number) as distinct_work_order_references,
  encode(digest(coalesce(string_agg(work_order_number,'|' order by work_order_number),''),'sha256'),'hex') as work_order_reference_fingerprint
from public.work_orders;
select encode(digest(coalesce(string_agg(id::text||':'||status,'|' order by id),''),'sha256'),'hex') as canonical_status_fingerprint from public.work_orders;
select count(*) filter(where deleted_at is null) as departments, count(*) filter(where deleted_at is null and not is_active) as inactive_departments from public.departments;
select p.proname,p.prosecdef,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('create_work_order','assign_work_order','transition_work_order','create_department','update_department');
select to_regclass('public.incidents') is null as incidents_absent, to_regclass('public.emergency_response_roster') is null as roster_absent;
rollback;

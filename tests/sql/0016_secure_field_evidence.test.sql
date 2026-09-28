\set ON_ERROR_STOP on
create or replace function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$begin if value is not true then raise exception 'ASSERTION FAILED: %',message;end if;end$$;
select pg_temp.assert_true(to_regclass('public.evidence_items') is not null,'evidence table exists');
select pg_temp.assert_true((select not public from storage.buckets where id='field-evidence'),'bucket is private');
select pg_temp.assert_true((select file_size_limit=10485760 from storage.buckets where id='field-evidence'),'bucket size limit');
select pg_temp.assert_true((select allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf']::text[] from storage.buckets where id='field-evidence'),'bucket MIME allowlist');
select pg_temp.assert_true(to_regprocedure('public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)') is not null,'registration RPC exists');
select pg_temp.assert_true(not has_function_privilege('anon','public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)','EXECUTE'),'anon execute denied');
select pg_temp.assert_true(not has_function_privilege('public','public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)','EXECUTE'),'public execute denied');
select pg_temp.assert_true(not has_function_privilege('service_role','public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)','EXECUTE'),'service role execute denied');
select pg_temp.assert_true(has_function_privilege('authenticated','public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)','EXECUTE'),'authenticated execute granted');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.evidence_items','INSERT'),'direct insert denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.evidence_items','UPDATE'),'direct update denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.evidence_items','DELETE'),'direct delete denied');
select pg_temp.assert_true((select relrowsecurity from pg_class where oid='public.evidence_items'::regclass),'RLS enabled');
select pg_temp.assert_true((select proconfig @> array['search_path=public, pg_temp'] from pg_proc where oid='public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'::regprocedure),'fixed function search path');
select pg_temp.assert_true((select count(*)=2 from pg_indexes where schemaname='public' and tablename='evidence_items' and indexname in ('evidence_work_order_idx','evidence_incident_idx')),'parent indexes exist');
select pg_temp.assert_true(not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'),'no broad storage policy');
select '0016 secure field evidence tests passed' as result;

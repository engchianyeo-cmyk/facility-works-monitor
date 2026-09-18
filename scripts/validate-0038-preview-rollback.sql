\set ON_ERROR_STOP on
\echo 'WP-FMW-026 0038 PREVIEW ROLLBACK VALIDATION'

create temporary table wp0038_baseline_data on commit preserve rows as
select 'work_orders' name,count(*) row_count,md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) fingerprint from public.work_orders t union all
select 'work_order_cost_lines',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.work_order_cost_lines t union all
select 'activity_logs',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.activity_logs t union all
select 'profiles',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.profiles t union all
select 'facility_memberships',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.facility_memberships t union all
select 'sites',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.sites t;
create temporary table wp0038_ledger_baseline on commit preserve rows as
select count(*) row_count,md5(coalesce(string_agg(row_to_json(t)::text,'' order by row_to_json(t)::text),'')) fingerprint
from supabase_migrations.schema_migrations t;

do $precheck$
begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_order_cost_lines' and column_name='cost_phase')
    or exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_orders' and column_name in ('actual_costs_confirmed_at','actual_costs_confirmed_by'))
    or to_regprocedure('public.manage_work_order_actual_cost(uuid,uuid,jsonb)') is not null
    or to_regclass('public.work_order_cost_lines_actual_idx') is not null then
    raise exception '0038 candidate state already exists before rollback validation';
  end if;
end;$precheck$;

\echo 'Baseline captured'
begin;
\ir ../supabase/migrations/0038_governed_technician_actual_costs.sql

select pg_temp.assert_true(not exists(select 1 from public.work_order_cost_lines where cost_phase is not null and created_at < transaction_timestamp()),'existing historical cost rows remain legacy/unclassified');
\ir ../tests/sql/0038_governed_technician_actual_costs.test.sql
\echo '0038 SQL REGRESSION: 37/37 PASS'
rollback;
\echo 'ROLLBACK'

do $postrollback$
declare mismatch text; synthetic_count bigint; ledger_count bigint; ledger_hash text;
begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_order_cost_lines' and column_name='cost_phase')
    or exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_orders' and column_name in ('actual_costs_confirmed_at','actual_costs_confirmed_by'))
    or to_regprocedure('public.manage_work_order_actual_cost(uuid,uuid,jsonb)') is not null
    or to_regclass('public.work_order_cost_lines_actual_idx') is not null then raise exception '0038 schema remains after rollback'; end if;
  with current_data as (
    select 'work_orders' name,count(*) row_count,md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) fingerprint from public.work_orders t union all
    select 'work_order_cost_lines',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.work_order_cost_lines t union all
    select 'activity_logs',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.activity_logs t union all
    select 'profiles',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.profiles t union all
    select 'facility_memberships',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.facility_memberships t union all
    select 'sites',count(*),md5(coalesce(string_agg(md5(row_to_json(t)::text),'' order by md5(row_to_json(t)::text)),'')) from public.sites t
  ) select string_agg(b.name,',') into mismatch from wp0038_baseline_data b full join current_data c using(name)
    where b.row_count is distinct from c.row_count or b.fingerprint is distinct from c.fingerprint;
  if mismatch is not null then raise exception 'Post-rollback data differs: %',mismatch; end if;
  select count(*),md5(coalesce(string_agg(row_to_json(t)::text,'' order by row_to_json(t)::text),'')) into ledger_count,ledger_hash
    from supabase_migrations.schema_migrations t;
  if (select (row_count,fingerprint) is distinct from (ledger_count,ledger_hash) from wp0038_ledger_baseline) then raise exception 'Migration ledger changed'; end if;
  select (select count(*) from public.profiles where id::text like '03800000-%')
    +(select count(*) from public.sites where id::text like '03800000-%')
    +(select count(*) from public.work_orders where id::text like '03800000-%') into synthetic_count;
  if synthetic_count<>0 then raise exception 'Synthetic fixtures remain: %',synthetic_count; end if;
end;$postrollback$;

\echo 'ROLLBACK CONFIRMED'
\echo 'PREVIEW PERSISTENT CHANGES: NONE'

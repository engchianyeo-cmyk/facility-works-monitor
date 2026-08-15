\set ON_ERROR_STOP on
begin transaction read only;

select current_database() as database_name,
  current_setting('server_version') as server_version,
  pg_catalog.now() as captured_at;

with inventory as (
  select 'table' as kind, n.nspname||'.'||c.relname as identity,
    pg_catalog.concat_ws('|',c.relkind,c.relrowsecurity,c.relforcerowsecurity) as definition
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','storage') and c.relkind in ('r','p','v','m')
  union all
  select 'column',table_schema||'.'||table_name||'.'||column_name,
    pg_catalog.concat_ws('|',ordinal_position,data_type,udt_name,is_nullable,column_default)
  from information_schema.columns where table_schema in ('public','storage')
  union all
  select 'constraint',n.nspname||'.'||c.relname||'.'||con.conname,
    pg_catalog.pg_get_constraintdef(con.oid,true)
  from pg_catalog.pg_constraint con join pg_catalog.pg_class c on c.oid=con.conrelid
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage')
  union all
  select 'index',schemaname||'.'||tablename||'.'||indexname,indexdef
  from pg_catalog.pg_indexes where schemaname in ('public','storage')
  union all
  select 'function',n.nspname||'.'||p.proname||'('||pg_catalog.pg_get_function_identity_arguments(p.oid)||')',
    pg_catalog.concat_ws('|',p.prosecdef,p.provolatile,p.proconfig,pg_catalog.pg_get_function_result(p.oid),pg_catalog.pg_get_functiondef(p.oid))
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  union all
  select 'trigger',event_object_schema||'.'||event_object_table||'.'||trigger_name,
    pg_catalog.concat_ws('|',event_manipulation,action_timing,action_orientation,action_statement)
  from information_schema.triggers where event_object_schema='public'
  union all
  select 'policy',schemaname||'.'||tablename||'.'||policyname,
    pg_catalog.concat_ws('|',permissive,roles,cmd,qual,with_check)
  from pg_catalog.pg_policies where schemaname in ('public','storage')
  union all
  select 'grant',table_schema||'.'||table_name||'.'||grantee||'.'||privilege_type,
    pg_catalog.concat_ws('|',is_grantable,with_hierarchy)
  from information_schema.role_table_grants where table_schema in ('public','storage')
  union all
  select 'function_grant',routine_schema||'.'||routine_name||'.'||grantee||'.'||privilege_type,
    is_grantable
  from information_schema.role_routine_grants where routine_schema='public'
)
select kind, count(*) as object_count,
  pg_catalog.md5(pg_catalog.string_agg(identity||'='||coalesce(definition,''),E'\n' order by identity)) as fingerprint
from inventory group by kind order by kind;

select (pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null)::int as migration_metadata_available \gset
\if :migration_metadata_available
select version,name,statements from supabase_migrations.schema_migrations order by version;
\else
select 'UNAVAILABLE' as migration_metadata;
\endif

rollback;

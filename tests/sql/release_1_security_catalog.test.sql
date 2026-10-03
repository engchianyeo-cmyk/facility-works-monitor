\set ON_ERROR_STOP on
-- Run after the complete migration chain, including later function replacements.
begin;
do $test$
declare violations text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into violations
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity;
  if violations is not null then raise exception 'Public tables without RLS: %', violations; end if;

  select string_agg(p.oid::regprocedure::text, ', ') into violations
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef
    and has_function_privilege('anon',p.oid,'EXECUTE');
  if violations is not null then raise exception 'Anonymous privileged function execution: %', violations; end if;

  select string_agg(p.oid::regprocedure::text, ', ') into violations
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and not exists (
    select 1 from unnest(p.proconfig) setting where setting like 'search_path=%'
  );
  if violations is not null then raise exception 'Unpinned privileged function search paths: %', violations; end if;

  select string_agg(p.oid::regprocedure::text, ', ') into violations
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname like '%\_core' escape '\'
    and (has_function_privilege('authenticated',p.oid,'EXECUTE')
      or has_function_privilege('anon',p.oid,'EXECUTE')
      or has_function_privilege('service_role',p.oid,'EXECUTE'));
  if violations is not null then raise exception 'Private wrapper cores exposed: %', violations; end if;

  select string_agg(c.relname, ', ') into violations
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='v'
    and has_table_privilege('authenticated',c.oid,'SELECT')
    and not coalesce(c.reloptions @> array['security_invoker=true'],false);
  if violations is not null then raise exception 'Authenticated views bypass invoker RLS: %', violations; end if;
end;
$test$;
rollback;

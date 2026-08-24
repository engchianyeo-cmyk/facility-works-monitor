\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $function$
begin
  if not coalesce(condition, false) then
    raise exception 'ASSERTION FAILED: %', message;
  end if;
end;
$function$;

create or replace function pg_temp.assert_raises(
  statement text,
  expected_message text,
  assertion_message text
)
returns void
language plpgsql
as $function$
declare
  caught_message text;
begin
  begin
    execute statement;
  exception when others then
    caught_message := sqlerrm;
  end;

  if caught_message is null then
    raise exception 'ASSERTION FAILED: % (statement unexpectedly succeeded)', assertion_message;
  end if;
  if pg_catalog.strpos(caught_message, expected_message) = 0 then
    raise exception 'ASSERTION FAILED: % (unexpected error: %)', assertion_message, caught_message;
  end if;
end;
$function$;

begin;

select pg_temp.assert_true(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.complete_password_change_trusted(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'public.complete_password_change_trusted(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.complete_password_change_trusted(uuid)',
    'EXECUTE'
  ),
  'password reconciliation remains service-only'
);

select pg_temp.assert_true(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.pm_business_date()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.pm_business_date()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'public',
    'public.pm_business_date()',
    'EXECUTE'
  ),
  'PM business date grants only the authenticated read dependency'
);

select pg_temp.assert_true(
  (select procedure.prosecdef
     and procedure.proconfig = array['search_path=pg_catalog']::text[]
   from pg_catalog.pg_proc as procedure
   where procedure.oid = 'public.complete_password_change_trusted(uuid)'::pg_catalog.regprocedure)
  and exists (
    select 1
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and not trigger_record.tgisinternal
      and trigger_record.tgname = 'protect_profile_authorization_fields'
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgfoid = 'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
  ),
  'safe function path and profile authorization trigger remain intact'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'a2000000-0000-4000-8000-000000000001',
  'password-repair@example.test',
  '{}'::jsonb
);

select pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
update public.profiles
set
  display_name = 'Password Repair User',
  is_active = true,
  password_change_required = true
where id = 'a2000000-0000-4000-8000-000000000001';
select pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);

set role service_role;
select public.complete_password_change_trusted(
  'a2000000-0000-4000-8000-000000000001'
) as result
\gset first_
reset role;

select pg_temp.assert_true(
  (:'first_result'::jsonb ->> 'ok')::boolean
  and (:'first_result'::jsonb ->> 'was_required')::boolean
  and not (
    select password_change_required
    from public.profiles
    where id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.activity_logs
    where user_id = 'a2000000-0000-4000-8000-000000000001'
      and action = 'user_first_password_changed'
  ),
  'first reconciliation clears readiness and writes the first-change audit'
);

set role service_role;
select public.complete_password_change_trusted(
  'a2000000-0000-4000-8000-000000000001'
) as result
\gset retry_
reset role;

select pg_temp.assert_true(
  (:'retry_result'::jsonb ->> 'ok')::boolean
  and not (:'retry_result'::jsonb ->> 'was_required')::boolean
  and (
    select pg_catalog.count(*) = 1
    from public.activity_logs
    where user_id = 'a2000000-0000-4000-8000-000000000001'
      and action = 'user_password_changed'
  ),
  'already-reconciled retry succeeds without a protected profile update and audits truthfully'
);

set role authenticated;
select pg_temp.assert_raises(
  $sql$select public.complete_password_change_trusted(
    'a2000000-0000-4000-8000-000000000001'
  )$sql$,
  'permission denied',
  'authenticated callers cannot invoke service-only reconciliation'
);
reset role;

set role service_role;
select pg_temp.assert_raises(
  $sql$select public.complete_password_change_trusted(
    'a2000000-0000-4000-8000-000000000099'
  )$sql$,
  'Active profile not found',
  'missing users fail closed'
);
reset role;

select pg_temp.assert_true(
  not exists (
    select 1
    from public.activity_logs
    where user_id = 'a2000000-0000-4000-8000-000000000099'
  ),
  'missing-user failure writes no audit event'
);

create function pg_temp.reject_password_audit()
returns trigger
language plpgsql
as $function$
begin
  if new.action in ('user_first_password_changed', 'user_password_changed') then
    raise exception 'synthetic audit failure';
  end if;
  return new;
end;
$function$;

create trigger reject_password_audit
before insert on public.activity_logs
for each row execute function pg_temp.reject_password_audit();

select pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
update public.profiles
set password_change_required = true
where id = 'a2000000-0000-4000-8000-000000000001';
select pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);

set role service_role;
select pg_temp.assert_raises(
  $sql$select public.complete_password_change_trusted(
    'a2000000-0000-4000-8000-000000000001'
  )$sql$,
  'synthetic audit failure',
  'audit insertion failure aborts reconciliation'
);
reset role;

select pg_temp.assert_true(
  (select password_change_required
   from public.profiles
   where id = 'a2000000-0000-4000-8000-000000000001')
  and (
    select pg_catalog.count(*) = 2
    from public.activity_logs
    where user_id = 'a2000000-0000-4000-8000-000000000001'
      and action in ('user_first_password_changed', 'user_password_changed')
  ),
  'audit failure rolls back readiness and creates no false audit event'
);

drop trigger reject_password_audit on public.activity_logs;

set role authenticated;
select public.pm_business_date();
select pg_catalog.count(*) from public.pm_occurrence_compliance;
reset role;

select pg_temp.assert_true(
  true,
  'authenticated PM compliance view is readable with the narrow date-function grant'
);

rollback;

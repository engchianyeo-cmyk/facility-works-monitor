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
  not pg_catalog.has_function_privilege(
    'public', 'public.bootstrap_first_administrator(uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'public.bootstrap_first_administrator(uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated', 'public.bootstrap_first_administrator(uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role', 'public.bootstrap_first_administrator(uuid)', 'EXECUTE'
  ),
  'bootstrap is callable only by its postgres owner'
);

select pg_temp.assert_true(
  exists (
    select 1
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and not trigger_record.tgisinternal
      and trigger_record.tgname = 'protect_profile_authorization_fields'
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgfoid =
        'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
  ),
  'profile authorization trigger remains enabled and unchanged'
);

-- Normalize disposable fixtures so the test begins with zero ready Administrators.
select pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
update public.profiles
set role = 'reviewer', is_active = false, deleted_at = null,
    password_change_required = true;
select pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);
delete from public.activity_logs
where action = 'first_administrator_bootstrapped';

insert into auth.users (id, email, raw_user_meta_data)
values
  ('a3000000-0000-4000-8000-000000000001', 'bootstrap-target@example.test', '{}'::jsonb),
  ('a3000000-0000-4000-8000-000000000002', 'bootstrap-other@example.test', '{}'::jsonb),
  ('a3000000-0000-4000-8000-000000000004', 'ineligible@example.test', '{}'::jsonb);

-- Suppress user triggers only for this prerequisite fixture so it represents
-- the required Auth-user-without-profile refusal case. Application triggers on
-- public.profiles remain enabled throughout the test.
set local session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data)
values (
  'a3000000-0000-4000-8000-000000000003',
  'missing-profile@example.test',
  '{}'::jsonb
);
set local session_replication_role = origin;

select pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
update public.profiles
set display_name = case id
  when 'a3000000-0000-4000-8000-000000000001' then 'Bootstrap Target'
  when 'a3000000-0000-4000-8000-000000000002' then 'Untouched Preserved User'
  else 'Ineligible User'
end
where id in (
  'a3000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000002',
  'a3000000-0000-4000-8000-000000000004'
);
update public.profiles
set is_active = true
where id = 'a3000000-0000-4000-8000-000000000004';
select pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);

select pg_temp.assert_raises(
  $sql$select public.bootstrap_first_administrator(
    'a3000000-0000-4000-8000-000000000099'
  )$sql$,
  'target Auth user does not exist',
  'unknown Auth UUID is refused'
);
select pg_temp.assert_raises(
  $sql$select public.bootstrap_first_administrator(
    'a3000000-0000-4000-8000-000000000003'
  )$sql$,
  'target profile does not exist',
  'Auth user without a profile is refused'
);
select pg_temp.assert_raises(
  $sql$select public.bootstrap_first_administrator(
    'a3000000-0000-4000-8000-000000000004'
  )$sql$,
  'not in the required quarantine state',
  'malformed or ineligible target state is refused'
);

select pg_temp.assert_true(
  (select role = 'reviewer' and is_active and password_change_required
   from public.profiles
   where id = 'a3000000-0000-4000-8000-000000000004')
  and not exists (
    select 1 from public.activity_logs
    where action = 'first_administrator_bootstrapped'
  ),
  'failed attempts leave profile and audit state unchanged'
);

-- A forced audit failure proves the promotion and audit are one transaction.
create function pg_temp.reject_bootstrap_audit()
returns trigger
language plpgsql
as $function$
begin
  if new.action = 'first_administrator_bootstrapped' then
    raise exception 'synthetic bootstrap audit failure';
  end if;
  return new;
end;
$function$;
create trigger reject_bootstrap_audit
before insert on public.activity_logs
for each row execute function pg_temp.reject_bootstrap_audit();

select pg_temp.assert_raises(
  $sql$select public.bootstrap_first_administrator(
    'a3000000-0000-4000-8000-000000000001'
  )$sql$,
  'synthetic bootstrap audit failure',
  'audit failure aborts bootstrap'
);
select pg_temp.assert_true(
  (select role = 'reviewer' and not is_active and password_change_required
   from public.profiles
   where id = 'a3000000-0000-4000-8000-000000000001'),
  'audit failure rolls back target authorization changes'
);
drop trigger reject_bootstrap_audit on public.activity_logs;

select public.bootstrap_first_administrator(
  'a3000000-0000-4000-8000-000000000001'
) as result
\gset bootstrap_

select pg_temp.assert_true(
  (:'bootstrap_result'::jsonb ->> 'ok')::boolean
  and (:'bootstrap_result'::jsonb ->> 'role') = 'administrator'
  and (:'bootstrap_result'::jsonb ->> 'is_active')::boolean
  and (:'bootstrap_result'::jsonb ->> 'password_change_required')::boolean
  and (
    select role = 'administrator'
      and is_active
      and deleted_at is null
      and password_change_required
    from public.profiles
    where id = 'a3000000-0000-4000-8000-000000000001'
  ),
  'valid explicit target is active Administrator but remains password-pending'
);

select pg_temp.assert_true(
  (select role = 'reviewer' and not is_active and deleted_at is null
      and password_change_required
   from public.profiles
   where id = 'a3000000-0000-4000-8000-000000000002'),
  'other preserved users remain untouched'
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 1
    from public.activity_logs
    where action = 'first_administrator_bootstrapped'
      and user_id = 'a3000000-0000-4000-8000-000000000001'
      and note::jsonb ->> 'resulting_role' = 'administrator'
      and (note::jsonb ->> 'is_active')::boolean
      and (note::jsonb ->> 'password_change_required')::boolean
  ),
  'bootstrap audit records target and resulting readiness without secrets'
);

select pg_temp.assert_raises(
  $sql$select public.bootstrap_first_administrator(
    'a3000000-0000-4000-8000-000000000002'
  )$sql$,
  'already been completed',
  'second execution against an unrelated eligible target is refused'
);

-- Prove the independent ready-Administrator guard without relying on marker order.
delete from public.activity_logs
where action = 'first_administrator_bootstrapped';
select pg_catalog.set_config('fmworks.password_change_completion', 'on', true);
update public.profiles
set password_change_required = false
where id = 'a3000000-0000-4000-8000-000000000001';
select pg_catalog.set_config('fmworks.password_change_completion', 'off', true);

select pg_temp.assert_raises(
  $sql$select public.bootstrap_first_administrator(
    'a3000000-0000-4000-8000-000000000002'
  )$sql$,
  'a ready Administrator already exists',
  'ready Administrator state independently blocks bootstrap'
);

set role authenticated;
select pg_temp.assert_raises(
  $sql$select public.bootstrap_first_administrator(
    'a3000000-0000-4000-8000-000000000002'
  )$sql$,
  'permission denied',
  'authenticated callers cannot use bootstrap for privilege escalation'
);
reset role;

set role service_role;
select pg_temp.assert_raises(
  $sql$select public.bootstrap_first_administrator(
    'a3000000-0000-4000-8000-000000000002'
  )$sql$,
  'permission denied',
  'service-role callers cannot use bootstrap for privilege escalation'
);
reset role;

rollback;

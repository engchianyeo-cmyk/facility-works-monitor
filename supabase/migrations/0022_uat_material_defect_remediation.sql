-- WP-UAT-008: repair password reconciliation idempotency and the narrow
-- authenticated PM-compliance read dependency found by local business UAT.

begin;

do $preflight$
begin
  if current_user <> 'postgres' then
    raise exception using
      errcode = '55000',
      message = '0022 refused: execute as the postgres migration role';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_roles
    where rolname in ('anon', 'authenticated', 'service_role')
  ) <> 3 then
    raise exception using
      errcode = '55000',
      message = '0022 refused: required Supabase API roles are unavailable';
  end if;

  if pg_catalog.to_regclass('public.profiles') is null
    or pg_catalog.to_regclass('public.activity_logs') is null
    or pg_catalog.to_regclass('public.pm_occurrence_compliance') is null
  then
    raise exception using
      errcode = '55000',
      message = '0022 refused: required predecessor relations are unavailable';
  end if;

  if pg_catalog.to_regprocedure('public.complete_password_change_trusted(uuid)') is null
    or pg_catalog.to_regprocedure('public.pm_business_date()') is null
  then
    raise exception using
      errcode = '55000',
      message = '0022 refused: required predecessor functions are unavailable';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.complete_password_change_trusted(uuid)'::pg_catalog.regprocedure
      and procedure.prosecdef
      and procedure.proowner = (select oid from pg_catalog.pg_roles where rolname = current_user)
  ) then
    raise exception using
      errcode = '55000',
      message = '0022 refused: password reconciliation ownership or SECURITY DEFINER contract is unexpected';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.pm_business_date()'::pg_catalog.regprocedure
      and not procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.prorettype = 'date'::pg_catalog.regtype
      and procedure.proowner = (select oid from pg_catalog.pg_roles where rolname = current_user)
      and procedure.proconfig = array['search_path=pg_catalog']::text[]
  ) then
    raise exception using
      errcode = '55000',
      message = '0022 refused: PM business-date function contract is unexpected';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and not trigger_record.tgisinternal
      and trigger_record.tgname = 'protect_profile_authorization_fields'
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgfoid = 'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
  ) <> 1 then
    raise exception using
      errcode = '55000',
      message = '0022 refused: profile authorization trigger contract is unavailable';
  end if;
end;
$preflight$;

create or replace function public.complete_password_change_trusted(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  target_profile public.profiles%rowtype;
  was_required boolean;
begin
  select profile.*
  into target_profile
  from public.profiles as profile
  where profile.id = p_user_id
    and profile.is_active = true
    and profile.deleted_at is null
  for update;

  if target_profile.id is null then
    raise exception 'Active profile not found';
  end if;

  was_required := target_profile.password_change_required;

  if was_required then
    perform pg_catalog.set_config(
      'fmworks.password_change_completion',
      'on',
      true
    );
    update public.profiles as profile
    set password_change_required = false
    where profile.id = p_user_id;
  end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    p_user_id,
    case
      when was_required then 'user_first_password_changed'
      else 'user_password_changed'
    end,
    target_profile.display_name,
    'Password value and recovery token are intentionally not recorded.'
  );

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'was_required', was_required
  );
end;
$function$;

revoke all on function public.complete_password_change_trusted(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.complete_password_change_trusted(uuid)
to service_role;

revoke all on function public.pm_business_date()
from public, anon, authenticated, service_role;
grant execute on function public.pm_business_date()
to authenticated;

comment on function public.complete_password_change_trusted(uuid) is
  'Service-only reconciliation after a confirmed Auth password update. Idempotent readiness handling preserves one truthful audit event per successful Auth update.';
comment on function public.pm_business_date() is
  'Returns the current Asia/Singapore business date. Authenticated execution supports the security-invoker PM compliance view.';

do $postflight$
begin
  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.complete_password_change_trusted(uuid)'::pg_catalog.regprocedure
      and procedure.prosecdef
      and procedure.proowner = (select oid from pg_catalog.pg_roles where rolname = current_user)
      and procedure.proconfig = array['search_path=pg_catalog']::text[]
  ) then
    raise exception using
      errcode = '55000',
      message = '0022 failed: password reconciliation function hardening is incomplete';
  end if;

  if pg_catalog.has_function_privilege('public', 'public.complete_password_change_trusted(uuid)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.complete_password_change_trusted(uuid)', 'EXECUTE')
    or pg_catalog.has_function_privilege('authenticated', 'public.complete_password_change_trusted(uuid)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('service_role', 'public.complete_password_change_trusted(uuid)', 'EXECUTE')
  then
    raise exception using
      errcode = '55000',
      message = '0022 failed: password reconciliation ACL is incorrect';
  end if;

  if pg_catalog.has_function_privilege('public', 'public.pm_business_date()', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.pm_business_date()', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.pm_business_date()', 'EXECUTE')
    or pg_catalog.has_function_privilege('service_role', 'public.pm_business_date()', 'EXECUTE')
  then
    raise exception using
      errcode = '55000',
      message = '0022 failed: PM business-date ACL is incorrect';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and not trigger_record.tgisinternal
      and trigger_record.tgname = 'protect_profile_authorization_fields'
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgfoid = 'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
  ) <> 1 then
    raise exception using
      errcode = '55000',
      message = '0022 failed: profile authorization trigger contract changed';
  end if;
end;
$postflight$;

commit;

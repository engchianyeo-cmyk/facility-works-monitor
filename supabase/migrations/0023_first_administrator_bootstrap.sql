-- WP-FMW-BOOTSTRAP-ADMIN: explicit, one-time first Administrator bootstrap.
--
-- This migration installs the operation only. It does not select or promote a
-- user. A controlled operator must later invoke it as postgres with an explicit
-- Auth UUID after reviewing the target profile.

begin;

do $preflight$
begin
  if current_user <> 'postgres' then
    raise exception using
      errcode = '55000',
      message = '0023 refused: execute as the postgres migration role';
  end if;

  if pg_catalog.to_regclass('auth.users') is null
    or pg_catalog.to_regclass('public.profiles') is null
    or pg_catalog.to_regclass('public.activity_logs') is null
    or pg_catalog.to_regprocedure('public.protect_profile_authorization_fields()') is null
    or pg_catalog.to_regprocedure('public.complete_password_change_trusted(uuid)') is null
  then
    raise exception using
      errcode = '55000',
      message = '0023 refused: required 0022 trust contracts are unavailable';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and not trigger_record.tgisinternal
      and trigger_record.tgname = 'protect_profile_authorization_fields'
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgfoid =
        'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
  ) <> 1 then
    raise exception using
      errcode = '55000',
      message = '0023 refused: profile authorization trigger contract is unavailable';
  end if;
end;
$preflight$;

create or replace function public.bootstrap_first_administrator(p_target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  target_profile public.profiles%rowtype;
begin
  if p_target_user_id is null then
    raise exception using
      errcode = '22004',
      message = 'First Administrator bootstrap requires an explicit target Auth UUID';
  end if;

  -- Shared with the final-ready-Administrator protections. This serializes the
  -- zero-ready check, target promotion, and one-time audit marker.
  perform pg_catalog.pg_advisory_xact_lock(6042026);

  if exists (
    select 1
    from public.activity_logs as activity
    where activity.action = 'first_administrator_bootstrapped'
  ) then
    raise exception using
      errcode = '55000',
      message = 'First Administrator bootstrap has already been completed';
  end if;

  if exists (
    select 1
    from public.profiles as profile
    where profile.role = 'administrator'
      and profile.is_active = true
      and profile.deleted_at is null
      and profile.password_change_required = false
  ) then
    raise exception using
      errcode = '55000',
      message = 'First Administrator bootstrap refused: a ready Administrator already exists';
  end if;

  if not exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = p_target_user_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'First Administrator bootstrap target Auth user does not exist';
  end if;

  select profile.*
  into target_profile
  from public.profiles as profile
  where profile.id = p_target_user_id
  for update;

  if target_profile.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'First Administrator bootstrap target profile does not exist';
  end if;

  if target_profile.role <> 'reviewer'
    or target_profile.is_active <> false
    or target_profile.deleted_at is not null
    or target_profile.password_change_required <> true
  then
    raise exception using
      errcode = '55000',
      message = 'First Administrator bootstrap target is not in the required quarantine state';
  end if;

  -- Cooperate with, rather than disable, the authorization-field trigger. The
  -- transaction-local capability is the same narrow mechanism used by audited
  -- Administrator RPCs and cannot survive this transaction.
  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);

  update public.profiles as profile
  set
    role = 'administrator',
    is_active = true,
    deleted_at = null
  where profile.id = p_target_user_id;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    p_target_user_id,
    'first_administrator_bootstrapped',
    'trusted database bootstrap',
    pg_catalog.jsonb_build_object(
      'event', 'first_administrator_bootstrap',
      'target_profile_id', p_target_user_id,
      'resulting_role', 'administrator',
      'is_active', true,
      'password_change_required', true
    )::text
  );

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'target_profile_id', p_target_user_id,
    'role', 'administrator',
    'is_active', true,
    'password_change_required', true
  );
end;
$function$;

revoke all on function public.bootstrap_first_administrator(uuid)
from public, anon, authenticated, service_role;

comment on function public.bootstrap_first_administrator(uuid) is
  'Postgres-owner-only, explicit and one-time promotion of one quarantined Auth profile; password readiness remains pending for the trusted first-password-change flow.';

do $postflight$
begin
  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure
    where procedure.oid =
      'public.bootstrap_first_administrator(uuid)'::pg_catalog.regprocedure
      and procedure.prosecdef
      and procedure.proowner = (
        select role_record.oid
        from pg_catalog.pg_roles as role_record
        where role_record.rolname = current_user
      )
      and procedure.proconfig = array['search_path=pg_catalog']::text[]
  ) then
    raise exception using
      errcode = '55000',
      message = '0023 failed: bootstrap function hardening is incomplete';
  end if;

  if pg_catalog.has_function_privilege(
      'public', 'public.bootstrap_first_administrator(uuid)', 'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'anon', 'public.bootstrap_first_administrator(uuid)', 'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'authenticated', 'public.bootstrap_first_administrator(uuid)', 'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'service_role', 'public.bootstrap_first_administrator(uuid)', 'EXECUTE'
    )
  then
    raise exception using
      errcode = '55000',
      message = '0023 failed: bootstrap function must remain postgres-owner-only';
  end if;
end;
$postflight$;

commit;

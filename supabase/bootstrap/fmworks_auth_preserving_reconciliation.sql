-- Exceptional fresh-install reconciliation for explicitly preserved Auth users.
-- The controlled runner must create pg_temp.fmworks_preserved_auth_ids and set
-- fmworks.auth_preservation_mode=on in the same database session.

\set ON_ERROR_STOP on

begin;

do $reconciliation$
declare
  preserve_auth boolean := coalesce(
    pg_catalog.current_setting('fmworks.auth_preservation_mode', true) = 'on',
    false
  );
begin
  if current_user <> 'postgres' then
    raise exception using
      errcode = '55000',
      message = 'FMWorks reconciliation refused: execute as the postgres migration role';
  end if;

  if not preserve_auth
    or pg_catalog.to_regclass('pg_temp.fmworks_preserved_auth_ids') is null then
    raise exception using
      errcode = '55000',
      message = 'FMWorks reconciliation refused: explicit auth-preserving session is unavailable';
  end if;

  if not exists (select 1 from auth.users)
    or not exists (select 1 from pg_temp.fmworks_preserved_auth_ids) then
    raise exception using
      errcode = '55000',
      message = 'FMWorks reconciliation refused: preserved identity set must be non-empty';
  end if;

  if exists (
    select existing.id from auth.users as existing
    except
    select allowed.id from pg_temp.fmworks_preserved_auth_ids as allowed
  ) or exists (
    select allowed.id from pg_temp.fmworks_preserved_auth_ids as allowed
    except
    select existing.id from auth.users as existing
  ) then
    raise exception using
      errcode = '55000',
      message = 'FMWorks reconciliation refused: preserved identity set no longer exactly matches auth.users';
  end if;

  if exists (
    select 1
    from public.profiles as profile
    join pg_temp.fmworks_preserved_auth_ids as allowed on allowed.id = profile.id
  ) then
    raise exception using
      errcode = '55000',
      message = 'FMWorks reconciliation refused: a preserved identity already has a profile';
  end if;

  insert into public.profiles (
    id,
    display_name,
    email,
    department,
    trade_discipline,
    contact_number,
    role,
    is_active,
    password_change_required,
    deleted_at
  )
  select
    allowed.id,
    'Pending preserved user',
    null,
    null,
    null,
    null,
    'reviewer',
    false,
    true,
    null
  from pg_temp.fmworks_preserved_auth_ids as allowed;

  if exists (
    select 1
    from pg_temp.fmworks_preserved_auth_ids as allowed
    left join public.profiles as profile on profile.id = allowed.id
    where profile.id is null
      or profile.role <> 'reviewer'
      or profile.is_active
      or not profile.password_change_required
      or profile.deleted_at is not null
      or public.pilot_account_ready(allowed.id)
  ) then
    raise exception using
      errcode = '55000',
      message = 'FMWorks reconciliation refused: preserved profile quarantine assertion failed';
  end if;
end;
$reconciliation$;

commit;

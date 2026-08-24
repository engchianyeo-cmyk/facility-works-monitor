-- WP-UAT-005: repair the fresh-install identity and trust contract.
--
-- This migration is additive. Historical migrations and the pre-0012
-- bootstrap remain immutable. It accepts only the confirmed fresh-install
-- predecessor or an equivalent historical predecessor whose already-present
-- objects match the established contract exactly.

begin;

do $preflight$
declare
  required_signature text;
  existing_definition text;
begin
  if current_user <> 'postgres' then
    raise exception using
      errcode = '55000',
      message = '0021 refused: execute as the postgres migration role';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_roles
    where rolname in ('anon', 'authenticated', 'service_role')
  ) <> 3 then
    raise exception using
      errcode = '55000',
      message = '0021 refused: required Supabase API roles are unavailable';
  end if;

  if pg_catalog.to_regclass('auth.users') is null
    or pg_catalog.to_regclass('public.profiles') is null
    or pg_catalog.to_regclass('public.account_invitations') is null
    or pg_catalog.to_regclass('public.work_orders') is null
    or pg_catalog.to_regclass('public.activity_logs') is null
  then
    raise exception using
      errcode = '55000',
      message = '0021 refused: required predecessor relations are unavailable';
  end if;

  foreach required_signature in array array[
    'public.record_user_presence(text)',
    'public.protect_profile_authorization_fields()',
    'public.handle_new_auth_user()',
    'public.pilot_account_ready(uuid)',
    'public.admin_update_profile(uuid,jsonb)',
    'public.admin_finalize_provisioned_profile(uuid,jsonb,text)',
    'public.admin_archive_profile(uuid,text)',
    'public.admin_prepare_permanent_profile_deletion(uuid,text)',
    'public.admin_record_permanent_delete_result(uuid,uuid,boolean,text)',
    'public.complete_password_change_trusted(uuid)'
  ] loop
    if pg_catalog.to_regprocedure(required_signature) is null then
      raise exception using
        errcode = '55000',
        message = '0021 refused: required 0020 predecessor function is unavailable',
        detail = required_signature;
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_proc as procedure
      where procedure.oid = pg_catalog.to_regprocedure(required_signature)
        and procedure.prosecdef
        and procedure.proowner = (select oid from pg_catalog.pg_roles where rolname = current_user)
    ) then
      raise exception using
        errcode = '55000',
        message = '0021 refused: predecessor function owner or SECURITY DEFINER contract is unexpected',
        detail = required_signature;
    end if;
  end loop;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'password_change_required'
      and data_type = 'boolean'
      and is_nullable = 'NO'
      and column_default = 'false'
  ) then
    raise exception using
      errcode = '55000',
      message = '0021 refused: profiles.password_change_required does not match the 0020 contract';
  end if;

  if (
    select pg_catalog.count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name in (
        'id', 'display_name', 'email', 'department', 'department_id',
        'trade_discipline', 'contact_number', 'role', 'is_active',
        'deleted_at', 'password_change_required', 'created_at', 'updated_at'
      )
  ) <> 13 then
    raise exception using
      errcode = '55000',
      message = '0021 refused: required profile columns are unavailable';
  end if;

  if (
    select pg_catalog.count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'account_invitations'
      and column_name in (
        'id', 'email', 'display_name', 'department', 'assigned_role',
        'is_active', 'token_hash', 'expires_at', 'used_at', 'created_by'
      )
  ) <> 10 then
    raise exception using
      errcode = '55000',
      message = '0021 refused: required invitation columns are unavailable';
  end if;

  if (
    select pg_catalog.count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'work_orders'
      and column_name in ('assigned_technician_id', 'status')
  ) <> 2 then
    raise exception using
      errcode = '55000',
      message = '0021 refused: required Work Order deletion-guard columns are unavailable';
  end if;

  if pg_catalog.to_regnamespace('extensions') is null
    or not exists (
      select 1
      from pg_catalog.pg_extension as extension
      where extension.extname = 'pgcrypto'
        and extension.extnamespace = pg_catalog.to_regnamespace('extensions')
    )
    or pg_catalog.to_regprocedure('extensions.digest(text,text)') is null
  then
    raise exception using
      errcode = '55000',
      message = '0021 refused: pgcrypto must provide extensions.digest(text,text)';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint as constraint_record
    join pg_catalog.pg_attribute as child_column
      on child_column.attrelid = constraint_record.conrelid
      and child_column.attnum = constraint_record.conkey[1]
    join pg_catalog.pg_attribute as parent_column
      on parent_column.attrelid = constraint_record.confrelid
      and parent_column.attnum = constraint_record.confkey[1]
    where constraint_record.contype = 'f'
      and constraint_record.conrelid = 'public.profiles'::pg_catalog.regclass
      and constraint_record.confrelid = 'auth.users'::pg_catalog.regclass
      and constraint_record.confdeltype = 'c'
      and pg_catalog.array_length(constraint_record.conkey, 1) = 1
      and child_column.attname = 'id'
      and parent_column.attname = 'id'
  ) then
    raise exception using
      errcode = '55000',
      message = '0021 refused: profiles.id must cascade from auth.users.id';
  end if;

  if (
      select pg_catalog.count(*)
      from pg_catalog.pg_trigger as trigger_record
      where trigger_record.tgrelid = 'auth.users'::pg_catalog.regclass
        and trigger_record.tgname = 'on_auth_user_created'
        and not trigger_record.tgisinternal
        and trigger_record.tgenabled = 'O'
        and trigger_record.tgfoid = 'public.handle_new_auth_user()'::pg_catalog.regprocedure
        and (trigger_record.tgtype & 1) = 1
        and (trigger_record.tgtype & 2) = 0
        and (trigger_record.tgtype & 4) = 4
        and (trigger_record.tgtype & (8 | 16 | 32 | 64)) = 0
    ) <> 1
    or (
      select pg_catalog.count(*)
      from pg_catalog.pg_trigger as trigger_record
      where trigger_record.tgrelid = 'auth.users'::pg_catalog.regclass
        and not trigger_record.tgisinternal
        and (
          trigger_record.tgname = 'on_auth_user_created'
          or trigger_record.tgfoid = 'public.handle_new_auth_user()'::pg_catalog.regprocedure
        )
    ) <> 1
  then
    raise exception using
      errcode = '55000',
      message = '0021 refused: auth.users trigger contract is unexpected';
  end if;

  if (
    select pg_catalog.count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name in ('last_active_at', 'last_seen_route')
  ) not in (0, 2) then
    raise exception using
      errcode = '55000',
      message = '0021 refused: presence columns are only partially installed';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'last_active_at'
      and not (
        data_type = 'timestamp with time zone'
        and is_nullable = 'YES'
        and column_default is null
      )
  ) or exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'last_seen_route'
      and not (
        data_type = 'text'
        and is_nullable = 'YES'
        and column_default is null
      )
  ) then
    raise exception using
      errcode = '55000',
      message = '0021 refused: pre-existing presence columns are incompatible';
  end if;

  if (
    (
      select pg_catalog.count(*) = 2
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'profiles'
        and column_name in ('last_active_at', 'last_seen_route')
    ) is distinct from (
      pg_catalog.to_regclass('public.profiles_last_active_at_idx') is not null
    )
  )
  then
    raise exception using
      errcode = '55000',
      message = '0021 refused: presence columns and index are only partially installed';
  end if;

  if pg_catalog.to_regclass('public.profiles_last_active_at_idx') is not null then
    select pg_catalog.pg_get_indexdef(index_record.indexrelid)
    into existing_definition
    from pg_catalog.pg_index as index_record
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_record.indexrelid
    join pg_catalog.pg_am as access_method
      on access_method.oid = index_relation.relam
    join pg_catalog.pg_attribute as indexed_column
      on indexed_column.attrelid = index_record.indrelid
      and indexed_column.attnum = index_record.indkey[0]
    where index_record.indexrelid = 'public.profiles_last_active_at_idx'::pg_catalog.regclass
      and index_record.indrelid = 'public.profiles'::pg_catalog.regclass
      and index_record.indisvalid
      and index_record.indisready
      and not index_record.indisunique
      and not index_record.indisprimary
      and index_record.indnkeyatts = 1
      and index_record.indnatts = 1
      and index_record.indexprs is null
      and indexed_column.attname = 'last_active_at'
      and (index_record.indoption[0] & 1) = 1
      and access_method.amname = 'btree';

    if existing_definition is null
      or existing_definition not like '%(last_active_at DESC)%'
      or existing_definition not like '%WHERE ((is_active = true) AND (deleted_at IS NULL))%'
    then
      raise exception using
        errcode = '55000',
        message = '0021 refused: pre-existing presence index is incompatible';
    end if;
  end if;

  if exists (
    select 1
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and not trigger_record.tgisinternal
      and (
        trigger_record.tgname = 'protect_profile_authorization_fields'
        or trigger_record.tgfoid = 'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
      )
      and not (
        trigger_record.tgname = 'protect_profile_authorization_fields'
        and trigger_record.tgfoid = 'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
        and trigger_record.tgenabled = 'O'
        and (trigger_record.tgtype & 1) = 1
        and (trigger_record.tgtype & 2) = 2
        and (trigger_record.tgtype & 16) = 16
        and (trigger_record.tgtype & (4 | 8 | 32 | 64)) = 0
      )
  ) then
    raise exception using
      errcode = '55000',
      message = '0021 refused: profile authorization trigger name is bound to an unexpected function';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and not trigger_record.tgisinternal
      and (
        trigger_record.tgname = 'protect_profile_deletion'
        or (
          pg_catalog.to_regprocedure('public.protect_profile_deletion()') is not null
          and trigger_record.tgfoid = pg_catalog.to_regprocedure('public.protect_profile_deletion()')
        )
      )
      and not (
        trigger_record.tgname = 'protect_profile_deletion'
        and pg_catalog.to_regprocedure('public.protect_profile_deletion()') is not null
        and trigger_record.tgfoid = pg_catalog.to_regprocedure('public.protect_profile_deletion()')
        and trigger_record.tgenabled = 'O'
        and (trigger_record.tgtype & 1) = 1
        and (trigger_record.tgtype & 2) = 2
        and (trigger_record.tgtype & 8) = 8
        and (trigger_record.tgtype & (4 | 16 | 32 | 64)) = 0
      )
  ) then
    raise exception using
      errcode = '55000',
      message = '0021 refused: profile deletion trigger name is bound to an unexpected function';
  end if;
end;
$preflight$;

alter table public.profiles
  add column if not exists last_active_at timestamptz,
  add column if not exists last_seen_route text;

comment on column public.profiles.last_active_at is
  'Timestamp of the latest throttled authenticated presence heartbeat.';
comment on column public.profiles.last_seen_route is
  'Sanitized application route from the latest authenticated presence heartbeat.';

create index if not exists profiles_last_active_at_idx
  on public.profiles (last_active_at desc)
  where is_active = true and deleted_at is null;

create or replace function public.record_user_presence(presence_route text default null)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor_id uuid := auth.uid();
  safe_route text;
begin
  if actor_id is null or not public.pilot_account_ready(actor_id) then
    return false;
  end if;

  safe_route := case
    when pg_catalog.left(pg_catalog.btrim(coalesce(presence_route, '')), 1) = '/'
      then pg_catalog.left(
        pg_catalog.split_part(pg_catalog.btrim(presence_route), '?', 1),
        200
      )
    else null
  end;

  update public.profiles as profile
  set
    last_active_at = pg_catalog.now(),
    last_seen_route = coalesce(safe_route, profile.last_seen_route)
  where profile.id = actor_id
    and public.pilot_account_ready(profile.id)
    and (
      profile.last_active_at is null
      or profile.last_active_at < pg_catalog.now() - interval '90 seconds'
      or (
        safe_route is not null
        and profile.last_seen_route is distinct from safe_route
      )
    );

  return found;
end;
$function$;

create or replace function public.protect_profile_authorization_fields()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  admin_rpc boolean := coalesce(
    pg_catalog.current_setting('fmworks.profile_admin_rpc', true),
    ''
  ) = 'on';
  password_rpc boolean := coalesce(
    pg_catalog.current_setting('fmworks.password_change_completion', true),
    ''
  ) = 'on';
  active_administrator_count integer;
begin
  if new.password_change_required is distinct from old.password_change_required
    and not admin_rpc
    and not password_rpc
  then
    raise exception 'Password readiness can only be changed by a trusted server operation';
  end if;

  if (
      new.role is distinct from old.role
      or new.is_active is distinct from old.is_active
      or new.deleted_at is distinct from old.deleted_at
    ) and not admin_rpc
  then
    raise exception 'Role, activation and archive changes require the audited Administrator operation';
  end if;

  if auth.uid() is distinct from old.id
    and not admin_rpc
    and not (
      password_rpc
      and new.password_change_required is distinct from old.password_change_required
      and new.display_name is not distinct from old.display_name
      and new.email is not distinct from old.email
      and new.department is not distinct from old.department
      and new.department_id is not distinct from old.department_id
      and new.trade_discipline is not distinct from old.trade_discipline
      and new.contact_number is not distinct from old.contact_number
      and new.role is not distinct from old.role
      and new.is_active is not distinct from old.is_active
      and new.deleted_at is not distinct from old.deleted_at
      and new.last_active_at is not distinct from old.last_active_at
      and new.last_seen_route is not distinct from old.last_seen_route
    )
  then
    raise exception 'Another user profile can only be changed by the audited Administrator operation';
  end if;

  if admin_rpc and auth.uid() = old.id and (
    new.role <> 'administrator'
    or new.is_active = false
    or new.deleted_at is not null
  ) then
    raise exception 'Administrators cannot demote, deactivate or archive their own account';
  end if;

  if old.role = 'administrator'
    and old.is_active = true
    and old.deleted_at is null
    and old.password_change_required = false
    and (
      new.role <> 'administrator'
      or new.is_active = false
      or new.deleted_at is not null
    )
  then
    perform pg_catalog.pg_advisory_xact_lock(6042026);
    select pg_catalog.count(*)
    into active_administrator_count
    from public.profiles as profile
    where profile.role = 'administrator'
      and profile.is_active = true
      and profile.deleted_at is null
      and profile.password_change_required = false;

    if active_administrator_count <= 1 then
      raise exception 'The final ready Administrator cannot be changed';
    end if;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

drop trigger if exists protect_profile_authorization_fields on public.profiles;
create trigger protect_profile_authorization_fields
  before update on public.profiles
  for each row execute function public.protect_profile_authorization_fields();

create or replace function public.protect_profile_deletion()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  ready_administrator_count integer;
begin
  if exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = old.id
  ) then
    raise insufficient_privilege using
      message = 'Profiles can only be permanently deleted through the trusted Auth deletion workflow';
  end if;

  if old.role = 'administrator'
    and old.is_active = true
    and old.deleted_at is null
    and old.password_change_required = false
  then
    perform pg_catalog.pg_advisory_xact_lock(6042026);
    select pg_catalog.count(*)
    into ready_administrator_count
    from public.profiles as profile
    where profile.role = 'administrator'
      and profile.is_active = true
      and profile.deleted_at is null
      and profile.password_change_required = false;

    if ready_administrator_count <= 1 then
      raise exception 'The final ready Administrator cannot be permanently deleted';
    end if;
  end if;

  if exists (
    select 1
    from public.work_orders as work_order
    where work_order.assigned_technician_id = old.id
      and work_order.status not in ('closed', 'cancelled')
  ) then
    raise exception 'Active work assignments must be reassigned before permanent deletion';
  end if;

  return old;
end;
$function$;

drop trigger if exists protect_profile_deletion on public.profiles;
create trigger protect_profile_deletion
  before delete on public.profiles
  for each row execute function public.protect_profile_deletion();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  invitation_token text := new.raw_user_meta_data ->> 'administrator_invitation_token';
  invitation public.account_invitations%rowtype;
begin
  if invitation_token is not null then
    select candidate.*
    into invitation
    from public.account_invitations as candidate
    where candidate.token_hash = pg_catalog.encode(
        extensions.digest(invitation_token, 'sha256'),
        'hex'
      )
      and pg_catalog.lower(candidate.email) = pg_catalog.lower(coalesce(new.email, ''))
      and candidate.is_active = true
      and candidate.used_at is null
      and candidate.expires_at > pg_catalog.now()
    for update;

    if invitation.id is null then
      raise exception 'Invalid, expired or previously used invitation';
    end if;

    insert into public.profiles (
      id, display_name, email, department, department_id,
      trade_discipline, contact_number, role, is_active,
      password_change_required, created_at, updated_at
    ) values (
      new.id,
      invitation.display_name,
      new.email,
      invitation.department,
      null,
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'trade_discipline'), ''),
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'contact_number'), ''),
      invitation.assigned_role,
      false,
      true,
      coalesce(new.created_at, pg_catalog.now()),
      pg_catalog.now()
    ) on conflict (id) do nothing;

    update public.account_invitations as candidate
    set used_at = pg_catalog.now()
    where candidate.id = invitation.id;

    return new;
  end if;

  insert into public.profiles (
    id, display_name, email, department, trade_discipline,
    contact_number, role, is_active, password_change_required,
    created_at, updated_at
  ) values (
    new.id,
    coalesce(
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(pg_catalog.split_part(coalesce(new.email, ''), '@', 1), ''),
      'Pending account'
    ),
    new.email,
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'department'), ''),
    null,
    null,
    'reviewer',
    false,
    true,
    coalesce(new.created_at, pg_catalog.now()),
    pg_catalog.now()
  ) on conflict (id) do nothing;

  return new;
end;
$function$;

revoke all on function public.record_user_presence(text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_user_presence(text) to authenticated;

revoke all on function public.protect_profile_authorization_fields()
  from public, anon, authenticated, service_role;
revoke all on function public.protect_profile_deletion()
  from public, anon, authenticated, service_role;
revoke all on function public.handle_new_auth_user()
  from public, anon, authenticated, service_role;

comment on function public.record_user_presence(text) is
  'Records a throttled heartbeat for the ready authenticated caller only.';
comment on function public.protect_profile_authorization_fields() is
  'Protects profile authorization state and trusted password reconciliation.';
comment on function public.protect_profile_deletion() is
  'Permits profile deletion only through the trusted Auth-user cascade, subject to final-Administrator and assignment safeguards.';
comment on function public.handle_new_auth_user() is
  'Creates a fail-closed quarantine profile and consumes only a valid Administrator provisioning ticket.';

do $postflight$
declare
  protected_signature text;
begin
  if (
    select pg_catalog.count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and (
        (
          column_name = 'last_active_at'
          and data_type = 'timestamp with time zone'
          and is_nullable = 'YES'
          and column_default is null
        )
        or (
          column_name = 'last_seen_route'
          and data_type = 'text'
          and is_nullable = 'YES'
          and column_default is null
        )
      )
  ) <> 2 then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: presence columns are not exact';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index as index_record
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_record.indexrelid
    join pg_catalog.pg_am as access_method
      on access_method.oid = index_relation.relam
    join pg_catalog.pg_attribute as indexed_column
      on indexed_column.attrelid = index_record.indrelid
      and indexed_column.attnum = index_record.indkey[0]
    where index_record.indexrelid = 'public.profiles_last_active_at_idx'::pg_catalog.regclass
      and index_record.indrelid = 'public.profiles'::pg_catalog.regclass
      and index_record.indisvalid
      and index_record.indisready
      and not index_record.indisunique
      and not index_record.indisprimary
      and index_record.indnkeyatts = 1
      and index_record.indnatts = 1
      and index_record.indexprs is null
      and indexed_column.attname = 'last_active_at'
      and (index_record.indoption[0] & 1) = 1
      and access_method.amname = 'btree'
      and pg_catalog.pg_get_indexdef(index_record.indexrelid) like '%(last_active_at DESC)%'
      and pg_catalog.pg_get_indexdef(index_record.indexrelid) like '%WHERE ((is_active = true) AND (deleted_at IS NULL))%'
  ) then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: presence index is not exact';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and trigger_record.tgname = 'protect_profile_authorization_fields'
      and not trigger_record.tgisinternal
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgfoid = 'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
      and (trigger_record.tgtype & 1) = 1
      and (trigger_record.tgtype & 2) = 2
      and (trigger_record.tgtype & 16) = 16
      and (trigger_record.tgtype & (4 | 8 | 32 | 64)) = 0
  ) <> 1 then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: profile authorization trigger is not exact';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and trigger_record.tgname = 'protect_profile_deletion'
      and not trigger_record.tgisinternal
      and trigger_record.tgenabled = 'O'
      and trigger_record.tgfoid = 'public.protect_profile_deletion()'::pg_catalog.regprocedure
      and (trigger_record.tgtype & 1) = 1
      and (trigger_record.tgtype & 2) = 2
      and (trigger_record.tgtype & 8) = 8
      and (trigger_record.tgtype & (4 | 16 | 32 | 64)) = 0
  ) <> 1 then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: profile deletion trigger is not exact';
  end if;

  if (
      select pg_catalog.count(*)
      from pg_catalog.pg_trigger as trigger_record
      where trigger_record.tgrelid = 'auth.users'::pg_catalog.regclass
        and trigger_record.tgname = 'on_auth_user_created'
        and not trigger_record.tgisinternal
        and trigger_record.tgenabled = 'O'
        and trigger_record.tgfoid = 'public.handle_new_auth_user()'::pg_catalog.regprocedure
        and (trigger_record.tgtype & 1) = 1
        and (trigger_record.tgtype & 2) = 0
        and (trigger_record.tgtype & 4) = 4
        and (trigger_record.tgtype & (8 | 16 | 32 | 64)) = 0
    ) <> 1
    or (
      select pg_catalog.count(*)
      from pg_catalog.pg_trigger as trigger_record
      where trigger_record.tgrelid = 'auth.users'::pg_catalog.regclass
        and not trigger_record.tgisinternal
        and (
          trigger_record.tgname = 'on_auth_user_created'
          or trigger_record.tgfoid = 'public.handle_new_auth_user()'::pg_catalog.regprocedure
        )
    ) <> 1
  then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: Auth provisioning trigger is not exact';
  end if;

  foreach protected_signature in array array[
    'public.record_user_presence(text)',
    'public.protect_profile_authorization_fields()',
    'public.protect_profile_deletion()',
    'public.handle_new_auth_user()'
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_proc as procedure
      where procedure.oid = protected_signature::pg_catalog.regprocedure
        and procedure.prosecdef
        and procedure.proowner = (select oid from pg_catalog.pg_roles where rolname = current_user)
        and procedure.proconfig = array['search_path=pg_catalog']::text[]
    ) then
      raise exception using
        errcode = '55000',
        message = '0021 postflight failed: affected function metadata is not exact',
        detail = protected_signature;
    end if;
  end loop;

  if pg_catalog.has_function_privilege('public', 'public.record_user_presence(text)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.record_user_presence(text)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.record_user_presence(text)', 'EXECUTE')
    or pg_catalog.has_function_privilege('service_role', 'public.record_user_presence(text)', 'EXECUTE')
  then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: presence RPC ACL is not exact';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        procedure.proacl,
        pg_catalog.acldefault('f', procedure.proowner)
      )
    ) as privilege
    where procedure.oid = 'public.record_user_presence(text)'::pg_catalog.regprocedure
      and privilege.privilege_type = 'EXECUTE'
      and privilege.grantee not in (
        procedure.proowner,
        (select oid from pg_catalog.pg_roles where rolname = 'authenticated')
      )
  ) then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: presence RPC has an unexpected EXECUTE grantee';
  end if;

  foreach protected_signature in array array[
    'public.protect_profile_authorization_fields()',
    'public.protect_profile_deletion()',
    'public.handle_new_auth_user()'
  ] loop
    if pg_catalog.has_function_privilege('public', protected_signature, 'EXECUTE')
      or pg_catalog.has_function_privilege('anon', protected_signature, 'EXECUTE')
      or pg_catalog.has_function_privilege('authenticated', protected_signature, 'EXECUTE')
      or pg_catalog.has_function_privilege('service_role', protected_signature, 'EXECUTE')
    then
      raise exception using
        errcode = '55000',
        message = '0021 postflight failed: trigger-only function ACL is not exact',
        detail = protected_signature;
    end if;
  end loop;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        procedure.proacl,
        pg_catalog.acldefault('f', procedure.proowner)
      )
    ) as privilege
    where procedure.oid in (
        'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure,
        'public.protect_profile_deletion()'::pg_catalog.regprocedure,
        'public.handle_new_auth_user()'::pg_catalog.regprocedure
      )
      and privilege.privilege_type = 'EXECUTE'
      and privilege.grantee <> procedure.proowner
  ) then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: trigger-only function has an unexpected EXECUTE grantee';
  end if;

  if pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'public.handle_new_auth_user()'::pg_catalog.regprocedure
    ),
    'extensions.digest'
  ) = 0 then
    raise exception using
      errcode = '55000',
      message = '0021 postflight failed: invitation digest is not schema-qualified';
  end if;
end;
$postflight$;

commit;

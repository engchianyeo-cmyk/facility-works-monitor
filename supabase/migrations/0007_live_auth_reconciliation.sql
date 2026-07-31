-- Live authentication reconciliation for the legacy Supabase profiles schema.
--
-- This migration SUPERSEDES the review-only SQL in 0004, 0005 and 0006 for
-- the existing live database. Do not execute those three migrations unchanged.
-- Preserve a database backup and run the read-only preflight queries supplied
-- with the implementation report before applying this file.
--
-- MIGRATION HISTORY SAFETY:
-- * Applying this file in SQL Editor changes schema/data but does NOT record
--   any version in Supabase migration history.
-- * Do not edit supabase_migrations.schema_migrations manually.
-- * Do not run `supabase db push` before history is reconciled; it can attempt
--   to execute 0004, 0005 and 0006 before reaching this file.
-- * Only after 0007 has been applied manually and all validation has passed,
--   inspect history with `supabase migration list --linked`. If the reviewed
--   live state truly contains the superseding effects, the supported tracking-
--   only commands are:
--     supabase migration repair 0004 --status applied --linked
--     supabase migration repair 0005 --status applied --linked
--     supabase migration repair 0006 --status applied --linked
--     supabase migration repair 0007 --status applied --linked
--   These commands update tracking only; they do not execute this SQL. Review
--   the exact versions printed by `supabase migration list --linked` before
--   running any repair command. No repair command is run by this migration.

begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. Preserve and extend the legacy profiles table
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists display_name text,
  add column if not exists email text,
  add column if not exists department text,
  add column if not exists role text,
  add column if not exists is_active boolean,
  add column if not exists created_at timestamptz,
  add column if not exists trade_discipline text,
  add column if not exists contact_number text,
  add column if not exists deleted_at timestamptz;

-- Preserve username, full_name, avatar_url and website. They remain available
-- for legacy consumers even though the current application does not read them.
update public.profiles as profile
set
  email = coalesce(profile.email, users.email),
  display_name = coalesce(
    nullif(trim(profile.display_name), ''),
    nullif(trim(profile.full_name), ''),
    nullif(trim(profile.username), ''),
    nullif(split_part(coalesce(users.email, ''), '@', 1), ''),
    'Reviewer'
  ),
  role = coalesce(profile.role, 'reviewer'),
  is_active = coalesce(profile.is_active, true),
  created_at = coalesce(
    profile.created_at,
    users.created_at,
    profile.updated_at,
    now()
  ),
  updated_at = coalesce(profile.updated_at, users.updated_at, now())
from auth.users as users
where users.id = profile.id;

-- Retain any orphaned legacy profile row without deleting it. Give required
-- application fields safe values while leaving email nullable.
update public.profiles
set
  display_name = coalesce(
    nullif(trim(display_name), ''),
    nullif(trim(full_name), ''),
    nullif(trim(username), ''),
    'Reviewer'
  ),
  role = coalesce(role, 'reviewer'),
  is_active = coalesce(is_active, true),
  created_at = coalesce(created_at, updated_at, now()),
  updated_at = coalesce(updated_at, now())
where
  display_name is null
  or trim(display_name) = ''
  or role is null
  or is_active is null
  or created_at is null
  or updated_at is null;

-- Backfill Auth identities that do not yet have a profile. Existing profile
-- roles and active flags are never overwritten by this insert.
insert into public.profiles (
  id,
  display_name,
  email,
  department,
  role,
  is_active,
  created_at,
  updated_at
)
select
  users.id,
  coalesce(
    nullif(trim(users.raw_user_meta_data ->> 'display_name'), ''),
    nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(users.raw_user_meta_data ->> 'username'), ''),
    nullif(split_part(coalesce(users.email, ''), '@', 1), ''),
    'Reviewer'
  ),
  users.email,
  nullif(trim(users.raw_user_meta_data ->> 'department'), ''),
  'reviewer',
  true,
  coalesce(users.created_at, now()),
  coalesce(users.updated_at, users.created_at, now())
from auth.users as users
where not exists (
  select 1
  from public.profiles as profile
  where profile.id = users.id
);

-- Reject unexpected non-null role values instead of silently overwriting them.
do $$
begin
  if exists (
    select 1
    from public.profiles
    where role not in (
      'reviewer',
      'initiator',
      'approver',
      'technician',
      'supervisor',
      'administrator'
    )
  ) then
    raise exception 'profiles contains unsupported non-null role values';
  end if;
end;
$$;

alter table public.profiles
  alter column display_name set not null,
  alter column role set default 'reviewer',
  alter column role set not null,
  alter column is_active set default true,
  alter column is_active set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_display_name_nonempty_check'
  ) then
    alter table public.profiles
      add constraint profiles_display_name_nonempty_check
      check (length(trim(display_name)) > 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_role_check'
  ) then
    alter table public.profiles
      add constraint profiles_role_check
      check (
        role in (
          'reviewer',
          'initiator',
          'approver',
          'technician',
          'supervisor',
          'administrator'
        )
      );
  end if;
end;
$$;

do $$
declare
  profile_auth_fkey_name text;
begin
  select constraint_row.conname
  into profile_auth_fkey_name
  from pg_constraint as constraint_row
  where constraint_row.conrelid = 'public.profiles'::regclass
    and constraint_row.contype = 'f'
    and constraint_row.confrelid = 'auth.users'::regclass
    and constraint_row.conkey = array[
      (
        select attnum
        from pg_attribute
        where attrelid = 'public.profiles'::regclass
          and attname = 'id'
      )
    ]::smallint[]
  limit 1;

  if profile_auth_fkey_name is null then
    alter table public.profiles
      add constraint profiles_id_auth_users_fkey
      foreign key (id) references auth.users(id) on delete cascade
      not valid;
  end if;
end;
$$;

-- Validate the Auth foreign key only when no preserved orphan profile exists.
do $$
declare
  profile_auth_fkey_name text;
begin
  select constraint_row.conname
  into profile_auth_fkey_name
  from pg_constraint as constraint_row
  where constraint_row.conrelid = 'public.profiles'::regclass
    and constraint_row.contype = 'f'
    and constraint_row.confrelid = 'auth.users'::regclass
    and constraint_row.conkey = array[
      (
        select attnum
        from pg_attribute
        where attrelid = 'public.profiles'::regclass
          and attname = 'id'
      )
    ]::smallint[]
  limit 1;

  if not exists (
    select 1
    from public.profiles as profile
    left join auth.users as users on users.id = profile.id
    where users.id is null
  ) then
    execute format(
      'alter table public.profiles validate constraint %I',
      profile_auth_fkey_name
    );
  else
    raise notice
      'Profile Auth foreign key remains NOT VALID because legacy orphan profiles exist';
  end if;
end;
$$;

create index if not exists profiles_role_active_idx
  on public.profiles (role, is_active);
create index if not exists profiles_email_lower_idx
  on public.profiles (lower(email));

-- ---------------------------------------------------------------------------
-- 2. Invitation foundation from the intended 0005/0006 design
-- ---------------------------------------------------------------------------

create table if not exists public.account_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null check (length(trim(email)) > 3),
  display_name text not null check (length(trim(display_name)) > 0),
  department text,
  assigned_role text not null,
  is_active boolean not null default true,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

alter table public.account_invitations
  drop constraint if exists account_invitations_assigned_role_check;
alter table public.account_invitations
  add constraint account_invitations_assigned_role_check
  check (
    assigned_role in (
      'reviewer',
      'initiator',
      'approver',
      'technician',
      'supervisor',
      'administrator'
    )
  );

create unique index if not exists account_invitations_open_email_idx
  on public.account_invitations (lower(email))
  where used_at is null and is_active = true;

-- ---------------------------------------------------------------------------
-- 3. Reconcile legacy and intended Auth user-creation trigger
-- ---------------------------------------------------------------------------

-- Remove the legacy trigger before replacing its target function. This leaves
-- exactly one intended AFTER INSERT trigger on auth.users.
drop trigger if exists on_auth_user_created on auth.users;

do $$
declare
  trigger_record record;
begin
  for trigger_record in
    select trigger_row.tgname
    from pg_trigger as trigger_row
    where trigger_row.tgrelid = 'auth.users'::regclass
      and not trigger_row.tgisinternal
      and (
        trigger_row.tgfoid = to_regprocedure('public.handle_new_user()')
        or trigger_row.tgfoid =
          to_regprocedure('public.handle_new_auth_user()')
      )
  loop
    execute format(
      'drop trigger if exists %I on auth.users',
      trigger_record.tgname
    );
  end loop;
end;
$$;

drop function if exists public.handle_new_user();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  requested_role text := lower(
    trim(coalesce(new.raw_user_meta_data ->> 'public_signup_role', 'reviewer'))
  );
  invitation_token text :=
    new.raw_user_meta_data ->> 'administrator_invitation_token';
  invitation public.account_invitations%rowtype;
begin
  if invitation_token is not null then
    select *
    into invitation
    from public.account_invitations
    where token_hash = encode(digest(invitation_token, 'sha256'), 'hex')
      and lower(email) = lower(coalesce(new.email, ''))
      and is_active = true
      and used_at is null
      and expires_at > now()
    for update;

    if invitation.id is null then
      raise exception 'Invalid, expired or previously used Administrator invitation';
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
      created_at,
      updated_at
    )
    values (
      new.id,
      invitation.display_name,
      new.email,
      invitation.department,
      nullif(trim(new.raw_user_meta_data ->> 'trade_discipline'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'contact_number'), ''),
      invitation.assigned_role,
      invitation.is_active,
      coalesce(new.created_at, now()),
      now()
    )
    on conflict (id) do nothing;

    update public.account_invitations
    set used_at = now()
    where id = invitation.id;

    return new;
  end if;

  if requested_role not in ('reviewer', 'technician') then
    requested_role := 'reviewer';
  end if;

  if nullif(trim(new.raw_user_meta_data ->> 'department'), '') is null then
    raise exception 'Department or company is required';
  end if;

  if requested_role = 'technician'
    and nullif(trim(new.raw_user_meta_data ->> 'trade_discipline'), '') is null
  then
    raise exception 'Trade or technical discipline is required';
  end if;

  if coalesce(new.raw_user_meta_data ->> 'account_terms_accepted', 'false')
    <> 'true' then
    raise exception 'Account responsibilities must be accepted';
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
    created_at,
    updated_at
  )
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Reviewer'
    ),
    new.email,
    nullif(trim(new.raw_user_meta_data ->> 'department'), ''),
    case
      when requested_role = 'technician'
        then nullif(trim(new.raw_user_meta_data ->> 'trade_discipline'), '')
      else null
    end,
    case
      when requested_role = 'technician'
        then nullif(trim(new.raw_user_meta_data ->> 'contact_number'), '')
      else null
    end,
    requested_role,
    true,
    coalesce(new.created_at, now()),
    now()
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- 4. Ownership links and work-order reference foundation from intended 0004
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.work_orders'::regclass
      and conname = 'work_orders_user_id_auth_fkey'
  ) then
    alter table public.work_orders
      add constraint work_orders_user_id_auth_fkey
      foreign key (user_id) references auth.users(id) on delete set null
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.activity_logs'::regclass
      and conname = 'activity_logs_user_id_auth_fkey'
  ) then
    alter table public.activity_logs
      add constraint activity_logs_user_id_auth_fkey
      foreign key (user_id) references auth.users(id) on delete set null
      not valid;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from public.work_orders as work_order
    left join auth.users as users on users.id = work_order.user_id
    where work_order.user_id is not null and users.id is null
  ) then
    alter table public.work_orders
      validate constraint work_orders_user_id_auth_fkey;
  else
    raise notice
      'work_orders_user_id_auth_fkey remains NOT VALID because orphan references exist';
  end if;

  if not exists (
    select 1
    from public.activity_logs as activity
    left join auth.users as users on users.id = activity.user_id
    where activity.user_id is not null and users.id is null
  ) then
    alter table public.activity_logs
      validate constraint activity_logs_user_id_auth_fkey;
  else
    raise notice
      'activity_logs_user_id_auth_fkey remains NOT VALID because orphan references exist';
  end if;
end;
$$;

create table if not exists public.work_order_number_counters (
  reference_year integer primary key
    check (reference_year between 2000 and 9999),
  last_value integer not null check (last_value > 0)
);

create or replace function public.next_work_order_number(
  reference_time timestamptz default now()
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  reference_year integer :=
    extract(year from reference_time at time zone 'UTC');
  reference_value integer;
begin
  insert into public.work_order_number_counters (reference_year, last_value)
  values (reference_year, 1)
  on conflict (reference_year)
  do update
    set last_value = public.work_order_number_counters.last_value + 1
  returning last_value into reference_value;

  return format(
    'FW-%s-%s',
    reference_year,
    lpad(reference_value::text, 4, '0')
  );
end;
$$;

alter table public.work_orders
  add column if not exists work_order_no text;

with numbered as (
  select
    id,
    extract(year from created_at at time zone 'UTC')::integer
      as reference_year,
    row_number() over (
      partition by extract(year from created_at at time zone 'UTC')
      order by created_at asc, id asc
    ) as reference_value
  from public.work_orders
  where work_order_no is null
)
update public.work_orders as work_order
set work_order_no = format(
  'FW-%s-%s',
  numbered.reference_year,
  lpad(numbered.reference_value::text, 4, '0')
)
from numbered
where work_order.id = numbered.id;

insert into public.work_order_number_counters (reference_year, last_value)
select
  split_part(work_order_no, '-', 2)::integer,
  max(split_part(work_order_no, '-', 3)::integer)
from public.work_orders
where work_order_no ~ '^FW-[0-9]{4}-[0-9]{4,}$'
group by split_part(work_order_no, '-', 2)::integer
on conflict (reference_year)
do update
  set last_value = greatest(
    public.work_order_number_counters.last_value,
    excluded.last_value
  );

create or replace function public.assign_work_order_number()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.work_order_no is null or trim(new.work_order_no) = '' then
    new.work_order_no := public.next_work_order_number(
      coalesce(new.created_at, now())
    );
  end if;
  return new;
end;
$$;

drop trigger if exists assign_work_order_number on public.work_orders;
create trigger assign_work_order_number
  before insert on public.work_orders
  for each row execute function public.assign_work_order_number();

alter table public.work_orders
  alter column work_order_no set not null;
create unique index if not exists work_orders_work_order_no_key
  on public.work_orders (work_order_no);

-- ---------------------------------------------------------------------------
-- 5. Role, final-Administrator and deletion safeguards
-- ---------------------------------------------------------------------------

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.role
  from public.profiles as profile
  where profile.id = auth.uid()
    and profile.is_active = true
    and profile.deleted_at is null
$$;

create or replace function public.protect_profile_authorization_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  active_administrator_count integer;
begin
  if new.role is distinct from old.role
    or new.is_active is distinct from old.is_active
  then
    if auth.uid() is not null
      and public.current_user_role() is distinct from 'administrator'
    then
      raise exception
        'Only an Administrator may change role or active status';
    end if;

    if auth.uid() = old.id
      and (
        new.role <> 'administrator'
        or new.is_active = false
      )
    then
      raise exception
        'Administrators cannot demote or deactivate their own active account';
    end if;

    if old.role = 'administrator'
      and old.is_active = true
      and (
        new.role <> 'administrator'
        or new.is_active = false
      )
    then
      perform pg_advisory_xact_lock(6042026);
      select count(*)
      into active_administrator_count
      from public.profiles
      where role = 'administrator'
        and is_active = true
        and deleted_at is null;

      if active_administrator_count <= 1 then
        raise exception 'The final active Administrator cannot be changed';
      end if;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists protect_profile_authorization_fields
  on public.profiles;
create trigger protect_profile_authorization_fields
  before update on public.profiles
  for each row execute function public.protect_profile_authorization_fields();

create or replace function public.protect_profile_deletion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  active_administrator_count integer;
begin
  if auth.uid() = old.id then
    raise exception 'Administrators cannot delete their own signed-in account';
  end if;

  if old.role = 'administrator' and old.is_active = true then
    perform pg_advisory_xact_lock(6042026);
    select count(*)
    into active_administrator_count
    from public.profiles
    where role = 'administrator'
      and is_active = true
      and deleted_at is null;

    if active_administrator_count <= 1 then
      raise exception 'The final active Administrator cannot be deleted';
    end if;
  end if;

  if exists (
    select 1
    from public.work_orders
    where assigned_technician_id = old.id
      and status not in ('done', 'completed', 'closed', 'rejected')
  ) then
    raise exception
      'Active work assignments must be reassigned before deletion';
  end if;

  return old;
end;
$$;

drop trigger if exists protect_profile_deletion on public.profiles;
create trigger protect_profile_deletion
  before delete on public.profiles
  for each row execute function public.protect_profile_deletion();

-- ---------------------------------------------------------------------------
-- 6. Controlled RLS reconciliation
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.account_invitations enable row level security;
alter table public.categories enable row level security;
alter table public.work_orders enable row level security;
alter table public.activity_logs enable row level security;

drop policy if exists "Public profiles are viewable by everyone."
  on public.profiles;
drop policy if exists "Users can insert their own profile."
  on public.profiles;
drop policy if exists "Users can update own profile."
  on public.profiles;
drop policy if exists "profiles_read_self_or_admin" on public.profiles;
drop policy if exists "profiles_update_self_or_admin" on public.profiles;

drop policy if exists "categories_v1_read" on public.categories;
drop policy if exists "categories_v1_write" on public.categories;
drop policy if exists "work_orders_v1_read" on public.work_orders;
drop policy if exists "work_orders_v1_write" on public.work_orders;
drop policy if exists "activity_logs_v1_read" on public.activity_logs;
drop policy if exists "activity_logs_v1_write" on public.activity_logs;

drop policy if exists "categories_read_authenticated" on public.categories;
drop policy if exists "categories_manage_admin" on public.categories;
drop policy if exists "work_orders_read_permitted" on public.work_orders;
drop policy if exists "work_orders_create_authenticated"
  on public.work_orders;
drop policy if exists "work_orders_update_permitted" on public.work_orders;
drop policy if exists "work_orders_delete_admin" on public.work_orders;
drop policy if exists "activity_logs_read_permitted"
  on public.activity_logs;
drop policy if exists "activity_logs_create_authenticated"
  on public.activity_logs;
drop policy if exists "activity_logs_admin_read" on public.activity_logs;
drop policy if exists "account_invitations_admin_manage"
  on public.account_invitations;

create policy "profiles_read_self_or_admin"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.current_user_role() = 'administrator'
  );

create policy "profiles_update_self_or_admin"
  on public.profiles for update
  to authenticated
  using (
    id = auth.uid()
    or public.current_user_role() = 'administrator'
  )
  with check (
    id = auth.uid()
    or public.current_user_role() = 'administrator'
  );

create policy "account_invitations_admin_manage"
  on public.account_invitations for all
  to authenticated
  using (public.current_user_role() = 'administrator')
  with check (
    public.current_user_role() = 'administrator'
    and created_by = auth.uid()
  );

create policy "categories_read_authenticated"
  on public.categories for select
  to authenticated
  using (true);

create policy "categories_manage_admin"
  on public.categories for all
  to authenticated
  using (public.current_user_role() = 'administrator')
  with check (public.current_user_role() = 'administrator');

create policy "work_orders_read_permitted"
  on public.work_orders for select
  to authenticated
  using (
    user_id is null
    or user_id = auth.uid()
    or assigned_technician_id = auth.uid()
    or public.current_user_role() in (
      'approver',
      'supervisor',
      'administrator'
    )
  );

create policy "work_orders_create_authenticated"
  on public.work_orders for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "work_orders_update_permitted"
  on public.work_orders for update
  to authenticated
  using (
    (
      user_id = auth.uid()
      and status = 'submitted'
      and public.current_user_role() in ('reviewer', 'initiator')
    )
    or (
      assigned_technician_id = auth.uid()
      and public.current_user_role() = 'technician'
    )
    or public.current_user_role() in (
      'approver',
      'supervisor',
      'administrator'
    )
  )
  with check (
    user_id = auth.uid()
    or assigned_technician_id = auth.uid()
    or public.current_user_role() in (
      'approver',
      'supervisor',
      'administrator'
    )
  );

create policy "work_orders_delete_admin"
  on public.work_orders for delete
  to authenticated
  using (public.current_user_role() = 'administrator');

create policy "activity_logs_read_permitted"
  on public.activity_logs for select
  to authenticated
  using (
    exists (
      select 1
      from public.work_orders
      where work_orders.id = activity_logs.work_order_id
    )
  );

create policy "activity_logs_create_authenticated"
  on public.activity_logs for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "activity_logs_admin_read"
  on public.activity_logs for select
  to authenticated
  using (public.current_user_role() = 'administrator');

-- ---------------------------------------------------------------------------
-- 7. One-time initial Administrator bootstrap
-- ---------------------------------------------------------------------------

insert into public.profiles (
  id,
  display_name,
  email,
  department,
  role,
  is_active,
  created_at,
  updated_at,
  deleted_at
)
select
  users.id,
  'Yeo Eng Chian',
  users.email,
  nullif(trim(users.raw_user_meta_data ->> 'department'), ''),
  'administrator',
  true,
  coalesce(users.created_at, now()),
  now(),
  null
from auth.users as users
where lower(users.email) = lower('engchian.yeo@gmail.com')
on conflict (id) do update
set
  display_name = 'Yeo Eng Chian',
  email = excluded.email,
  role = 'administrator',
  is_active = true,
  deleted_at = null,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- 8. Transactional validation
-- ---------------------------------------------------------------------------

do $$
declare
  auth_trigger_count integer;
begin
  if exists (
    select 1
    from public.profiles
    where display_name is null
      or trim(display_name) = ''
      or role is null
      or is_active is null
      or created_at is null
      or updated_at is null
  ) then
    raise exception 'Profile required-field backfill is incomplete';
  end if;

  if exists (
    select users.id
    from auth.users as users
    left join public.profiles as profile on profile.id = users.id
    where profile.id is null
  ) then
    raise exception 'One or more Auth users still lack profiles';
  end if;

  select count(*)
  into auth_trigger_count
  from pg_trigger
  where tgrelid = 'auth.users'::regclass
    and not tgisinternal
    and tgname = 'on_auth_user_created'
    and tgfoid = 'public.handle_new_auth_user()'::regprocedure;

  if auth_trigger_count <> 1 then
    raise exception
      'Expected exactly one on_auth_user_created trigger targeting handle_new_auth_user';
  end if;

  if not exists (
    select 1
    from public.profiles
    where lower(email) = lower('engchian.yeo@gmail.com')
      and display_name = 'Yeo Eng Chian'
      and role = 'administrator'
      and is_active = true
      and deleted_at is null
  ) then
    raise exception
      'Initial Administrator Auth identity was not found or was not promoted';
  end if;

  if exists (
    select work_order_no
    from public.work_orders
    group by work_order_no
    having work_order_no is null or count(*) > 1
  ) then
    raise exception 'Work-order reference validation failed';
  end if;
end;
$$;

commit;

-- ---------------------------------------------------------------------------
-- Manual rollback outline (review and execute selectively; do not automate)
-- ---------------------------------------------------------------------------
-- 1. Restore the pre-migration database backup if validation fails after commit.
-- 2. Restore the three legacy profiles policies only if reverting to the legacy
--    application; do not restore public work-order writes for a live rollout.
-- 3. Drop on_auth_user_created and recreate it against handle_new_user() only
--    if that legacy function has first been restored from the backup definition.
-- 4. Drop handle_new_auth_user(), current_user_role(),
--    protect_profile_authorization_fields(), protect_profile_deletion(),
--    next_work_order_number() and assign_work_order_number() only after removing
--    their dependent triggers/policies.
-- 5. Drop account_invitations and work_order_number_counters only if no new
--    invitation or reference data has been created.
-- 6. Keep all added profile columns during rollback unless a verified export
--    proves they contain no new data. Never drop username, full_name, avatar_url
--    or website.
-- 7. Do not delete backfilled profiles. Reconcile them manually against
--    auth.users if the application rollout is reversed.

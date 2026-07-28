-- Administrator-only user management, invitation and account-safety controls.
-- REVIEW ONLY: apply 0004 and 0005 first. Do not apply without a database
-- backup and verification of the initial Administrator Auth identity.

begin;

create extension if not exists pgcrypto;

alter table public.profiles
  add column if not exists deleted_at timestamptz;

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

-- Public registrations remain limited to Reviewer and Technician. A secure
-- Administrator invitation may assign any valid application role. The raw
-- invitation token is compared to its SHA-256 hash and immediately consumed.
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
      is_active
    )
    values (
      new.id,
      invitation.display_name,
      new.email,
      invitation.department,
      nullif(trim(new.raw_user_meta_data ->> 'trade_discipline'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'contact_number'), ''),
      invitation.assigned_role,
      invitation.is_active
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
    role
  )
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      split_part(coalesce(new.email, 'Reviewer'), '@', 1)
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
    requested_role
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

-- Serialize Administrator role/status changes to prevent two concurrent
-- requests from removing the final active Administrator.
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
      and public.current_user_role() <> 'administrator'
    then
      raise exception 'Only an Administrator may change role or active status';
    end if;

    if auth.uid() = old.id
      and (
        new.role <> 'administrator'
        or new.is_active = false
      )
    then
      raise exception 'Administrators cannot demote or deactivate their own active account';
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
    raise exception 'Active work assignments must be reassigned before deletion';
  end if;

  return old;
end;
$$;

drop trigger if exists protect_profile_deletion on public.profiles;
create trigger protect_profile_deletion
  before delete on public.profiles
  for each row execute function public.protect_profile_deletion();

drop policy if exists "activity_logs_admin_read" on public.activity_logs;
create policy "activity_logs_admin_read"
  on public.activity_logs for select
  to authenticated
  using (public.current_user_role() = 'administrator');

-- Controlled one-time bootstrap; this is not a recurring login-time email check.
insert into public.profiles (
  id,
  display_name,
  email,
  department,
  role,
  is_active,
  deleted_at
)
select
  users.id,
  'Yeo Eng Chian',
  users.email,
  nullif(trim(users.raw_user_meta_data ->> 'department'), ''),
  'administrator',
  true,
  null
from auth.users as users
where lower(users.email) = lower('engchian.yeo@gmail.com')
on conflict (id) do update
set
  display_name = excluded.display_name,
  email = excluded.email,
  role = 'administrator',
  is_active = true,
  deleted_at = null,
  updated_at = now();

commit;

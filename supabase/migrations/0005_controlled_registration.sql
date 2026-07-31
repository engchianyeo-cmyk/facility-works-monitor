-- ============================================================================
-- SUPERSEDED FOR THE EXISTING LEGACY LIVE DATABASE
-- DO NOT EXECUTE THIS FILE AGAINST THAT DATABASE UNCHANGED.
--
-- Its safe intended effects are incorporated into
-- 0007_live_auth_reconciliation.sql. Retain this file unchanged below this
-- safety header for migration provenance.
-- ============================================================================

-- Controlled first-time registration and Administrator-invitation foundation.
-- REVIEW ONLY: apply 0004_auth_foundation.sql first, then review and apply this
-- migration through the Supabase dashboard or CLI. The application must never
-- trust a public role value without this database enforcement.

begin;

-- Role-specific profile details. A single profile continues to hold one role.
alter table public.profiles
  add column if not exists trade_discipline text,
  add column if not exists contact_number text;

-- Public signup metadata is only a request. This trigger is the authority:
-- reviewer and technician are accepted; every other value is safely replaced
-- with reviewer. Existing profiles are never updated during login or signup.
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
begin
  if nullif(trim(new.raw_user_meta_data ->> 'department'), '') is null then
    raise exception 'Department or company is required';
  end if;

  if requested_role not in ('reviewer', 'technician') then
    requested_role := 'reviewer';
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

-- Secure data foundation for future Administrator-issued invitations.
-- Only a hash of the invitation token is stored. The future acceptance route
-- must compare the signup email, reject expired/used/inactive invitations and
-- obtain the role from assigned_role rather than request metadata.
create table if not exists public.account_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null check (length(trim(email)) > 3),
  display_name text not null check (length(trim(display_name)) > 0),
  department text,
  assigned_role text not null check (
    assigned_role in (
      'initiator',
      'approver',
      'supervisor',
      'administrator'
    )
  ),
  is_active boolean not null default true,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create unique index if not exists account_invitations_open_email_idx
  on public.account_invitations (lower(email))
  where used_at is null and is_active = true;

alter table public.account_invitations enable row level security;

drop policy if exists "account_invitations_admin_manage"
  on public.account_invitations;
create policy "account_invitations_admin_manage"
  on public.account_invitations for all
  to authenticated
  using (public.current_user_role() = 'administrator')
  with check (
    public.current_user_role() = 'administrator'
    and created_by = auth.uid()
  );

-- Keep authorization fields database-protected. Users may update ordinary
-- profile details under RLS, but role and active status remain Administrator-only.
create or replace function public.protect_profile_authorization_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (
    new.role is distinct from old.role
    or new.is_active is distinct from old.is_active
  ) and public.current_user_role() <> 'administrator' then
    raise exception 'Only an administrator may change role or active status';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

commit;

-- Later application steps:
-- 1. Add an Administrator-only invitation interface.
-- 2. Generate cryptographically random invitation tokens in secure server code.
-- 3. Store only token hashes and email the one-time raw token.
-- 4. Add an acceptance endpoint that atomically consumes a valid invitation.

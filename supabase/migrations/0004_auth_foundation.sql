-- FM Works Phase 2B-2C authentication and reference-number foundation.
-- REVIEW ONLY: do not apply until the application and rollout plan are approved.
-- This migration intentionally preserves the five live work-order statuses.

begin;

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(trim(display_name)) > 0),
  email text,
  department text,
  role text not null default 'reviewer'
    check (role in (
      'reviewer',
      'initiator',
      'approver',
      'technician',
      'supervisor',
      'administrator'
    )),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profiles_role_active_idx
  on public.profiles (role, is_active);

-- Self-registration is always forced to reviewer, regardless of client metadata.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (
    id,
    display_name,
    email,
    department,
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
    'reviewer'
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Backfill profiles only for Auth users that already exist at migration time.
insert into public.profiles (id, display_name, email, department, role)
select
  users.id,
  coalesce(
    nullif(trim(users.raw_user_meta_data ->> 'display_name'), ''),
    split_part(coalesce(users.email, 'Reviewer'), '@', 1)
  ),
  users.email,
  nullif(trim(users.raw_user_meta_data ->> 'department'), ''),
  'reviewer'
from auth.users as users
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Authenticated ownership/audit identity
-- ---------------------------------------------------------------------------

alter table public.work_orders
  add constraint work_orders_user_id_auth_fkey
  foreign key (user_id) references auth.users(id) on delete set null
  not valid;

alter table public.activity_logs
  add constraint activity_logs_user_id_auth_fkey
  foreign key (user_id) references auth.users(id) on delete set null
  not valid;

-- Existing nullable rows remain valid. Validate separately after review.
alter table public.work_orders
  validate constraint work_orders_user_id_auth_fkey;
alter table public.activity_logs
  validate constraint activity_logs_user_id_auth_fkey;

-- ---------------------------------------------------------------------------
-- Race-safe human-readable work-order references
-- ---------------------------------------------------------------------------

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
  reference_year integer := extract(year from reference_time at time zone 'UTC');
  reference_value integer;
begin
  insert into public.work_order_number_counters (reference_year, last_value)
  values (reference_year, 1)
  on conflict (reference_year)
  do update set last_value = public.work_order_number_counters.last_value + 1
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

-- Deterministic one-time backfill: created_at ascending, then UUID ascending.
with numbered as (
  select
    id,
    extract(year from created_at at time zone 'UTC')::integer as reference_year,
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
do update set last_value = greatest(
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
-- Role helper and staged RLS proposal
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
$$;

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

drop trigger if exists protect_profile_authorization_fields
  on public.profiles;
create trigger protect_profile_authorization_fields
  before update on public.profiles
  for each row execute function public.protect_profile_authorization_fields();

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.work_orders enable row level security;
alter table public.activity_logs enable row level security;

-- Remove demo-open policies only when this reviewed migration is applied.
drop policy if exists "categories_v1_read" on public.categories;
drop policy if exists "categories_v1_write" on public.categories;
drop policy if exists "work_orders_v1_read" on public.work_orders;
drop policy if exists "work_orders_v1_write" on public.work_orders;
drop policy if exists "activity_logs_v1_read" on public.activity_logs;
drop policy if exists "activity_logs_v1_write" on public.activity_logs;

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
    user_id is null -- transitional access for the existing 24 legacy rows
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

-- Validation checks for the deployment checklist.
do $$
begin
  if exists (
    select 1
    from public.work_orders
    where work_order_no is null
  ) then
    raise exception 'work_order_no backfill left null values';
  end if;

  if exists (
    select work_order_no
    from public.work_orders
    group by work_order_no
    having count(*) > 1
  ) then
    raise exception 'work_order_no backfill produced duplicates';
  end if;
end;
$$;

commit;

-- Rollback outline (review and run manually if needed):
-- 1. Restore the v1 policies from 0001_init.sql.
-- 2. Drop trigger assign_work_order_number on public.work_orders.
-- 3. Drop function public.assign_work_order_number().
-- 4. Drop function public.next_work_order_number(timestamptz).
-- 5. Drop table public.work_order_number_counters.
-- 6. Drop column public.work_orders.work_order_no.
-- 7. Drop the two auth foreign keys.
-- 8. Drop trigger on_auth_user_created on auth.users.
-- 9. Drop function public.handle_new_auth_user().
-- 10. Drop function public.current_user_role().
-- 11. Drop function public.protect_profile_authorization_fields().
-- 12. Drop table public.profiles.

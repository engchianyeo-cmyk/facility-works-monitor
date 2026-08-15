-- FMWorks fresh Supabase prerequisite bootstrap.
--
-- Purpose: establish the minimum application state required immediately before
-- migration 0012 on a completely fresh Supabase database.
-- Supported target: fresh Supabase managed schemas with no FMWorks application
-- objects and an empty Auth database.
--
-- Historical migrations 0001-0011 are provenance only and are not replayed by
-- this bootstrap. Migration 0011 is intentionally excluded. The required next
-- migration is 0012_department_management_foundation.sql, followed in order by
-- 0013 through 0020.
--
-- NEVER apply this file to an existing FMWorks, customer, Preview, or Production
-- database. It deliberately refuses a second execution or any detected FMWorks
-- application installation.

\set ON_ERROR_STOP on

begin;

do $bootstrap_preflight$
declare
  object_name text;
begin
  if current_user <> 'postgres' then
    raise exception using
      errcode = '55000',
      message = 'FMWorks bootstrap refused: execute as the local postgres migration role';
  end if;

  if pg_catalog.to_regclass('auth.users') is null
    or pg_catalog.to_regprocedure('auth.uid()') is null
    or pg_catalog.to_regclass('storage.buckets') is null
    or pg_catalog.to_regclass('storage.objects') is null then
    raise exception using
      errcode = '55000',
      message = 'FMWorks bootstrap refused: required Supabase managed schemas are unavailable';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_roles
    where rolname in ('anon', 'authenticated', 'service_role')
  ) <> 3 then
    raise exception using
      errcode = '55000',
      message = 'FMWorks bootstrap refused: required Supabase roles are unavailable';
  end if;

  if exists (select 1 from auth.users) then
    raise exception using
      errcode = '55000',
      message = 'FMWorks bootstrap refused: auth.users must be empty';
  end if;

  foreach object_name in array array[
    'public.profiles',
    'public.categories',
    'public.work_orders',
    'public.activity_logs',
    'public.account_invitations',
    'public.work_order_number_counters',
    'public.notification_outbox',
    'public.departments',
    'public.incidents',
    'public.assets',
    'public.maintenance_requirements'
  ] loop
    if pg_catalog.to_regclass(object_name) is not null then
      raise exception using
        errcode = '55000',
        message = 'FMWorks bootstrap refused: existing application object detected',
        detail = object_name;
    end if;
  end loop;
end;
$bootstrap_preflight$;

-- Supabase grants broad default privileges on newly created public objects.
-- Normalize the migration role before any FMWorks object or later migration is
-- created; each approved browser surface is granted explicitly below or by its
-- owning migration.
alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  grant all on tables to service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  grant all on sequences to service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  email text,
  department text,
  role text not null default 'reviewer',
  is_active boolean not null default false,
  trade_discipline text,
  contact_number text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  deleted_at timestamptz,
  constraint profiles_display_name_nonempty_check
    check (pg_catalog.length(pg_catalog.btrim(display_name)) > 0),
  constraint profiles_role_check check (role in (
    'reviewer', 'initiator', 'approver', 'technician', 'supervisor', 'administrator'
  ))
);

create index profiles_role_active_idx
  on public.profiles(role, is_active)
  where deleted_at is null;
create unique index profiles_email_lower_idx
  on public.profiles(pg_catalog.lower(email))
  where email is not null and deleted_at is null;

create table public.account_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  display_name text not null,
  department text,
  assigned_role text not null,
  is_active boolean not null default true,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  constraint account_invitations_role_check check (assigned_role in (
    'reviewer', 'initiator', 'approver', 'technician', 'supervisor', 'administrator'
  ))
);

create unique index account_invitations_open_email_idx
  on public.account_invitations(pg_catalog.lower(email))
  where used_at is null and is_active = true;

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  name text not null,
  created_at timestamptz not null default pg_catalog.now(),
  constraint categories_name_nonempty_check
    check (pg_catalog.length(pg_catalog.btrim(name)) > 0)
);

create table public.work_order_number_counters (
  reference_year integer primary key,
  last_value integer not null check (last_value > 0)
);

create table public.work_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  title text not null,
  description text,
  location text not null,
  category_id uuid references public.categories(id) on delete set null,
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'critical')),
  status text not null default 'submitted' check (status in (
    'submitted', 'reviewed', 'approved', 'assigned', 'accepted',
    'in_progress', 'completed', 'verified', 'closed', 'rejected'
  )),
  submitted_by text,
  assigned_to text,
  photo_url text,
  ai_priority_score numeric,
  ai_priority_source text,
  ai_priority_confidence numeric,
  ai_priority_review_status text default 'unreviewed',
  assigned_technician_id uuid references public.profiles(id) on delete restrict,
  assigned_vendor_id uuid,
  assigned_by text,
  assigned_at timestamptz,
  accepted_at timestamptz,
  completed_at timestamptz,
  verified_at timestamptz,
  closed_at timestamptz,
  work_order_no text not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create unique index work_orders_work_order_no_key
  on public.work_orders(work_order_no);
create index work_orders_assigned_technician_idx
  on public.work_orders(assigned_technician_id)
  where assigned_technician_id is not null;

create table public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  work_order_id uuid references public.work_orders(id) on delete cascade,
  action text not null,
  from_status text,
  to_status text,
  actor text,
  note text,
  ai_model text,
  ai_confidence numeric,
  created_at timestamptz not null default pg_catalog.now()
);

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  event_type text not null,
  event_key text not null,
  recipient_user_id uuid references public.profiles(id) on delete restrict,
  recipient_email text,
  payload jsonb not null default '{}'::jsonb,
  delivery_status text not null default 'pending'
    check (delivery_status in ('pending', 'processing', 'sent', 'failed')),
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  available_at timestamptz not null default pg_catalog.now(),
  sent_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint notification_outbox_event_recipient_key
    unique nulls not distinct(event_key, recipient_user_id, recipient_email)
);

create index notification_outbox_delivery_idx
  on public.notification_outbox(delivery_status, available_at, created_at);

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select profile.role
  from public.profiles as profile
  where profile.id = auth.uid()
    and profile.is_active = true
    and profile.deleted_at is null
$function$;

create or replace function public.next_work_order_number(
  reference_time timestamptz default pg_catalog.now()
)
returns text
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  reference_year integer := extract(year from reference_time at time zone 'UTC');
  reference_value integer;
begin
  insert into public.work_order_number_counters(reference_year, last_value)
  values(reference_year, 1)
  on conflict(reference_year) do update
    set last_value = public.work_order_number_counters.last_value + 1
  returning last_value into reference_value;

  return pg_catalog.format(
    'FW-%s-%s', reference_year, pg_catalog.lpad(reference_value::text, 4, '0')
  );
end
$function$;

create or replace function public.assign_work_order_number()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
begin
  if new.work_order_no is null or pg_catalog.btrim(new.work_order_no) = '' then
    new.work_order_no := public.next_work_order_number(new.created_at);
  end if;
  return new;
end
$function$;

create trigger assign_work_order_number
  before insert on public.work_orders
  for each row execute function public.assign_work_order_number();

create or replace function public.set_row_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end
$function$;

create trigger set_notification_outbox_updated_at
  before update on public.notification_outbox
  for each row execute function public.set_row_updated_at();

-- Until migration 0020 replaces this trigger function, all newly created Auth
-- identities are quarantined as inactive Reviewers. No client-supplied role or
-- activation value is trusted.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
begin
  insert into public.profiles(
    id, display_name, email, department, role, is_active
  ) values (
    new.id,
    coalesce(
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(pg_catalog.split_part(coalesce(new.email, ''), '@', 1), ''),
      'Pending user'
    ),
    new.email,
    null,
    'reviewer',
    false
  )
  on conflict(id) do nothing;
  return new;
end
$function$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

alter table public.profiles enable row level security;
alter table public.account_invitations enable row level security;
alter table public.categories enable row level security;
alter table public.work_orders enable row level security;
alter table public.activity_logs enable row level security;
alter table public.work_order_number_counters enable row level security;
alter table public.notification_outbox enable row level security;

revoke all on table public.profiles, public.account_invitations,
  public.categories, public.work_orders, public.activity_logs,
  public.work_order_number_counters, public.notification_outbox
  from public, anon, authenticated;

grant select on table public.profiles, public.categories, public.work_orders,
  public.activity_logs, public.notification_outbox to authenticated;

grant all on table public.profiles, public.account_invitations,
  public.categories, public.work_orders, public.activity_logs,
  public.work_order_number_counters, public.notification_outbox to service_role;

create policy profiles_read_self_or_admin
  on public.profiles for select to authenticated
  using (id = auth.uid() or public.current_user_role() = 'administrator');

create policy categories_read_authenticated
  on public.categories for select to authenticated
  using (auth.uid() is not null);

create policy work_orders_read_permitted
  on public.work_orders for select to authenticated
  using (
    user_id = auth.uid()
    or assigned_technician_id = auth.uid()
    or public.current_user_role() in ('approver', 'supervisor', 'administrator')
  );

create policy activity_logs_read_permitted
  on public.activity_logs for select to authenticated
  using (
    user_id = auth.uid()
    or public.current_user_role() in ('approver', 'supervisor', 'administrator')
    or exists (
      select 1 from public.work_orders as work_order
      where work_order.id = activity_logs.work_order_id
        and (
          work_order.user_id = auth.uid()
          or work_order.assigned_technician_id = auth.uid()
        )
    )
  );

create policy notification_outbox_read_admin
  on public.notification_outbox for select to authenticated
  using (public.current_user_role() = 'administrator');

revoke all on function public.current_user_role() from public, anon, authenticated, service_role;
grant execute on function public.current_user_role() to authenticated;
revoke all on function public.next_work_order_number(timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.assign_work_order_number() from public, anon, authenticated, service_role;
revoke all on function public.set_row_updated_at() from public, anon, authenticated, service_role;
revoke all on function public.handle_new_auth_user() from public, anon, authenticated, service_role;

commit;

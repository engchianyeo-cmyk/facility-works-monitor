\set ON_ERROR_STOP on

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
grant usage on schema auth, public to anon, authenticated, service_role;

create table auth.users (
  id uuid primary key,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

create or replace function auth.uid()
returns uuid language sql stable set search_path = pg_catalog as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users(id),
  username text,
  full_name text,
  avatar_url text,
  website text,
  display_name text not null,
  email text,
  department text,
  role text not null,
  is_active boolean not null default true,
  trade_discipline text,
  contact_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create or replace function public.current_user_role()
returns text language sql stable security definer set search_path = pg_catalog as $$
  select role from public.profiles
  where id = auth.uid() and is_active = true and deleted_at is null
$$;

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.work_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  title text not null,
  description text,
  location text not null,
  category_id uuid references public.categories(id),
  priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
  status text not null default 'submitted' check (status in ('submitted','reviewed','approved','assigned','accepted','in_progress','completed','verified','closed','rejected')),
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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index work_orders_work_order_no_key on public.work_orders(work_order_no);

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
  created_at timestamptz not null default now()
);

create table public.work_order_number_counters (
  reference_year integer primary key,
  last_value integer not null check (last_value > 0)
);
create or replace function public.next_work_order_number(reference_time timestamptz default now())
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare reference_year integer := extract(year from reference_time at time zone 'UTC'); reference_value integer;
begin
  insert into public.work_order_number_counters values (reference_year, 1)
  on conflict (reference_year) do update set last_value = public.work_order_number_counters.last_value + 1
  returning last_value into reference_value;
  return format('FW-%s-%s', reference_year, lpad(reference_value::text, 4, '0'));
end $$;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.work_orders enable row level security;
alter table public.activity_logs enable row level security;
grant select on public.profiles, public.categories, public.work_orders, public.activity_logs to authenticated;

insert into auth.users (id,email) values
 ('10000000-0000-4000-8000-000000000001','admin@example.test'),
 ('10000000-0000-4000-8000-000000000002','approver@example.test'),
 ('10000000-0000-4000-8000-000000000003','reviewer@example.test'),
 ('10000000-0000-4000-8000-000000000004','tech@example.test'),
 ('10000000-0000-4000-8000-000000000005','inactive-tech@example.test'),
 ('10000000-0000-4000-8000-000000000006','supervisor@example.test');
insert into public.profiles (id,display_name,email,department,role,is_active) values
 ('10000000-0000-4000-8000-000000000001','Admin','admin@example.test','Facilities','administrator',true),
 ('10000000-0000-4000-8000-000000000002','Approver','approver@example.test','Facilities','approver',true),
 ('10000000-0000-4000-8000-000000000003','Reviewer','reviewer@example.test','Facilities','reviewer',true),
 ('10000000-0000-4000-8000-000000000004','Technician','tech@example.test','Facilities','technician',true),
 ('10000000-0000-4000-8000-000000000005','Inactive Technician','inactive-tech@example.test','Facilities','technician',false),
 ('10000000-0000-4000-8000-000000000006','Supervisor','supervisor@example.test','Facilities','supervisor',true);

insert into public.categories (id,name) values ('20000000-0000-4000-8000-000000000001','Mechanical');
insert into public.work_orders (id,user_id,title,location,priority,status,submitted_by,work_order_no) values
 ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','Legacy done','Plant','medium','completed','Reviewer','FW-2025-0042'),
 ('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003','Legacy reviewed','Plant','medium','reviewed','Reviewer','FW-2025-0043'),
 ('30000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003','Legacy rejected','Plant','medium','rejected','Reviewer','FW-2025-0044');
insert into public.work_order_number_counters values (2025,44),(2026,1);

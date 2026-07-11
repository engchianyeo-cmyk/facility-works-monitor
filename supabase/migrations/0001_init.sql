create table if not exists categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  name text not null,
  created_at timestamptz not null default now()
);

alter table categories enable row level security;
drop policy if exists "categories_v1_read" on categories;
create policy "categories_v1_read" on categories for select using (true);
drop policy if exists "categories_v1_write" on categories;
create policy "categories_v1_write" on categories for all using (true) with check (true);

insert into categories (id, name) values
  ('a1000000-0000-0000-0000-000000000001', 'Electrical'),
  ('a1000000-0000-0000-0000-000000000002', 'Plumbing'),
  ('a1000000-0000-0000-0000-000000000003', 'HVAC'),
  ('a1000000-0000-0000-0000-000000000004', 'Structural'),
  ('a1000000-0000-0000-0000-000000000005', 'Cleaning')
on conflict (id) do nothing;

create table if not exists work_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  title text not null,
  description text,
  location text not null,
  category_id uuid references categories(id),
  priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
  status text not null default 'submitted' check (status in ('submitted','approved','in_progress','done','rejected')),
  submitted_by text,
  assigned_to text,
  photo_url text,
  ai_priority_score numeric,
  ai_priority_source text,
  ai_priority_confidence numeric,
  ai_priority_review_status text default 'unreviewed',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table work_orders enable row level security;
drop policy if exists "work_orders_v1_read" on work_orders;
create policy "work_orders_v1_read" on work_orders for select using (true);
drop policy if exists "work_orders_v1_write" on work_orders;
create policy "work_orders_v1_write" on work_orders for all using (true) with check (true);

insert into work_orders (id, title, description, location, category_id, priority, status, submitted_by, created_at, updated_at) values
  ('b1000000-0000-0000-0000-000000000001', 'Broken fluorescent light in corridor', 'Two ceiling lights flickering and one fully out near stairwell B.', 'Block A – Corridor 2', 'a1000000-0000-0000-0000-000000000001', 'medium', 'submitted', 'John Reyes', now() - interval '3 hours', now() - interval '3 hours'),
  ('b1000000-0000-0000-0000-000000000002', 'Leaking pipe under kitchen sink', 'Water pooling under the sink in staff kitchen, needs urgent fix.', 'Ground Floor – Staff Kitchen', 'a1000000-0000-0000-0000-000000000002', 'high', 'approved', 'Maria Santos', now() - interval '1 day', now() - interval '2 hours'),
  ('b1000000-0000-0000-0000-000000000003', 'AC unit not cooling in Server Room', 'Temperature reading 28°C. Server room HVAC blowing warm air.', 'Basement – Server Room', 'a1000000-0000-0000-0000-000000000003', 'critical', 'in_progress', 'Carlos Mendez', now() - interval '2 days', now() - interval '1 hour'),
  ('b1000000-0000-0000-0000-000000000004', 'Cracked floor tile near entrance', 'Large crack in tile poses trip hazard at main lobby entrance.', 'Main Lobby', 'a1000000-0000-0000-0000-000000000004', 'medium', 'done', 'Ana Lim', now() - interval '5 days', now() - interval '1 day'),
  ('b1000000-0000-0000-0000-000000000005', 'Deep clean of restrooms on 3rd floor', 'Routine deep clean requested after renovation works completed.', '3rd Floor – Restrooms', 'a1000000-0000-0000-0000-000000000005', 'low', 'submitted', 'Ben Torres', now() - interval '30 minutes', now() - interval '30 minutes')
on conflict (id) do nothing;

create table if not exists activity_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  work_order_id uuid references work_orders(id) on delete cascade,
  action text not null,
  from_status text,
  to_status text,
  actor text,
  note text,
  ai_model text,
  ai_confidence numeric,
  created_at timestamptz not null default now()
);

alter table activity_logs enable row level security;
drop policy if exists "activity_logs_v1_read" on activity_logs;
create policy "activity_logs_v1_read" on activity_logs for select using (true);
drop policy if exists "activity_logs_v1_write" on activity_logs;
create policy "activity_logs_v1_write" on activity_logs for all using (true) with check (true);

insert into activity_logs (work_order_id, action, from_status, to_status, actor, note, created_at) values
  ('b1000000-0000-0000-0000-000000000002', 'status_change', 'submitted', 'approved', 'Facility Manager', 'Approved — technician scheduled for tomorrow morning.', now() - interval '2 hours'),
  ('b1000000-0000-0000-0000-000000000003', 'status_change', 'submitted', 'approved', 'Facility Manager', 'Critical priority approved immediately.', now() - interval '1 day 20 hours'),
  ('b1000000-0000-0000-0000-000000000003', 'status_change', 'approved', 'in_progress', 'Carlos Mendez', 'Technician on site, parts ordered.', now() - interval '1 hour'),
  ('b1000000-0000-0000-0000-000000000004', 'status_change', 'submitted', 'approved', 'Facility Manager', 'Approved, non-urgent.', now() - interval '4 days'),
  ('b1000000-0000-0000-0000-000000000004', 'status_change', 'approved', 'in_progress', 'Ana Lim', 'Started tile replacement.', now() - interval '3 days'),
  ('b1000000-0000-0000-0000-000000000004', 'status_change', 'in_progress', 'done', 'Ana Lim', 'Tile replaced and area cleared.', now() - interval '1 day')
on conflict do nothing;
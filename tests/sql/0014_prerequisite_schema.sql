\set ON_ERROR_STOP on
\ir 0013_prerequisite_schema.sql

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  event_type text not null,
  event_key text not null,
  recipient_user_id uuid references public.profiles(id) on delete restrict,
  recipient_email text,
  payload jsonb not null default '{}'::jsonb,
  delivery_status text not null default 'pending'
    check (delivery_status in ('pending','processing','sent','failed')),
  attempts integer not null default 0 check (attempts>=0),
  last_error text,
  available_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_outbox_event_recipient_key
    unique nulls not distinct(event_key,recipient_user_id,recipient_email)
);

create or replace function public.set_row_updated_at()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin new.updated_at:=now(); return new; end $$;

alter table public.notification_outbox enable row level security;
grant select on public.notification_outbox to authenticated;


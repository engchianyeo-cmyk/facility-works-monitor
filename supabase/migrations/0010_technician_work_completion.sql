-- ============================================================================
-- Facility Works Monitor
-- Migration 0010: Technician work-completion Stage 1 foundation
--
-- REVIEW ONLY. DO NOT APPLY UNTIL THE LIVE STATUS-CONSTRAINT PREFLIGHT OUTPUT
-- HAS BEEN CAPTURED AND REVIEWED.
--
-- This migration:
-- * is intentionally blocked until the exact deployed status constraint and
--   current status counts have been captured and reviewed;
-- * does not rewrite any work_orders row, including legacy done rows;
-- * adds completion, evidence, and notification-outbox schema;
-- * creates a private evidence bucket with no authenticated Storage policies;
-- * does not grant Technicians direct work_orders UPDATE access.
--
-- Email delivery is NOT implemented. notification_outbox rows remain pending
-- until a separately reviewed provider/worker confirms delivery.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Status-constraint preservation gate
-- ---------------------------------------------------------------------------
-- Run these read-only preflight queries separately and retain their output:
-- SELECT
--   con.conname AS constraint_name,
--   pg_get_constraintdef(con.oid) AS constraint_definition
-- FROM pg_constraint con
-- JOIN pg_class rel
--   ON rel.oid = con.conrelid
-- JOIN pg_namespace nsp
--   ON nsp.oid = rel.relnamespace
-- WHERE nsp.nspname = 'public'
--   AND rel.relname = 'work_orders'
--   AND con.contype = 'c';
--
-- SELECT status, COUNT(*) AS record_count
-- FROM public.work_orders
-- GROUP BY status
-- ORDER BY status;
--
-- No replacement constraint is proposed here. After the preflight output is
-- reviewed, a static CHECK definition must preserve every live permitted value
-- plus, at minimum:
--   submitted, approved, assigned, in_progress, completion_submitted,
--   completed, done, rejected.
-- Existing done rows must not be rewritten.
--
-- This deliberate exception makes the review-only migration fail before any
-- schema or Storage change can occur. Replace it only in a separately reviewed
-- revision containing the approved static constraint definition.
do $status_constraint_review_required$
begin
  raise exception
    'Migration 0010 blocked: capture and review the live work_orders constraints and status counts first';
end;
$status_constraint_review_required$;

-- ---------------------------------------------------------------------------
-- 1. Work-order lifecycle metadata
-- ---------------------------------------------------------------------------

alter table public.work_orders
  add column if not exists work_started_at timestamptz,
  add column if not exists completion_submitted_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists completed_by uuid,
  add column if not exists completion_rejected_at timestamptz,
  add column if not exists completion_rejected_by uuid,
  add column if not exists completion_rejection_reason text;

do $work_order_foreign_keys$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.work_orders'::regclass
      and conname = 'work_orders_completed_by_profile_fkey'
  ) then
    alter table public.work_orders
      add constraint work_orders_completed_by_profile_fkey
      foreign key (completed_by)
      references public.profiles(id)
      on delete restrict
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.work_orders'::regclass
      and conname = 'work_orders_completion_rejected_by_profile_fkey'
  ) then
    alter table public.work_orders
      add constraint work_orders_completion_rejected_by_profile_fkey
      foreign key (completion_rejected_by)
      references public.profiles(id)
      on delete restrict
      not valid;
  end if;
end;
$work_order_foreign_keys$;

do $validate_work_order_foreign_keys$
begin
  if not exists (
    select 1
    from public.work_orders as work_order
    left join public.profiles as profile
      on profile.id = work_order.completed_by
    where work_order.completed_by is not null
      and profile.id is null
  ) then
    alter table public.work_orders
      validate constraint work_orders_completed_by_profile_fkey;
  else
    raise notice
      'work_orders_completed_by_profile_fkey remains NOT VALID because legacy orphan references exist';
  end if;

  if not exists (
    select 1
    from public.work_orders as work_order
    left join public.profiles as profile
      on profile.id = work_order.completion_rejected_by
    where work_order.completion_rejected_by is not null
      and profile.id is null
  ) then
    alter table public.work_orders
      validate constraint work_orders_completion_rejected_by_profile_fkey;
  else
    raise notice
      'work_orders_completion_rejected_by_profile_fkey remains NOT VALID because legacy orphan references exist';
  end if;
end;
$validate_work_order_foreign_keys$;

-- ---------------------------------------------------------------------------
-- 2. Completion drafts and review records
-- ---------------------------------------------------------------------------

create table if not exists public.work_order_completions (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null
    references public.work_orders(id) on delete cascade,
  technician_id uuid not null
    references public.profiles(id) on delete restrict,
  work_performed text,
  findings text,
  corrective_action text,
  materials_used text,
  outstanding_work text,
  technician_comments text,
  safety_check_completed boolean not null default false,
  testing_result text,
  latitude numeric
    check (latitude is null or latitude between -90 and 90),
  longitude numeric
    check (longitude is null or longitude between -180 and 180),
  started_at timestamptz,
  finished_at timestamptz,
  signed_off boolean not null default false,
  signed_off_at timestamptz,
  submitted_at timestamptz,
  submission_version integer not null default 0
    check (submission_version >= 0),
  approval_status text not null default 'draft'
    check (approval_status in ('draft', 'submitted', 'rejected', 'approved')),
  approved_by uuid
    references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint work_order_completions_one_per_order unique (work_order_id),
  constraint work_order_completions_id_work_order_key
    unique (id, work_order_id)
);

create index if not exists work_order_completions_work_order_idx
  on public.work_order_completions (work_order_id);

create index if not exists work_order_completions_technician_idx
  on public.work_order_completions (technician_id);

-- ---------------------------------------------------------------------------
-- 3. Validated evidence metadata
-- ---------------------------------------------------------------------------

create or replace function public.storage_work_order_id(object_name text)
returns uuid
language plpgsql
immutable
set search_path = public, pg_temp
as $storage_path$
declare
  candidate text;
begin
  if object_name !~
    '^work-orders/[0-9a-fA-F-]+/(before|after|supporting)/[^/]+$'
  then
    return null;
  end if;

  candidate := split_part(object_name, '/', 2);

  if candidate !~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
  then
    return null;
  end if;

  return candidate::uuid;
end;
$storage_path$;

revoke execute on function public.storage_work_order_id(text) from public;
grant execute on function public.storage_work_order_id(text) to service_role;

create table if not exists public.work_order_evidence (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null
    references public.work_orders(id) on delete cascade,
  completion_id uuid,
  evidence_type text not null
    check (evidence_type in ('before', 'after', 'supporting')),
  storage_path text not null unique,
  original_file_name text,
  mime_type text,
  file_size bigint
    check (file_size is null or file_size between 1 and 10485760),
  uploaded_by uuid not null
    references public.profiles(id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  captured_at timestamptz,
  latitude numeric
    check (latitude is null or latitude between -90 and 90),
  longitude numeric
    check (longitude is null or longitude between -180 and 180),
  constraint work_order_evidence_path_matches_order_check
    check (public.storage_work_order_id(storage_path) = work_order_id)
);

do $evidence_foreign_key$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.work_order_evidence'::regclass
      and conname = 'work_order_evidence_completion_work_order_fkey'
  ) then
    alter table public.work_order_evidence
      add constraint work_order_evidence_completion_work_order_fkey
      foreign key (completion_id, work_order_id)
      references public.work_order_completions(id, work_order_id)
      on delete cascade
      not valid;
  end if;
end;
$evidence_foreign_key$;

do $validate_evidence_foreign_key$
begin
  if not exists (
    select 1
    from public.work_order_evidence as evidence
    left join public.work_order_completions as completion
      on completion.id = evidence.completion_id
      and completion.work_order_id = evidence.work_order_id
    where evidence.completion_id is not null
      and completion.id is null
  ) then
    alter table public.work_order_evidence
      validate constraint work_order_evidence_completion_work_order_fkey;
  else
    raise notice
      'work_order_evidence_completion_work_order_fkey remains NOT VALID because legacy mismatches exist';
  end if;
end;
$validate_evidence_foreign_key$;

create index if not exists work_order_evidence_work_order_idx
  on public.work_order_evidence (work_order_id);

create index if not exists work_order_evidence_completion_idx
  on public.work_order_evidence (completion_id);

create index if not exists work_order_evidence_uploaded_by_idx
  on public.work_order_evidence (uploaded_by);

-- ---------------------------------------------------------------------------
-- 4. Durable notification outbox (delivery is not implemented in Stage 1)
-- ---------------------------------------------------------------------------

create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null
    references public.work_orders(id) on delete cascade,
  event_type text not null,
  event_key text not null,
  recipient_user_id uuid
    references public.profiles(id) on delete restrict,
  recipient_email text,
  payload jsonb not null default '{}'::jsonb,
  delivery_status text not null default 'pending'
    check (delivery_status in ('pending', 'processing', 'sent', 'failed')),
  attempts integer not null default 0
    check (attempts >= 0),
  last_error text,
  available_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_outbox_event_recipient_key
    unique nulls not distinct (
      event_key,
      recipient_user_id,
      recipient_email
    )
);

comment on table public.notification_outbox is
  'Durable notification queue. Stage 1 creates queue records only; external email delivery is not implemented.';

create index if not exists notification_outbox_delivery_idx
  on public.notification_outbox (delivery_status, available_at);

-- ---------------------------------------------------------------------------
-- 5. updated_at maintenance
-- ---------------------------------------------------------------------------

create or replace function public.set_row_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $updated_at$
begin
  new.updated_at := now();
  return new;
end;
$updated_at$;

revoke execute on function public.set_row_updated_at() from public;

drop trigger if exists set_work_order_completions_updated_at
  on public.work_order_completions;

create trigger set_work_order_completions_updated_at
  before update on public.work_order_completions
  for each row execute function public.set_row_updated_at();

drop trigger if exists set_notification_outbox_updated_at
  on public.notification_outbox;

create trigger set_notification_outbox_updated_at
  before update on public.notification_outbox
  for each row execute function public.set_row_updated_at();

-- ---------------------------------------------------------------------------
-- 6. Private evidence bucket
-- ---------------------------------------------------------------------------
-- No authenticated Storage object policy is created in Stage 1. Stage 2 must
-- use protected server endpoints with explicit assignment/role validation and
-- the service role for upload, deletion, and short-lived signed URL creation.
--
-- Before application, review all existing Storage policies to confirm no
-- pre-existing bucket-agnostic policy would also cover this new bucket:
--
-- select policyname, cmd, roles, qual, with_check
-- from pg_policies
-- where schemaname = 'storage' and tablename = 'objects'
-- order by policyname;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'work-order-evidence',
  'work-order-evidence',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- 7. Stage 1 RLS
-- ---------------------------------------------------------------------------

alter table public.work_order_completions enable row level security;
alter table public.work_order_evidence enable row level security;
alter table public.notification_outbox enable row level security;

-- Preserve legacy-null visibility for Reviewer/Initiator accounts while
-- ensuring a Technician can read only the work order currently assigned to
-- their Auth UUID.
drop policy if exists "work_orders_read_permitted"
  on public.work_orders;

create policy "work_orders_read_permitted"
  on public.work_orders for select
  to authenticated
  using (
    (
      public.current_user_role() = 'technician'
      and assigned_technician_id = auth.uid()
    )
    or (
      public.current_user_role() in ('reviewer', 'initiator')
      and (
        user_id = auth.uid()
        or user_id is null
      )
    )
    or public.current_user_role() in (
      'approver',
      'supervisor',
      'administrator'
    )
  );

drop policy if exists "work_order_completions_read_authorized"
  on public.work_order_completions;

create policy "work_order_completions_read_authorized"
  on public.work_order_completions for select
  to authenticated
  using (
    exists (
      select 1
      from public.work_orders as work_order
      where work_order.id = work_order_completions.work_order_id
        and (
          (
            public.current_user_role() = 'technician'
            and work_order.assigned_technician_id = auth.uid()
            and work_order_completions.technician_id = auth.uid()
          )
          or public.current_user_role() in (
            'approver',
            'supervisor',
            'administrator'
          )
        )
    )
  );

-- Completion mutations are reserved for separately reviewed protected server
-- endpoints/functions. Authenticated browser clients receive read access only.
revoke insert, update, delete
  on public.work_order_completions
  from authenticated;

grant select
  on public.work_order_completions
  to authenticated;

drop policy if exists "work_order_evidence_read_authorized"
  on public.work_order_evidence;

create policy "work_order_evidence_read_authorized"
  on public.work_order_evidence for select
  to authenticated
  using (
    exists (
      select 1
      from public.work_orders as work_order
      where work_order.id = work_order_evidence.work_order_id
        and (
          (
            public.current_user_role() = 'technician'
            and work_order.assigned_technician_id = auth.uid()
          )
          or public.current_user_role() in (
            'approver',
            'supervisor',
            'administrator'
          )
        )
    )
  );

-- Evidence metadata mutations are reserved for protected Stage 2 server
-- endpoints. Authenticated clients receive SELECT only.
revoke insert, update, delete
  on public.work_order_evidence
  from authenticated;

grant select
  on public.work_order_evidence
  to authenticated;

drop policy if exists "notification_outbox_read_admin"
  on public.notification_outbox;

create policy "notification_outbox_read_admin"
  on public.notification_outbox for select
  to authenticated
  using (public.current_user_role() = 'administrator');

revoke insert, update, delete
  on public.notification_outbox
  from authenticated;

grant select
  on public.notification_outbox
  to authenticated;

-- No work_orders UPDATE policy is changed in Stage 1. Technician lifecycle
-- mutations require separately reviewed protected workflow functions/routes.
-- No new audit table is introduced; later lifecycle functions must write to
-- public.activity_logs and enqueue notification_outbox rows as queued only.

commit;

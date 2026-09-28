-- Core Work Order Engine.
-- Migration 0010 is intentionally unapplied and no object from it is required.
begin;

-- A prior successful execution may already have installed the immutable-state
-- trigger. Drop and recreate it transactionally around idempotent normalization.
drop trigger if exists protect_terminal_work_order on public.work_orders;

-- ---------------------------------------------------------------------------
-- Canonical reference data and assignment foundations
-- ---------------------------------------------------------------------------

create table if not exists public.vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  trade text,
  contact_name text,
  contact_email text,
  contact_phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.vendors add column if not exists active boolean not null default true;
alter table public.vendors add column if not exists updated_at timestamptz not null default now();
alter table public.vendors add column if not exists deleted_at timestamptz;
create index if not exists vendors_active_idx
  on public.vendors (active) where deleted_at is null;

create table if not exists public.maintenance_teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  department_id uuid references public.departments(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint maintenance_teams_name_nonempty_check
    check (pg_catalog.length(pg_catalog.btrim(name)) > 0)
);
create unique index if not exists maintenance_teams_name_active_unique_idx
  on public.maintenance_teams (pg_catalog.lower(name)) where deleted_at is null;

create table if not exists public.maintenance_team_members (
  team_id uuid not null references public.maintenance_teams(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (team_id, profile_id)
);

-- ---------------------------------------------------------------------------
-- Preserve legacy records while establishing canonical work-order columns
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = 'public.work_orders'::pg_catalog.regclass
      and attname = 'work_order_no' and not attisdropped
  ) and not exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = 'public.work_orders'::pg_catalog.regclass
      and attname = 'work_order_number' and not attisdropped
  ) then
    alter table public.work_orders rename column work_order_no to work_order_number;
    perform pg_catalog.set_config('fmworks.migration_0013_legacy_upgrade', 'on', true);
  end if;
end;
$$;

alter table public.work_orders
  add column if not exists work_order_number text,
  add column if not exists requested_by uuid,
  add column if not exists department_id uuid,
  add column if not exists site text,
  add column if not exists asset_id uuid,
  add column if not exists source text not null default 'manual',
  add column if not exists source_reference text,
  add column if not exists alert_id text,
  add column if not exists prediction_reference text,
  add column if not exists health_score_at_creation numeric,
  add column if not exists failure_probability numeric,
  add column if not exists predicted_failure_date date,
  add column if not exists recommended_action text,
  add column if not exists confidence_score numeric,
  add column if not exists due_date date,
  add column if not exists estimated_hours numeric,
  add column if not exists priority_rank smallint generated always as (
    case priority when 'low' then 1 when 'medium' then 2
      when 'high' then 3 when 'critical' then 4 else 0 end
  ) stored,
  add column if not exists actual_labour_hours numeric,
  add column if not exists completion_notes text,
  add column if not exists internal_notes text,
  add column if not exists cancellation_reason text,
  add column if not exists assigned_team_id uuid,
  add column if not exists assigned_by_user_id uuid,
  add column if not exists submitted_at timestamptz,
  add column if not exists approved_at timestamptz,
  add column if not exists started_at timestamptz,
  add column if not exists reviewed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists contact_number text,
  add column if not exists duplicated_from_id uuid;

update public.work_orders
set requested_by = user_id
where requested_by is null and user_id is not null;

-- Remove the legacy 0002 constraint before translating terminal statuses.
alter table public.work_orders drop constraint if exists work_orders_status_check;

update public.work_orders
set status = case status
  when 'done' then 'completed'
  when 'verified' then 'reviewed'
  when 'rejected' then 'cancelled'
  when 'accepted' then 'assigned'
  when 'reviewed' then 'submitted'
  else status
end
where coalesce(
  pg_catalog.current_setting('fmworks.migration_0013_legacy_upgrade', true),
  'off'
) = 'on';

update public.work_orders
set
  source = coalesce(nullif(pg_catalog.lower(pg_catalog.btrim(source)), ''), 'manual'),
  submitted_at = case when status <> 'draft' then coalesce(submitted_at, created_at) else submitted_at end,
  approved_at = case when status in ('approved','assigned','in_progress','completed','reviewed','closed') then coalesce(approved_at, updated_at, created_at) else approved_at end,
  assigned_at = case when status in ('assigned','in_progress','completed','reviewed','closed') then coalesce(assigned_at, updated_at, created_at) else assigned_at end,
  started_at = case when status in ('in_progress','completed','reviewed','closed') then coalesce(started_at, updated_at, created_at) else started_at end,
  completed_at = case when status in ('completed','reviewed','closed') then coalesce(completed_at, updated_at, created_at) else completed_at end,
  reviewed_at = case when status in ('reviewed','closed') then coalesce(reviewed_at, verified_at, updated_at, created_at) else reviewed_at end,
  closed_at = case when status = 'closed' then coalesce(closed_at, updated_at, created_at) else closed_at end,
  cancelled_at = case when status = 'cancelled' then coalesce(cancelled_at, updated_at, created_at) else cancelled_at end;

alter table public.work_orders drop constraint if exists work_orders_priority_check;
alter table public.work_orders drop constraint if exists work_orders_source_check;
alter table public.work_orders drop constraint if exists work_orders_hours_check;
alter table public.work_orders drop constraint if exists work_orders_predictive_ranges_check;
alter table public.work_orders drop constraint if exists work_orders_due_date_check;
alter table public.work_orders drop constraint if exists work_orders_primary_assignment_check;

alter table public.work_orders
  add constraint work_orders_status_check check (status in (
    'draft','submitted','approved','assigned','in_progress',
    'completed','reviewed','closed','cancelled'
  )),
  add constraint work_orders_priority_check
    check (priority in ('low','medium','high','critical')),
  add constraint work_orders_source_check check (source in (
    'manual','reactive','preventive','inspection','condition_based','predictive'
  )),
  add constraint work_orders_hours_check check (
    (estimated_hours is null or estimated_hours >= 0)
    and (actual_labour_hours is null or actual_labour_hours >= 0)
  ),
  add constraint work_orders_predictive_ranges_check check (
    (health_score_at_creation is null or health_score_at_creation between 0 and 100)
    and (failure_probability is null or failure_probability between 0 and 1)
    and (confidence_score is null or confidence_score between 0 and 1)
  ),
  add constraint work_orders_due_date_check check (
    due_date is null or due_date >= coalesce(submitted_at, created_at)::date
  ),
  add constraint work_orders_primary_assignment_check check (
    (case when assigned_technician_id is null then 0 else 1 end)
    + (case when assigned_vendor_id is null then 0 else 1 end)
    + (case when assigned_team_id is null then 0 else 1 end) <= 1
  );

do $$
begin
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.work_orders'::pg_catalog.regclass and conname = 'work_orders_requested_by_fkey') then
    alter table public.work_orders add constraint work_orders_requested_by_fkey
      foreign key (requested_by) references auth.users(id) on delete set null not valid;
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.work_orders'::pg_catalog.regclass and conname = 'work_orders_department_id_fkey') then
    alter table public.work_orders add constraint work_orders_department_id_fkey
      foreign key (department_id) references public.departments(id) on delete restrict not valid;
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.work_orders'::pg_catalog.regclass and conname = 'work_orders_assigned_vendor_fkey') then
    alter table public.work_orders add constraint work_orders_assigned_vendor_fkey
      foreign key (assigned_vendor_id) references public.vendors(id) on delete restrict not valid;
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.work_orders'::pg_catalog.regclass and conname = 'work_orders_assigned_team_fkey') then
    alter table public.work_orders add constraint work_orders_assigned_team_fkey
      foreign key (assigned_team_id) references public.maintenance_teams(id) on delete restrict not valid;
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.work_orders'::pg_catalog.regclass and conname = 'work_orders_assigned_by_user_fkey') then
    alter table public.work_orders add constraint work_orders_assigned_by_user_fkey
      foreign key (assigned_by_user_id) references auth.users(id) on delete set null not valid;
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.work_orders'::pg_catalog.regclass and conname = 'work_orders_duplicated_from_fkey') then
    alter table public.work_orders add constraint work_orders_duplicated_from_fkey
      foreign key (duplicated_from_id) references public.work_orders(id) on delete restrict not valid;
  end if;
end;
$$;

alter table public.work_orders validate constraint work_orders_requested_by_fkey;
alter table public.work_orders validate constraint work_orders_department_id_fkey;
alter table public.work_orders validate constraint work_orders_assigned_vendor_fkey;
alter table public.work_orders validate constraint work_orders_assigned_team_fkey;
alter table public.work_orders validate constraint work_orders_assigned_by_user_fkey;
alter table public.work_orders validate constraint work_orders_duplicated_from_fkey;

create unique index if not exists work_orders_work_order_number_key
  on public.work_orders (work_order_number);
create index if not exists work_orders_status_created_idx
  on public.work_orders (status, created_at desc);
create index if not exists work_orders_department_idx on public.work_orders (department_id);
create index if not exists work_orders_source_idx on public.work_orders (source);
create index if not exists work_orders_due_date_idx on public.work_orders (due_date);
create index if not exists work_orders_requested_by_idx on public.work_orders (requested_by);
create index if not exists work_orders_assigned_vendor_idx on public.work_orders (assigned_vendor_id);
create index if not exists work_orders_assigned_team_idx on public.work_orders (assigned_team_id);

drop index if exists public.work_orders_work_order_no_key;

-- Replace the legacy trigger after the column rename.
create or replace function public.next_work_order_number(
  reference_time timestamptz default pg_catalog.now()
)
returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_reference_year integer := extract(year from reference_time at time zone 'UTC');
  reference_value integer;
begin
  insert into public.work_order_number_counters (reference_year, last_value)
  values (v_reference_year, 1)
  on conflict (reference_year) do update
    set last_value = public.work_order_number_counters.last_value + 1
  returning last_value into reference_value;
  return pg_catalog.format(
    'FW-%s-%s', v_reference_year, pg_catalog.lpad(reference_value::text, 4, '0')
  );
end;
$$;

create or replace function public.assign_work_order_number()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.work_order_number is null or pg_catalog.btrim(new.work_order_number) = '' then
    new.work_order_number := public.next_work_order_number(
      coalesce(new.created_at, pg_catalog.now())
    );
  end if;
  return new;
end;
$$;
drop trigger if exists assign_work_order_number on public.work_orders;
create trigger assign_work_order_number
  before insert on public.work_orders
  for each row execute function public.assign_work_order_number();
alter table public.work_orders alter column work_order_number set not null;

-- ---------------------------------------------------------------------------
-- Shared security helpers and immutable terminal-state protection
-- ---------------------------------------------------------------------------

create or replace function public.work_order_actor()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select pg_catalog.jsonb_build_object(
    'id', profile.id,
    'name', profile.display_name,
    'role', profile.role,
    'department_id', profile.department_id
  )
  from public.profiles as profile
  where profile.id = auth.uid()
    and profile.is_active = true
    and profile.deleted_at is null
$$;

-- Harden the authoritative 0007 role helper without changing its contract.
create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select profile.role
  from public.profiles as profile
  where profile.id = auth.uid()
    and profile.is_active = true
    and profile.deleted_at is null
$$;

create or replace function public.protect_terminal_work_order()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if old.status in ('closed', 'cancelled')
    and coalesce(
      pg_catalog.current_setting('fmworks.admin_correction', true),
      'off'
    ) <> 'on'
  then
    raise exception using errcode = '55000', message = 'TERMINAL_IMMUTABLE';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_terminal_work_order on public.work_orders;
create trigger protect_terminal_work_order
  before update or delete on public.work_orders
  for each row execute function public.protect_terminal_work_order();

create or replace function public.work_order_result_error(p_code text, p_message text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select pg_catalog.jsonb_build_object(
    'ok', false,
    'code', p_code,
    'message', p_message
  )
$$;

-- ---------------------------------------------------------------------------
-- Transaction-safe mutations
-- ---------------------------------------------------------------------------

create or replace function public.create_work_order(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  requested_status text := pg_catalog.lower(coalesce(p_payload ->> 'status', 'draft'));
  requested_source text := pg_catalog.lower(coalesce(p_payload ->> 'source', 'manual'));
  result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid;
  actor_name := actor ->> 'name';
  actor_role := actor ->> 'role';
  if actor_role = 'technician' then return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot create work orders.'); end if;
  if requested_status not in ('draft', 'submitted') then return public.work_order_result_error('VALIDATION_ERROR', 'A new work order must be Draft or Submitted.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', ''))) < 3
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', ''))) > 200
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'location', ''))) = 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'Title and location are required.'); end if;
  if pg_catalog.lower(coalesce(p_payload ->> 'priority', 'medium')) not in ('low','medium','high','critical')
    or requested_source not in ('manual','reactive','preventive','inspection','condition_based','predictive')
  then return public.work_order_result_error('VALIDATION_ERROR', 'Priority or source is invalid.'); end if;
  if p_payload ? 'estimated_hours' and (p_payload ->> 'estimated_hours')::numeric < 0
    or p_payload ? 'health_score_at_creation' and (p_payload ->> 'health_score_at_creation')::numeric not between 0 and 100
    or p_payload ? 'failure_probability' and (p_payload ->> 'failure_probability')::numeric not between 0 and 1
    or p_payload ? 'confidence_score' and (p_payload ->> 'confidence_score')::numeric not between 0 and 1
  then return public.work_order_result_error('VALIDATION_ERROR', 'A numeric work-order value is outside its allowed range.'); end if;
  if nullif(p_payload ->> 'department_id', '') is not null and not exists (
    select 1 from public.departments where id = (p_payload ->> 'department_id')::uuid and is_active = true and deleted_at is null
  ) then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected department is unavailable.'); end if;

  begin
    insert into public.work_orders (
      user_id, requested_by, title, description, location, site, category_id,
      priority, status, source, source_reference, alert_id, prediction_reference,
      asset_id, health_score_at_creation, failure_probability,
      predicted_failure_date, recommended_action, confidence_score,
      department_id, due_date, estimated_hours, internal_notes,
      submitted_by, submitted_at, contact_number
    ) values (
      actor_id, actor_id,
      pg_catalog.btrim(p_payload ->> 'title'),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'description', '')), ''),
      pg_catalog.btrim(p_payload ->> 'location'),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'site', '')), ''),
      nullif(p_payload ->> 'category_id', '')::uuid,
      pg_catalog.lower(coalesce(p_payload ->> 'priority', 'medium')),
      requested_status, requested_source,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'source_reference', '')), ''),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'alert_id', '')), ''),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'prediction_reference', '')), ''),
      nullif(p_payload ->> 'asset_id', '')::uuid,
      nullif(p_payload ->> 'health_score_at_creation', '')::numeric,
      nullif(p_payload ->> 'failure_probability', '')::numeric,
      nullif(p_payload ->> 'predicted_failure_date', '')::date,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'recommended_action', '')), ''),
      nullif(p_payload ->> 'confidence_score', '')::numeric,
      nullif(p_payload ->> 'department_id', '')::uuid,
      nullif(p_payload ->> 'due_date', '')::date,
      nullif(p_payload ->> 'estimated_hours', '')::numeric,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'internal_notes', '')), ''),
      actor_name,
      case when requested_status = 'submitted' then pg_catalog.now() else null end,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'contact_number', '')), '')
    ) returning * into result;

    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (
      actor_id, result.id, 'work_order_created', null, result.status, actor_name,
      pg_catalog.jsonb_build_object('source', result.source, 'submitted', result.status = 'submitted')::text
    );
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception
    when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
      return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
    when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order creation failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order creation failed.');
end;
$$;

create or replace function public.update_work_order(p_work_order_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  previous public.work_orders%rowtype;
  result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Closed and cancelled work orders are immutable.'); end if;
  if actor_role <> 'administrator' and not (actor_id = previous.requested_by and actor_role in ('reviewer','initiator') and previous.status = 'draft') then
    return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot edit this work order.');
  end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', previous.title))) < 3
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'location', previous.location))) = 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'Title and location are required.'); end if;
  if nullif(p_payload ->> 'department_id', '') is not null and not exists (
    select 1 from public.departments where id = (p_payload ->> 'department_id')::uuid and is_active = true and deleted_at is null
  ) then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected department is unavailable.'); end if;

  begin
    update public.work_orders set
      title = pg_catalog.btrim(coalesce(p_payload ->> 'title', title)),
      description = case when p_payload ? 'description' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'description', '')), '') else description end,
      location = pg_catalog.btrim(coalesce(p_payload ->> 'location', location)),
      site = case when p_payload ? 'site' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'site', '')), '') else site end,
      category_id = case when p_payload ? 'category_id' then nullif(p_payload ->> 'category_id', '')::uuid else category_id end,
      priority = case when p_payload ? 'priority' then pg_catalog.lower(p_payload ->> 'priority') else priority end,
      source = case when p_payload ? 'source' then pg_catalog.lower(p_payload ->> 'source') else source end,
      department_id = case when p_payload ? 'department_id' then nullif(p_payload ->> 'department_id', '')::uuid else department_id end,
      asset_id = case when p_payload ? 'asset_id' then nullif(p_payload ->> 'asset_id', '')::uuid else asset_id end,
      source_reference = case when p_payload ? 'source_reference' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'source_reference', '')), '') else source_reference end,
      alert_id = case when p_payload ? 'alert_id' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'alert_id', '')), '') else alert_id end,
      prediction_reference = case when p_payload ? 'prediction_reference' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'prediction_reference', '')), '') else prediction_reference end,
      health_score_at_creation = case when p_payload ? 'health_score_at_creation' then nullif(p_payload ->> 'health_score_at_creation', '')::numeric else health_score_at_creation end,
      failure_probability = case when p_payload ? 'failure_probability' then nullif(p_payload ->> 'failure_probability', '')::numeric else failure_probability end,
      predicted_failure_date = case when p_payload ? 'predicted_failure_date' then nullif(p_payload ->> 'predicted_failure_date', '')::date else predicted_failure_date end,
      recommended_action = case when p_payload ? 'recommended_action' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'recommended_action', '')), '') else recommended_action end,
      confidence_score = case when p_payload ? 'confidence_score' then nullif(p_payload ->> 'confidence_score', '')::numeric else confidence_score end,
      due_date = case when p_payload ? 'due_date' then nullif(p_payload ->> 'due_date', '')::date else due_date end,
      estimated_hours = case when p_payload ? 'estimated_hours' then nullif(p_payload ->> 'estimated_hours', '')::numeric else estimated_hours end,
      internal_notes = case when p_payload ? 'internal_notes' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'internal_notes', '')), '') else internal_notes end,
      contact_number = case when p_payload ? 'contact_number' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'contact_number', '')), '') else contact_number end,
      updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, actor, note)
    values (actor_id, result.id, 'work_order_updated', actor_name,
      pg_catalog.jsonb_build_object('before', pg_catalog.to_jsonb(previous), 'after', pg_catalog.to_jsonb(result))::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when check_violation or invalid_text_representation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order update failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order update failed.');
end;
$$;

create or replace function public.assign_work_order(
  p_work_order_id uuid,
  p_assignment_type text,
  p_assignee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  previous public.work_orders%rowtype; result public.work_orders%rowtype; assignee_name text;
  mode text := pg_catalog.lower(coalesce(p_assignment_type, ''));
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  if actor_role not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot assign work orders.'); end if;
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status not in ('approved','assigned') then return public.work_order_result_error('INVALID_TRANSITION', 'Assignment is allowed only after approval.'); end if;
  if mode = 'technician' then
    select display_name into assignee_name from public.profiles where id = p_assignee_id and role = 'technician' and is_active = true and deleted_at is null;
  elsif mode = 'vendor' then
    select name into assignee_name from public.vendors where id = p_assignee_id and active = true and deleted_at is null;
  elsif mode = 'team' then
    select name into assignee_name from public.maintenance_teams where id = p_assignee_id and is_active = true and deleted_at is null;
  else return public.work_order_result_error('INVALID_ASSIGNMENT', 'Assignment type is invalid.');
  end if;
  if assignee_name is null then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected assignee is unavailable.'); end if;
  if previous.status = 'assigned' and (
    (mode = 'technician' and previous.assigned_technician_id = p_assignee_id and previous.assigned_vendor_id is null and previous.assigned_team_id is null)
    or (mode = 'vendor' and previous.assigned_vendor_id = p_assignee_id and previous.assigned_technician_id is null and previous.assigned_team_id is null)
    or (mode = 'team' and previous.assigned_team_id = p_assignee_id and previous.assigned_technician_id is null and previous.assigned_vendor_id is null)
  ) then
    return pg_catalog.jsonb_build_object(
      'ok', true,
      'code', 'NO_CHANGE',
      'message', 'The work order is already assigned to this assignee.',
      'work_order', pg_catalog.to_jsonb(previous)
    );
  end if;
  begin
    update public.work_orders set
      assigned_technician_id = case when mode = 'technician' then p_assignee_id else null end,
      assigned_vendor_id = case when mode = 'vendor' then p_assignee_id else null end,
      assigned_team_id = case when mode = 'team' then p_assignee_id else null end,
      assigned_to = assignee_name, assigned_by = actor_name, assigned_by_user_id = actor_id,
      assigned_at = pg_catalog.now(), accepted_at = null, status = 'assigned', updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, result.id, case when previous.status = 'assigned' then 'work_order_reassigned' else 'work_order_assigned' end,
      previous.status, result.status, actor_name,
      pg_catalog.jsonb_build_object('assignment_type', mode, 'assignee_id', p_assignee_id, 'assignee_name', assignee_name)::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Work-order assignment failed.'); end;
end;
$$;

create or replace function public.transition_work_order(
  p_work_order_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  previous public.work_orders%rowtype; result public.work_orders%rowtype;
  action text := pg_catalog.lower(coalesce(p_action, '')); target_status text;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Closed and cancelled work orders are immutable.'); end if;

  target_status := case action
    when 'submit' then 'submitted' when 'approve' then 'approved'
    when 'start' then 'in_progress' when 'complete' then 'completed'
    when 'review' then 'reviewed' when 'close' then 'closed'
    when 'cancel' then 'cancelled' when 'accept' then 'assigned' else null end;
  if target_status is null or not (
    (action = 'submit' and previous.status = 'draft')
    or (action = 'approve' and previous.status = 'submitted')
    or (action = 'accept' and previous.status = 'assigned' and previous.accepted_at is null)
    or (action = 'start' and previous.status = 'assigned' and previous.accepted_at is not null)
    or (action = 'complete' and previous.status = 'in_progress')
    or (action = 'review' and previous.status = 'completed')
    or (action = 'close' and previous.status = 'reviewed')
    or (action = 'cancel' and previous.status in ('draft','submitted','approved','assigned','in_progress','completed','reviewed'))
  ) then return public.work_order_result_error('INVALID_TRANSITION', 'The requested workflow transition is not allowed.'); end if;

  if action = 'submit' and not (actor_id = previous.requested_by and actor_role in ('reviewer','initiator','approver','supervisor')) and actor_role <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the requester may submit this work order.');
  elsif action in ('approve','review','close') and actor_role not in ('approver','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Approver or Administrator authority is required.');
  elsif action = 'approve' and actor_id = previous.requested_by then
    if actor_role <> 'administrator' then return public.work_order_result_error('SELF_APPROVAL_DENIED', 'Requesters cannot approve their own work orders.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-approval requires an override reason.'); end if;
  elsif action in ('accept','start','complete') and actor_role <> 'administrator' and not (actor_role = 'technician' and actor_id = previous.assigned_technician_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the assigned technician or an Administrator may perform this action.');
  elsif action = 'cancel' and actor_role not in ('approver','supervisor','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot cancel work orders.');
  end if;
  if action = 'cancel' and reason is null then return public.work_order_result_error('CANCELLATION_REASON_REQUIRED', 'A cancellation reason is required.'); end if;
  if action = 'complete' and (
    nullif(pg_catalog.btrim(coalesce(p_payload ->> 'completion_notes', '')), '') is null
    or nullif(p_payload ->> 'actual_labour_hours', '')::numeric is null
    or nullif(p_payload ->> 'actual_labour_hours', '')::numeric < 0
  ) then return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Completion notes and non-negative actual labour hours are required.'); end if;

  begin
    update public.work_orders set
      status = target_status,
      submitted_at = case when action = 'submit' then pg_catalog.now() else submitted_at end,
      approved_at = case when action = 'approve' then pg_catalog.now() else approved_at end,
      accepted_at = case when action = 'accept' then pg_catalog.now() else accepted_at end,
      started_at = case when action = 'start' then pg_catalog.now() else started_at end,
      completed_at = case when action = 'complete' then pg_catalog.now() else completed_at end,
      reviewed_at = case when action = 'review' then pg_catalog.now() else reviewed_at end,
      closed_at = case when action = 'close' then pg_catalog.now() else closed_at end,
      cancelled_at = case when action = 'cancel' then pg_catalog.now() else cancelled_at end,
      completion_notes = case when action = 'complete' then pg_catalog.btrim(p_payload ->> 'completion_notes') else completion_notes end,
      actual_labour_hours = case when action = 'complete' then (p_payload ->> 'actual_labour_hours')::numeric else actual_labour_hours end,
      cancellation_reason = case when action = 'cancel' then reason else cancellation_reason end,
      updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, result.id, 'work_order_' || action, previous.status, result.status, actor_name,
      pg_catalog.jsonb_build_object('reason', reason, 'payload', p_payload,
        'administrator_override', action = 'approve' and actor_id = previous.requested_by and actor_role = 'administrator')::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Work-order transition failed.'); end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more transition values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order transition failed.');
end;
$$;

create or replace function public.duplicate_work_order(p_work_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  source_order public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  if actor_role = 'technician' then return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot duplicate work orders.'); end if;
  select * into source_order from public.work_orders where id = p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  begin
    insert into public.work_orders (
      user_id, requested_by, title, description, location, site, category_id,
      priority, status, source, source_reference, alert_id, prediction_reference,
      asset_id, health_score_at_creation, failure_probability,
      predicted_failure_date, recommended_action, confidence_score,
      department_id, due_date, estimated_hours, internal_notes,
      submitted_by, contact_number, duplicated_from_id
    ) values (
      actor_id, actor_id, source_order.title, source_order.description,
      source_order.location, source_order.site, source_order.category_id,
      source_order.priority, 'draft', source_order.source,
      source_order.source_reference, source_order.alert_id, source_order.prediction_reference,
      source_order.asset_id, source_order.health_score_at_creation,
      source_order.failure_probability, source_order.predicted_failure_date,
      source_order.recommended_action, source_order.confidence_score,
      source_order.department_id, source_order.due_date, source_order.estimated_hours,
      source_order.internal_notes, actor_name, source_order.contact_number, source_order.id
    ) returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, actor, note)
    values (actor_id, result.id, 'work_order_duplicated', actor_name,
      pg_catalog.jsonb_build_object('source_work_order_id', source_order.id, 'source_work_order_number', source_order.work_order_number)::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Work-order duplication failed.'); end;
end;
$$;

create or replace function public.admin_correct_work_order(
  p_work_order_id uuid,
  p_changes jsonb,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; previous public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if actor is null or actor ->> 'role' <> 'administrator' then return public.work_order_result_error('ACCESS_DENIED', 'Administrator authority is required.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_reason, '')), '') is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'An administrative correction reason is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name';
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  begin
    perform pg_catalog.set_config('fmworks.admin_correction', 'on', true);
    update public.work_orders set
      title = case when p_changes ? 'title' then pg_catalog.btrim(p_changes ->> 'title') else title end,
      description = case when p_changes ? 'description' then nullif(pg_catalog.btrim(coalesce(p_changes ->> 'description', '')), '') else description end,
      location = case when p_changes ? 'location' then pg_catalog.btrim(p_changes ->> 'location') else location end,
      internal_notes = case when p_changes ? 'internal_notes' then nullif(pg_catalog.btrim(coalesce(p_changes ->> 'internal_notes', '')), '') else internal_notes end,
      cancellation_reason = case when p_changes ? 'cancellation_reason' then nullif(pg_catalog.btrim(coalesce(p_changes ->> 'cancellation_reason', '')), '') else cancellation_reason end,
      updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, result.id, 'work_order_admin_corrected', previous.status, result.status, actor_name,
      pg_catalog.jsonb_build_object('reason', pg_catalog.btrim(p_reason), 'before', pg_catalog.to_jsonb(previous), 'after', pg_catalog.to_jsonb(result))::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Administrative correction failed.'); end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Read policies and least-privilege execution grants
-- ---------------------------------------------------------------------------

create or replace function public.list_public_work_orders()
returns table (
  id uuid,
  work_order_number text,
  title text,
  location text,
  site text,
  category_name text,
  priority text,
  status text,
  source text,
  due_date date,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select
    work_order.id,
    work_order.work_order_number,
    work_order.title,
    work_order.location,
    work_order.site,
    category.name,
    work_order.priority,
    work_order.status,
    work_order.source,
    work_order.due_date,
    work_order.created_at
  from public.work_orders as work_order
  left join public.categories as category on category.id = work_order.category_id
  where work_order.status <> 'draft'
  order by work_order.created_at desc
  limit 200
$$;

alter table public.vendors enable row level security;
alter table public.maintenance_teams enable row level security;
alter table public.maintenance_team_members enable row level security;

revoke all on public.work_orders from anon, authenticated;
grant select on public.work_orders to authenticated;
revoke insert, update, delete on public.activity_logs from anon, authenticated;
revoke all on public.vendors, public.maintenance_teams, public.maintenance_team_members from anon;
grant select on public.vendors, public.maintenance_teams, public.maintenance_team_members to authenticated;

drop policy if exists work_orders_create_authenticated on public.work_orders;
drop policy if exists work_orders_update_permitted on public.work_orders;
drop policy if exists work_orders_delete_admin on public.work_orders;
drop policy if exists work_orders_read_permitted on public.work_orders;
create policy work_orders_read_permitted on public.work_orders for select to authenticated using (
  requested_by = auth.uid()
  or assigned_technician_id = auth.uid()
  or public.current_user_role() in ('approver','supervisor','administrator')
);
drop policy if exists activity_logs_create_authenticated on public.activity_logs;

drop policy if exists vendors_authenticated_read on public.vendors;
create policy vendors_authenticated_read on public.vendors for select to authenticated using (active = true and deleted_at is null);
drop policy if exists maintenance_teams_authenticated_read on public.maintenance_teams;
create policy maintenance_teams_authenticated_read on public.maintenance_teams for select to authenticated using (is_active = true and deleted_at is null);
drop policy if exists maintenance_team_members_authenticated_read on public.maintenance_team_members;
create policy maintenance_team_members_authenticated_read on public.maintenance_team_members for select to authenticated using (is_active = true);

drop policy if exists profiles_active_technicians_for_assigners on public.profiles;
create policy profiles_active_technicians_for_assigners on public.profiles
  for select to authenticated using (
    role = 'technician' and is_active = true and deleted_at is null
    and public.current_user_role() in ('approver','supervisor','administrator')
  );

revoke all on function public.assign_work_order_number() from public, anon, authenticated, service_role;
revoke all on function public.next_work_order_number(timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.work_order_actor() from public, anon, authenticated, service_role;
revoke all on function public.current_user_role() from public, anon, authenticated, service_role;
grant execute on function public.current_user_role() to authenticated;
revoke all on function public.protect_terminal_work_order() from public, anon, authenticated, service_role;
revoke all on function public.work_order_result_error(text, text) from public, anon, authenticated, service_role;

revoke all on function public.create_work_order(jsonb) from public, anon, service_role;
revoke all on function public.update_work_order(uuid, jsonb) from public, anon, service_role;
revoke all on function public.assign_work_order(uuid, text, uuid) from public, anon, service_role;
revoke all on function public.transition_work_order(uuid, text, jsonb) from public, anon, service_role;
revoke all on function public.duplicate_work_order(uuid) from public, anon, service_role;
revoke all on function public.admin_correct_work_order(uuid, jsonb, text) from public, anon, service_role;
revoke all on function public.list_public_work_orders() from public, anon, authenticated, service_role;

grant execute on function public.create_work_order(jsonb) to authenticated;
grant execute on function public.update_work_order(uuid, jsonb) to authenticated;
grant execute on function public.assign_work_order(uuid, text, uuid) to authenticated;
grant execute on function public.transition_work_order(uuid, text, jsonb) to authenticated;
grant execute on function public.duplicate_work_order(uuid) to authenticated;
grant execute on function public.admin_correct_work_order(uuid, jsonb, text) to authenticated;
grant execute on function public.list_public_work_orders() to anon, authenticated;

commit;

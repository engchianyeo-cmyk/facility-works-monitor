-- Department management foundation.
-- Preserves profiles.department during staged normalization.
begin;
create extension if not exists pgcrypto;

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  description text,
  cost_centre text,
  manager_id uuid references public.profiles(id) on delete set null,
  parent_department_id uuid references public.departments(id) on delete set null,
  colour_tag text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint departments_code_nonempty_check check (length(trim(code)) > 0),
  constraint departments_name_nonempty_check check (length(trim(name)) > 0),
  constraint departments_colour_tag_check check (colour_tag is null or colour_tag ~ '^#[0-9A-Fa-f]{6}$'),
  constraint departments_not_own_parent_check check (parent_department_id is null or parent_department_id <> id)
);

create unique index if not exists departments_code_active_unique_idx
  on public.departments (lower(code)) where deleted_at is null;
create unique index if not exists departments_name_active_unique_idx
  on public.departments (lower(name)) where deleted_at is null;
create index if not exists departments_manager_idx
  on public.departments (manager_id) where deleted_at is null;
create index if not exists departments_parent_idx
  on public.departments (parent_department_id) where deleted_at is null;

alter table public.profiles add column if not exists department_id uuid;

with legacy_departments as (
  select distinct on (lower(trim(profile.department)))
    lower(trim(profile.department)) as normalized_name,
    trim(profile.department) as department_name
  from public.profiles as profile
  where nullif(trim(profile.department), '') is not null
  order by lower(trim(profile.department)), trim(profile.department)
)
insert into public.departments (code, name, description, is_active)
select
  upper(
    coalesce(
      nullif(
        left(
          trim(both '-' from regexp_replace(legacy.department_name, '[^A-Za-z0-9]+', '-', 'g')),
          17
        ),
        ''
      ),
      'DEPT'
    )
  ) || '-' || upper(left(md5(legacy.normalized_name), 6)),
  legacy.department_name,
  'Migrated from legacy profile department values.',
  true
from legacy_departments as legacy
where not exists (
    select 1 from public.departments d
    where lower(d.name) = legacy.normalized_name and d.deleted_at is null
  );

update public.profiles p
set department_id = d.id
from public.departments d
where p.department_id is null
  and nullif(trim(p.department), '') is not null
  and lower(d.name) = lower(trim(p.department))
  and d.deleted_at is null;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_department_id_fkey'
  ) then
    alter table public.profiles
      add constraint profiles_department_id_fkey
      foreign key (department_id) references public.departments(id)
      on delete set null not valid;
  end if;
end $$;
alter table public.profiles validate constraint profiles_department_id_fkey;
create index if not exists profiles_department_id_idx
  on public.profiles (department_id) where deleted_at is null;

create or replace function public.set_department_updated_at()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  new.code := upper(trim(new.code));
  new.name := trim(new.name);
  new.description := nullif(trim(new.description), '');
  new.cost_centre := nullif(trim(new.cost_centre), '');
  new.colour_tag := nullif(trim(new.colour_tag), '');
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists set_department_updated_at on public.departments;
create trigger set_department_updated_at
  before insert or update on public.departments
  for each row execute function public.set_department_updated_at();

create or replace function public.sync_profile_department_label()
returns trigger language plpgsql security definer set search_path = pg_catalog as $$
begin
  if new.department_id is null then return new; end if;
  select d.name into new.department
  from public.departments d
  where d.id = new.department_id and d.deleted_at is null;
  if new.department is null then raise exception 'Selected department is unavailable'; end if;
  return new;
end $$;
drop trigger if exists sync_profile_department_label on public.profiles;
create trigger sync_profile_department_label
  before insert or update of department_id on public.profiles
  for each row execute function public.sync_profile_department_label();

alter table public.departments enable row level security;
revoke all on public.departments from anon;
revoke all on public.departments from authenticated;
grant select on public.departments to authenticated;

drop policy if exists departments_authenticated_read on public.departments;
create policy departments_authenticated_read on public.departments
  for select to authenticated
  using (deleted_at is null or public.current_user_role() = 'administrator');

drop policy if exists departments_administrator_insert on public.departments;
drop policy if exists departments_administrator_update on public.departments;

revoke all on function public.set_department_updated_at() from public, anon, authenticated;
revoke all on function public.sync_profile_department_label() from public, anon, authenticated;

-- Department mutations are exposed only through these transaction-safe RPCs.
-- Expected failures use a small structured result so callers do not receive
-- raw constraint details. Unexpected failures roll back the mutation and audit
-- insert together inside the PL/pgSQL exception subtransaction.
create or replace function public.create_department(
  p_code text,
  p_name text,
  p_description text default null,
  p_cost_centre text default null,
  p_manager_id uuid default null,
  p_parent_department_id uuid default null,
  p_colour_tag text default null,
  p_is_active boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  actor_name text;
  normalized_code text := upper(trim(coalesce(p_code, '')));
  normalized_name text := trim(coalesce(p_name, ''));
  normalized_colour text := nullif(trim(coalesce(p_colour_tag, '')), '');
  result public.departments%rowtype;
begin
  select profile.display_name
    into actor_name
  from public.profiles as profile
  where profile.id = actor_id
    and profile.role = 'administrator'
    and profile.is_active = true
    and profile.deleted_at is null;

  if actor_name is null then
    return jsonb_build_object('ok', false, 'code', 'access_denied', 'message', 'Administrator access is required.');
  end if;
  if normalized_code !~ '^[A-Z0-9][A-Z0-9_-]{0,23}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_code', 'message', 'Department code is invalid.');
  end if;
  if normalized_name = '' or length(normalized_name) > 120 then
    return jsonb_build_object('ok', false, 'code', 'invalid_name', 'message', 'Department name is invalid.');
  end if;
  if normalized_colour is not null and normalized_colour !~ '^#[0-9A-Fa-f]{6}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_colour', 'message', 'Department colour is invalid.');
  end if;
  if p_parent_department_id is not null and not exists (
    select 1 from public.departments
    where id = p_parent_department_id and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_parent', 'message', 'Parent department is unavailable.');
  end if;
  if p_manager_id is not null and not exists (
    select 1 from public.profiles
    where id = p_manager_id and is_active = true and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_manager', 'message', 'Department manager is unavailable.');
  end if;
  if exists (
    select 1 from public.departments
    where deleted_at is null
      and (lower(code) = lower(normalized_code) or lower(name) = lower(normalized_name))
  ) then
    return jsonb_build_object('ok', false, 'code', 'duplicate_department', 'message', 'An active department already uses that code or name.');
  end if;

  begin
    insert into public.departments (
      code, name, description, cost_centre, manager_id,
      parent_department_id, colour_tag, is_active, created_by
    ) values (
      normalized_code,
      normalized_name,
      nullif(trim(coalesce(p_description, '')), ''),
      nullif(trim(coalesce(p_cost_centre, '')), ''),
      p_manager_id,
      p_parent_department_id,
      normalized_colour,
      coalesce(p_is_active, true),
      actor_id
    ) returning * into result;

    insert into public.activity_logs (user_id, action, actor, note)
    values (
      actor_id,
      'department_admin_created',
      actor_name,
      jsonb_build_object('department_id', result.id, 'code', result.code, 'name', result.name)::text
    );

    return jsonb_build_object('ok', true, 'department', to_jsonb(result));
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'code', 'duplicate_department', 'message', 'An active department already uses that code or name.');
    when foreign_key_violation then
      return jsonb_build_object('ok', false, 'code', 'invalid_reference', 'message', 'A selected department reference is unavailable.');
    when others then
      return jsonb_build_object('ok', false, 'code', 'internal_error', 'message', 'Department creation failed.');
  end;
end;
$$;

create or replace function public.update_department(
  p_department_id uuid,
  p_code text,
  p_name text,
  p_description text default null,
  p_cost_centre text default null,
  p_manager_id uuid default null,
  p_parent_department_id uuid default null,
  p_colour_tag text default null,
  p_is_active boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  actor_name text;
  normalized_code text := upper(trim(coalesce(p_code, '')));
  normalized_name text := trim(coalesce(p_name, ''));
  normalized_colour text := nullif(trim(coalesce(p_colour_tag, '')), '');
  previous public.departments%rowtype;
  result public.departments%rowtype;
begin
  select profile.display_name
    into actor_name
  from public.profiles as profile
  where profile.id = actor_id
    and profile.role = 'administrator'
    and profile.is_active = true
    and profile.deleted_at is null;

  if actor_name is null then
    return jsonb_build_object('ok', false, 'code', 'access_denied', 'message', 'Administrator access is required.');
  end if;
  if p_department_id is null then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'message', 'Department not found.');
  end if;
  if normalized_code !~ '^[A-Z0-9][A-Z0-9_-]{0,23}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_code', 'message', 'Department code is invalid.');
  end if;
  if normalized_name = '' or length(normalized_name) > 120 then
    return jsonb_build_object('ok', false, 'code', 'invalid_name', 'message', 'Department name is invalid.');
  end if;
  if normalized_colour is not null and normalized_colour !~ '^#[0-9A-Fa-f]{6}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_colour', 'message', 'Department colour is invalid.');
  end if;
  if p_parent_department_id = p_department_id then
    return jsonb_build_object('ok', false, 'code', 'self_parent', 'message', 'A department cannot be its own parent.');
  end if;
  if p_parent_department_id is not null and not exists (
    select 1 from public.departments
    where id = p_parent_department_id and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_parent', 'message', 'Parent department is unavailable.');
  end if;
  if p_manager_id is not null and not exists (
    select 1 from public.profiles
    where id = p_manager_id and is_active = true and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_manager', 'message', 'Department manager is unavailable.');
  end if;

  select * into previous
  from public.departments
  where id = p_department_id and deleted_at is null
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'message', 'Department not found.');
  end if;
  if exists (
    select 1 from public.departments
    where id <> p_department_id
      and deleted_at is null
      and (lower(code) = lower(normalized_code) or lower(name) = lower(normalized_name))
  ) then
    return jsonb_build_object('ok', false, 'code', 'duplicate_department', 'message', 'An active department already uses that code or name.');
  end if;

  begin
    update public.departments
    set code = normalized_code,
        name = normalized_name,
        description = nullif(trim(coalesce(p_description, '')), ''),
        cost_centre = nullif(trim(coalesce(p_cost_centre, '')), ''),
        manager_id = p_manager_id,
        parent_department_id = p_parent_department_id,
        colour_tag = normalized_colour,
        is_active = coalesce(p_is_active, true)
    where id = p_department_id
    returning * into result;

    if previous.name is distinct from result.name then
      update public.profiles
      set department = result.name
      where department_id = p_department_id;
    end if;

    insert into public.activity_logs (user_id, action, actor, note)
    values (
      actor_id,
      'department_admin_updated',
      actor_name,
      jsonb_build_object(
        'department_id', result.id,
        'previous_code', previous.code,
        'code', result.code,
        'previous_name', previous.name,
        'name', result.name
      )::text
    );

    return jsonb_build_object('ok', true, 'department', to_jsonb(result));
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'code', 'duplicate_department', 'message', 'An active department already uses that code or name.');
    when foreign_key_violation then
      return jsonb_build_object('ok', false, 'code', 'invalid_reference', 'message', 'A selected department reference is unavailable.');
    when others then
      return jsonb_build_object('ok', false, 'code', 'internal_error', 'message', 'Department update failed.');
  end;
end;
$$;

create or replace function public.archive_department(p_department_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  actor_name text;
  active_user_count bigint;
  result public.departments%rowtype;
begin
  select profile.display_name
    into actor_name
  from public.profiles as profile
  where profile.id = actor_id
    and profile.role = 'administrator'
    and profile.is_active = true
    and profile.deleted_at is null;

  if actor_name is null then
    return jsonb_build_object('ok', false, 'code', 'access_denied', 'message', 'Administrator access is required.');
  end if;

  select * into result
  from public.departments
  where id = p_department_id and deleted_at is null
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'message', 'Department not found.');
  end if;

  select count(*) into active_user_count
  from public.profiles
  where department_id = p_department_id
    and is_active = true
    and deleted_at is null;
  if active_user_count > 0 then
    return jsonb_build_object(
      'ok', false,
      'code', 'active_users_assigned',
      'message', 'Department cannot be archived while active users are assigned.',
      'active_user_count', active_user_count
    );
  end if;

  begin
    update public.departments
    set is_active = false, deleted_at = now()
    where id = p_department_id
    returning * into result;

    insert into public.activity_logs (user_id, action, actor, note)
    values (
      actor_id,
      'department_admin_archived',
      actor_name,
      jsonb_build_object('department_id', result.id, 'code', result.code, 'name', result.name)::text
    );

    return jsonb_build_object('ok', true, 'department', to_jsonb(result));
  exception
    when others then
      return jsonb_build_object('ok', false, 'code', 'internal_error', 'message', 'Department archive failed.');
  end;
end;
$$;

revoke all on function public.create_department(text, text, text, text, uuid, uuid, text, boolean)
  from public, anon, service_role;
revoke all on function public.update_department(uuid, text, text, text, text, uuid, uuid, text, boolean)
  from public, anon, service_role;
revoke all on function public.archive_department(uuid)
  from public, anon, service_role;

grant execute on function public.create_department(text, text, text, text, uuid, uuid, text, boolean)
  to authenticated;
grant execute on function public.update_department(uuid, text, text, text, text, uuid, uuid, text, boolean)
  to authenticated;
grant execute on function public.archive_department(uuid)
  to authenticated;
commit;

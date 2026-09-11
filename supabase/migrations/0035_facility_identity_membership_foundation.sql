-- WP-FMW-022: authoritative facility identity and Technician membership foundation.
-- This migration intentionally does not change Work Order mutation authority.
begin;

do $preflight$
declare
  relation_name text;
  required_column text;
begin
  if current_user <> 'postgres' then
    raise exception '0035 must be applied as postgres';
  end if;

  foreach relation_name in array array['sites','profiles','work_orders','facility_areas','assets'] loop
    if pg_catalog.to_regclass('public.' || relation_name) is null then
      raise exception '0035 prerequisite table missing: public.%', relation_name;
    end if;
  end loop;

  foreach required_column in array array['id','code','name','is_active'] loop
    if not exists (
      select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name='sites' and c.column_name=required_column
    ) then
      raise exception '0035 sites prerequisite column missing: %', required_column;
    end if;
  end loop;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid='public.sites'::regclass and c.contype='p'
      and c.conkey=array[(select a.attnum from pg_catalog.pg_attribute a where a.attrelid=c.conrelid and a.attname='id')]
  ) then
    raise exception '0035 sites.id must be the authoritative primary key';
  end if;

  if (select count(*) from public.sites) > 1
    or exists (
      select 1 from public.sites
      where code <> 'UAT-FAC-001' or name <> 'FMWorks UAT Facility'
    ) then
    raise exception '0035 cannot safely perform the explicit single-facility UAT backfill';
  end if;

  if pg_catalog.to_regprocedure('public.pilot_account_ready(uuid)') is null
    or pg_catalog.to_regprocedure('public.current_user_role()') is null
    or pg_catalog.to_regprocedure('public.transition_work_order(uuid,text,jsonb)') is null
    or pg_catalog.to_regprocedure('public.record_work_order_execution(uuid,jsonb)') is null
    or pg_catalog.to_regprocedure('public.verify_completed_work(uuid,jsonb)') is null
    or pg_catalog.to_regprocedure('public.protect_profile_authorization_fields()') is null then
    raise exception '0035 protected authorization prerequisite missing';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid='public.record_work_order_execution(uuid,jsonb)'::regprocedure
      and p.prosecdef
      and p.proowner=(select r.oid from pg_catalog.pg_roles r where r.rolname='postgres')
      and 'search_path=pg_catalog'=any(p.proconfig)
  )
    or not has_function_privilege('authenticated','public.record_work_order_execution(uuid,jsonb)','EXECUTE')
    or has_function_privilege('anon','public.record_work_order_execution(uuid,jsonb)','EXECUTE')
    or has_function_privilege('service_role','public.record_work_order_execution(uuid,jsonb)','EXECUTE') then
    raise exception '0035 execution-function security prerequisite mismatch';
  end if;

  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid='public.work_orders'::regclass)
    or not exists (
      select 1 from pg_catalog.pg_policy p
      where p.polrelid='public.work_orders'::regclass
        and p.polname='work_orders_read_permitted'
        and p.polcmd='r'
        and p.polroles=array['authenticated'::regrole::oid]
    ) then
    raise exception '0035 Work Order RLS prerequisite mismatch';
  end if;

  if pg_catalog.to_regclass('public.facility_memberships') is not null
    or pg_catalog.to_regprocedure('public.technician_facility_read_permitted(uuid)') is not null
    or pg_catalog.to_regprocedure('public.resolve_facility_for_write(uuid)') is not null
    or exists (
      select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name in ('work_orders','facility_areas','assets')
        and c.column_name='facility_id'
    ) then
    raise exception '0035 conflicting or partial state already exists';
  end if;
end;
$preflight$;

-- Snapshot security-sensitive contracts and protected profile data so the
-- transaction itself proves they were not modified.
create temporary table wp_fmw_0035_function_snapshot on commit drop as
select p.oid::regprocedure::text as identity,
       p.prosecdef,
       p.proconfig,
       p.proacl,
       pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) as definition_hash
from pg_catalog.pg_proc p
where p.oid in (
  'public.transition_work_order(uuid,text,jsonb)'::regprocedure,
  'public.verify_completed_work(uuid,jsonb)'::regprocedure,
  'public.pilot_account_ready(uuid)'::regprocedure,
  'public.protect_profile_authorization_fields()'::regprocedure
);

create temporary table wp_fmw_0035_profile_snapshot on commit drop as
select id, email, role, is_active, deleted_at, password_change_required,
       display_name, department_id, trade_discipline, contact_number
from public.profiles;

insert into public.sites(code,name,is_active)
values ('UAT-FAC-001','FMWorks UAT Facility',true)
on conflict (code) do update
set name=excluded.name,
    is_active=excluded.is_active
where public.sites.name=excluded.name;

do $facility_seed$
begin
  if (select count(*) from public.sites where code='UAT-FAC-001' and name='FMWorks UAT Facility' and is_active) <> 1 then
    raise exception '0035 UAT facility seed postcondition failed';
  end if;
end;
$facility_seed$;

alter table public.work_orders add column facility_id uuid;
alter table public.facility_areas add column facility_id uuid;
alter table public.assets add column facility_id uuid;

alter table public.work_orders
  add constraint work_orders_facility_id_fkey foreign key(facility_id)
  references public.sites(id) on delete restrict not valid;
alter table public.facility_areas
  add constraint facility_areas_facility_id_fkey foreign key(facility_id)
  references public.sites(id) on delete restrict not valid;
alter table public.assets
  add constraint assets_facility_id_fkey foreign key(facility_id)
  references public.sites(id) on delete restrict not valid;

-- Use an explicit table rewrite rather than bypassing the immutable-terminal
-- trigger for historical Work Orders. ALTER TYPE does not fire row triggers.
do $backfill$
declare uat_facility_id uuid;
begin
  select id into strict uat_facility_id
  from public.sites where code='UAT-FAC-001';

  execute pg_catalog.format(
    'alter table public.work_orders alter column facility_id type uuid using coalesce(facility_id,%L::uuid)',
    uat_facility_id
  );
  execute pg_catalog.format(
    'alter table public.facility_areas alter column facility_id type uuid using coalesce(facility_id,%L::uuid)',
    uat_facility_id
  );
  execute pg_catalog.format(
    'alter table public.assets alter column facility_id type uuid using coalesce(facility_id,%L::uuid)',
    uat_facility_id
  );
end;
$backfill$;

alter table public.work_orders validate constraint work_orders_facility_id_fkey;
alter table public.facility_areas validate constraint facility_areas_facility_id_fkey;
alter table public.assets validate constraint assets_facility_id_fkey;

alter table public.work_orders alter column facility_id set not null;
alter table public.facility_areas alter column facility_id set not null;
alter table public.assets alter column facility_id set not null;

create index work_orders_facility_idx on public.work_orders(facility_id);
create index facility_areas_facility_idx on public.facility_areas(facility_id,active);
create index assets_facility_idx on public.assets(facility_id,lifecycle_status);

create table public.facility_memberships (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.sites(id) on delete restrict,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  membership_role text not null check (membership_role in ('technician','supervisor','facility_manager')),
  active boolean not null default true,
  effective_from timestamptz not null default pg_catalog.now(),
  effective_to timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default pg_catalog.now(),
  constraint facility_memberships_period_check
    check (effective_to is null or effective_to > effective_from)
);

create unique index facility_memberships_active_unique_idx
  on public.facility_memberships(facility_id,profile_id,membership_role)
  where active;
create index facility_memberships_profile_lookup_idx
  on public.facility_memberships(profile_id,facility_id)
  where active;

-- Existing assignment is the only unambiguous evidence used for membership.
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select distinct w.facility_id,p.id,'technician',null::uuid
from public.work_orders w
join public.profiles p on p.id=w.assigned_technician_id
where p.role='technician' and p.is_active and p.deleted_at is null;

alter table public.facility_memberships enable row level security;
revoke all on table public.facility_memberships from public,anon,authenticated,service_role;
grant select on table public.facility_memberships to authenticated;

create policy facility_memberships_read_permitted
on public.facility_memberships for select to authenticated
using (
  profile_id=auth.uid()
  or public.current_user_role()='administrator'
);

create or replace function public.technician_facility_read_permitted(p_facility_id uuid)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select public.pilot_account_ready(auth.uid())
    and public.current_user_role()='technician'
    and exists (
      select 1
      from public.facility_memberships fm
      join public.sites s on s.id=fm.facility_id
      where fm.profile_id=auth.uid()
        and fm.facility_id=p_facility_id
        and fm.membership_role='technician'
        and fm.active
        and fm.effective_from <= pg_catalog.now()
        and (fm.effective_to is null or fm.effective_to > pg_catalog.now())
        and s.is_active
    )
$function$;

revoke all on function public.technician_facility_read_permitted(uuid)
from public,anon,service_role;
grant execute on function public.technician_facility_read_permitted(uuid) to authenticated;

-- Resolve an omitted facility without guessing: an actor's one active
-- membership wins; otherwise a sole active Facility is safe. Ambiguity fails.
create or replace function public.resolve_facility_for_write(p_actor_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path=pg_catalog
as $function$
declare
  resolved uuid;
begin
  select pg_catalog.min(fm.facility_id::text)::uuid into resolved
  from public.facility_memberships fm
  join public.sites s on s.id=fm.facility_id and s.is_active
  where fm.profile_id=p_actor_id and fm.active
    and fm.effective_from <= pg_catalog.now()
    and (fm.effective_to is null or fm.effective_to > pg_catalog.now())
  having pg_catalog.count(distinct fm.facility_id)=1;

  if resolved is null then
    select pg_catalog.min(s.id::text)::uuid into resolved
    from public.sites s where s.is_active
    having pg_catalog.count(*)=1;
  end if;
  return resolved;
end;
$function$;
revoke all on function public.resolve_facility_for_write(uuid)
from public,anon,authenticated,service_role;

create or replace function public.assign_work_order_facility()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
declare linked_asset_facility uuid; linked_area_facility uuid;
begin
  if new.asset_id is not null then
    select a.facility_id into linked_asset_facility from public.assets a where a.id=new.asset_id;
  end if;
  if new.facility_area_id is not null then
    select a.facility_id into linked_area_facility from public.facility_areas a where a.id=new.facility_area_id;
  end if;
  new.facility_id:=coalesce(new.facility_id,linked_asset_facility,linked_area_facility,public.resolve_facility_for_write(auth.uid()));
  if new.facility_id is null then raise exception using errcode='23514',message='FACILITY_REQUIRED'; end if;
  if not exists(select 1 from public.sites s where s.id=new.facility_id and s.is_active) then
    raise exception using errcode='23514',message='FACILITY_INVALID';
  end if;
  if linked_asset_facility is not null and linked_asset_facility<>new.facility_id then
    raise exception using errcode='23514',message='FACILITY_ASSET_MISMATCH';
  end if;
  if linked_area_facility is not null and linked_area_facility<>new.facility_id then
    raise exception using errcode='23514',message='FACILITY_AREA_MISMATCH';
  end if;
  return new;
end;
$function$;

create or replace function public.assign_asset_facility()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
begin
  new.facility_id:=coalesce(new.facility_id,public.resolve_facility_for_write(auth.uid()));
  if new.facility_id is null then raise exception using errcode='23514',message='FACILITY_REQUIRED'; end if;
  if not exists(select 1 from public.sites s where s.id=new.facility_id and s.is_active) then
    raise exception using errcode='23514',message='FACILITY_INVALID';
  end if;
  return new;
end;
$function$;

create or replace function public.assign_facility_area_facility()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
begin
  new.facility_id:=coalesce(new.facility_id,public.resolve_facility_for_write(auth.uid()));
  if new.facility_id is null then raise exception using errcode='23514',message='FACILITY_REQUIRED'; end if;
  if not exists(select 1 from public.sites s where s.id=new.facility_id and s.is_active) then
    raise exception using errcode='23514',message='FACILITY_INVALID';
  end if;
  return new;
end;
$function$;

revoke all on function public.assign_work_order_facility() from public,anon,authenticated,service_role;
revoke all on function public.assign_asset_facility() from public,anon,authenticated,service_role;
revoke all on function public.assign_facility_area_facility() from public,anon,authenticated,service_role;

create trigger assign_work_order_facility
before insert or update of facility_id,asset_id,facility_area_id on public.work_orders
for each row execute function public.assign_work_order_facility();
create trigger assign_asset_facility
before insert or update of facility_id on public.assets
for each row execute function public.assign_asset_facility();
create trigger assign_facility_area_facility
before insert or update of facility_id on public.facility_areas
for each row execute function public.assign_facility_area_facility();

-- Repair the predecessor's SQL-NULL authorization edge before expanding
-- Technician read visibility. All execution data, lifecycle, and audit
-- behavior is retained from 0034; only the assignment predicate is made
-- explicitly fail-closed.
create or replace function public.record_work_order_execution(
  p_work_order_id uuid,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  previous public.work_orders%rowtype;
  result public.work_orders%rowtype;
  work_performed text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'completion_notes','')), '');
  requested_hours numeric;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'name', actor ->> 'display_name', 'Unknown user');
  actor_role := actor ->> 'role';

  select * into previous from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status in ('completed','reviewed','closed','cancelled') then
    return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Execution cannot be changed after formal completion or cancellation.');
  end if;
  if previous.status not in ('assigned','in_progress') then
    return public.work_order_result_error('INVALID_TRANSITION', 'Work may be recorded only for an assigned or In Progress Work Order.');
  end if;
  if actor_role <> 'administrator'
    and not (
      actor_role='technician'
      and previous.assigned_technician_id is not null
      and actor_id=previous.assigned_technician_id
    ) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the assigned Technician or an Administrator may record work performed.');
  end if;

  begin requested_hours := nullif(p_payload ->> 'actual_labour_hours','')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Work performed statement and cumulative non-negative labour hours are required.');
  end;
  if work_performed is null or requested_hours is null or requested_hours < 0 then
    return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Work performed statement and cumulative non-negative labour hours are required.');
  end if;
  if previous.actual_labour_hours is not null and requested_hours < previous.actual_labour_hours then
    return public.work_order_result_error('CUMULATIVE_LABOUR_REQUIRED', 'Cumulative labour hours cannot be lower than the previously recorded total.');
  end if;

  update public.work_orders set
    completion_notes=work_performed,
    actual_labour_hours=requested_hours,
    updated_at=pg_catalog.now()
  where id=previous.id returning * into result;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,result.id,'work_order_execution_recorded',previous.status,previous.status,actor_name,
    pg_catalog.jsonb_build_object(
      'work_performed',result.completion_notes,
      'cumulative_labour_hours',result.actual_labour_hours,
      'recorded_by',actor_id,
      'recorded_at',pg_catalog.now(),
      'status_unchanged',true
    )::text);

  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'status_unchanged',true);
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Work execution data is invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work execution could not be recorded.');
end;
$function$;

revoke all on function public.record_work_order_execution(uuid,jsonb)
from public,anon,service_role;
grant execute on function public.record_work_order_execution(uuid,jsonb) to authenticated;

drop policy work_orders_read_permitted on public.work_orders;
create policy work_orders_read_permitted
on public.work_orders for select to authenticated
using (
  public.pilot_account_ready(auth.uid())
  and (
    (
      public.current_user_role()='technician'
      and public.technician_facility_read_permitted(facility_id)
    )
    or (
      public.current_user_role()<>'technician'
      and (
        requested_by=auth.uid()
        or assigned_technician_id=auth.uid()
        or public.current_user_role() in ('approver','supervisor','administrator')
      )
    )
  )
);
-- SELECT is still fully constrained by the RLS policy above; without this
-- table privilege PostgreSQL rejects the query before evaluating that policy.
grant select on table public.work_orders to authenticated;

do $postconditions$
declare
  object_name text;
  config text[];
begin
  if exists(select 1 from public.work_orders where facility_id is null)
    or exists(select 1 from public.facility_areas where facility_id is null)
    or exists(select 1 from public.assets where facility_id is null) then
    raise exception '0035 authoritative facility backfill failed';
  end if;

  if exists (
    select 1 from public.work_orders w join public.assets a on a.id=w.asset_id
    where w.facility_id<>a.facility_id
  ) or exists (
    select 1 from public.work_orders w join public.facility_areas a on a.id=w.facility_area_id
    where w.facility_id<>a.facility_id
  ) then
    raise exception '0035 linked-object facility consistency failed';
  end if;

  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid='public.facility_memberships'::regclass)
    or not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid='public.work_orders'::regclass) then
    raise exception '0035 RLS postcondition failed';
  end if;
  if not has_table_privilege('authenticated','public.work_orders','SELECT') then
    raise exception '0035 authenticated RLS SELECT privilege postcondition failed';
  end if;

  foreach object_name in array array[
    'public.record_work_order_execution(uuid,jsonb)',
    'public.technician_facility_read_permitted(uuid)',
    'public.resolve_facility_for_write(uuid)',
    'public.assign_work_order_facility()',
    'public.assign_asset_facility()',
    'public.assign_facility_area_facility()'
  ] loop
    select p.proconfig into config from pg_catalog.pg_proc p
    where p.oid=object_name::regprocedure and p.prosecdef;
    if config is null or not ('search_path=pg_catalog'=any(config)) then
      raise exception '0035 function security postcondition failed: %',object_name;
    end if;
  end loop;

  if has_function_privilege('anon','public.technician_facility_read_permitted(uuid)','EXECUTE')
    or has_function_privilege('service_role','public.technician_facility_read_permitted(uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.technician_facility_read_permitted(uuid)','EXECUTE') then
    raise exception '0035 read-helper privilege postcondition failed';
  end if;
  if has_function_privilege('anon','public.record_work_order_execution(uuid,jsonb)','EXECUTE')
    or has_function_privilege('service_role','public.record_work_order_execution(uuid,jsonb)','EXECUTE')
    or not has_function_privilege('authenticated','public.record_work_order_execution(uuid,jsonb)','EXECUTE') then
    raise exception '0035 execution-function privilege postcondition failed';
  end if;

  if exists (
    select 1 from wp_fmw_0035_function_snapshot before
    full join (
      select p.oid::regprocedure::text as identity,p.prosecdef,p.proconfig,p.proacl,
             pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) as definition_hash
      from pg_catalog.pg_proc p
      where p.oid in (
        'public.transition_work_order(uuid,text,jsonb)'::regprocedure,
        'public.verify_completed_work(uuid,jsonb)'::regprocedure,
        'public.pilot_account_ready(uuid)'::regprocedure,
        'public.protect_profile_authorization_fields()'::regprocedure
      )
    ) after using(identity)
    where before.identity is null or after.identity is null
       or (before.prosecdef,before.proconfig,before.proacl,before.definition_hash)
          is distinct from
          (after.prosecdef,after.proconfig,after.proacl,after.definition_hash)
  ) then
    raise exception '0035 protected function contract changed';
  end if;

  if exists (
    select 1 from wp_fmw_0035_profile_snapshot before
    full join (
      select id,email,role,is_active,deleted_at,password_change_required,
             display_name,department_id,trade_discipline,contact_number
      from public.profiles
    ) after using(id)
    where before.id is null or after.id is null
       or row(before.email,before.role,before.is_active,before.deleted_at,before.password_change_required,
              before.display_name,before.department_id,before.trade_discipline,before.contact_number)
          is distinct from
          row(after.email,after.role,after.is_active,after.deleted_at,after.password_change_required,
              after.display_name,after.department_id,after.trade_discipline,after.contact_number)
  ) then
    raise exception '0035 protected profile data changed';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid='public.profiles'::regclass
      and t.tgname='protect_profile_authorization_fields'
      and t.tgenabled='O' and not t.tgisinternal
      and t.tgfoid='public.protect_profile_authorization_fields()'::regprocedure
  ) then
    raise exception '0035 profile protection trigger postcondition failed';
  end if;
end;
$postconditions$;

commit;

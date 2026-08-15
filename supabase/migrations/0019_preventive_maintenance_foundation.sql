-- WP-PM-001A: Preventive Maintenance database foundation and recurrence engine.
-- LOCAL CANDIDATE ONLY. Preview fingerprint and migrations 0018/0019 reconciliation remain mandatory.
begin;

do $preflight$
declare due_definition text;
begin
  if pg_catalog.to_regclass('public.assets') is null
    or pg_catalog.to_regclass('public.work_orders') is null
    or pg_catalog.to_regclass('public.activity_logs') is null
    or pg_catalog.to_regclass('public.notification_outbox') is null
    or pg_catalog.to_regprocedure('public.work_order_actor()') is null
    or pg_catalog.to_regprocedure('public.next_work_order_number(timestamp with time zone)') is null then
    raise exception '0019 prerequisite missing: migrations 0012-0018 are required';
  end if;
  if pg_catalog.to_regclass('public.maintenance_requirements') is not null then
    raise exception '0019 prerequisite mismatch: PM objects already exist';
  end if;
  select pg_catalog.pg_get_constraintdef(c.oid) into due_definition
  from pg_catalog.pg_constraint c
  where c.conrelid='public.work_orders'::pg_catalog.regclass
    and c.conname='work_orders_due_date_check' and c.contype='c';
  if due_definition is null
    or due_definition !~* 'due_date IS NULL'
    or due_definition !~* 'due_date >=.*COALESCE\(submitted_at, created_at\).*date'
    or due_definition ~* 'pm_occurrence_id' then
    raise exception '0019 blocked: unexpected work_orders_due_date_check definition: %',coalesce(due_definition,'MISSING');
  end if;
end;
$preflight$;

create table public.maintenance_requirement_number_counters (
  reference_year integer primary key,
  last_value integer not null check(last_value>0)
);

create table public.maintenance_requirements (
  id uuid primary key default gen_random_uuid(),
  requirement_number text not null unique,
  asset_id uuid not null references public.assets(id) on delete restrict,
  state text not null default 'draft' check(state in ('draft','active','inactive')),
  current_revision_id uuid,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint maintenance_requirements_number_check check(requirement_number ~ '^PM-[0-9]{4}-[0-9]{6}$')
);
create index maintenance_requirements_asset_state_idx on public.maintenance_requirements(asset_id,state);

create table public.maintenance_requirement_revisions (
  id uuid primary key default gen_random_uuid(),
  requirement_id uuid not null references public.maintenance_requirements(id) on delete restrict,
  revision_number integer not null check(revision_number>0),
  title text not null check(length(pg_catalog.btrim(title)) between 3 and 200),
  scope text not null check(length(pg_catalog.btrim(scope)) between 3 and 4000),
  maintenance_type text not null check(maintenance_type in ('preventive','inspection')),
  interval_value integer not null check(interval_value between 1 and 365),
  interval_unit text not null check(interval_unit in ('day','week','month','year')),
  first_due_date date not null,
  lead_time_days integer not null default 0 check(lead_time_days between 0 and 365),
  department_id uuid references public.departments(id) on delete restrict,
  responsible_team_id uuid references public.maintenance_teams(id) on delete restrict,
  default_priority text not null default 'medium' check(default_priority in ('low','medium','high','critical')),
  estimated_hours numeric check(estimated_hours is null or estimated_hours>=0),
  evidence_guidance text check(evidence_guidance is null or length(evidence_guidance)<=2000),
  instructions text check(instructions is null or length(instructions)<=4000),
  procedure_reference text check(procedure_reference is null or length(procedure_reference)<=500),
  effective_date date not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  unique(requirement_id,revision_number),
  constraint maintenance_revision_anchor_check check(first_due_date>=effective_date)
);
create index maintenance_revisions_effective_idx on public.maintenance_requirement_revisions(requirement_id,effective_date desc,revision_number desc);
alter table public.maintenance_requirements add constraint maintenance_requirements_current_revision_fkey
  foreign key(current_revision_id) references public.maintenance_requirement_revisions(id) on delete restrict;

create table public.pm_occurrences (
  id uuid primary key default gen_random_uuid(),
  requirement_id uuid not null references public.maintenance_requirements(id) on delete restrict,
  requirement_revision_id uuid not null references public.maintenance_requirement_revisions(id) on delete restrict,
  asset_id uuid not null references public.assets(id) on delete restrict,
  occurrence_number integer not null check(occurrence_number>0),
  original_due_date date not null,
  current_due_date date not null,
  generation_status text not null default 'pending' check(generation_status in ('pending','generated','generation_failed','cancelled')),
  generated_at timestamptz,
  generation_attempts integer not null default 0 check(generation_attempts>=0),
  last_generation_error_code text,
  cancelled_by uuid references public.profiles(id) on delete restrict,
  cancellation_reason text,
  cancelled_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  unique(requirement_id,original_due_date),
  unique(requirement_revision_id,occurrence_number),
  constraint pm_occurrence_due_check check(current_due_date>=original_due_date),
  constraint pm_occurrence_generated_check check(
    (generation_status='generated' and generated_at is not null)
    or (generation_status<>'generated' and generated_at is null)
  ),
  constraint pm_occurrence_cancelled_check check(
    (generation_status='cancelled' and cancelled_by is not null and cancellation_reason is not null and cancelled_at is not null)
    or (generation_status<>'cancelled' and cancelled_by is null and cancellation_reason is null and cancelled_at is null)
  )
);
create index pm_occurrences_due_status_idx on public.pm_occurrences(current_due_date,generation_status);
create index pm_occurrences_asset_due_idx on public.pm_occurrences(asset_id,current_due_date desc);
create index pm_occurrences_failed_idx on public.pm_occurrences(current_due_date) where generation_status='generation_failed';

create table public.pm_occurrence_deferrals (
  id uuid primary key default gen_random_uuid(),
  occurrence_id uuid not null references public.pm_occurrences(id) on delete restrict,
  sequence_number integer not null check(sequence_number>0),
  previous_due_date date not null,
  revised_due_date date not null,
  reason text not null check(length(pg_catalog.btrim(reason)) between 3 and 2000),
  deferred_by uuid not null references public.profiles(id) on delete restrict,
  deferred_at timestamptz not null default pg_catalog.now(),
  unique(occurrence_id,sequence_number),
  constraint pm_deferral_date_check check(revised_due_date>previous_due_date)
);
create index pm_deferrals_occurrence_idx on public.pm_occurrence_deferrals(occurrence_id,deferred_at desc);

alter table public.work_orders add column pm_occurrence_id uuid;
alter table public.work_orders add constraint work_orders_pm_occurrence_fkey
  foreign key(pm_occurrence_id) references public.pm_occurrences(id) on delete restrict;
create unique index work_orders_pm_occurrence_unique_idx on public.work_orders(pm_occurrence_id) where pm_occurrence_id is not null;
alter table public.work_orders drop constraint work_orders_due_date_check;
alter table public.work_orders add constraint work_orders_due_date_check check(
  due_date is null or pm_occurrence_id is not null or due_date>=coalesce(submitted_at,created_at)::date
);

alter table public.activity_logs add column maintenance_requirement_id uuid references public.maintenance_requirements(id) on delete restrict;
alter table public.activity_logs add column pm_occurrence_id uuid references public.pm_occurrences(id) on delete restrict;
create index activity_logs_pm_requirement_idx on public.activity_logs(maintenance_requirement_id,created_at desc) where maintenance_requirement_id is not null;
create index activity_logs_pm_occurrence_idx on public.activity_logs(pm_occurrence_id,created_at desc) where pm_occurrence_id is not null;

alter table public.notification_outbox add column pm_occurrence_id uuid references public.pm_occurrences(id) on delete restrict;
alter table public.notification_outbox drop constraint notification_outbox_target_check;
alter table public.notification_outbox add constraint notification_outbox_target_check check(
  work_order_id is not null or incident_id is not null or pm_occurrence_id is not null
);
create index notification_outbox_pm_occurrence_idx on public.notification_outbox(pm_occurrence_id,delivery_status,created_at desc) where pm_occurrence_id is not null;

create or replace function public.protect_pm_revision()
returns trigger language plpgsql set search_path=pg_catalog as $fn$
begin raise exception using errcode='55000',message='Maintenance Requirement revisions are immutable.'; end;
$fn$;
create trigger protect_pm_revision before update or delete on public.maintenance_requirement_revisions
  for each row execute function public.protect_pm_revision();

alter table public.maintenance_requirements enable row level security;
alter table public.maintenance_requirement_revisions enable row level security;
alter table public.pm_occurrences enable row level security;
alter table public.pm_occurrence_deferrals enable row level security;

create policy maintenance_requirements_read on public.maintenance_requirements for select to authenticated using(
  public.current_user_role() in ('approver','supervisor','administrator')
  or (state='active' and public.current_user_role() in ('reviewer','initiator'))
  or (public.current_user_role()='technician' and exists(
    select 1 from public.pm_occurrences o join public.work_orders w on w.pm_occurrence_id=o.id
    where o.requirement_id=maintenance_requirements.id and w.assigned_technician_id=auth.uid()
  ))
);
create policy maintenance_revisions_read on public.maintenance_requirement_revisions for select to authenticated using(
  exists(select 1 from public.maintenance_requirements r where r.id=requirement_id)
);
create policy pm_occurrences_read on public.pm_occurrences for select to authenticated using(
  public.current_user_role() in ('approver','supervisor','administrator')
  or (public.current_user_role()='technician' and exists(
    select 1 from public.work_orders w where w.pm_occurrence_id=pm_occurrences.id and w.assigned_technician_id=auth.uid()
  ))
);
create policy pm_deferrals_read on public.pm_occurrence_deferrals for select to authenticated using(
  exists(select 1 from public.pm_occurrences o where o.id=occurrence_id)
);

drop policy if exists activity_logs_read_permitted on public.activity_logs;
create policy activity_logs_read_permitted on public.activity_logs for select to authenticated using(
  (work_order_id is not null and exists(select 1 from public.work_orders w where w.id=activity_logs.work_order_id))
  or (incident_id is not null and exists(select 1 from public.incidents i where i.id=activity_logs.incident_id))
  or (asset_id is not null and exists(select 1 from public.assets a where a.id=activity_logs.asset_id))
  or (maintenance_requirement_id is not null and exists(select 1 from public.maintenance_requirements r where r.id=activity_logs.maintenance_requirement_id))
  or (pm_occurrence_id is not null and exists(select 1 from public.pm_occurrences o where o.id=activity_logs.pm_occurrence_id))
  or public.current_user_role()='administrator'
);

revoke all on public.maintenance_requirement_number_counters,public.maintenance_requirements,
  public.maintenance_requirement_revisions,public.pm_occurrences,public.pm_occurrence_deferrals from public,anon,authenticated;
grant select on public.maintenance_requirements,public.maintenance_requirement_revisions,public.pm_occurrences,public.pm_occurrence_deferrals to authenticated;

create or replace function public.pm_result_error(p_code text,p_message text)
returns jsonb language sql immutable set search_path=pg_catalog as $fn$
  select pg_catalog.jsonb_build_object('ok',false,'code',p_code,'message',p_message)
$fn$;

create or replace function public.pm_business_date()
returns date language sql stable set search_path=pg_catalog as $fn$
  select (pg_catalog.now() at time zone 'Asia/Singapore')::date
$fn$;

create or replace function public.next_maintenance_requirement_number(p_reference timestamptz default pg_catalog.now())
returns text language plpgsql security definer set search_path=pg_catalog as $fn$
declare y integer:=extract(year from p_reference at time zone 'Asia/Singapore'); n integer;
begin
  insert into public.maintenance_requirement_number_counters(reference_year,last_value) values(y,1)
  on conflict(reference_year) do update set last_value=public.maintenance_requirement_number_counters.last_value+1
  returning last_value into n;
  return 'PM-'||y::text||'-'||pg_catalog.lpad(n::text,6,'0');
end;
$fn$;

create or replace function public.calculate_pm_due_date(p_revision_id uuid,p_occurrence_number integer)
returns date language plpgsql security definer set search_path=pg_catalog as $fn$
declare r public.maintenance_requirement_revisions; offset_value integer; target_month date; last_day integer;
begin
  if p_occurrence_number<1 then raise exception 'Occurrence number must be positive'; end if;
  select * into r from public.maintenance_requirement_revisions where id=p_revision_id;
  if not found then raise exception 'Maintenance Requirement revision not found'; end if;
  offset_value:=(p_occurrence_number-1)*r.interval_value;
  if r.interval_unit='day' then return r.first_due_date+offset_value;
  elsif r.interval_unit='week' then return r.first_due_date+(offset_value*7);
  else
    if r.interval_unit='year' then offset_value:=offset_value*12; end if;
    target_month:=(pg_catalog.date_trunc('month',r.first_due_date)::date+pg_catalog.make_interval(months=>offset_value))::date;
    last_day:=extract(day from (target_month+pg_catalog.make_interval(months=>1)-pg_catalog.make_interval(days=>1))::date);
    return target_month+(least(extract(day from r.first_due_date)::integer,last_day)-1);
  end if;
end;
$fn$;

create or replace function public.create_pm_requirement(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; req public.maintenance_requirements; rev public.maintenance_requirement_revisions;
  asset_state text; effective date:=coalesce(nullif(p_payload->>'effective_date','')::date,public.pm_business_date()); first_due date:=nullif(p_payload->>'first_due_date','')::date;
  department_value uuid:=nullif(p_payload->>'department_id','')::uuid; team_value uuid:=nullif(p_payload->>'responsible_team_id','')::uuid;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select lifecycle_status into asset_state from public.assets where id=nullif(p_payload->>'asset_id','')::uuid;
  if asset_state is null or asset_state='decommissioned' then return public.pm_result_error('INVALID_ASSET','Selected Asset is unavailable for PM.'); end if;
  if pg_catalog.btrim(coalesce(p_payload->>'title',''))='' or pg_catalog.btrim(coalesce(p_payload->>'scope',''))=''
    or pg_catalog.lower(coalesce(p_payload->>'maintenance_type','')) not in ('preventive','inspection')
    or pg_catalog.lower(coalesce(p_payload->>'interval_unit','')) not in ('day','week','month','year')
    or coalesce((p_payload->>'interval_value')::integer,0) not between 1 and 365
    or first_due is null or effective>public.pm_business_date() or first_due<effective
    or pg_catalog.lower(coalesce(p_payload->>'default_priority','medium')) not in ('low','medium','high','critical') then
    return public.pm_result_error('VALIDATION_ERROR','Maintenance Requirement values are invalid.'); end if;
  if department_value is not null and not exists(select 1 from public.departments d where d.id=department_value and d.is_active and d.deleted_at is null) then return public.pm_result_error('INVALID_REFERENCE','Department is unavailable.'); end if;
  if team_value is not null and not exists(select 1 from public.maintenance_teams t where t.id=team_value and t.is_active and t.deleted_at is null) then return public.pm_result_error('INVALID_REFERENCE','Responsible team is unavailable.'); end if;
  insert into public.maintenance_requirements(requirement_number,asset_id,created_by,updated_by)
  values(public.next_maintenance_requirement_number(),(p_payload->>'asset_id')::uuid,actor_id,actor_id) returning * into req;
  insert into public.maintenance_requirement_revisions(requirement_id,revision_number,title,scope,maintenance_type,interval_value,interval_unit,first_due_date,lead_time_days,department_id,responsible_team_id,default_priority,estimated_hours,evidence_guidance,instructions,procedure_reference,effective_date,created_by)
  values(req.id,1,pg_catalog.btrim(p_payload->>'title'),pg_catalog.btrim(p_payload->>'scope'),pg_catalog.lower(p_payload->>'maintenance_type'),(p_payload->>'interval_value')::integer,pg_catalog.lower(p_payload->>'interval_unit'),first_due,coalesce(nullif(p_payload->>'lead_time_days','')::integer,0),department_value,team_value,pg_catalog.lower(coalesce(p_payload->>'default_priority','medium')),nullif(p_payload->>'estimated_hours','')::numeric,nullif(pg_catalog.btrim(coalesce(p_payload->>'evidence_guidance','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'instructions','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'procedure_reference','')),''),effective,actor_id) returning * into rev;
  update public.maintenance_requirements set current_revision_id=rev.id where id=req.id returning * into req;
  insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,action,actor,note)
  values(actor_id,req.asset_id,req.id,'pm_requirement_created',actor->>'name',pg_catalog.jsonb_build_object('requirement_number',req.requirement_number,'revision',1,'state','draft')::text);
  return pg_catalog.jsonb_build_object('ok',true,'requirement',pg_catalog.to_jsonb(req),'revision',pg_catalog.to_jsonb(rev));
exception when invalid_text_representation or numeric_value_out_of_range or check_violation then return public.pm_result_error('VALIDATION_ERROR','Maintenance Requirement values are invalid.');
when others then return public.pm_result_error('INTERNAL_ERROR','Maintenance Requirement creation failed.'); end;
$fn$;

create or replace function public.revise_pm_requirement(p_requirement_id uuid,p_payload jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); req public.maintenance_requirements; previous public.maintenance_requirement_revisions; rev public.maintenance_requirement_revisions;
  actor_id uuid; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); effective date:=coalesce(nullif(p_payload->>'effective_date','')::date,public.pm_business_date()); first_due date:=nullif(p_payload->>'first_due_date','')::date;
  department_value uuid:=nullif(p_payload->>'department_id','')::uuid; team_value uuid:=nullif(p_payload->>'responsible_team_id','')::uuid;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if reason is null then return public.pm_result_error('REASON_REQUIRED','A revision reason is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into req from public.maintenance_requirements where id=p_requirement_id for update;
  if not found then return public.pm_result_error('NOT_FOUND','Maintenance Requirement not found.'); end if;
  if exists(select 1 from public.assets a where a.id=req.asset_id and a.lifecycle_status='decommissioned') then return public.pm_result_error('INVALID_ASSET','A decommissioned Asset cannot receive a new PM revision.'); end if;
  select * into previous from public.maintenance_requirement_revisions where id=req.current_revision_id;
  if pg_catalog.btrim(coalesce(p_payload->>'title',''))='' or pg_catalog.btrim(coalesce(p_payload->>'scope',''))=''
    or pg_catalog.lower(coalesce(p_payload->>'maintenance_type','')) not in ('preventive','inspection')
    or pg_catalog.lower(coalesce(p_payload->>'interval_unit','')) not in ('day','week','month','year')
    or coalesce((p_payload->>'interval_value')::integer,0) not between 1 and 365
    or first_due is null or effective>public.pm_business_date() or effective<previous.effective_date or first_due<effective then return public.pm_result_error('VALIDATION_ERROR','Revision values are invalid.'); end if;
  if department_value is not null and not exists(select 1 from public.departments d where d.id=department_value and d.is_active and d.deleted_at is null) then return public.pm_result_error('INVALID_REFERENCE','Department is unavailable.'); end if;
  if team_value is not null and not exists(select 1 from public.maintenance_teams t where t.id=team_value and t.is_active and t.deleted_at is null) then return public.pm_result_error('INVALID_REFERENCE','Responsible team is unavailable.'); end if;
  insert into public.maintenance_requirement_revisions(requirement_id,revision_number,title,scope,maintenance_type,interval_value,interval_unit,first_due_date,lead_time_days,department_id,responsible_team_id,default_priority,estimated_hours,evidence_guidance,instructions,procedure_reference,effective_date,created_by)
  values(req.id,previous.revision_number+1,pg_catalog.btrim(p_payload->>'title'),pg_catalog.btrim(p_payload->>'scope'),pg_catalog.lower(p_payload->>'maintenance_type'),(p_payload->>'interval_value')::integer,pg_catalog.lower(p_payload->>'interval_unit'),first_due,coalesce(nullif(p_payload->>'lead_time_days','')::integer,0),department_value,team_value,pg_catalog.lower(coalesce(p_payload->>'default_priority','medium')),nullif(p_payload->>'estimated_hours','')::numeric,nullif(pg_catalog.btrim(coalesce(p_payload->>'evidence_guidance','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'instructions','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'procedure_reference','')),''),effective,(actor->>'id')::uuid) returning * into rev;
  update public.maintenance_requirements set current_revision_id=rev.id,updated_by=actor_id,updated_at=pg_catalog.now() where id=req.id returning * into req;
  insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,action,actor,note) values(actor_id,req.asset_id,req.id,'pm_requirement_revised',actor->>'name',pg_catalog.jsonb_build_object('before_revision',previous.revision_number,'after_revision',rev.revision_number,'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'requirement',pg_catalog.to_jsonb(req),'revision',pg_catalog.to_jsonb(rev));
exception when invalid_text_representation or numeric_value_out_of_range or check_violation then return public.pm_result_error('VALIDATION_ERROR','Revision values are invalid.');
when others then return public.pm_result_error('INTERNAL_ERROR','Maintenance Requirement revision failed.'); end;
$fn$;

create or replace function public.activate_pm_requirement(p_requirement_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); req public.maintenance_requirements;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  select * into req from public.maintenance_requirements where id=p_requirement_id for update; if not found then return public.pm_result_error('NOT_FOUND','Maintenance Requirement not found.'); end if;
  if req.state='active' then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','requirement',pg_catalog.to_jsonb(req)); end if;
  if not exists(select 1 from public.assets a where a.id=req.asset_id and a.lifecycle_status<>'decommissioned') then return public.pm_result_error('INVALID_ASSET','Selected Asset is unavailable for PM.'); end if;
  update public.maintenance_requirements set state='active',updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=req.id returning * into req;
  insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,action,actor,note) values((actor->>'id')::uuid,req.asset_id,req.id,'pm_requirement_activated',actor->>'name',pg_catalog.jsonb_build_object('reason',nullif(pg_catalog.btrim(coalesce(p_reason,'')),''))::text);
  return pg_catalog.jsonb_build_object('ok',true,'requirement',pg_catalog.to_jsonb(req));
end;
$fn$;

create or replace function public.deactivate_pm_requirement(p_requirement_id uuid,p_reason text,p_cancel_future boolean default false)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); req public.maintenance_requirements; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); cancelled_count integer:=0;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if reason is null then return public.pm_result_error('REASON_REQUIRED','A deactivation reason is required.'); end if;
  select * into req from public.maintenance_requirements where id=p_requirement_id for update; if not found then return public.pm_result_error('NOT_FOUND','Maintenance Requirement not found.'); end if;
  if req.state='inactive' and not p_cancel_future then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','requirement',pg_catalog.to_jsonb(req)); end if;
  update public.maintenance_requirements set state='inactive',updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=req.id returning * into req;
  if p_cancel_future then
    with changed as (
      update public.pm_occurrences set generation_status='cancelled',cancelled_by=(actor->>'id')::uuid,cancellation_reason=reason,cancelled_at=pg_catalog.now()
      where requirement_id=req.id and generation_status in ('pending','generation_failed') and current_due_date>public.pm_business_date() returning id,asset_id
    ), logged as (
      insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
      select (actor->>'id')::uuid,c.asset_id,req.id,c.id,'pm_occurrence_cancelled',actor->>'name',pg_catalog.jsonb_build_object('reason',reason,'source','requirement_deactivation')::text from changed c returning 1
    ) select count(*) into cancelled_count from logged;
  end if;
  insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,action,actor,note) values((actor->>'id')::uuid,req.asset_id,req.id,'pm_requirement_deactivated',actor->>'name',pg_catalog.jsonb_build_object('reason',reason,'future_occurrences_cancelled',cancelled_count)::text);
  return pg_catalog.jsonb_build_object('ok',true,'requirement',pg_catalog.to_jsonb(req),'cancelled_occurrences',cancelled_count);
end;
$fn$;

create or replace function public.materialize_pm_occurrences(p_through_date date)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); req record; n integer; due_value date; inserted public.pm_occurrences; created_count integer:=0; today date:=public.pm_business_date();
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if p_through_date is null or p_through_date<today or p_through_date>today+366 then return public.pm_result_error('INVALID_HORIZON','Materialization horizon must be within 366 days.'); end if;
  for req in select r.id requirement_id,r.asset_id,r.current_revision_id from public.maintenance_requirements r join public.assets a on a.id=r.asset_id where r.state='active' and a.lifecycle_status<>'decommissioned' order by r.id loop
    n:=1;
    loop
      if n>10000 then raise exception 'PM recurrence safety bound exceeded'; end if;
      due_value:=public.calculate_pm_due_date(req.current_revision_id,n);
      exit when due_value>p_through_date;
      inserted:=null;
      insert into public.pm_occurrences(requirement_id,requirement_revision_id,asset_id,occurrence_number,original_due_date,current_due_date)
      values(req.requirement_id,req.current_revision_id,req.asset_id,n,due_value,due_value)
      on conflict do nothing returning * into inserted;
      if inserted.id is not null then
        created_count:=created_count+1;
        insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
        values((actor->>'id')::uuid,inserted.asset_id,inserted.requirement_id,inserted.id,'pm_occurrence_created',actor->>'name',pg_catalog.jsonb_build_object('original_due_date',inserted.original_due_date,'occurrence_number',inserted.occurrence_number)::text);
      end if;
      n:=n+1;
    end loop;
  end loop;
  return pg_catalog.jsonb_build_object('ok',true,'created_occurrences',created_count,'through_date',p_through_date);
end;
$fn$;

create or replace function public.generate_pm_work_order(p_occurrence_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); occurrence public.pm_occurrences; req public.maintenance_requirements; rev public.maintenance_requirement_revisions; asset public.assets; work public.work_orders; attempt integer; error_code text; previous_error_code text;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  select * into occurrence from public.pm_occurrences where id=p_occurrence_id for update; if not found then return public.pm_result_error('NOT_FOUND','PM Occurrence not found.'); end if;
  select * into work from public.work_orders where pm_occurrence_id=occurrence.id;
  if found then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(work),'occurrence',pg_catalog.to_jsonb(occurrence)); end if;
  if occurrence.generation_status='cancelled' then return public.pm_result_error('OCCURRENCE_CANCELLED','Cancelled PM Occurrences cannot generate work.'); end if;
  select * into req from public.maintenance_requirements where id=occurrence.requirement_id;
  select * into rev from public.maintenance_requirement_revisions where id=occurrence.requirement_revision_id;
  select * into asset from public.assets where id=occurrence.asset_id;
  attempt:=occurrence.generation_attempts+1;
  previous_error_code:=occurrence.last_generation_error_code;
  if req.state<>'active' then error_code:='REQUIREMENT_INACTIVE';
  elsif asset.lifecycle_status='decommissioned' then error_code:='ASSET_DECOMMISSIONED';
  elsif rev.requirement_id<>req.id or req.asset_id<>asset.id then error_code:='PM_REFERENCE_MISMATCH'; end if;
  if error_code is not null then
    update public.pm_occurrences set generation_status='generation_failed',generation_attempts=attempt,last_generation_error_code=error_code where id=occurrence.id returning * into occurrence;
    if previous_error_code is distinct from error_code then
      insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note) values((actor->>'id')::uuid,asset.id,req.id,occurrence.id,'pm_generation_failed',actor->>'name',pg_catalog.jsonb_build_object('code',error_code,'attempt',attempt)::text);
      insert into public.notification_outbox(pm_occurrence_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
      select occurrence.id,'pm_generation_failed','pm-occurrence:'||occurrence.id::text||':generation-failed:'||error_code,p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('pm_occurrence_id',occurrence.id,'code',error_code,'status','queued'),'pending'
      from public.profiles p where p.is_active and p.deleted_at is null and p.role in ('supervisor','administrator') on conflict do nothing;
    end if;
    return public.pm_result_error(error_code,'PM Work Order generation is blocked.');
  end if;
  begin
    insert into public.work_orders(user_id,requested_by,title,description,location,site,priority,status,source,source_reference,asset_id,department_id,due_date,estimated_hours,internal_notes,submitted_by,submitted_at,pm_occurrence_id)
    values((actor->>'id')::uuid,(actor->>'id')::uuid,rev.title,rev.scope,asset.location,asset.site,rev.default_priority,'submitted',rev.maintenance_type,req.requirement_number,asset.id,rev.department_id,occurrence.current_due_date,rev.estimated_hours,
      nullif(pg_catalog.concat_ws(E'\n\n',case when rev.instructions is not null then 'Instructions: '||rev.instructions end,case when rev.evidence_guidance is not null then 'Evidence guidance: '||rev.evidence_guidance end,case when rev.procedure_reference is not null then 'Procedure: '||rev.procedure_reference end),''),actor->>'name',pg_catalog.now(),occurrence.id) returning * into work;
    insert into public.activity_logs(user_id,work_order_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,from_status,to_status,actor,note)
    values((actor->>'id')::uuid,work.id,asset.id,req.id,occurrence.id,'work_order_created',null,'submitted',actor->>'name',pg_catalog.jsonb_build_object('source',work.source,'pm_requirement',req.requirement_number)::text);
    insert into public.activity_logs(user_id,work_order_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
    values((actor->>'id')::uuid,work.id,asset.id,req.id,occurrence.id,'pm_work_order_generated',actor->>'name',pg_catalog.jsonb_build_object('original_due_date',occurrence.original_due_date,'current_due_date',occurrence.current_due_date,'attempt',attempt)::text);
    update public.pm_occurrences set generation_status='generated',generated_at=pg_catalog.now(),generation_attempts=attempt,last_generation_error_code=null where id=occurrence.id returning * into occurrence;
    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(work),'occurrence',pg_catalog.to_jsonb(occurrence));
  exception when others then
    error_code:='WORK_ORDER_GENERATION_FAILED';
    update public.pm_occurrences set generation_status='generation_failed',generation_attempts=attempt,last_generation_error_code=error_code where id=occurrence.id returning * into occurrence;
    if previous_error_code is distinct from error_code then
      insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note) values((actor->>'id')::uuid,asset.id,req.id,occurrence.id,'pm_generation_failed',actor->>'name',pg_catalog.jsonb_build_object('code',error_code,'attempt',attempt)::text);
      insert into public.notification_outbox(pm_occurrence_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
      select occurrence.id,'pm_generation_failed','pm-occurrence:'||occurrence.id::text||':generation-failed:'||error_code,p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('pm_occurrence_id',occurrence.id,'code',error_code,'status','queued'),'pending'
      from public.profiles p where p.is_active and p.deleted_at is null and p.role in ('supervisor','administrator') on conflict do nothing;
    end if;
    return public.pm_result_error(error_code,'PM Work Order generation failed.');
  end;
end;
$fn$;

create or replace function public.process_due_pm_work(p_through_date date)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); materialized jsonb; row record; result jsonb; generated integer:=0; failed integer:=0;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  materialized:=public.materialize_pm_occurrences(p_through_date); if coalesce((materialized->>'ok')::boolean,false) is not true then return materialized; end if;
  for row in select id from public.pm_occurrences where current_due_date<=p_through_date and generation_status in ('pending','generation_failed') order by current_due_date,id loop
    result:=public.generate_pm_work_order(row.id);
    if coalesce((result->>'ok')::boolean,false) then generated:=generated+1; else failed:=failed+1; end if;
  end loop;
  return pg_catalog.jsonb_build_object('ok',true,'materialized',coalesce((materialized->>'created_occurrences')::integer,0),'generated',generated,'failed',failed,'through_date',p_through_date);
end;
$fn$;

create or replace function public.defer_pm_occurrence(p_occurrence_id uuid,p_revised_due_date date,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); occurrence public.pm_occurrences; deferral public.pm_occurrence_deferrals; work public.work_orders; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); sequence integer;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if reason is null then return public.pm_result_error('REASON_REQUIRED','A deferral reason is required.'); end if;
  select * into occurrence from public.pm_occurrences where id=p_occurrence_id for update; if not found then return public.pm_result_error('NOT_FOUND','PM Occurrence not found.'); end if;
  if occurrence.generation_status='cancelled' then return public.pm_result_error('OCCURRENCE_CANCELLED','Cancelled PM Occurrences cannot be deferred.'); end if;
  if p_revised_due_date is null or p_revised_due_date<=occurrence.current_due_date then return public.pm_result_error('VALIDATION_ERROR','Revised due date must be later than the current due date.'); end if;
  select * into work from public.work_orders where pm_occurrence_id=occurrence.id for update;
  if found and work.status in ('in_progress','completed','reviewed','closed','cancelled') then return public.pm_result_error('WORK_ALREADY_STARTED','PM cannot be deferred after work has started or terminated.'); end if;
  select coalesce(pg_catalog.max(d.sequence_number),0)+1 into sequence from public.pm_occurrence_deferrals d where d.occurrence_id=occurrence.id;
  insert into public.pm_occurrence_deferrals(occurrence_id,sequence_number,previous_due_date,revised_due_date,reason,deferred_by)
  values(occurrence.id,sequence,occurrence.current_due_date,p_revised_due_date,reason,(actor->>'id')::uuid) returning * into deferral;
  update public.pm_occurrences set current_due_date=p_revised_due_date where id=occurrence.id returning * into occurrence;
  if work.id is not null then update public.work_orders set due_date=p_revised_due_date,updated_at=pg_catalog.now() where id=work.id returning * into work; end if;
  insert into public.activity_logs(user_id,work_order_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
  values((actor->>'id')::uuid,work.id,occurrence.asset_id,occurrence.requirement_id,occurrence.id,'pm_occurrence_deferred',actor->>'name',pg_catalog.jsonb_build_object('sequence',sequence,'previous_due_date',deferral.previous_due_date,'revised_due_date',deferral.revised_due_date,'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'occurrence',pg_catalog.to_jsonb(occurrence),'deferral',pg_catalog.to_jsonb(deferral),'work_order',case when work.id is null then null else pg_catalog.to_jsonb(work) end);
end;
$fn$;

create or replace function public.cancel_pm_occurrence(p_occurrence_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); occurrence public.pm_occurrences; work public.work_orders; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null or actor->>'role'<>'administrator' then return public.pm_result_error('ACCESS_DENIED','Administrator authority is required.'); end if;
  if reason is null then return public.pm_result_error('REASON_REQUIRED','A cancellation reason is required.'); end if;
  select * into occurrence from public.pm_occurrences where id=p_occurrence_id for update; if not found then return public.pm_result_error('NOT_FOUND','PM Occurrence not found.'); end if;
  if occurrence.generation_status='cancelled' then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','occurrence',pg_catalog.to_jsonb(occurrence)); end if;
  select * into work from public.work_orders where pm_occurrence_id=occurrence.id for update;
  if found and work.status<>'cancelled' then return public.pm_result_error('WORK_ORDER_CANCELLATION_REQUIRED','Cancel the linked Work Order through its existing lifecycle first.'); end if;
  update public.pm_occurrences set generation_status='cancelled',generated_at=null,cancelled_by=(actor->>'id')::uuid,cancellation_reason=reason,cancelled_at=pg_catalog.now() where id=occurrence.id returning * into occurrence;
  insert into public.activity_logs(user_id,work_order_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
  values((actor->>'id')::uuid,work.id,occurrence.asset_id,occurrence.requirement_id,occurrence.id,'pm_occurrence_cancelled',actor->>'name',pg_catalog.jsonb_build_object('reason',reason,'linked_work_order',work.id)::text);
  return pg_catalog.jsonb_build_object('ok',true,'occurrence',pg_catalog.to_jsonb(occurrence));
end;
$fn$;

create view public.pm_occurrence_compliance with(security_invoker=true) as
select o.id,o.requirement_id,o.requirement_revision_id,o.asset_id,o.original_due_date,o.current_due_date,o.generation_status,
  w.id work_order_id,w.status work_order_status,w.reviewed_at,
  count(d.id)::integer deferral_count,
  count(d.id)>0 deferred,count(d.id)>1 repeatedly_deferred,
  case
    when o.generation_status='cancelled' then 'cancelled'
    when o.generation_status='generation_failed' and w.id is null then 'generation_failed'
    when w.reviewed_at is not null and (w.reviewed_at at time zone 'Asia/Singapore')::date<=o.current_due_date then 'completed_on_time'
    when w.reviewed_at is not null then 'completed_late'
    when o.current_due_date<public.pm_business_date() then 'overdue'
    when o.current_due_date=public.pm_business_date() then 'due'
    else 'scheduled'
  end compliance_state
from public.pm_occurrences o
left join public.work_orders w on w.pm_occurrence_id=o.id
left join public.pm_occurrence_deferrals d on d.occurrence_id=o.id
group by o.id,w.id;
grant select on public.pm_occurrence_compliance to authenticated;

revoke all on function public.protect_pm_revision(),public.pm_result_error(text,text),public.pm_business_date(),public.next_maintenance_requirement_number(timestamptz),public.calculate_pm_due_date(uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.create_pm_requirement(jsonb),public.revise_pm_requirement(uuid,jsonb,text),public.activate_pm_requirement(uuid,text),public.deactivate_pm_requirement(uuid,text,boolean),public.materialize_pm_occurrences(date),public.generate_pm_work_order(uuid),public.process_due_pm_work(date),public.defer_pm_occurrence(uuid,date,text),public.cancel_pm_occurrence(uuid,text) from public,anon,service_role;
grant execute on function public.create_pm_requirement(jsonb),public.revise_pm_requirement(uuid,jsonb,text),public.activate_pm_requirement(uuid,text),public.deactivate_pm_requirement(uuid,text,boolean),public.materialize_pm_occurrences(date),public.generate_pm_work_order(uuid),public.process_due_pm_work(date),public.defer_pm_occurrence(uuid,date,text),public.cancel_pm_occurrence(uuid,text) to authenticated;

commit;

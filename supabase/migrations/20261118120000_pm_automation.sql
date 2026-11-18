-- M35 (owner decisions D-67, 18 Nov 2026): planned maintenance runs by itself.
-- 1. Each facility has a Planned maintenance setting: off / plan_only (dates and reminders, no Work Orders) / full
--    (Work Orders created automatically on the day) / full_critical (Work Orders for critical equipment only).
--    Set by the Super-Administrator with a reason. New facilities start on plan_only.
-- 2. Allowed window around each planned date: weekly ±1 day, monthly ±3, quarterly ±7, six-monthly ±14, annual ±21.
--    A Supervisor / Facility Manager moves a date inside it (earlier or later) with a reason; beyond it only the
--    Super-Administrator or the facility's Facility Administrator (also for deferrals).
-- 3. pm_daily_run(): once a day (scheduled outside this migration) — lists the next 31 days, moves weekend dates to
--    Friday or Monday (whichever has fewer tasks that day, inside the window) and creates the Work Orders that are due,
--    as the facility's setting allows. It acts in the name of the Super-Administrator; every step is audited.
begin;

-- 1. Planned maintenance setting ---------------------------------------------------------------------------------------
alter table public.facility_settings add column pm_mode text not null default 'plan_only'
  check (pm_mode in ('off','plan_only','full','full_critical'));
comment on column public.facility_settings.pm_mode is 'M35: off / plan_only / full / full_critical (owner D-67).';

create or replace function public.facility_pm_mode(p_facility_id uuid)
returns text language sql stable security definer set search_path = pg_catalog as $function$
  select coalesce((select s.pm_mode from public.facility_settings s where s.facility_id = p_facility_id), 'plan_only')
$function$;
create or replace function public.pm_creates_work(p_facility_id uuid, p_criticality text)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select case public.facility_pm_mode(p_facility_id) when 'full' then true when 'full_critical' then p_criticality = 'critical' else false end
$function$;
revoke all on function public.facility_pm_mode(uuid), public.pm_creates_work(uuid, text) from public, anon, service_role;
grant execute on function public.facility_pm_mode(uuid), public.pm_creates_work(uuid, text) to authenticated;

create or replace function public.admin_set_pm_mode(p_facility_id uuid, p_mode text, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); v_previous text; v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  if actor is null or actor ->> 'role' <> 'administrator' then return public.pm_result_error('ACCESS_DENIED', 'Only the Super-Administrator changes the planned maintenance setting.'); end if;
  if p_mode is null or p_mode not in ('off','plan_only','full','full_critical') then return public.pm_result_error('VALIDATION_ERROR', 'Choose Off, Plan only, Full or Full for critical equipment only.'); end if;
  if pg_catalog.length(v_reason) < 5 then return public.pm_result_error('VALIDATION_ERROR', 'Give a reason of at least 5 characters.'); end if;
  if not exists(select 1 from public.sites where id = p_facility_id and is_active) then return public.pm_result_error('NOT_FOUND', 'Facility not found.'); end if;
  v_previous := public.facility_pm_mode(p_facility_id);
  if v_previous = p_mode then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE'); end if;
  insert into public.facility_settings(facility_id, pm_mode, updated_by, updated_at) values (p_facility_id, p_mode, (actor ->> 'id')::uuid, pg_catalog.now())
  on conflict (facility_id) do update set pm_mode = excluded.pm_mode, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  insert into public.facility_settings_history(facility_id, previous, next, reason, changed_by)
  values (p_facility_id, pg_catalog.jsonb_build_object('pm_mode', v_previous), pg_catalog.jsonb_build_object('pm_mode', p_mode), v_reason, (actor ->> 'id')::uuid);
  return pg_catalog.jsonb_build_object('ok', true, 'previous', v_previous, 'pm_mode', p_mode);
end;
$function$;
revoke all on function public.admin_set_pm_mode(uuid, text, text) from public, anon, service_role;
grant execute on function public.admin_set_pm_mode(uuid, text, text) to authenticated;

-- 2. Allowed window ----------------------------------------------------------------------------------------------------
create or replace function public.pm_window_days(p_value integer, p_unit text)
returns integer language sql immutable set search_path = pg_catalog as $function$
  select case
    when p_unit = 'day' then 0
    when p_unit = 'week' and p_value = 1 then 1
    when p_unit = 'month' and p_value = 1 then 3
    when p_unit = 'month' and p_value = 3 then 7
    when p_unit = 'month' and p_value = 6 then 14
    when (p_unit = 'month' and p_value = 12) or (p_unit = 'year' and p_value = 1) then 21
    else least(21, (p_value * case p_unit when 'week' then 7 when 'month' then 30 when 'year' then 365 else 1 end) / 10)
  end
$function$;
create or replace function public.pm_within_window(p_occurrence_id uuid, p_date date)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select coalesce((select pg_catalog.abs(p_date - o.original_due_date) <= public.pm_window_days(v.interval_value, v.interval_unit)
    from public.pm_occurrences o join public.maintenance_requirement_revisions v on v.id = o.requirement_revision_id where o.id = p_occurrence_id), false)
$function$;
-- Who may go beyond the window: the Super-Administrator or the facility's Facility Administrator (owner D-67 B).
create or replace function public.pm_window_overrider(p_facility_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and (public.current_user_role() = 'administrator'
    or (public.current_user_role() = 'facility_administrator' and public.active_facility_member(p_facility_id, 'facility_administrator')))
$function$;
revoke all on function public.pm_window_days(integer, text), public.pm_within_window(uuid, date), public.pm_window_overrider(uuid) from public, anon, service_role;
grant execute on function public.pm_window_days(integer, text), public.pm_within_window(uuid, date), public.pm_window_overrider(uuid) to authenticated;

-- A date may now also move earlier, inside the window (at most 21 days, the widest window).
alter table public.pm_occurrences drop constraint pm_occurrence_due_check;
alter table public.pm_occurrences add constraint pm_occurrence_due_check check (current_due_date >= original_due_date - 21);

create table public.pm_occurrence_reschedules (
  id uuid primary key default gen_random_uuid(),
  occurrence_id uuid not null references public.pm_occurrences(id) on delete restrict,
  previous_due_date date not null,
  revised_due_date date not null,
  reason text not null check (pg_catalog.length(pg_catalog.btrim(reason)) between 3 and 2000),
  beyond_window boolean not null default false,
  automatic boolean not null default false,
  rescheduled_by uuid not null references public.profiles(id) on delete restrict,
  rescheduled_at timestamptz not null default pg_catalog.now(),
  constraint pm_reschedule_changed check (revised_due_date <> previous_due_date)
);
create index pm_reschedules_occurrence_idx on public.pm_occurrence_reschedules(occurrence_id, rescheduled_at desc);
comment on table public.pm_occurrence_reschedules is 'M35: planned-maintenance date moves (Supervisor inside the window; weekend moves by the daily run).';
alter table public.pm_occurrence_reschedules enable row level security;
revoke all on public.pm_occurrence_reschedules from public, anon, authenticated, service_role;
grant select on public.pm_occurrence_reschedules to authenticated;
create policy pm_occurrence_reschedules_read on public.pm_occurrence_reschedules for select to authenticated using (
  exists(select 1 from public.pm_occurrences o where o.id = occurrence_id));

create or replace function public.reschedule_pm_occurrence(p_occurrence_id uuid, p_new_date date, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); occurrence public.pm_occurrences; work public.work_orders; v_facility uuid; v_within boolean;
  v_reason text := pg_catalog.btrim(coalesce(p_reason, '')); v_previous date;
begin
  if actor is null then return public.pm_result_error('ACCESS_DENIED', 'Please sign in.'); end if;
  select * into occurrence from public.pm_occurrences where id = p_occurrence_id for update;
  if not found then return public.pm_result_error('NOT_FOUND', 'Planned maintenance date not found.'); end if;
  if occurrence.generation_status = 'cancelled' then return public.pm_result_error('OCCURRENCE_CANCELLED', 'This planned maintenance was cancelled.'); end if;
  v_facility := public.facility_of_asset(occurrence.asset_id);
  if not public.pm_planner_for(v_facility) and not public.pm_window_overrider(v_facility) then
    return public.pm_result_error('ACCESS_DENIED', 'A Supervisor or Facility Manager of this facility changes planned dates.'); end if;
  if p_new_date is null or p_new_date < public.pm_business_date() then return public.pm_result_error('VALIDATION_ERROR', 'Choose today or a later date.'); end if;
  if pg_catalog.length(v_reason) < 3 then return public.pm_result_error('REASON_REQUIRED', 'Give a short reason for the change.'); end if;
  if p_new_date = occurrence.current_due_date then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE'); end if;
  v_within := public.pm_within_window(occurrence.id, p_new_date);
  if not v_within and not public.pm_window_overrider(v_facility) then
    return public.pm_result_error('BEYOND_WINDOW', 'That date is outside the allowed window. The Super-Administrator or the Facility Administrator approves dates beyond it.'); end if;
  if p_new_date < occurrence.original_due_date - 21 then return public.pm_result_error('VALIDATION_ERROR', 'A date cannot move more than 21 days earlier than planned.'); end if;
  select * into work from public.work_orders where pm_occurrence_id = occurrence.id for update;
  if found and work.status in ('in_progress','completed','reviewed','closed','cancelled') then
    return public.pm_result_error('WORK_ALREADY_STARTED', 'The work has started, so its date can no longer change.'); end if;
  v_previous := occurrence.current_due_date;
  update public.pm_occurrences set current_due_date = p_new_date where id = occurrence.id;
  if work.id is not null then update public.work_orders set due_date = p_new_date, updated_at = pg_catalog.now() where id = work.id; end if;
  insert into public.pm_occurrence_reschedules(occurrence_id, previous_due_date, revised_due_date, reason, beyond_window, rescheduled_by)
  values (occurrence.id, v_previous, p_new_date, v_reason, not v_within, (actor ->> 'id')::uuid);
  insert into public.activity_logs(user_id, work_order_id, asset_id, maintenance_requirement_id, pm_occurrence_id, action, actor, note)
  values ((actor ->> 'id')::uuid, work.id, occurrence.asset_id, occurrence.requirement_id, occurrence.id, 'pm_occurrence_rescheduled', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('previous_due_date', v_previous, 'revised_due_date', p_new_date, 'planned', occurrence.original_due_date, 'beyond_window', not v_within, 'reason', v_reason)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'previous_due_date', v_previous, 'revised_due_date', p_new_date, 'beyond_window', not v_within);
end;
$function$;
revoke all on function public.reschedule_pm_occurrence(uuid, date, text) from public, anon, service_role;
grant execute on function public.reschedule_pm_occurrence(uuid, date, text) to authenticated;

-- Existing functions follow the setting: no dates for 'off'; Work Orders only where the setting allows.
create or replace function public.materialize_pm_occurrences(p_through_date date)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); req record; n integer; due_value date; inserted public.pm_occurrences; created_count integer:=0; today date:=public.pm_business_date();
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if p_through_date is null or p_through_date<today or p_through_date>today+366 then return public.pm_result_error('INVALID_HORIZON','Materialization horizon must be within 366 days.'); end if;
  for req in select r.id requirement_id,r.asset_id,r.current_revision_id from public.maintenance_requirements r join public.assets a on a.id=r.asset_id where r.state='active' and a.lifecycle_status<>'decommissioned' and public.facility_pm_mode(a.facility_id)<>'off' order by r.id loop
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

create or replace function public.process_due_pm_work(p_through_date date)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); materialized jsonb; row record; result jsonb; generated integer:=0; failed integer:=0;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  materialized:=public.materialize_pm_occurrences(p_through_date); if coalesce((materialized->>'ok')::boolean,false) is not true then return materialized; end if;
  for row in select o.id from public.pm_occurrences o join public.assets a on a.id=o.asset_id where o.current_due_date<=p_through_date and o.generation_status in ('pending','generation_failed') and public.pm_creates_work(a.facility_id,a.criticality) order by o.current_due_date,o.id loop
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
  -- M35: beyond the allowed window only the Super-Administrator or the facility's Facility Administrator.
  if not public.pm_within_window(occurrence.id,p_revised_due_date) and not public.pm_window_overrider(public.facility_of_asset(occurrence.asset_id)) then
    return public.pm_result_error('BEYOND_WINDOW','That date is outside the allowed window. The Super-Administrator or the Facility Administrator approves dates beyond it.'); end if;
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

-- 3. The daily run ------------------------------------------------------------------------------------------------------
create or replace function public.pm_daily_run(p_today date default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare v_today date := coalesce(p_today, public.pm_business_date()); v_actor uuid; mat jsonb; o record; r jsonb;
  v_window integer; v_fri date; v_mon date; v_pick date; v_fri_load integer; v_mon_load integer;
  moved integer := 0; generated integer := 0; failed integer := 0;
begin
  select p.id into v_actor from public.profiles p where p.role = 'administrator' and p.is_active and p.deleted_at is null
    and public.pilot_account_ready(p.id) order by p.created_at limit 1;
  if v_actor is null then return public.pm_result_error('NO_ACTOR', 'No ready Super-Administrator to act for the daily run.'); end if;
  perform pg_catalog.set_config('request.jwt.claim.sub', v_actor::text, true),
          pg_catalog.set_config('request.jwt.claims', pg_catalog.jsonb_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  -- a. List the next 31 days.
  mat := public.materialize_pm_occurrences(v_today + 31);
  if coalesce((mat ->> 'ok')::boolean, false) is not true then return mat; end if;
  -- b. Weekend dates move to Friday or Monday inside the window, to the day with fewer tasks (owner D-67 C).
  for o in
    select x.id, x.current_due_date d, x.asset_id, a.facility_id, v.interval_value, v.interval_unit
    from public.pm_occurrences x join public.assets a on a.id = x.asset_id join public.maintenance_requirement_revisions v on v.id = x.requirement_revision_id
    where x.generation_status = 'pending' and x.current_due_date between v_today and v_today + 31 and x.current_due_date = x.original_due_date
      and pg_catalog.date_part('isodow', x.current_due_date) in (6, 7) and v.interval_unit <> 'day'
      and public.facility_pm_mode(a.facility_id) <> 'off'
      and not exists(select 1 from public.pm_occurrence_reschedules s where s.occurrence_id = x.id)
    order by x.current_due_date, x.id
  loop
    v_window := public.pm_window_days(o.interval_value, o.interval_unit);
    v_fri := o.d - case when pg_catalog.date_part('isodow', o.d) = 6 then 1 else 2 end;
    v_mon := o.d + case when pg_catalog.date_part('isodow', o.d) = 6 then 2 else 1 end;
    if o.d - v_fri > v_window or v_fri < v_today then v_fri := null; end if;
    if v_mon - o.d > v_window then v_mon := null; end if;
    if v_fri is null and v_mon is null then continue; end if;
    select count(*) into v_fri_load from public.pm_occurrences y join public.assets b on b.id = y.asset_id where b.facility_id = o.facility_id and y.current_due_date = v_fri and y.generation_status <> 'cancelled';
    select count(*) into v_mon_load from public.pm_occurrences y join public.assets b on b.id = y.asset_id where b.facility_id = o.facility_id and y.current_due_date = v_mon and y.generation_status <> 'cancelled';
    v_pick := case when v_fri is null then v_mon when v_mon is null then v_fri when v_mon_load < v_fri_load then v_mon else v_fri end;
    update public.pm_occurrences set current_due_date = v_pick where id = o.id;
    insert into public.pm_occurrence_reschedules(occurrence_id, previous_due_date, revised_due_date, reason, automatic, rescheduled_by)
    values (o.id, o.d, v_pick, 'Weekend date moved to ' || case when v_pick < o.d then 'Friday' else 'Monday' end || ' (fewer tasks that day)', true, v_actor);
    moved := moved + 1;
  end loop;
  -- c. Create the Work Orders that are due, where the facility's setting allows (owner D-67: Facility 2 critical only).
  for o in
    select x.id from public.pm_occurrences x join public.assets a on a.id = x.asset_id join public.maintenance_requirement_revisions v on v.id = x.requirement_revision_id
    where x.generation_status in ('pending','generation_failed') and x.current_due_date - coalesce(v.lead_time_days, 0) <= v_today
      and public.pm_creates_work(a.facility_id, a.criticality)
    order by x.current_due_date, x.id
  loop
    r := public.generate_pm_work_order(o.id);
    if coalesce((r ->> 'ok')::boolean, false) then generated := generated + 1; else failed := failed + 1; end if;
  end loop;
  insert into public.activity_logs(user_id, action, actor, note)
  values (v_actor, 'pm_daily_run', 'FMWorks daily run', pg_catalog.jsonb_build_object('date', v_today, 'listed', coalesce((mat ->> 'created_occurrences')::integer, 0),
    'weekend_moves', moved, 'work_orders', generated, 'failed', failed)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'date', v_today, 'listed', coalesce((mat ->> 'created_occurrences')::integer, 0), 'weekend_moves', moved, 'work_orders', generated, 'failed', failed);
end;
$function$;
revoke all on function public.pm_daily_run(date) from public, anon, authenticated;
grant execute on function public.pm_daily_run(date) to service_role;

commit;

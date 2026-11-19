-- M36 (owner decisions D-67 D-G, 18 Nov 2026): the Daily round.
-- One "Daily round" Work Order per facility per day (every day), ready 07:00 and due 10:00 by default, with a
-- tick-off checklist: checks (for example "Chiller CH-01") each with items (tick, or a reading with its unit). Items
-- and checks can be added. The Approver, Supervisor, Facility Manager, Facility Administrator or Super-Administrator
-- sets the Technician who does it and the one who covers. It is routine: no permit, method statement or risk
-- assessment, no quotation, no SLA clock. The Technician records each item; when every item is recorded the round is
-- completed and closed. Created by the daily run (M35) where the facility's setting creates Work Orders.
begin;

-- 1. Settings per facility -------------------------------------------------------------------------------------------
alter table public.facility_settings
  add column daily_round_enabled boolean not null default false,
  add column daily_round_ready time not null default '07:00',
  add column daily_round_due time not null default '10:00',
  add column daily_round_technician_id uuid references public.profiles(id) on delete set null,
  add column daily_round_cover_id uuid references public.profiles(id) on delete set null,
  add constraint facility_settings_daily_round_times check (daily_round_due > daily_round_ready);

-- Who looks after a facility's Daily round (owner D-67 D: Approver, Supervisor or Facility Manager; plus the
-- Facility Administrator and the Super-Administrator).
create or replace function public.daily_round_editor(p_facility_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and (public.current_user_role() = 'administrator' or exists(
    select 1 from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = auth.uid() and m.active
      and m.membership_role in ('approver','supervisor','facility_manager','facility_administrator')
      and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now())))
$function$;
create or replace function public.facility_member(p_facility_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and (public.current_user_role() = 'administrator' or exists(
    select 1 from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = auth.uid() and m.active
      and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now())))
$function$;
revoke all on function public.daily_round_editor(uuid), public.facility_member(uuid) from public, anon, service_role;
grant execute on function public.daily_round_editor(uuid), public.facility_member(uuid) to authenticated;

-- 2. Checklist -------------------------------------------------------------------------------------------------------
create table public.daily_round_checks (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.sites(id) on delete restrict,
  position integer not null default 100,
  title text not null check (pg_catalog.length(pg_catalog.btrim(title)) between 2 and 200),
  equipment text check (equipment is null or pg_catalog.length(equipment) <= 300),
  asset_id uuid references public.assets(id) on delete set null,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);
create index daily_round_checks_facility_idx on public.daily_round_checks(facility_id, position) where active;
create table public.daily_round_items (
  id uuid primary key default gen_random_uuid(),
  check_id uuid not null references public.daily_round_checks(id) on delete restrict,
  position integer not null default 100,
  label text not null check (pg_catalog.length(pg_catalog.btrim(label)) between 2 and 300),
  reading_unit text check (reading_unit is null or pg_catalog.length(reading_unit) between 1 and 20),
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now()
);
create index daily_round_items_check_idx on public.daily_round_items(check_id, position) where active;
comment on table public.daily_round_checks is 'M36: the Daily round checklist of a facility (owner D-67 D).';
comment on table public.daily_round_items is 'M36: the items of a Daily round check; reading_unit set = a reading is entered, null = tick only.';

-- 3. The Daily round Work Order and its results -------------------------------------------------------------------------
alter table public.work_orders add column daily_round_date date;
create unique index work_orders_daily_round_unique on public.work_orders(facility_id, daily_round_date) where daily_round_date is not null;
create table public.daily_round_results (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete restrict,
  item_id uuid not null references public.daily_round_items(id) on delete restrict,
  ok boolean not null,
  reading text check (reading is null or pg_catalog.length(reading) <= 60),
  note text check (note is null or pg_catalog.length(note) <= 1000),
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  recorded_at timestamptz not null default pg_catalog.now(),
  unique (work_order_id, item_id)
);
comment on table public.daily_round_results is 'M36: what the Technician found for each item of a Daily round.';

alter table public.daily_round_checks enable row level security;
alter table public.daily_round_items enable row level security;
alter table public.daily_round_results enable row level security;
revoke all on public.daily_round_checks, public.daily_round_items, public.daily_round_results from public, anon, authenticated, service_role;
grant select on public.daily_round_checks, public.daily_round_items, public.daily_round_results to authenticated;
create policy daily_round_checks_read on public.daily_round_checks for select to authenticated using (public.facility_member(facility_id));
create policy daily_round_items_read on public.daily_round_items for select to authenticated using (
  exists(select 1 from public.daily_round_checks c where c.id = check_id));
create policy daily_round_results_read on public.daily_round_results for select to authenticated using (
  exists(select 1 from public.work_orders w where w.id = work_order_id));

-- 4. Functions ---------------------------------------------------------------------------------------------------------
create or replace function public.set_daily_round_settings(p_facility_id uuid, p_enabled boolean, p_technician_id uuid, p_cover_id uuid, p_ready time, p_due time, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); v_reason text := pg_catalog.btrim(coalesce(p_reason, '')); v_previous jsonb;
begin
  if actor is null or not public.daily_round_editor(p_facility_id) then
    return public.pm_result_error('ACCESS_DENIED', 'The Approver, Supervisor, Facility Manager or Facility Administrator of this facility sets the Daily round.'); end if;
  if pg_catalog.length(v_reason) < 3 then return public.pm_result_error('REASON_REQUIRED', 'Give a short reason.'); end if;
  if p_ready is null or p_due is null or p_due <= p_ready then return public.pm_result_error('VALIDATION_ERROR', 'The round must be due after it is ready.'); end if;
  if (p_technician_id is not null and not public.active_facility_member(p_facility_id, 'technician', p_technician_id))
     or (p_cover_id is not null and not public.active_facility_member(p_facility_id, 'technician', p_cover_id)) then
    return public.pm_result_error('INVALID_REFERENCE', 'Choose Technicians who are staff of this facility.'); end if;
  if p_enabled and p_technician_id is null then return public.pm_result_error('VALIDATION_ERROR', 'Choose the Technician who does the round.'); end if;
  select pg_catalog.jsonb_build_object('enabled', daily_round_enabled, 'technician', daily_round_technician_id, 'cover', daily_round_cover_id, 'ready', daily_round_ready, 'due', daily_round_due)
    into v_previous from public.facility_settings where facility_id = p_facility_id;
  insert into public.facility_settings(facility_id, daily_round_enabled, daily_round_technician_id, daily_round_cover_id, daily_round_ready, daily_round_due, updated_by, updated_at)
  values (p_facility_id, coalesce(p_enabled, false), p_technician_id, p_cover_id, p_ready, p_due, (actor ->> 'id')::uuid, pg_catalog.now())
  on conflict (facility_id) do update set daily_round_enabled = excluded.daily_round_enabled, daily_round_technician_id = excluded.daily_round_technician_id,
    daily_round_cover_id = excluded.daily_round_cover_id, daily_round_ready = excluded.daily_round_ready, daily_round_due = excluded.daily_round_due,
    updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  insert into public.facility_settings_history(facility_id, previous, next, reason, changed_by)
  values (p_facility_id, pg_catalog.jsonb_build_object('daily_round', v_previous),
    pg_catalog.jsonb_build_object('daily_round', pg_catalog.jsonb_build_object('enabled', coalesce(p_enabled, false), 'technician', p_technician_id, 'cover', p_cover_id, 'ready', p_ready, 'due', p_due)),
    v_reason, (actor ->> 'id')::uuid);
  return pg_catalog.jsonb_build_object('ok', true);
end;
$function$;

create or replace function public.save_daily_round_check(p_check_id uuid, p_facility_id uuid, p_title text, p_equipment text, p_position integer, p_active boolean)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); v_facility uuid; v_id uuid;
begin
  v_facility := coalesce((select facility_id from public.daily_round_checks where id = p_check_id), p_facility_id);
  if actor is null or v_facility is null or not public.daily_round_editor(v_facility) then return public.pm_result_error('ACCESS_DENIED', 'You cannot change this Daily round.'); end if;
  if p_check_id is null then
    insert into public.daily_round_checks(facility_id, position, title, equipment, active, created_by)
    values (v_facility, coalesce(p_position, 100), pg_catalog.btrim(p_title), nullif(pg_catalog.btrim(coalesce(p_equipment, '')), ''), coalesce(p_active, true), (actor ->> 'id')::uuid)
    returning id into v_id;
  else
    update public.daily_round_checks set title = pg_catalog.btrim(p_title), equipment = nullif(pg_catalog.btrim(coalesce(p_equipment, '')), ''),
      position = coalesce(p_position, position), active = coalesce(p_active, active), updated_at = pg_catalog.now()
    where id = p_check_id returning id into v_id;
  end if;
  insert into public.activity_logs(user_id, action, actor, note) values ((actor ->> 'id')::uuid, 'daily_round_check_saved', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('check_id', v_id, 'facility_id', v_facility, 'title', p_title, 'active', p_active)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation then return public.pm_result_error('VALIDATION_ERROR', 'Give the check a name of 2 to 200 characters.');
end;
$function$;

create or replace function public.save_daily_round_item(p_item_id uuid, p_check_id uuid, p_label text, p_reading_unit text, p_position integer, p_active boolean)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); v_check uuid; v_facility uuid; v_id uuid;
begin
  v_check := coalesce((select check_id from public.daily_round_items where id = p_item_id), p_check_id);
  select facility_id into v_facility from public.daily_round_checks where id = v_check;
  if actor is null or v_facility is null or not public.daily_round_editor(v_facility) then return public.pm_result_error('ACCESS_DENIED', 'You cannot change this Daily round.'); end if;
  if p_item_id is null then
    insert into public.daily_round_items(check_id, position, label, reading_unit, active, created_by)
    values (v_check, coalesce(p_position, 100), pg_catalog.btrim(p_label), nullif(pg_catalog.btrim(coalesce(p_reading_unit, '')), ''), coalesce(p_active, true), (actor ->> 'id')::uuid)
    returning id into v_id;
  else
    update public.daily_round_items set label = pg_catalog.btrim(p_label), reading_unit = nullif(pg_catalog.btrim(coalesce(p_reading_unit, '')), ''),
      position = coalesce(p_position, position), active = coalesce(p_active, active)
    where id = p_item_id returning id into v_id;
  end if;
  insert into public.activity_logs(user_id, action, actor, note) values ((actor ->> 'id')::uuid, 'daily_round_item_saved', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('item_id', v_id, 'check_id', v_check, 'label', p_label, 'active', p_active)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation then return public.pm_result_error('VALIDATION_ERROR', 'Give the item 2 to 300 characters, and a unit of up to 20.');
end;
$function$;

-- Create a facility's round for a day (the daily run, or an editor pressing "Start today's round").
create or replace function public.create_daily_round(p_facility_id uuid, p_date date)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); s public.facility_settings; v_site text; v_tech uuid; v_existing uuid; w public.work_orders; v_checks text;
begin
  if actor is null then return public.pm_result_error('ACCESS_DENIED', 'Please sign in.'); end if;
  if not (actor ->> 'role' = 'administrator' or public.daily_round_editor(p_facility_id)) then
    return public.pm_result_error('ACCESS_DENIED', 'The Approver, Supervisor or Facility Manager of this facility starts the Daily round.'); end if;
  select * into s from public.facility_settings where facility_id = p_facility_id;
  if s.facility_id is null or not s.daily_round_enabled then return public.pm_result_error('NOT_ENABLED', 'The Daily round is not switched on for this facility.'); end if;
  if p_date is null or p_date < public.pm_business_date() - 1 or p_date > public.pm_business_date() + 1 then return public.pm_result_error('VALIDATION_ERROR', 'A round is for today.'); end if;
  select id into v_existing from public.work_orders where facility_id = p_facility_id and daily_round_date = p_date;
  if v_existing is not null then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE', 'work_order_id', v_existing); end if;
  if not exists(select 1 from public.daily_round_items i join public.daily_round_checks c on c.id = i.check_id where c.facility_id = p_facility_id and c.active and i.active) then
    return public.pm_result_error('EMPTY_CHECKLIST', 'Add checks to the Daily round first.'); end if;
  -- The Technician who does it, or the cover when that person is not an active member (leave comes in part 4).
  v_tech := case when s.daily_round_technician_id is not null and public.active_facility_member(p_facility_id, 'technician', s.daily_round_technician_id)
                   and exists(select 1 from public.profiles p where p.id = s.daily_round_technician_id and p.is_active and p.deleted_at is null) then s.daily_round_technician_id
                 else s.daily_round_cover_id end;
  select name into v_site from public.sites where id = p_facility_id;
  select pg_catalog.string_agg(c.title, '; ' order by c.position, c.title) into v_checks from public.daily_round_checks c where c.facility_id = p_facility_id and c.active;
  insert into public.work_orders(user_id, requested_by, title, description, location, site, priority, status, source, facility_id, due_date,
    assigned_technician_id, in_house_work, daily_round_date, approved_at, assigned_by_user_id, assigned_at, submitted_by, submitted_at)
  values ((actor ->> 'id')::uuid, (actor ->> 'id')::uuid, 'Daily round — ' || pg_catalog.to_char(p_date, 'Dy DD Mon YYYY'),
    'Routine daily checks (no permit, method statement or risk assessment). Ready ' || pg_catalog.to_char(s.daily_round_ready, 'HH24:MI') || ', due by ' || pg_catalog.to_char(s.daily_round_due, 'HH24:MI') || '. Checks: ' || v_checks,
    'Daily round — all listed areas', coalesce(v_site, 'Facility'), 'medium', 'approved', 'inspection', p_facility_id, p_date,
    v_tech, true, p_date, pg_catalog.now(), (actor ->> 'id')::uuid, pg_catalog.now(), coalesce(actor ->> 'display_name', actor ->> 'name'), pg_catalog.now())
  returning * into w;
  insert into public.activity_logs(user_id, work_order_id, action, actor, note) values ((actor ->> 'id')::uuid, w.id, 'daily_round_created', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('date', p_date, 'technician_id', v_tech)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'work_order_id', w.id, 'work_order_number', w.work_order_number);
end;
$function$;

-- Who records a round: its Technician, the cover, or an editor of the facility.
create or replace function public.daily_round_recorder(p_work_order_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select exists(select 1 from public.work_orders w left join public.facility_settings s on s.facility_id = w.facility_id
    where w.id = p_work_order_id and w.daily_round_date is not null and public.pilot_account_ready(auth.uid())
      and (w.assigned_technician_id = auth.uid() or s.daily_round_cover_id = auth.uid() or s.daily_round_technician_id = auth.uid() or public.daily_round_editor(w.facility_id)))
$function$;

create or replace function public.record_daily_round_item(p_work_order_id uuid, p_item_id uuid, p_ok boolean, p_reading text, p_note text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); w public.work_orders; v_unit text;
begin
  select * into w from public.work_orders where id = p_work_order_id for update;
  if w.id is null or w.daily_round_date is null then return public.pm_result_error('NOT_FOUND', 'Daily round not found.'); end if;
  if actor is null or not public.daily_round_recorder(w.id) then return public.pm_result_error('ACCESS_DENIED', 'The Technician of this round records it.'); end if;
  if w.status in ('closed','cancelled','reviewed','completed') then return public.pm_result_error('ROUND_CLOSED', 'This round is already completed.'); end if;
  select i.reading_unit into v_unit from public.daily_round_items i join public.daily_round_checks c on c.id = i.check_id where i.id = p_item_id and c.facility_id = w.facility_id;
  if not found then return public.pm_result_error('NOT_FOUND', 'Item not found in this round.'); end if;
  if p_ok is null then return public.pm_result_error('VALIDATION_ERROR', 'Choose OK or Not OK.'); end if;
  if v_unit is not null and pg_catalog.length(pg_catalog.btrim(coalesce(p_reading, ''))) = 0 then return public.pm_result_error('VALIDATION_ERROR', 'Enter the reading.'); end if;
  if not p_ok and pg_catalog.length(pg_catalog.btrim(coalesce(p_note, ''))) < 3 then return public.pm_result_error('VALIDATION_ERROR', 'Say what is wrong.'); end if;
  insert into public.daily_round_results(work_order_id, item_id, ok, reading, note, recorded_by)
  values (w.id, p_item_id, p_ok, nullif(pg_catalog.btrim(coalesce(p_reading, '')), ''), nullif(pg_catalog.btrim(coalesce(p_note, '')), ''), (actor ->> 'id')::uuid)
  on conflict (work_order_id, item_id) do update set ok = excluded.ok, reading = excluded.reading, note = excluded.note, recorded_by = excluded.recorded_by, recorded_at = pg_catalog.now();
  if w.status in ('approved','assigned') then
    update public.work_orders set status = 'in_progress', started_at = coalesce(started_at, pg_catalog.now()), actual_work_started_at = coalesce(actual_work_started_at, pg_catalog.now()),
      updated_at = pg_catalog.now() where id = w.id;
    insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
    values ((actor ->> 'id')::uuid, w.id, 'daily_round_started', w.status, 'in_progress', coalesce(actor ->> 'display_name', actor ->> 'name'), '{}');
  end if;
  return pg_catalog.jsonb_build_object('ok', true);
end;
$function$;

create or replace function public.complete_daily_round(p_work_order_id uuid, p_note text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); w public.work_orders; v_missing integer; v_faults integer;
begin
  select * into w from public.work_orders where id = p_work_order_id for update;
  if w.id is null or w.daily_round_date is null then return public.pm_result_error('NOT_FOUND', 'Daily round not found.'); end if;
  if actor is null or not public.daily_round_recorder(w.id) then return public.pm_result_error('ACCESS_DENIED', 'The Technician of this round completes it.'); end if;
  if w.status in ('closed','cancelled') then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE'); end if;
  select count(*) into v_missing from public.daily_round_items i join public.daily_round_checks c on c.id = i.check_id
    where c.facility_id = w.facility_id and c.active and i.active and not exists(select 1 from public.daily_round_results r where r.work_order_id = w.id and r.item_id = i.id);
  if v_missing > 0 then return public.pm_result_error('INCOMPLETE', v_missing || ' item(s) still to record.'); end if;
  select count(*) into v_faults from public.daily_round_results where work_order_id = w.id and not ok;
  update public.work_orders set status = 'closed', started_at = coalesce(started_at, pg_catalog.now()), actual_work_started_at = coalesce(actual_work_started_at, pg_catalog.now()),
    actual_work_ended_at = pg_catalog.now(), completed_at = pg_catalog.now(), reviewed_at = pg_catalog.now(), verified_at = pg_catalog.now(), closed_at = pg_catalog.now(), updated_at = pg_catalog.now(),
    completion_notes = nullif(pg_catalog.btrim(coalesce(p_note, '')), '')
  where id = w.id;
  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values ((actor ->> 'id')::uuid, w.id, 'daily_round_completed', w.status, 'closed', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('faults', v_faults, 'note', p_note)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'faults', v_faults);
end;
$function$;

revoke all on function public.set_daily_round_settings(uuid, boolean, uuid, uuid, time, time, text), public.save_daily_round_check(uuid, uuid, text, text, integer, boolean),
  public.save_daily_round_item(uuid, uuid, text, text, integer, boolean), public.create_daily_round(uuid, date), public.daily_round_recorder(uuid),
  public.record_daily_round_item(uuid, uuid, boolean, text, text), public.complete_daily_round(uuid, text) from public, anon, service_role;
grant execute on function public.set_daily_round_settings(uuid, boolean, uuid, uuid, time, time, text), public.save_daily_round_check(uuid, uuid, text, text, integer, boolean),
  public.save_daily_round_item(uuid, uuid, text, text, integer, boolean), public.create_daily_round(uuid, date), public.daily_round_recorder(uuid),
  public.record_daily_round_item(uuid, uuid, boolean, text, text), public.complete_daily_round(uuid, text) to authenticated;

-- 5. No SLA clock for the Daily round; the daily run creates the rounds.
create or replace function public.attach_approved_sla_clock()
returns trigger language plpgsql set search_path = pg_catalog as $fn$
declare selected_rule public.sla_rules; start_time timestamptz := coalesce(new.submitted_at, new.created_at, pg_catalog.now());
begin
  -- M36: the Daily round is routine; it has no SLA clock.
  if new.daily_round_date is not null then return new; end if;
  selected_rule := public.sla_rule_for(new.facility_id, new.sla_service_category_id, new.priority, start_time);
  if selected_rule.id is not null then
    insert into public.work_order_sla_clocks(work_order_id, sla_rule_id, started_at, acknowledgement_deadline, response_deadline, attendance_deadline, make_safe_deadline, rectification_deadline)
    values (new.id, selected_rule.id, start_time,
      case when selected_rule.acknowledgement_minutes is not null then start_time + pg_catalog.make_interval(mins => selected_rule.acknowledgement_minutes) end,
      case when selected_rule.response_minutes is not null then start_time + pg_catalog.make_interval(mins => selected_rule.response_minutes) end,
      case when selected_rule.attendance_minutes is not null then start_time + pg_catalog.make_interval(mins => selected_rule.attendance_minutes) end,
      case when selected_rule.make_safe_minutes is not null then start_time + pg_catalog.make_interval(mins => selected_rule.make_safe_minutes) end,
      start_time + pg_catalog.make_interval(mins => selected_rule.rectification_minutes))
    on conflict (work_order_id) do nothing;
  end if;
  return new;
end;$fn$;

create or replace function public.pm_daily_run(p_today date default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare v_today date := coalesce(p_today, public.pm_business_date()); v_actor uuid; mat jsonb; o record; r jsonb;
  v_window integer; v_fri date; v_mon date; v_pick date; v_fri_load integer; v_mon_load integer;
  moved integer := 0; generated integer := 0; failed integer := 0; rounds integer := 0;
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
  -- d. M36: the Daily round of each facility that has it switched on.
  for o in select fs.facility_id from public.facility_settings fs join public.sites s on s.id = fs.facility_id and s.is_active
    where fs.daily_round_enabled and fs.pm_mode not in ('off','plan_only') loop
    r := public.create_daily_round(o.facility_id, v_today);
    if coalesce((r ->> 'ok')::boolean, false) and r ->> 'code' is distinct from 'NO_CHANGE' then rounds := rounds + 1; end if;
  end loop;
  insert into public.activity_logs(user_id, action, actor, note)
  values (v_actor, 'pm_daily_run', 'FMWorks daily run', pg_catalog.jsonb_build_object('date', v_today, 'listed', coalesce((mat ->> 'created_occurrences')::integer, 0),
    'weekend_moves', moved, 'work_orders', generated, 'failed', failed, 'daily_rounds', rounds)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'date', v_today, 'listed', coalesce((mat ->> 'created_occurrences')::integer, 0), 'weekend_moves', moved, 'work_orders', generated, 'failed', failed, 'daily_rounds', rounds);
end;
$function$;
revoke all on function public.pm_daily_run(date) from public, anon, authenticated;
grant execute on function public.pm_daily_run(date) to service_role;

commit;

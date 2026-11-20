-- M37 (owner, 20 Nov 2026): the trial facility is not staffed for a high load, so Facility 2 goes to "Plan only"
-- (no automatic planned-maintenance Work Orders). The Daily round keeps running on Plan only: it is one routine
-- Work Order a day; only "Off" (or switching the round off) stops it.
begin;

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
  -- d. M36/M37: the Daily round of each facility that has it switched on, also on Plan only (only Off stops it).
  for o in select fs.facility_id from public.facility_settings fs join public.sites s on s.id = fs.facility_id and s.is_active
    where fs.daily_round_enabled and fs.pm_mode <> 'off' loop
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

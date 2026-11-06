begin;
-- D-36 (6 Nov 2026): field work never waits for the app. A Technician who has already carried out emergency work
-- (in-house or by a contractor) records it on one screen. This function does, all or nothing, what the Technician
-- would otherwise do in five places: create the Work Order as emergency work assigned to themselves, submit it
-- (emergency work starts without approval), record the actual start and end times, record the work-performed
-- statement and cumulative labour hours, and, when they confirm there are no separate costs to log, confirm the
-- execution cost ledger. Photos and Submit Physical Completion follow from the same screen through the existing
-- endpoints. The Approver's review afterwards is unchanged. If any step is refused, nothing is saved.

create or replace function public.record_emergency_work_done(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  started timestamptz;
  ended timestamptz;
  statement text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'completion_notes', '')), '');
  hours numeric;
  r jsonb;
  wo uuid;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'display_name', actor ->> 'name', 'Unknown user');
  if actor ->> 'role' <> 'technician' then
    return public.work_order_result_error('ACCESS_DENIED', 'Emergency work already done is recorded by the Technician who carried it out or witnessed it.');
  end if;
  begin
    started := nullif(p_payload ->> 'started_at', '')::timestamptz;
    ended := nullif(p_payload ->> 'ended_at', '')::timestamptz;
    hours := nullif(p_payload ->> 'actual_labour_hours', '')::numeric;
  exception when others then
    return public.work_order_result_error('VALIDATION_ERROR', 'Check the start time, end time and labour hours.');
  end;
  if started is null or ended is null then
    return public.work_order_result_error('VALIDATION_ERROR', 'Enter when the work started and when it ended.');
  end if;
  if statement is null or hours is null or hours < 0 then
    return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Describe the work performed and enter the labour hours.');
  end if;

  begin
    r := public.create_work_order(
      (p_payload - 'started_at' - 'ended_at' - 'completion_notes' - 'actual_labour_hours' - 'no_separate_costs'
         - 'status' - 'assigned_technician_id')
      || pg_catalog.jsonb_build_object('status', 'draft', 'emergency_work', true, 'source', 'reactive'));
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception using errcode = 'FWM36', message = r::text; end if;
    wo := (r -> 'work_order' ->> 'id')::uuid;
    r := public.transition_work_order(wo, 'submit', pg_catalog.jsonb_build_object('reason', 'Emergency work recorded after it was carried out'));
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception using errcode = 'FWM36', message = r::text; end if;
    r := public.set_work_order_actual_times(wo, started, ended);
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception using errcode = 'FWM36', message = r::text; end if;
    r := public.record_work_order_execution(wo, pg_catalog.jsonb_build_object('completion_notes', statement, 'actual_labour_hours', hours));
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception using errcode = 'FWM36', message = r::text; end if;
    if coalesce(nullif(p_payload ->> 'no_separate_costs', '')::boolean, false) then
      r := public.manage_work_order_actual_cost(wo, null, '{"operation":"confirm"}'::jsonb);
      if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception using errcode = 'FWM36', message = r::text; end if;
    end if;
    insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, wo, 'work_order_emergency_recorded_after_work', 'draft', 'in_progress', actor_name,
      pg_catalog.jsonb_build_object('started_at', started, 'ended_at', ended, 'actual_labour_hours', hours,
        'in_house_work', coalesce(nullif(p_payload ->> 'in_house_work', '')::boolean, false),
        'no_separate_costs', coalesce(nullif(p_payload ->> 'no_separate_costs', '')::boolean, false))::text);
  exception when sqlstate 'FWM36' then
    -- Every step, including creating the Work Order, is undone: nothing half-recorded remains.
    return sqlerrm::jsonb;
  end;

  return pg_catalog.jsonb_build_object('ok', true, 'work_order',
    (select pg_catalog.to_jsonb(w) from public.work_orders w where w.id = wo));
end;
$function$;

revoke all on function public.record_emergency_work_done(jsonb) from public, anon, service_role;
grant execute on function public.record_emergency_work_done(jsonb) to authenticated;

do $postcheck$
begin
  if to_regprocedure('public.record_emergency_work_done(jsonb)') is null then
    raise exception 'D-36 emergency recording was not installed';
  end if;
end;$postcheck$;
commit;

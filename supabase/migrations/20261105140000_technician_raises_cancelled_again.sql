begin;
-- D-35 (5 Nov 2026): a cancelled Work Order stays cancelled, but its Technician can raise it again as a new Draft
-- ("Raise again as new Draft"), keeping the link to the cancelled one (duplicated_from_id). Before this, only
-- approval roles could duplicate, and the copy made them the preparer. Other roles' duplication is unchanged.

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
  select * into source_order from public.work_orders where id = p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  -- D-35 (5 Nov 2026): a Technician may raise again, as a new Draft, a cancelled Work Order they were assigned to or
  -- prepared, in a facility they belong to. The new Draft is assigned to them so they can prepare and submit it; it
  -- goes through approval again. The cancelled Work Order stays cancelled.
  if actor_role = 'technician' then
    if source_order.status <> 'cancelled'
       or actor_id not in (coalesce(source_order.assigned_technician_id, '00000000-0000-0000-0000-000000000000'::uuid),
                           coalesce(source_order.requested_by, '00000000-0000-0000-0000-000000000000'::uuid))
       or not public.technician_facility_read_permitted(source_order.facility_id) then
      return public.work_order_result_error('ACCESS_DENIED', 'A Technician can only raise again a cancelled Work Order they were assigned to or prepared.');
    end if;
  end if;
  begin
    insert into public.work_orders (
      user_id, requested_by, title, description, location, site, category_id,
      priority, status, source, source_reference, alert_id, prediction_reference,
      asset_id, health_score_at_creation, failure_probability,
      predicted_failure_date, recommended_action, confidence_score,
      department_id, due_date, estimated_hours, internal_notes,
      submitted_by, contact_number, duplicated_from_id,
      facility_id, facility_area_id, assigned_technician_id
    ) values (
      actor_id, actor_id, source_order.title, source_order.description,
      source_order.location, source_order.site, source_order.category_id,
      source_order.priority, 'draft', source_order.source,
      source_order.source_reference, source_order.alert_id, source_order.prediction_reference,
      source_order.asset_id, source_order.health_score_at_creation,
      source_order.failure_probability, source_order.predicted_failure_date,
      source_order.recommended_action, source_order.confidence_score,
      source_order.department_id,
      -- UAT 4 Nov 2026 (D-32): a passed due date is not copied; the preparer sets a new one.
      case when source_order.due_date >= current_date then source_order.due_date end,
      source_order.estimated_hours,
      source_order.internal_notes, actor_name, source_order.contact_number, source_order.id,
      case when actor_role = 'technician' then source_order.facility_id end,
      case when actor_role = 'technician' then source_order.facility_area_id end,
      case when actor_role = 'technician' then actor_id end
    ) returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, actor, note)
    values (actor_id, result.id, 'work_order_duplicated', actor_name,
      pg_catalog.jsonb_build_object('source_work_order_id', source_order.id, 'source_work_order_number', source_order.work_order_number,
        'raised_again_after_cancellation', source_order.status = 'cancelled')::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Work-order duplication failed.'); end;
end;
$$;

revoke all on function public.duplicate_work_order(uuid) from public, anon, service_role;
grant execute on function public.duplicate_work_order(uuid) to authenticated;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.duplicate_work_order(uuid)'::regprocedure), 'raised_again_after_cancellation') = 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.duplicate_work_order(uuid)'::regprocedure), 'source_order.due_date >= current_date') = 0 then
    raise exception 'D-35 raise-again was not installed';
  end if;
end;$postcheck$;
commit;

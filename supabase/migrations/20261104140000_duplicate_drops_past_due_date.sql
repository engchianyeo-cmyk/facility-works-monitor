begin;
-- D-32 (4 Nov 2026): "Duplicate as draft" failed for any Work Order whose due date had passed, because the copy kept
-- the old due date and a new Work Order may not start overdue (work_orders_due_date_check). The copy now leaves a
-- passed due date empty, so the preparer sets a new one; a future due date is still copied.

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
      source_order.department_id,
      -- UAT 4 Nov 2026 (D-32): a passed due date is not copied; the preparer sets a new one.
      case when source_order.due_date >= current_date then source_order.due_date end,
      source_order.estimated_hours,
      source_order.internal_notes, actor_name, source_order.contact_number, source_order.id
    ) returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, actor, note)
    values (actor_id, result.id, 'work_order_duplicated', actor_name,
      pg_catalog.jsonb_build_object('source_work_order_id', source_order.id, 'source_work_order_number', source_order.work_order_number)::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Work-order duplication failed.'); end;
end;
$$;

revoke all on function public.duplicate_work_order(uuid) from public, anon, service_role;
grant execute on function public.duplicate_work_order(uuid) to authenticated;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.duplicate_work_order(uuid)'::regprocedure), 'source_order.due_date >= current_date') = 0 then
    raise exception 'D-32 duplicate due-date fix was not installed';
  end if;
end;$postcheck$;
commit;

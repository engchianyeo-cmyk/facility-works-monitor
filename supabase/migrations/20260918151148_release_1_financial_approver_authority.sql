begin;

create or replace function public.approve_work_order_financial(
  p_work_order_id uuid,
  p_approved_budget numeric,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb := public.work_order_actor();
  w public.work_orders%rowtype;
  control public.work_order_financial_controls%rowtype;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  select * into w from public.work_orders where id = p_work_order_id;
  select * into control from public.work_order_financial_controls where work_order_id = p_work_order_id for update;
  if w.id is null or control.work_order_id is null then
    return public.work_order_result_error('NOT_FOUND', 'Financial control not found.');
  end if;
  if actor ->> 'role' = 'technician' then
    return public.work_order_result_error('SELF_APPROVAL_DENIED', 'Technicians cannot approve expenditure.');
  end if;
  if actor ->> 'role' = 'supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Same-facility Supervisor authority is required.');
  end if;
  if actor ->> 'role' = 'facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Same-facility Facility Manager authority is required.');
  end if;
  if actor ->> 'role' not in ('approver', 'supervisor', 'facility_manager', 'administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Independent financial approval authority is required.');
  end if;
  if control.cost_status <> 'recommended' or control.recommended_by is null then
    return public.work_order_result_error('COST_RECOMMENDATION_REQUIRED', 'A cost recommendation is required first.');
  end if;
  if control.recommended_by = (actor ->> 'id')::uuid then
    return public.work_order_result_error('SELF_APPROVAL_DENIED', 'The recommender cannot approve the same expenditure.');
  end if;
  if p_approved_budget is null or p_approved_budget < 0 or nullif(pg_catalog.btrim(coalesce(p_note, '')), '') is null then
    return public.work_order_result_error('VALIDATION_ERROR', 'Approved budget and approval note are required.');
  end if;
  update public.work_order_financial_controls
  set approved_budget = p_approved_budget,
      cost_status = 'approved',
      financial_approved_by = (actor ->> 'id')::uuid,
      financial_approved_at = pg_catalog.now(),
      financial_approval_note = pg_catalog.btrim(p_note),
      updated_at = pg_catalog.now()
  where work_order_id = w.id
  returning * into control;
  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values (
    (actor ->> 'id')::uuid,
    w.id,
    'work_order_financial_approved',
    w.status,
    w.status,
    actor ->> 'name',
    pg_catalog.jsonb_build_object('approved_budget', p_approved_budget, 'recommended_by', control.recommended_by)::text
  );
  return pg_catalog.jsonb_build_object('ok', true, 'financial', pg_catalog.to_jsonb(control));
end;
$function$;

revoke all on function public.approve_work_order_financial(uuid, numeric, text) from public, anon, service_role;
grant execute on function public.approve_work_order_financial(uuid, numeric, text) to authenticated;

do $uat$
declare
  target_work_order uuid;
  target_approver uuid;
begin
  select id into target_work_order from public.work_orders where work_order_number = 'WO-TEST-012';
  select id into target_approver from public.profiles
  where email = 'sctpec2413@gmail.com' and role = 'approver' and is_active and deleted_at is null;
  if target_work_order is null or target_approver is null then
    raise exception 'WO-TEST-012 financial Approver UAT prerequisite missing';
  end if;
  update public.work_order_financial_controls
  set cost_status = 'recommended',
      approved_budget = null,
      financial_approved_by = null,
      financial_approved_at = null,
      financial_approval_note = null,
      updated_at = pg_catalog.now()
  where work_order_id = target_work_order and recommended_by is not null;
  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values (
    target_approver,
    target_work_order,
    'uat_financial_approver_verification_prepared',
    (select status from public.work_orders where id = target_work_order),
    (select status from public.work_orders where id = target_work_order),
    'Preview UAT remediation',
    pg_catalog.jsonb_build_object('reason', 'Prove independent approval with the configured Approver identity')::text
  );
end;
$uat$;

commit;

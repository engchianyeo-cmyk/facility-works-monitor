-- WP-WO-011: UAT Completed Work remediation.
-- Adds evidence voiding controls, restores named Administrator presentation data,
-- and permits audited Administrator self-verification of Completed Work.
begin;

do $preflight$
begin
  if current_user <> 'postgres' then raise exception '0030 must be applied as postgres'; end if;
  if to_regclass('public.work_orders') is null
    or to_regclass('public.evidence_items') is null
    or to_regclass('public.contractor_payment_assessments') is null
    or to_regprocedure('public.work_order_actor()') is null
    or to_regprocedure('public.work_order_result_error(text,text)') is null
  then raise exception '0030 prerequisite missing: apply 0028 and 0029 first'; end if;
end;
$preflight$;

alter table public.evidence_items add column if not exists deleted_at timestamptz;
alter table public.evidence_items add column if not exists deleted_by uuid references public.profiles(id) on delete restrict;
alter table public.evidence_items add column if not exists deletion_reason text;

create index if not exists evidence_items_active_work_order_idx
  on public.evidence_items(work_order_id, category)
  where deleted_at is null;

-- Repair the preserved UAT Administrator placeholder without overwriting a real name.
update public.profiles
set display_name = 'EC Yeo'
where lower(coalesce(email,'')) = 'engchian.yeo@gmail.com'
  and (display_name is null or btrim(display_name) = '' or lower(btrim(display_name)) = 'pending preserved user');

create or replace function public.verify_completed_work(
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
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  completion_activity_id uuid;
  completion_actor_id uuid;
  cycle_number integer;
  administrator_self_verification boolean := false;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;

  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'name', actor ->> 'display_name', 'Unknown user');
  actor_role := actor ->> 'role';

  select * into previous
  from public.work_orders
  where id = p_work_order_id
  for update;

  if not found then
    return public.work_order_result_error('NOT_FOUND', 'Work order not found.');
  end if;

  if previous.status = 'reviewed' then
    return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE', 'work_order', pg_catalog.to_jsonb(previous));
  end if;

  if previous.status <> 'completed' then
    return public.work_order_result_error('INVALID_TRANSITION', 'Only Completed Work awaiting verification can be verified.');
  end if;

  if actor_role not in ('supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Supervisor, Facility Manager or Administrator authority is required.');
  end if;

  select l.id, l.user_id
    into completion_activity_id, completion_actor_id
  from public.activity_logs l
  where l.work_order_id = previous.id
    and l.action = 'work_order_complete'
  order by l.created_at desc, l.id desc
  limit 1;

  if completion_activity_id is null then
    return public.work_order_result_error('COMPLETION_AUDIT_REQUIRED', 'The latest Completed Work audit record could not be found.');
  end if;

  if actor_id = completion_actor_id then
    if actor_role <> 'administrator' then
      return public.work_order_result_error('SELF_REVIEW_DENIED', 'Technician, Supervisor and Facility Manager Completed Work must be verified by another authorised person.');
    end if;
    if reason is null then
      return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-verification requires an override reason.');
    end if;
    administrator_self_verification := true;
  end if;

  select count(*) + 1 into cycle_number
  from public.activity_logs l
  where l.work_order_id = previous.id
    and l.action = 'work_order_returned_for_rework';

  update public.work_orders
  set status = 'reviewed',
      reviewed_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  where id = previous.id
  returning * into result;

  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values(
    actor_id,
    result.id,
    'work_order_review',
    'completed',
    'reviewed',
    actor_name,
    pg_catalog.jsonb_build_object(
      'cycle', cycle_number,
      'decision', 'verified',
      'reason', reason,
      'completion_activity_id', completion_activity_id,
      'independent_review', not administrator_self_verification,
      'administrator_self_verification', administrator_self_verification,
      'verified_by', actor_id,
      'verified_at', pg_catalog.now()
    )::text
  );

  if result.assigned_technician_id is not null then
    insert into public.notification_outbox(
      work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status
    )
    select result.id,
      'work_order_completion_accepted',
      'work_order:'||result.id::text||':completion:'||cycle_number::text||':accepted',
      p.id,p.id,p.email,'email',
      pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),
      'pending'
    from public.profiles p
    where p.id = result.assigned_technician_id
      and p.is_active
      and p.deleted_at is null
    on conflict do nothing;
  end if;

  if result.assigned_vendor_id is not null then
    insert into public.contractor_payment_assessments(
      work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,payment_due_at
    )
    values(
      result.id,
      result.assigned_vendor_id,
      'awaiting_approval',
      coalesce((select sum(amount) from public.work_order_cost_lines where work_order_id=result.id),0),
      pg_catalog.now(),
      pg_catalog.now() + interval '30 days'
    )
    on conflict(work_order_id) do update set
      status='awaiting_approval',
      assessed_amount=excluded.assessed_amount,
      completed_work_accepted_at=excluded.completed_work_accepted_at,
      payment_due_at=excluded.payment_due_at,
      updated_at=pg_catalog.now();
  end if;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'work_order', pg_catalog.to_jsonb(result),
    'cycle', cycle_number,
    'administrator_self_verification', administrator_self_verification,
    'notification_status', 'queued'
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Completed Work verification data is invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Completed Work verification failed.');
end;
$function$;

revoke all on function public.verify_completed_work(uuid,jsonb) from public, anon;
grant execute on function public.verify_completed_work(uuid,jsonb) to authenticated;

commit;

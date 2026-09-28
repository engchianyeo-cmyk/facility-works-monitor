-- Keep verified completion, final-account recommendation, approval, and Finance payment
-- as separate governed steps. Repair approved-but-unpaid assessments without erasing history.
begin;

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
  actual_total numeric(14,2);
  administrator_self_verification boolean := false;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;

  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'name', actor ->> 'display_name', 'Unknown user');
  actor_role := actor ->> 'role';

  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status = 'reviewed' then
    return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE', 'work_order', pg_catalog.to_jsonb(previous));
  end if;
  if previous.status <> 'completed' then
    return public.work_order_result_error('INVALID_TRANSITION', 'Only Completed Work awaiting verification can be verified.');
  end if;
  if actor_role not in ('supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Supervisor, Facility Manager or Administrator authority is required.');
  end if;

  select l.id, l.user_id into completion_activity_id, completion_actor_id
  from public.activity_logs l
  where l.work_order_id = previous.id and l.action = 'work_order_complete'
  order by l.created_at desc, l.id desc limit 1;
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

  select count(*) + 1 into cycle_number from public.activity_logs l
  where l.work_order_id = previous.id and l.action = 'work_order_returned_for_rework';

  update public.work_orders set status='reviewed', reviewed_at=pg_catalog.now(), updated_at=pg_catalog.now()
  where id=previous.id returning * into result;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,result.id,'work_order_review','completed','reviewed',actor_name,
    pg_catalog.jsonb_build_object('cycle',cycle_number,'decision','verified','reason',reason,
      'completion_activity_id',completion_activity_id,'independent_review',not administrator_self_verification,
      'administrator_self_verification',administrator_self_verification,'verified_by',actor_id,
      'verified_at',pg_catalog.now())::text);

  if result.assigned_technician_id is not null then
    insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
    select result.id,'work_order_completion_accepted','work_order:'||result.id::text||':completion:'||cycle_number::text||':accepted',
      p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),'pending'
    from public.profiles p
    where p.id=result.assigned_technician_id and p.is_active and p.deleted_at is null
    on conflict do nothing;
  end if;

  if result.assigned_vendor_id is not null then
    select coalesce(pg_catalog.sum(c.amount),0) into actual_total
    from public.work_order_cost_lines c
    where c.work_order_id=result.id and c.cost_phase='actual';

    insert into public.contractor_payment_assessments(
      work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,payment_term_started_at,payment_due_at
    ) values(result.id,result.assigned_vendor_id,'draft',actual_total,result.reviewed_at,result.reviewed_at,result.reviewed_at+interval '30 days')
    on conflict(work_order_id) do update set
      vendor_id=excluded.vendor_id,status='draft',assessed_amount=excluded.assessed_amount,
      completed_work_accepted_at=excluded.completed_work_accepted_at,
      payment_term_started_at=excluded.payment_term_started_at,payment_due_at=excluded.payment_due_at,
      recommended_by=null,recommended_at=null,approved_by=null,approved_at=null,approval_note=null,
      completion_notified_at=null,paid_at=null,paid_amount=null,payment_reference=null,paid_by=null,payment_note=null,
      updated_at=pg_catalog.now();
  end if;

  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle_number,
    'administrator_self_verification',administrator_self_verification,'notification_status','queued');
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Completed Work verification data is invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Completed Work verification failed.');
end;
$function$;

create or replace function public.reopen_work_order_payment_for_correction(p_work_order_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare
  actor jsonb:=public.work_order_actor();
  actor_id uuid;
  w public.work_orders%rowtype;
  result public.contractor_payment_assessments%rowtype;
  actual_total numeric(14,2);
  reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Independent payment correction authority is required.');
  end if;
  if reason is null or pg_catalog.length(reason)>1000 then
    return public.work_order_result_error('VALIDATION_ERROR','A bounded payment correction reason is required.');
  end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Payment assessment was not found.'); end if;
  if result.status<>'approved_for_payment' or result.paid_at is not null then
    return public.work_order_result_error('INVALID_TRANSITION','Only an approved, unpaid assessment may be reopened for correction.');
  end if;
  if result.recommended_by=actor_id then
    return public.work_order_result_error('SELF_APPROVAL_DENIED','The payment recommender cannot reopen their own assessment approval.');
  end if;
  select coalesce(pg_catalog.sum(c.amount),0) into actual_total
  from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
  update public.contractor_payment_assessments set
    status='returned',assessed_amount=actual_total,completed_work_accepted_at=w.reviewed_at,
    payment_term_started_at=w.reviewed_at,payment_due_at=w.reviewed_at+interval '30 days',
    approval_note=null,approved_by=null,approved_at=null,completion_notified_at=null,updated_at=pg_catalog.now()
  where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'contractor_payment_reopened_for_correction',w.status,w.status,actor->>'name',
    pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'reason',reason,
      'corrected_assessed_amount',actual_total,'basis','confirmed_actual_cost_only',
      'prior_approval_preserved_in_activity_history',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;
$function$;

revoke all on function public.verify_completed_work(uuid,jsonb) from public,anon;
grant execute on function public.verify_completed_work(uuid,jsonb) to authenticated;
revoke all on function public.reopen_work_order_payment_for_correction(uuid,text) from public,anon;
grant execute on function public.reopen_work_order_payment_for_correction(uuid,text) to authenticated;

commit;

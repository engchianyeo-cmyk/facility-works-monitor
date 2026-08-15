-- WP-WO-006: secure completion review and repeated rework cycles.
-- Prerequisites: the exact Release 1.2 contracts established by 0012-0016.
-- This migration deliberately keeps the existing Work Order status set.

begin;

do $preflight$
declare
  status_definition text;
  transition_search_path text[];
begin
  if to_regprocedure('public.transition_work_order(uuid,text,jsonb)') is null then
    raise exception '0017 prerequisite missing: public.transition_work_order(uuid,text,jsonb)';
  end if;
  if to_regclass('public.work_orders') is null
    or to_regclass('public.activity_logs') is null
    or to_regclass('public.notification_outbox') is null
    or to_regclass('public.evidence_items') is null then
    raise exception '0017 prerequisite missing: required Release 1.2 table';
  end if;
  if exists (
    select 1 from (values
      ('work_orders','id'),('work_orders','status'),('work_orders','assigned_technician_id'),
      ('work_orders','completion_notes'),('work_orders','actual_labour_hours'),('work_orders','completed_at'),
      ('activity_logs','id'),('activity_logs','user_id'),('activity_logs','work_order_id'),
      ('activity_logs','action'),('activity_logs','from_status'),('activity_logs','to_status'),
      ('activity_logs','actor'),('activity_logs','note'),('activity_logs','created_at'),
      ('notification_outbox','work_order_id'),('notification_outbox','event_type'),
      ('notification_outbox','event_key'),('notification_outbox','recipient_user_id'),
      ('notification_outbox','recipient_profile_id'),('notification_outbox','recipient_email'),
      ('notification_outbox','channel'),('notification_outbox','payload'),
      ('notification_outbox','delivery_status'),
      ('evidence_items','id'),('evidence_items','work_order_id'),('evidence_items','uploaded_at')
    ) as required(table_name,column_name)
    where not exists (
      select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name=required.table_name and c.column_name=required.column_name
    )
  ) then
    raise exception '0017 prerequisite mismatch: required column is missing';
  end if;
  select pg_get_constraintdef(c.oid) into status_definition
  from pg_constraint c
  where c.conrelid='public.work_orders'::regclass and c.conname='work_orders_status_check' and c.contype='c';
  if status_definition is null
    or status_definition not like '%draft%'
    or status_definition not like '%submitted%'
    or status_definition not like '%approved%'
    or status_definition not like '%assigned%'
    or status_definition not like '%in_progress%'
    or status_definition not like '%completed%'
    or status_definition not like '%reviewed%'
    or status_definition not like '%closed%'
    or status_definition not like '%cancelled%' then
    raise exception '0017 prerequisite mismatch: Work Order status constraint is not the reviewed 0013 contract';
  end if;
  if to_regclass('public.notification_outbox_event_recipient_channel_idx') is null then
    raise exception '0017 prerequisite missing: notification outbox deduplication index';
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid='public.work_orders'::regclass)
    or not (select c.relrowsecurity from pg_class c where c.oid='public.activity_logs'::regclass)
    or not (select c.relrowsecurity from pg_class c where c.oid='public.notification_outbox'::regclass)
    or not (select c.relrowsecurity from pg_class c where c.oid='public.evidence_items'::regclass) then
    raise exception '0017 prerequisite mismatch: required RLS is not enabled';
  end if;
  if has_table_privilege('authenticated','public.work_orders','UPDATE')
    or has_table_privilege('authenticated','public.activity_logs','INSERT')
    or has_table_privilege('authenticated','public.notification_outbox','INSERT') then
    raise exception '0017 prerequisite mismatch: direct authenticated mutation privilege is too broad';
  end if;
  select p.proconfig into transition_search_path
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.oid='public.transition_work_order(uuid,text,jsonb)'::regprocedure and p.prosecdef;
  if transition_search_path is null or not ('search_path=pg_catalog'=any(transition_search_path)) then
    raise exception '0017 prerequisite mismatch: transition function security contract is unexpected';
  end if;
end;
$preflight$;

create index if not exists activity_logs_work_order_action_idx
  on public.activity_logs (work_order_id, action, created_at desc, id desc)
  where work_order_id is not null;

create or replace function public.transition_work_order(
  p_work_order_id uuid,
  p_action text,
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
  action text := pg_catalog.lower(coalesce(p_action, ''));
  target_status text;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  cycle_number integer;
  evidence_ids jsonb := '[]'::jsonb;
  transition_activity_id uuid;
  completion_activity_id uuid;
  completion_actor_id uuid;
  completion_note_text text;
  completion_note jsonb := '{}'::jsonb;
  prior_hours numeric;
  requested_hours numeric;
  recipient_count integer;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  actor_id := (actor ->> 'id')::uuid;
  actor_name := actor ->> 'name';
  actor_role := actor ->> 'role';

  select * into previous from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;

  -- Network retries after a committed mutation are successful no-ops.
  if (action='complete' and previous.status='completed')
    or (action='review' and previous.status='reviewed')
    or (action='return_for_rework' and previous.status='in_progress' and exists(
      select 1 from public.activity_logs l where l.work_order_id=previous.id
        and l.action='work_order_returned_for_rework'
        and not exists(select 1 from public.activity_logs later where later.work_order_id=previous.id and later.created_at>l.created_at and later.action='work_order_complete')
    )) then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(previous));
  end if;

  if previous.status in ('closed','cancelled') then
    return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Closed and cancelled work orders are immutable.');
  end if;

  target_status := case action
    when 'submit' then 'submitted'
    when 'approve' then 'approved'
    when 'accept' then 'assigned'
    when 'start' then 'in_progress'
    when 'complete' then 'completed'
    when 'return_for_rework' then 'in_progress'
    when 'review' then 'reviewed'
    when 'close' then 'closed'
    when 'cancel' then 'cancelled'
    else null
  end;
  if target_status is null or not (
    (action='submit' and previous.status='draft')
    or (action='approve' and previous.status='submitted')
    or (action='accept' and previous.status='assigned' and previous.accepted_at is null)
    or (action='start' and previous.status='assigned' and previous.accepted_at is not null)
    or (action='complete' and previous.status='in_progress')
    or (action='return_for_rework' and previous.status='completed')
    or (action='review' and previous.status='completed')
    or (action='close' and previous.status='reviewed')
    or (action='cancel' and previous.status in ('draft','submitted','approved','assigned','in_progress','completed','reviewed'))
  ) then
    return public.work_order_result_error('INVALID_TRANSITION', 'The requested workflow transition is not allowed.');
  end if;

  if action='submit'
    and not (actor_id=previous.requested_by and actor_role in ('reviewer','initiator','approver','supervisor'))
    and actor_role<>'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the requester may submit this work order.');
  elsif action='approve' and actor_role not in ('approver','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Approver or Administrator authority is required.');
  elsif action='approve' and actor_id=previous.requested_by then
    if actor_role<>'administrator' then return public.work_order_result_error('SELF_APPROVAL_DENIED', 'Requesters cannot approve their own work orders.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-approval requires an override reason.'); end if;
  elsif action in ('review','return_for_rework') and actor_role not in ('approver','supervisor','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Approver, Supervisor, or Administrator authority is required.');
  elsif action='close' and actor_role not in ('approver','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Approver or Administrator authority is required to close work orders.');
  elsif action in ('accept','start','complete') and actor_role<>'administrator'
    and not (actor_role='technician' and actor_id=previous.assigned_technician_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the assigned technician or an Administrator may perform this action.');
  elsif action='cancel' and actor_role not in ('approver','supervisor','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot cancel work orders.');
  end if;

  if action='cancel' and reason is null then
    return public.work_order_result_error('CANCELLATION_REASON_REQUIRED', 'A cancellation reason is required.');
  end if;
  if action='return_for_rework' and reason is null then
    return public.work_order_result_error('REWORK_REASON_REQUIRED', 'A rework reason is required.');
  end if;
  if action='return_for_rework' and not exists(
    select 1 from public.profiles p where p.id=previous.assigned_technician_id
      and p.role='technician' and p.is_active and p.deleted_at is null
  ) then
    return public.work_order_result_error('INVALID_ASSIGNMENT', 'Return for rework requires an active assigned Technician.');
  end if;

  if action='complete' then
    begin requested_hours := nullif(p_payload ->> 'actual_labour_hours','')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Completion notes and cumulative non-negative labour hours are required.');
    end;
    if nullif(pg_catalog.btrim(coalesce(p_payload ->> 'completion_notes','')),'') is null
      or requested_hours is null or requested_hours<0 then
      return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Completion notes and cumulative non-negative labour hours are required.');
    end if;
    select count(*)+1 into cycle_number from public.activity_logs l
      where l.work_order_id=previous.id and l.action='work_order_returned_for_rework';
    prior_hours := previous.actual_labour_hours;
    if cycle_number>1 and prior_hours is not null and requested_hours<prior_hours then
      return public.work_order_result_error('CUMULATIVE_LABOUR_REQUIRED', 'Resubmitted labour hours must be the cumulative total and cannot be lower than the previous submission.');
    end if;
    select coalesce(pg_catalog.jsonb_agg(e.id order by e.uploaded_at,e.id),'[]'::jsonb)
      into evidence_ids from public.evidence_items e where e.work_order_id=previous.id;
  end if;

  if action in ('review','return_for_rework') then
    select count(*)+1 into cycle_number from public.activity_logs l
      where l.work_order_id=previous.id and l.action='work_order_returned_for_rework';
    select l.id,l.user_id,l.note
      into completion_activity_id,completion_actor_id,completion_note_text
    from public.activity_logs l
    where l.work_order_id=previous.id and l.action='work_order_complete'
    order by l.created_at desc,l.id desc limit 1;
    begin
      completion_note := coalesce(nullif(completion_note_text,'')::jsonb,'{}'::jsonb);
    exception when invalid_text_representation then
      completion_note := '{}'::jsonb;
    end;
    evidence_ids := case
      when pg_catalog.jsonb_typeof(completion_note -> 'evidence_ids')='array'
        then completion_note -> 'evidence_ids'
      else '[]'::jsonb
    end;
  end if;

  if action='review' and actor_role='administrator' and actor_id=completion_actor_id and reason is null then
    return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-review requires an override reason.');
  end if;

  begin
    if action='return_for_rework' then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,previous.id,'work_order_returned_for_rework','completed','in_progress',actor_name,
        pg_catalog.jsonb_build_object(
          'cycle',cycle_number,'reason',reason,'previous_completion_activity_id',completion_activity_id,
          'previous_completion',pg_catalog.jsonb_build_object(
            'completion_notes',previous.completion_notes,'cumulative_labour_hours',previous.actual_labour_hours,
            'completed_at',previous.completed_at,'evidence_ids',evidence_ids,
            'actor_id',completion_actor_id,'activity_note',completion_note
          ),
          'returned_by',actor_id,'returned_at',pg_catalog.now()
        )::text)
      returning id into transition_activity_id;
    end if;

    update public.work_orders set
      status=target_status,
      submitted_at=case when action='submit' then pg_catalog.now() else submitted_at end,
      approved_at=case when action='approve' then pg_catalog.now() else approved_at end,
      accepted_at=case when action='accept' then pg_catalog.now() else accepted_at end,
      started_at=case when action='start' then pg_catalog.now() else started_at end,
      completed_at=case when action='complete' then pg_catalog.now() when action='return_for_rework' then null else completed_at end,
      reviewed_at=case when action='review' then pg_catalog.now() else reviewed_at end,
      closed_at=case when action='close' then pg_catalog.now() else closed_at end,
      cancelled_at=case when action='cancel' then pg_catalog.now() else cancelled_at end,
      completion_notes=case when action='complete' then pg_catalog.btrim(p_payload ->> 'completion_notes') else completion_notes end,
      actual_labour_hours=case when action='complete' then requested_hours else actual_labour_hours end,
      cancellation_reason=case when action='cancel' then reason else cancellation_reason end,
      updated_at=pg_catalog.now()
    where id=previous.id returning * into result;

    if action<>'return_for_rework' then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,result.id,'work_order_'||action,previous.status,result.status,actor_name,
        case when action='complete' then pg_catalog.jsonb_build_object(
          'cycle',cycle_number,'completion_notes',result.completion_notes,
          'cumulative_labour_hours',result.actual_labour_hours,'completed_at',result.completed_at,
          'evidence_ids',evidence_ids,'submitted_by',actor_id,'submitted_at',pg_catalog.now(),
          'resubmission',cycle_number>1
        )
        when action='review' then pg_catalog.jsonb_build_object(
          'cycle',cycle_number,'decision','accepted','reason',reason,
          'completion_activity_id',completion_activity_id,
          'administrator_override',actor_role='administrator' and actor_id=completion_actor_id
        )
        else pg_catalog.jsonb_build_object(
          'reason',reason,'payload',p_payload,
          'administrator_override',action='approve' and actor_id=previous.requested_by and actor_role='administrator'
        ) end::text)
      returning id into transition_activity_id;
    end if;

    if action='complete' then
      with primary_recipients as (
        select p.id,p.email from public.profiles p
        where p.is_active and p.deleted_at is null and p.role in ('approver','supervisor') and p.id<>actor_id
      ), recipients as (
        select * from primary_recipients
        union all
        select p.id,p.email from public.profiles p
        where p.is_active and p.deleted_at is null and p.role='administrator' and p.id<>actor_id
          and not exists(select 1 from primary_recipients)
      )
      insert into public.notification_outbox(
        work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status
      ) select result.id,
          case when cycle_number=1 then 'work_order_completion_submitted' else 'work_order_completion_resubmitted' end,
          'work_order:'||result.id::text||':completion:'||cycle_number::text||':submitted',
          r.id,r.id,r.email,'email',
          pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),
          'pending'
        from recipients r on conflict do nothing;
    elsif action='return_for_rework' then
      insert into public.notification_outbox(
        work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status
      ) select result.id,'work_order_completion_returned_for_rework',
          'work_order:'||result.id::text||':completion:'||cycle_number::text||':returned',
          p.id,p.id,p.email,'email',
          pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),
          'pending'
        from public.profiles p where p.id=result.assigned_technician_id
        on conflict do nothing;
    elsif action='review' and result.assigned_technician_id is not null then
      insert into public.notification_outbox(
        work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status
      ) select result.id,'work_order_completion_accepted',
          'work_order:'||result.id::text||':completion:'||cycle_number::text||':accepted',
          p.id,p.id,p.email,'email',
          pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),
          'pending'
        from public.profiles p where p.id=result.assigned_technician_id and p.is_active and p.deleted_at is null
        on conflict do nothing;
    end if;

    return pg_catalog.jsonb_build_object(
      'ok',true,'work_order',pg_catalog.to_jsonb(result),
      'cycle',case when action in ('complete','return_for_rework','review') then cycle_number else null end,
      'notification_status',case when action in ('complete','return_for_rework','review') then 'queued' else null end
    );
  exception when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order transition failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more transition values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order transition failed.');
end;
$function$;

revoke all on function public.transition_work_order(uuid,text,jsonb)
  from public,anon,service_role;
grant execute on function public.transition_work_order(uuid,text,jsonb)
  to authenticated;

commit;

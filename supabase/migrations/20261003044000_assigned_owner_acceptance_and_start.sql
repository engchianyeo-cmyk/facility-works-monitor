begin;
create or replace function public.accept_work_responsibility(p_work_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  actor jsonb:=public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  w public.work_orders%rowtype;
  result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  actor_name:=coalesce(actor->>'display_name',actor->>'name','Unknown user');
  actor_role:=actor->>'role';
  if actor_role not in ('technician','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Field execution authority is required.');
  end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('approved','assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Responsibility may be accepted only for approved or active work.'); end if;
  if not public.field_work_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Active facility authority is required for this work order.'); end if;
  if w.assigned_technician_id is not null and w.assigned_technician_id<>actor_id then return public.work_order_result_error('ASSIGNMENT_CONFLICT','Another field-responsible person already owns this work order.'); end if;
  if w.assigned_technician_id=actor_id and w.accepted_at is not null then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;

  update public.work_orders
  set assigned_technician_id=actor_id,
      assigned_to=actor_name,
      assigned_at=coalesce(assigned_at,pg_catalog.now()),
      accepted_at=pg_catalog.now(),
      status=case when status='approved' then 'assigned' else status end,
      updated_at=pg_catalog.now()
  where id=w.id
  returning * into result;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_responsibility_accepted',w.status,result.status,actor_name,
    pg_catalog.jsonb_build_object(
      'responsible_field_profile_id',actor_id,
      'responsible_field_role',actor_role,
      'facility_id',w.facility_id,
      'assigned_vendor_id',w.assigned_vendor_id,
      'accepted_at',pg_catalog.now()
    )::text);

  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
exception
  when check_violation or foreign_key_violation then return public.work_order_result_error('VALIDATION_ERROR','Responsibility could not be accepted.');
  when others then return public.work_order_result_error('INTERNAL_ERROR','Responsibility acceptance failed.');
end;
$function$;

alter function public.transition_work_order(uuid,text,jsonb) rename to transition_work_order_20261003_core;
revoke all on function public.transition_work_order_20261003_core(uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.transition_work_order(p_work_order_id uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb; actor_id uuid; w public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if coalesce(lower(p_action),'')<>'start' then return public.transition_work_order_20261003_core(p_work_order_id,p_action,p_payload); end if;
  actor:=public.work_order_actor();
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator')
    or w.assigned_technician_id is distinct from actor_id or not public.field_work_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility field owner may start work.');
  end if;
  if w.status='in_progress' then return jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',to_jsonb(w)); end if;
  if w.status<>'assigned' or w.accepted_at is null then
    return public.work_order_result_error('INVALID_TRANSITION','Accept the assigned work before starting it.');
  end if;
  update public.work_orders set status='in_progress',started_at=coalesce(started_at,now()),updated_at=now()
    where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_start',w.status,result.status,actor->>'name',
      jsonb_build_object('responsible_field_profile_id',actor_id,'responsible_field_role',actor->>'role','facility_id',w.facility_id)::text);
  return jsonb_build_object('ok',true,'work_order',to_jsonb(result));
exception when others then return public.work_order_result_error('INTERNAL_ERROR','Work could not be started.');
end;
$function$;
revoke all on function public.accept_work_responsibility(uuid),public.transition_work_order(uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.accept_work_responsibility(uuid),public.transition_work_order(uuid,text,jsonb) to authenticated;
commit;

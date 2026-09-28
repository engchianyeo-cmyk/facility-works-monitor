-- WP-FMW-027: distinguish approved proposed cost from Technician-recorded actual cost.
-- Existing rows remain deliberately unclassified: their historical meaning cannot be inferred safely.

do $preflight$
declare object_name text; config text[];
begin
  if current_user <> 'postgres' then raise exception '0038 must be applied as postgres'; end if;
  foreach object_name in array array['public.work_orders','public.work_order_cost_lines','public.activity_logs','public.profiles','public.facility_memberships'] loop
    if pg_catalog.to_regclass(object_name) is null then raise exception '0038 prerequisite missing: %',object_name; end if;
  end loop;
  foreach object_name in array array[
    'public.work_order_actor()','public.work_order_result_error(text,text)',
    'public.technician_facility_read_permitted(uuid)','public.submit_physical_completion(uuid,jsonb)'
  ] loop
    if pg_catalog.to_regprocedure(object_name) is null then raise exception '0038 prerequisite function missing: %',object_name; end if;
  end loop;
  select p.proconfig into config from pg_catalog.pg_proc p where p.oid='public.submit_physical_completion(uuid,jsonb)'::regprocedure and p.prosecdef;
  if config is null or config<>array['search_path=pg_catalog'] then raise exception '0038 completion prerequisite security mismatch'; end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_order_cost_lines' and column_name='cost_phase')
    or exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_orders' and column_name in ('actual_costs_confirmed_at','actual_costs_confirmed_by'))
    or pg_catalog.to_regprocedure('public.manage_work_order_actual_cost(uuid,uuid,jsonb)') is not null then
    raise exception '0038 conflicting or partial state already exists';
  end if;
end;$preflight$;

alter table public.work_order_cost_lines
  add column cost_phase text,
  add constraint work_order_cost_lines_cost_phase_check check (cost_phase in ('proposed','actual'));
alter table public.work_order_cost_lines alter column cost_phase set default 'proposed';

alter table public.work_orders
  add column actual_costs_confirmed_at timestamptz,
  add column actual_costs_confirmed_by uuid references public.profiles(id) on delete restrict,
  add constraint work_orders_actual_cost_confirmation_check check (
    (actual_costs_confirmed_at is null and actual_costs_confirmed_by is null)
    or (actual_costs_confirmed_at is not null and actual_costs_confirmed_by is not null)
  );

create index work_order_cost_lines_actual_idx
on public.work_order_cost_lines(work_order_id,created_at,id)
where cost_phase='actual';

create or replace function public.manage_work_order_actual_cost(
  p_work_order_id uuid,
  p_cost_line_id uuid,
  p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare
  actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; w public.work_orders%rowtype;
  operation text:=pg_catalog.lower(coalesce(p_payload->>'operation','upsert'));
  kind text; detail text; measure text; worker text; quantity_value numeric; rate_value numeric;
  existing public.work_order_cost_lines%rowtype; result public.work_order_cost_lines%rowtype;
  previous_value jsonb; actual_count bigint; actual_total numeric;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name','Unknown user');
  if actor->>'role'<>'technician' then return public.work_order_result_error('ACCESS_DENIED','Assigned Technician authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('ACTUAL_COST_READ_ONLY','Actual execution costs are read-only outside active assigned work.'); end if;
  if w.assigned_technician_id is null or w.assigned_technician_id<>actor_id
    or not public.technician_facility_read_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility assigned Technician responsibility is required.');
  end if;

  if operation='confirm' then
    if p_cost_line_id is not null then return public.work_order_result_error('VALIDATION_ERROR','Cost-line identity is not accepted when confirming actual costing.'); end if;
    update public.work_orders set actual_costs_confirmed_at=pg_catalog.now(),actual_costs_confirmed_by=actor_id,updated_at=pg_catalog.now()
      where id=w.id;
    select pg_catalog.count(*),coalesce(pg_catalog.sum(c.amount),0) into actual_count,actual_total
      from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_actual_costing_confirmed',w.status,w.status,actor_name,
      pg_catalog.jsonb_build_object('facility_id',w.facility_id,'actual_line_count',actual_count,'actual_total',actual_total,
        'confirmed_at',pg_catalog.now())::text);
    return pg_catalog.jsonb_build_object('ok',true,'confirmed',true,'actual_line_count',actual_count,'actual_total',actual_total);
  end if;
  if operation<>'upsert' then return public.work_order_result_error('VALIDATION_ERROR','Actual-cost operation is invalid.'); end if;

  kind:=pg_catalog.lower(coalesce(p_payload->>'cost_type',''));
  detail:=nullif(pg_catalog.btrim(coalesce(p_payload->>'description','')),'');
  measure:=nullif(pg_catalog.btrim(coalesce(p_payload->>'unit','')),'');
  worker:=nullif(pg_catalog.btrim(coalesce(p_payload->>'worker_name','')),'');
  begin quantity_value:=(p_payload->>'quantity')::numeric; exception when others then quantity_value:=null; end;
  begin rate_value:=(p_payload->>'unit_rate')::numeric; exception when others then rate_value:=null; end;
  if kind not in ('labour','material','equipment','service','callout') or detail is null or measure is null
    or quantity_value is null or quantity_value<0 or rate_value is null or rate_value<0 then
    return public.work_order_result_error('VALIDATION_ERROR','Cost type, description, non-negative quantity, unit and non-negative unit rate are required.');
  end if;
  if pg_catalog.length(detail)>1000 or pg_catalog.length(measure)>100 or pg_catalog.length(coalesce(worker,''))>200 then
    return public.work_order_result_error('VALIDATION_ERROR','Actual-cost text exceeds the permitted length.');
  end if;

  if p_cost_line_id is null then
    insert into public.work_order_cost_lines(work_order_id,vendor_id,worker_name,cost_type,description,quantity,unit,unit_rate,entered_by,cost_phase)
    values(w.id,case when kind in ('service','callout') then w.assigned_vendor_id end,worker,kind,detail,quantity_value,measure,rate_value,actor_id,'actual')
    returning * into result;
  else
    select * into existing from public.work_order_cost_lines c where c.id=p_cost_line_id and c.work_order_id=w.id for update;
    if not found then return public.work_order_result_error('NOT_FOUND','Actual cost line not found.'); end if;
    if existing.cost_phase is distinct from 'actual' then return public.work_order_result_error('PROPOSED_COST_PROTECTED','Proposed or legacy cost lines cannot be changed through actual-cost recording.'); end if;
    if existing.entered_by<>actor_id then return public.work_order_result_error('ACCESS_DENIED','A Technician may update only their own active actual-cost line.'); end if;
    if existing.technician_certified_at is not null or existing.approved_at is not null then
      return public.work_order_result_error('ACTUAL_COST_LOCKED','Certified or approved actual-cost lines are read-only.');
    end if;
    previous_value:=pg_catalog.to_jsonb(existing);
    update public.work_order_cost_lines set
      vendor_id=case when kind in ('service','callout') then w.assigned_vendor_id end,
      worker_name=worker,cost_type=kind,description=detail,quantity=quantity_value,unit=measure,unit_rate=rate_value
    where id=existing.id returning * into result;
  end if;

  update public.work_orders set actual_costs_confirmed_at=null,actual_costs_confirmed_by=null,updated_at=pg_catalog.now() where id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,case when p_cost_line_id is null then 'work_order_actual_cost_created' else 'work_order_actual_cost_updated' end,
    w.status,w.status,actor_name,pg_catalog.jsonb_build_object('facility_id',w.facility_id,'cost_line_id',result.id,
      'previous',previous_value,'new',pg_catalog.to_jsonb(result),'recorded_at',pg_catalog.now())::text);
  return pg_catalog.jsonb_build_object('ok',true,'cost_line',pg_catalog.to_jsonb(result),'actual_costing_confirmed',false);
exception
  when check_violation or foreign_key_violation or invalid_text_representation or numeric_value_out_of_range then
    return public.work_order_result_error('VALIDATION_ERROR','Actual cost data is invalid.');
  when others then return public.work_order_result_error('INTERNAL_ERROR','Actual cost could not be recorded.');
end;$function$;

create or replace function public.submit_physical_completion(p_work_order_id uuid,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; w public.work_orders%rowtype; result public.work_orders%rowtype;
  statement text; hours numeric; evidence_ids jsonb; cycle integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name','Unknown user');
  if actor->>'role'<>'technician' then return public.work_order_result_error('ACCESS_DENIED','Assigned Technician authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Only active assigned work may be submitted as physically complete.'); end if;
  if w.assigned_technician_id is null or w.assigned_technician_id<>actor_id or not public.technician_facility_read_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility assigned Technician responsibility is required.');
  end if;
  statement:=nullif(pg_catalog.btrim(coalesce(p_payload->>'completion_notes',w.completion_notes,'')),'');
  begin hours:=coalesce(nullif(p_payload->>'actual_labour_hours','')::numeric,w.actual_labour_hours); exception when others then hours:=null; end;
  if statement is null then return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED','A work-performed statement is required.'); end if;
  if hours is null or hours<0 then return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED','Cumulative non-negative labour hours are required.'); end if;
  if w.actual_labour_hours is not null and hours<w.actual_labour_hours then return public.work_order_result_error('CUMULATIVE_LABOUR_REQUIRED','Cumulative labour hours cannot decrease.'); end if;
  if w.actual_costs_confirmed_at is null or w.actual_costs_confirmed_by<>actor_id then
    return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Confirm that actual costing is complete, including a genuine zero-cost outcome, before physical completion.');
  end if;
  select coalesce(pg_catalog.jsonb_agg(e.id order by e.uploaded_at,e.id),'[]'::jsonb) into evidence_ids
  from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null;
  if pg_catalog.jsonb_array_length(evidence_ids)=0 then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','At least one active After evidence item is required.'); end if;
  select pg_catalog.count(*)+1 into cycle from public.activity_logs l where l.work_order_id=w.id and l.action='work_order_returned_for_rework';
  update public.work_orders set status='completed',completion_notes=statement,actual_labour_hours=hours,
    started_at=coalesce(started_at,pg_catalog.now()),completed_at=pg_catalog.now(),updated_at=pg_catalog.now()
  where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_complete',w.status,'completed',actor_name,
    pg_catalog.jsonb_build_object('cycle',cycle,'completion_notes',statement,'cumulative_labour_hours',hours,
      'completed_at',result.completed_at,'evidence_ids',evidence_ids,'submitted_by',actor_id,'submitted_at',pg_catalog.now(),
      'actual_costs_confirmed_at',w.actual_costs_confirmed_at,'submission_type','technician_physical_completion')::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle);
exception when check_violation or invalid_text_representation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Physical completion data is invalid.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Physical completion submission failed.'); end;$function$;

revoke all on function public.manage_work_order_actual_cost(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function public.manage_work_order_actual_cost(uuid,uuid,jsonb) to authenticated;
revoke all on function public.submit_physical_completion(uuid,jsonb) from public,anon,service_role;
grant execute on function public.submit_physical_completion(uuid,jsonb) to authenticated;

do $postconditions$
declare definition text;
begin
  select pg_catalog.pg_get_functiondef(p.oid) into definition from pg_catalog.pg_proc p
    where p.oid='public.manage_work_order_actual_cost(uuid,uuid,jsonb)'::regprocedure
      and p.prosecdef and p.proconfig=array['search_path=pg_catalog'];
  if definition is null or definition not like '%w.assigned_technician_id<>actor_id%'
    or definition not like '%public.technician_facility_read_permitted(w.facility_id)%'
    or definition not like '%w.status not in (''assigned'',''in_progress'')%'
    or definition not like '%existing.cost_phase is distinct from ''actual''%'
    or definition not like '%existing.entered_by<>actor_id%' then
    raise exception '0038 actual-cost authorization postcondition failed';
  end if;
  if has_function_privilege('public','public.manage_work_order_actual_cost(uuid,uuid,jsonb)','EXECUTE')
    or has_function_privilege('anon','public.manage_work_order_actual_cost(uuid,uuid,jsonb)','EXECUTE')
    or has_function_privilege('service_role','public.manage_work_order_actual_cost(uuid,uuid,jsonb)','EXECUTE')
    or not has_function_privilege('authenticated','public.manage_work_order_actual_cost(uuid,uuid,jsonb)','EXECUTE') then
    raise exception '0038 actual-cost function privilege postcondition failed';
  end if;
  if has_table_privilege('authenticated','public.work_order_cost_lines','INSERT')
    or has_table_privilege('authenticated','public.work_order_cost_lines','UPDATE')
    or has_table_privilege('authenticated','public.work_order_cost_lines','DELETE') then
    raise exception '0038 direct cost-line mutation unexpectedly granted';
  end if;
  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid='public.work_order_cost_lines'::regclass) then
    raise exception '0038 cost-line RLS is not enabled';
  end if;
end;$postconditions$;

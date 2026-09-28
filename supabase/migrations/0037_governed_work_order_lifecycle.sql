-- WP-FMW-026A: governed approval, field responsibility, physical completion and verification readiness.
-- No historical Work Order, evidence, activity, cost, profile or Auth data is repaired here.

do $preflight$
declare object_name text; config text[]; readiness_oid oid; actor_oid oid; error_oid oid;
begin
  if current_user <> 'postgres' then raise exception '0037 must be applied as postgres'; end if;
  foreach object_name in array array[
    'public.work_orders','public.work_order_cost_lines','public.evidence_items',
    'public.activity_logs','public.facility_memberships','public.sites','public.profiles'
  ] loop
    if pg_catalog.to_regclass(object_name) is null then raise exception '0037 prerequisite missing: %',object_name; end if;
  end loop;
  readiness_oid:=pg_catalog.to_regprocedure('public.pilot_account_ready(uuid)');
  if readiness_oid is null then
    raise exception '0037 prerequisite missing: public.pilot_account_ready(uuid)';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='pilot_account_ready'
        and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_user_id uuid')<>1
    or not exists (
      select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_language l on l.oid=p.prolang
      where p.oid=readiness_oid
        and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_user_id uuid'
        and pg_catalog.pg_get_function_result(p.oid)='boolean'
        and l.lanname='sql'
        and p.provolatile='s'
        and p.prosecdef
        and 'search_path=public, pg_temp'=any(p.proconfig)
    ) then
    raise exception '0037 pilot_account_ready prerequisite definition/security mismatch';
  end if;
  if exists (
      select 1 from pg_catalog.pg_proc p,
        lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
      where p.oid=readiness_oid and acl.grantee=0 and acl.privilege_type='EXECUTE'
    )
    or pg_catalog.has_function_privilege('anon',readiness_oid,'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated',readiness_oid,'EXECUTE')
    or pg_catalog.has_function_privilege('service_role',readiness_oid,'EXECUTE') then
    raise exception '0037 pilot_account_ready prerequisite EXECUTE privilege mismatch';
  end if;
  foreach object_name in array array[
    'public.transition_work_order(uuid,text,jsonb)',
    'public.transition_work_order_0034_core(uuid,text,jsonb)',
    'public.verify_completed_work(uuid,jsonb)',
    'public.record_work_order_execution(uuid,jsonb)',
    'public.technician_facility_read_permitted(uuid)',
    'public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'
  ] loop
    if pg_catalog.to_regprocedure(object_name) is null then raise exception '0037 prerequisite function missing: %',object_name; end if;
    select p.proconfig into config from pg_catalog.pg_proc p where p.oid=object_name::regprocedure and p.prosecdef;
    if config is null or not ('search_path=pg_catalog'=any(config)) then
      raise exception '0037 prerequisite function security mismatch: %',object_name;
    end if;
  end loop;
  actor_oid:=pg_catalog.to_regprocedure('public.work_order_actor()');
  if actor_oid is null then
    raise exception '0037 prerequisite function missing: public.work_order_actor()';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='work_order_actor'
        and pg_catalog.pg_get_function_identity_arguments(p.oid)='')<>1
    or not exists (
      select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_language l on l.oid=p.prolang
      where p.oid=actor_oid
        and pg_catalog.pg_get_function_identity_arguments(p.oid)=''
        and pg_catalog.pg_get_function_result(p.oid)='jsonb'
        and l.lanname='sql'
        and p.provolatile='s'
        and p.prosecdef
        and 'search_path=public, pg_temp'=any(p.proconfig)
    ) then
    raise exception '0037 work_order_actor prerequisite definition/security mismatch';
  end if;
  if exists (
      select 1 from pg_catalog.pg_proc p,
        lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
      where p.oid=actor_oid and acl.grantee=0 and acl.privilege_type='EXECUTE'
    )
    or pg_catalog.has_function_privilege('anon',actor_oid,'EXECUTE')
    or pg_catalog.has_function_privilege('authenticated',actor_oid,'EXECUTE')
    or pg_catalog.has_function_privilege('service_role',actor_oid,'EXECUTE') then
    raise exception '0037 work_order_actor prerequisite EXECUTE privilege mismatch';
  end if;
  error_oid:=pg_catalog.to_regprocedure('public.work_order_result_error(text,text)');
  if error_oid is null then
    raise exception '0037 prerequisite function missing: public.work_order_result_error(text,text)';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='work_order_result_error'
        and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_code text, p_message text')<>1
    or not exists (
      select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_language l on l.oid=p.prolang
      where p.oid=error_oid
        and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_code text, p_message text'
        and pg_catalog.pg_get_function_result(p.oid)='jsonb'
        and l.lanname='sql'
        and p.provolatile='i'
        and not p.prosecdef
        and 'search_path=pg_catalog'=any(p.proconfig)
    ) then
    raise exception '0037 work_order_result_error prerequisite definition/security mismatch';
  end if;
  if exists (
      select 1 from pg_catalog.pg_proc p,
        lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
      where p.oid=error_oid and acl.grantee=0 and acl.privilege_type='EXECUTE'
    )
    or pg_catalog.has_function_privilege('anon',error_oid,'EXECUTE')
    or pg_catalog.has_function_privilege('authenticated',error_oid,'EXECUTE')
    or pg_catalog.has_function_privilege('service_role',error_oid,'EXECUTE') then
    raise exception '0037 work_order_result_error prerequisite EXECUTE privilege mismatch';
  end if;
  if pg_catalog.to_regclass('public.work_order_approval_basis') is not null
    or pg_catalog.to_regprocedure('public.work_order_approval_readiness(uuid)') is not null
    or pg_catalog.to_regprocedure('public.set_work_order_approval_basis(uuid,jsonb)') is not null
    or pg_catalog.to_regprocedure('public.accept_work_responsibility(uuid)') is not null
    or pg_catalog.to_regprocedure('public.submit_physical_completion(uuid,jsonb)') is not null
    or pg_catalog.to_regprocedure('public.work_order_verification_readiness(uuid)') is not null then
    raise exception '0037 conflicting or partial state already exists';
  end if;
  if pg_catalog.to_regprocedure('public.facility_manager_facility_permitted(uuid)') is not null
    or pg_catalog.to_regprocedure('public.supervisor_facility_permitted(uuid)') is not null
    or pg_catalog.to_regprocedure('public.verify_completed_work_0037_core(uuid,jsonb)') is not null then
    raise exception '0037 conflicting Facility Manager alignment state already exists';
  end if;
end;
$preflight$;

create temporary table wp_fmw_0037_security_snapshot on commit drop as
select p.oid::regprocedure::text identity,p.prosecdef,p.proconfig,p.proacl,
       pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) definition_hash
from pg_catalog.pg_proc p where p.oid in (
  'public.record_work_order_execution(uuid,jsonb)'::regprocedure,
  'public.technician_facility_read_permitted(uuid)'::regprocedure,
  'public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'::regprocedure,
  'public.protect_profile_authorization_fields()'::regprocedure
);

-- Align the valid stored Facility Manager role with account readiness while
-- retaining every existing readiness condition. This does not alter profiles.
create or replace function public.pilot_account_ready(p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select exists (
    select 1 from public.profiles profile
    where profile.id=p_user_id
      and profile.is_active=true
      and profile.deleted_at is null
      and profile.password_change_required=false
      and profile.role in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator')
  )
$function$;
revoke all on function public.pilot_account_ready(uuid) from public,anon,service_role;
grant execute on function public.pilot_account_ready(uuid) to authenticated;

create or replace function public.facility_manager_facility_permitted(p_facility_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select public.pilot_account_ready(auth.uid())
    and public.current_user_role()='facility_manager'
    and exists (
      select 1 from public.facility_memberships fm join public.sites s on s.id=fm.facility_id
      where fm.profile_id=auth.uid() and fm.facility_id=p_facility_id
        and fm.membership_role='facility_manager' and fm.active
        and fm.effective_from<=pg_catalog.now()
        and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
        and s.is_active
    )
$function$;
revoke all on function public.facility_manager_facility_permitted(uuid) from public,anon,service_role;
grant execute on function public.facility_manager_facility_permitted(uuid) to authenticated;

create or replace function public.supervisor_facility_permitted(p_facility_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select public.pilot_account_ready(auth.uid())
    and public.current_user_role()='supervisor'
    and exists (
      select 1 from public.facility_memberships fm join public.sites s on s.id=fm.facility_id
      where fm.profile_id=auth.uid() and fm.facility_id=p_facility_id
        and fm.membership_role='supervisor' and fm.active
        and fm.effective_from<=pg_catalog.now()
        and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
        and s.is_active
    )
$function$;
revoke all on function public.supervisor_facility_permitted(uuid) from public,anon,service_role;
grant execute on function public.supervisor_facility_permitted(uuid) to authenticated;

drop policy work_orders_read_permitted on public.work_orders;
create policy work_orders_read_permitted on public.work_orders for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (
    (public.current_user_role()='technician' and public.technician_facility_read_permitted(facility_id))
    or (public.current_user_role()<>'technician' and (
      requested_by=auth.uid() or assigned_technician_id=auth.uid()
      or public.current_user_role() in ('approver','administrator')
      or public.supervisor_facility_permitted(facility_id)
      or public.facility_manager_facility_permitted(facility_id)
    ))
  )
);

create table public.work_order_approval_basis (
  work_order_id uuid primary key references public.work_orders(id) on delete restrict,
  cost_basis text not null check (pg_catalog.btrim(cost_basis)<>''),
  execution_arrangement text not null check (pg_catalog.btrim(execution_arrangement)<>''),
  safety_isolation_information text not null check (pg_catalog.btrim(safety_isolation_information)<>''),
  board_approval_reference text,
  board_approval_date date,
  board_supporting_document_reference text,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint work_order_approval_basis_board_fields check (
    (board_approval_reference is null and board_approval_date is null and board_supporting_document_reference is null)
    or (nullif(pg_catalog.btrim(board_approval_reference),'') is not null
      and board_approval_date is not null
      and nullif(pg_catalog.btrim(board_supporting_document_reference),'') is not null)
  )
);
alter table public.work_order_approval_basis enable row level security;
revoke all on table public.work_order_approval_basis from public,anon,authenticated,service_role;
grant select on table public.work_order_approval_basis to authenticated;
create policy work_order_approval_basis_read_permitted on public.work_order_approval_basis
for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and exists (
    select 1 from public.work_orders w where w.id=work_order_id
  )
);

create or replace function public.set_work_order_approval_basis(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; actor_role text; actor_name text; w public.work_orders%rowtype;
  proposed numeric; cost_basis text; arrangement text; safety text; board_ref text; board_date date; board_document text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_role:=actor->>'role'; actor_name:=coalesce(actor->>'name','Unknown user');
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('draft','submitted') then return public.work_order_result_error('INVALID_TRANSITION','Approval basis may be changed only before approval.'); end if;
  if actor_role='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  if actor_role='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if actor_role<>'administrator' and not (actor_id=w.requested_by and actor_role in ('reviewer','initiator','approver','supervisor','facility_manager'))
    and actor_role not in ('supervisor','facility_manager') then return public.work_order_result_error('ACCESS_DENIED','You cannot prepare this approval basis.'); end if;
  begin proposed:=(p_payload->>'proposed_cost')::numeric; exception when others then proposed:=null; end;
  cost_basis:=nullif(pg_catalog.btrim(coalesce(p_payload->>'cost_basis','')),'');
  arrangement:=nullif(pg_catalog.btrim(coalesce(p_payload->>'execution_arrangement','')),'');
  safety:=nullif(pg_catalog.btrim(coalesce(p_payload->>'safety_isolation_information','')),'');
  board_ref:=nullif(pg_catalog.btrim(coalesce(p_payload->>'board_approval_reference','')),'');
  board_document:=nullif(pg_catalog.btrim(coalesce(p_payload->>'board_supporting_document_reference','')),'');
  begin board_date:=nullif(p_payload->>'board_approval_date','')::date; exception when others then board_date:=null; end;
  if proposed is null or proposed<0 or cost_basis is null or arrangement is null or safety is null then
    return public.work_order_result_error('VALIDATION_ERROR','Structured proposed cost, cost basis, execution arrangement and safety/isolation information are required.');
  end if;
  if proposed>1000000 and (board_ref is null or board_date is null or board_document is null) then
    return public.work_order_result_error('BOARD_APPROVAL_REQUIRED','Board approval reference, date and supporting document reference are required above S$1,000,000.');
  end if;
  if exists(select 1 from public.work_order_cost_lines c where c.work_order_id=w.id and (c.technician_certified_at is not null or c.approved_at is not null)) then
    return public.work_order_result_error('COST_BASIS_LOCKED','Certified or approved cost lines cannot be replaced through pre-work approval preparation.');
  end if;
  delete from public.work_order_cost_lines c where c.work_order_id=w.id;
  insert into public.work_order_cost_lines(work_order_id,cost_type,description,quantity,unit,unit_rate,entered_by)
  values(w.id,'service','Pre-work proposed cost',1,'lump_sum',proposed,actor_id);
  insert into public.work_order_approval_basis(work_order_id,cost_basis,execution_arrangement,safety_isolation_information,
    board_approval_reference,board_approval_date,board_supporting_document_reference,updated_by)
  values(w.id,cost_basis,arrangement,safety,board_ref,board_date,board_document,actor_id)
  on conflict(work_order_id) do update set cost_basis=excluded.cost_basis,execution_arrangement=excluded.execution_arrangement,
    safety_isolation_information=excluded.safety_isolation_information,board_approval_reference=excluded.board_approval_reference,
    board_approval_date=excluded.board_approval_date,board_supporting_document_reference=excluded.board_supporting_document_reference,
    updated_by=excluded.updated_by,updated_at=pg_catalog.now();
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_approval_basis_recorded',w.status,w.status,actor_name,
    pg_catalog.jsonb_build_object('proposed_cost',proposed,'board_approval_recorded',proposed>1000000,'status_unchanged',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'data',public.work_order_approval_readiness(w.id));
exception when check_violation or invalid_text_representation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Approval basis is invalid.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Approval basis could not be saved.'); end;$function$;

-- A Technician field witness may coexist with one contractor or one team.
-- Multiple execution providers remain prohibited.
alter table public.work_orders drop constraint work_orders_primary_assignment_check;
alter table public.work_orders add constraint work_orders_primary_assignment_check check (
  (case when assigned_vendor_id is null then 0 else 1 end)
  + (case when assigned_team_id is null then 0 else 1 end) <= 1
);

create or replace function public.work_order_approval_readiness(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; basis public.work_order_approval_basis%rowtype;
  proposed numeric; line_count integer; missing jsonb:='[]'::jsonb; authority text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not (public.current_user_role() in ('approver','administrator')
    or public.supervisor_facility_permitted(w.facility_id)
    or public.facility_manager_facility_permitted(w.facility_id)
    or w.requested_by=auth.uid() or w.assigned_technician_id=auth.uid()
    or public.technician_facility_read_permitted(w.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.');
  end if;
  select pg_catalog.count(*),coalesce(pg_catalog.sum(c.amount),0) into line_count,proposed
  from public.work_order_cost_lines c where c.work_order_id=w.id;
  select * into basis from public.work_order_approval_basis b where b.work_order_id=w.id;
  if w.facility_id is null then missing:=missing||'"facility"'::jsonb; end if;
  if w.asset_id is null and w.facility_area_id is null and nullif(pg_catalog.btrim(coalesce(w.location,'')),'') is null then missing:=missing||'"asset_or_location"'::jsonb; end if;
  if nullif(pg_catalog.btrim(coalesce(w.description,'')),'') is null then missing:=missing||'"requested_work_scope"'::jsonb; end if;
  if w.priority is null then missing:=missing||'"priority_operational_risk"'::jsonb; end if;
  if line_count=0 then missing:=missing||'"structured_proposed_cost"'::jsonb; end if;
  if basis.work_order_id is null or nullif(pg_catalog.btrim(coalesce(basis.cost_basis,'')),'') is null then missing:=missing||'"cost_basis"'::jsonb; end if;
  if basis.work_order_id is null or nullif(pg_catalog.btrim(coalesce(basis.execution_arrangement,'')),'') is null then missing:=missing||'"execution_arrangement"'::jsonb; end if;
  if basis.work_order_id is null or nullif(pg_catalog.btrim(coalesce(basis.safety_isolation_information,'')),'') is null then missing:=missing||'"safety_isolation_information"'::jsonb; end if;
  authority:=case when proposed<=250000 then 'supervisor' when proposed<=500000 then 'facility_manager'
    when proposed<=1000000 then 'administrator' else 'company_board_then_administrator_release' end;
  if proposed>1000000 and (basis.board_approval_reference is null or basis.board_approval_date is null or basis.board_supporting_document_reference is null) then
    missing:=missing||'"board_approval_reference_date_and_supporting_document"'::jsonb;
  end if;
  return pg_catalog.jsonb_build_object('ok',true,'ready',pg_catalog.jsonb_array_length(missing)=0,
    'missing_requirements',missing,'required_authority',authority,'proposed_cost',proposed,
    'approval_reason',case when pg_catalog.jsonb_array_length(missing)=0 then 'Structured pre-work approval basis is complete.' end,
    'blocking_reason',case when pg_catalog.jsonb_array_length(missing)>0 then 'Required structured pre-work approval information is incomplete.' end);
end;$function$;

create or replace function public.accept_work_responsibility(p_work_order_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; w public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name','Unknown user');
  if actor->>'role'<>'technician' then return public.work_order_result_error('ACCESS_DENIED','Technician authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('approved','assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Responsibility may be accepted only for approved or active work.'); end if;
  if not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Active same-facility Technician membership is required.'); end if;
  if w.assigned_technician_id is not null and w.assigned_technician_id<>actor_id then return public.work_order_result_error('ASSIGNMENT_CONFLICT','Another Technician already owns field responsibility.'); end if;
  if w.assigned_technician_id=actor_id then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
  update public.work_orders set assigned_technician_id=actor_id,assigned_to=actor_name,
    assigned_at=coalesce(assigned_at,pg_catalog.now()),accepted_at=pg_catalog.now(),
    status=case when status='approved' then 'assigned' else status end,updated_at=pg_catalog.now()
  where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_responsibility_accepted',w.status,result.status,actor_name,
    pg_catalog.jsonb_build_object('responsible_technician_id',actor_id,'facility_id',w.facility_id,'accepted_at',pg_catalog.now())::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
exception when check_violation or foreign_key_violation then return public.work_order_result_error('VALIDATION_ERROR','Responsibility could not be accepted.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Responsibility acceptance failed.'); end;$function$;

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
      'submission_type','technician_physical_completion')::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle);
exception when check_violation or invalid_text_representation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Physical completion data is invalid.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Physical completion submission failed.'); end;$function$;

create or replace function public.work_order_verification_readiness(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; event_id uuid; event_actor uuid; missing jsonb:='[]'::jsonb; same_actor boolean;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role' not in ('supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Completed Work verification authority is required.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  if w.status<>'completed' then missing:=missing||'"completed_awaiting_verification_status"'::jsonb; end if;
  select l.id,l.user_id into event_id,event_actor from public.activity_logs l where l.work_order_id=w.id and l.action='work_order_complete' order by l.created_at desc,l.id desc limit 1;
  if event_id is null then missing:=missing||'"authoritative_completion_submission_event"'::jsonb; end if;
  same_actor:=event_actor=(actor->>'id')::uuid;
  if same_actor and actor->>'role'<>'administrator' then missing:=missing||'"independent_authorised_verifier"'::jsonb; end if;
  return pg_catalog.jsonb_build_object('ok',true,'verification_ready',pg_catalog.jsonb_array_length(missing)=0,
    'missing_requirements',missing,'completion_event_found',event_id is not null,'completion_event_id',event_id,
    'legacy_completion_record',w.status='completed' and event_id is null,
    'self_verification_reason_required',same_actor and actor->>'role'='administrator');
end;$function$;

-- Preserve the established 0030 verification implementation behind a private
-- core and add only the Facility Manager facility-scope guard.
alter function public.verify_completed_work(uuid,jsonb) rename to verify_completed_work_0037_core;
revoke all on function public.verify_completed_work_0037_core(uuid,jsonb) from public,anon,authenticated,service_role;
create or replace function public.verify_completed_work(p_work_order_id uuid,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); facility uuid;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select w.facility_id into facility from public.work_orders w where w.id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(facility) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(facility) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  return public.verify_completed_work_0037_core(p_work_order_id,p_payload);
end;$function$;

-- Gate approval and preserve Administrator-only exception completion. All other
-- established transitions remain delegated to the protected 0034 core.
create or replace function public.transition_work_order(p_work_order_id uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_orders%rowtype;
  action text:=pg_catalog.lower(coalesce(p_action,'')); reason text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'reason','')),''); readiness jsonb; cost numeric; role text; actor_id uuid; actor_name text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  role:=actor->>'role'; actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name','Unknown user');
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if role='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  if role='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if action not in ('approve','complete') then return public.transition_work_order_0034_core(p_work_order_id,p_action,p_payload); end if;
  if action='complete' then
    if role<>'administrator' then return public.work_order_result_error('ACCESS_DENIED','Use the assigned Technician physical-completion submission.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED','Administrator exception completion requires an explicit audited reason.'); end if;
    readiness:=public.transition_work_order_0034_core(p_work_order_id,'complete',
      pg_catalog.jsonb_build_object('completion_notes',w.completion_notes,'actual_labour_hours',w.actual_labour_hours));
    if coalesce((readiness->>'ok')::boolean,false) then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,w.id,'administrator_exception_completion_recorded',w.status,'completed',actor_name,
        pg_catalog.jsonb_build_object('reason',reason,'completion_actor_id',actor_id,'recorded_at',pg_catalog.now())::text);
    end if;
    return readiness;
  end if;
  if w.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only submitted work may be approved to proceed.'); end if;
  readiness:=public.work_order_approval_readiness(w.id);
  if not coalesce((readiness->>'ready')::boolean,false) then return public.work_order_result_error('APPROVAL_NOT_READY',coalesce(readiness->>'blocking_reason','Approval basis is incomplete.')); end if;
  cost:=(readiness->>'proposed_cost')::numeric;
  if (cost<=250000 and role not in ('supervisor','facility_manager','administrator'))
    or (cost>250000 and cost<=500000 and role not in ('facility_manager','administrator'))
    or (cost>500000 and role<>'administrator') then return public.work_order_result_error('APPROVAL_AUTHORITY_EXCEEDED','Your monetary approval authority is insufficient.'); end if;
  if actor_id=w.requested_by and role<>'administrator' then return public.work_order_result_error('SELF_APPROVAL_DENIED','A requester cannot approve their own proposed work.'); end if;
  if actor_id=w.requested_by and reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED','Administrator self-approval requires an audited reason.'); end if;
  update public.work_orders set status='approved',approved_at=pg_catalog.now(),updated_at=pg_catalog.now() where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_approve','submitted','approved',actor_name,
    pg_catalog.jsonb_build_object('decision','approved_to_proceed','proposed_cost',cost,'required_authority',readiness->>'required_authority',
      'reason',reason,'administrator_override',actor_id=w.requested_by and role='administrator')::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'approval_readiness',readiness);
exception when invalid_text_representation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Approval data is invalid.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Work Order approval failed.'); end;$function$;

revoke all on function public.work_order_approval_readiness(uuid) from public,anon,service_role;
revoke all on function public.set_work_order_approval_basis(uuid,jsonb) from public,anon,service_role;
revoke all on function public.accept_work_responsibility(uuid) from public,anon,service_role;
revoke all on function public.submit_physical_completion(uuid,jsonb) from public,anon,service_role;
revoke all on function public.work_order_verification_readiness(uuid) from public,anon,service_role;
revoke all on function public.verify_completed_work(uuid,jsonb) from public,anon,service_role;
revoke all on function public.verify_completed_work_0037_core(uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.transition_work_order(uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.work_order_approval_readiness(uuid) to authenticated;
grant execute on function public.set_work_order_approval_basis(uuid,jsonb) to authenticated;
grant execute on function public.accept_work_responsibility(uuid) to authenticated;
grant execute on function public.submit_physical_completion(uuid,jsonb) to authenticated;
grant execute on function public.work_order_verification_readiness(uuid) to authenticated;
grant execute on function public.verify_completed_work(uuid,jsonb) to authenticated;
grant execute on function public.transition_work_order(uuid,text,jsonb) to authenticated;

do $postconditions$
declare object_name text; config text[];
begin
  foreach object_name in array array[
    'public.work_order_approval_readiness(uuid)','public.set_work_order_approval_basis(uuid,jsonb)','public.accept_work_responsibility(uuid)',
    'public.submit_physical_completion(uuid,jsonb)','public.work_order_verification_readiness(uuid)',
    'public.verify_completed_work(uuid,jsonb)','public.transition_work_order(uuid,text,jsonb)',
    'public.pilot_account_ready(uuid)','public.facility_manager_facility_permitted(uuid)','public.supervisor_facility_permitted(uuid)'
  ] loop
    select p.proconfig into config from pg_catalog.pg_proc p where p.oid=object_name::regprocedure and p.prosecdef;
    if config is null or config<>array['search_path=pg_catalog'] then raise exception '0037 function security postcondition failed: %',object_name; end if;
    if not has_function_privilege('authenticated',object_name,'EXECUTE') or has_function_privilege('anon',object_name,'EXECUTE')
      or has_function_privilege('service_role',object_name,'EXECUTE') then raise exception '0037 function grant postcondition failed: %',object_name; end if;
  end loop;
  if has_function_privilege('authenticated','public.verify_completed_work_0037_core(uuid,jsonb)','EXECUTE')
    or has_function_privilege('anon','public.verify_completed_work_0037_core(uuid,jsonb)','EXECUTE')
    or has_function_privilege('service_role','public.verify_completed_work_0037_core(uuid,jsonb)','EXECUTE') then
    raise exception '0037 private verification core grant postcondition failed';
  end if;
  if not exists(select 1 from pg_catalog.pg_policy p where p.polrelid='public.work_orders'::regclass
    and p.polname='work_orders_read_permitted' and p.polcmd='r' and p.polroles=array['authenticated'::regrole::oid]
    and pg_catalog.pg_get_expr(p.polqual,p.polrelid) like '%facility_manager_facility_permitted%'
    and pg_catalog.pg_get_expr(p.polqual,p.polrelid) like '%supervisor_facility_permitted%') then
    raise exception '0037 Work Order management facility-scope policy postcondition failed';
  end if;
  if exists(select 1 from wp_fmw_0037_security_snapshot before full join (
    select p.oid::regprocedure::text identity,p.prosecdef,p.proconfig,p.proacl,pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) definition_hash
    from pg_catalog.pg_proc p where p.oid in ('public.record_work_order_execution(uuid,jsonb)'::regprocedure,
      'public.technician_facility_read_permitted(uuid)'::regprocedure,
      'public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)'::regprocedure,
      'public.protect_profile_authorization_fields()'::regprocedure)) after using(identity)
    where before.identity is null or after.identity is null or (before.prosecdef,before.proconfig,before.proacl,before.definition_hash)
      is distinct from (after.prosecdef,after.proconfig,after.proacl,after.definition_hash)) then
    raise exception '0037 changed protected 0035/0036 security contracts';
  end if;
  if not exists(select 1 from pg_catalog.pg_trigger t where t.tgrelid='public.profiles'::regclass
    and t.tgname='protect_profile_authorization_fields' and t.tgenabled='O' and not t.tgisinternal) then
    raise exception '0037 profile authorization protection trigger missing';
  end if;
end;$postconditions$;

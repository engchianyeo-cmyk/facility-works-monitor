-- WP-LC2-M1: Work Order Lifecycle v2 foundations.
-- Design: docs/design/WORK_ORDER_LIFECYCLE_V2.md (approved 2026-10-20). Decisions D-01..D-06.
-- Adds the Finance role, Approver facility memberships and facility-scoped Approver
-- visibility, Administrator-only versioned approval limits, Administrator-only quotation
-- threshold changes, company terminology labels, Work Order copied parties, and one
-- approval-authority helper used by later lifecycle migrations.

begin;

do $preflight$
begin
  if current_user <> 'postgres' then raise exception 'LC2-M1 must be applied as postgres'; end if;
  if pg_catalog.to_regclass('public.work_order_approval_limit_versions') is not null
    or pg_catalog.to_regclass('public.terminology_labels') is not null
    or pg_catalog.to_regclass('public.work_order_copied_parties') is not null
    or pg_catalog.to_regprocedure('public.work_order_approval_authority(uuid,numeric)') is not null then
    raise exception 'LC2-M1 conflicting or partial state already exists';
  end if;
  if pg_catalog.to_regprocedure('public.change_procurement_policy(numeric,text,uuid)') is null
    or pg_catalog.to_regclass('public.facility_memberships') is null then
    raise exception 'LC2-M1 prerequisite missing';
  end if;
end;$preflight$;

-- 1. Finance role -------------------------------------------------------------
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role = any (array[
  'reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance']));

create or replace function public.pilot_account_ready(p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select exists (
    select 1 from public.profiles profile
    where profile.id=p_user_id
      and profile.is_active=true
      and profile.deleted_at is null
      and profile.password_change_required=false
      and profile.role in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance')
  )
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_profile(p_target_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  previous_profile public.profiles%rowtype;
  result public.profiles%rowtype;
  next_role text;
  next_display_name text;
  next_trade text;
  next_active boolean;
  next_department_id uuid;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or not public.pilot_account_ready(actor_profile.id)
  then
    raise exception 'Administrator authorization required';
  end if;

  select * into previous_profile from public.profiles
  where id = p_target_id and deleted_at is null for update;
  if previous_profile.id is null then raise exception 'Profile not found'; end if;

  next_role := lower(trim(coalesce(p_payload ->> 'role', previous_profile.role)));
  next_display_name := trim(coalesce(p_payload ->> 'display_name', previous_profile.display_name));
  next_trade := nullif(trim(case when p_payload ? 'trade_discipline'
    then coalesce(p_payload ->> 'trade_discipline', '')
    else coalesce(previous_profile.trade_discipline, '') end), '');
  next_active := case when p_payload ? 'is_active'
    then (p_payload ->> 'is_active')::boolean else previous_profile.is_active end;
  next_department_id := case when p_payload ? 'department_id'
    then nullif(p_payload ->> 'department_id', '')::uuid
    else previous_profile.department_id end;

  if next_role not in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance')
    or next_display_name = ''
  then raise exception 'Invalid profile values'; end if;
  if next_role = 'technician' and next_trade is null then
    raise exception 'Technicians require a trade or discipline';
  end if;
  if next_department_id is not null and not exists (
    select 1 from public.departments where id = next_department_id and deleted_at is null
  ) then raise exception 'Department is unavailable'; end if;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set
    display_name = next_display_name,
    department_id = next_department_id,
    trade_discipline = case when next_role = 'technician' then next_trade else null end,
    contact_number = case when p_payload ? 'contact_number'
      then nullif(trim(coalesce(p_payload ->> 'contact_number', '')), '')
      else contact_number end,
    role = next_role,
    is_active = next_active
  where id = p_target_id
  returning * into result;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    'user_admin_profile_updated',
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', result.id,
      'previous_role', previous_profile.role,
      'role', result.role,
      'previous_active', previous_profile.is_active,
      'is_active', result.is_active
    )::text
  );

  return pg_catalog.to_jsonb(result);
end;
$function$;


CREATE OR REPLACE FUNCTION public.admin_finalize_provisioned_profile(p_target_id uuid, p_payload jsonb, p_event text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  target_profile public.profiles%rowtype;
  result public.profiles%rowtype;
  target_role text := lower(trim(coalesce(p_payload ->> 'role', '')));
  target_name text := trim(coalesce(p_payload ->> 'display_name', ''));
  target_trade text := nullif(trim(coalesce(p_payload ->> 'trade_discipline', '')), '');
  target_department_id uuid := nullif(p_payload ->> 'department_id', '')::uuid;
  target_active boolean := coalesce((p_payload ->> 'is_active')::boolean, true);
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or not public.pilot_account_ready(actor_profile.id)
  then raise exception 'Administrator authorization required'; end if;
  if p_event not in ('user_admin_invited','user_admin_direct_created','user_admin_pending_activated')
  then raise exception 'Unsupported provisioning event'; end if;

  select * into target_profile from public.profiles where id = p_target_id for update;
  if target_profile.id is null then raise exception 'Quarantine profile was not created'; end if;
  if target_role not in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance')
    or target_name = ''
  then raise exception 'Invalid profile values'; end if;
  if target_role = 'technician' and target_trade is null then
    raise exception 'Technicians require a trade or discipline';
  end if;
  if target_department_id is not null and not exists (
    select 1 from public.departments where id = target_department_id and deleted_at is null
  ) then raise exception 'Department is unavailable'; end if;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set
    display_name = target_name,
    department_id = target_department_id,
    trade_discipline = case when target_role = 'technician' then target_trade else null end,
    contact_number = nullif(trim(coalesce(p_payload ->> 'contact_number', '')), ''),
    role = target_role,
    is_active = target_active,
    deleted_at = null,
    password_change_required = true
  where id = p_target_id
  returning * into result;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    p_event,
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', result.id,
      'role', result.role,
      'is_active', result.is_active,
      'password_change_required', true
    )::text
  );

  return pg_catalog.to_jsonb(result);
end;
$function$;



-- 2. Approver facility memberships and facility-scoped Approver visibility ---------
alter table public.facility_memberships drop constraint facility_memberships_membership_role_check;
alter table public.facility_memberships add constraint facility_memberships_membership_role_check
  check (membership_role = any (array['technician','approver','supervisor','facility_manager']));

create function public.approver_facility_permitted(p_facility_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select public.pilot_account_ready(auth.uid())
    and public.current_user_role()='approver'
    and exists (
      select 1 from public.facility_memberships fm join public.sites s on s.id=fm.facility_id
      where fm.profile_id=auth.uid() and fm.facility_id=p_facility_id
        and fm.membership_role='approver' and fm.active
        and fm.effective_from<=pg_catalog.now()
        and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
        and s.is_active
    )
$function$;

-- Approval authority facility check: Administrator anywhere; Approver, Supervisor and
-- Facility Manager only through an active same-role membership of the facility.
create function public.approval_facility_permitted(p_facility_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and (
    public.current_user_role()='administrator'
    or public.approver_facility_permitted(p_facility_id)
    or public.supervisor_facility_permitted(p_facility_id)
    or public.facility_manager_facility_permitted(p_facility_id)
  )
$function$;

drop policy work_orders_read_permitted on public.work_orders;
create policy work_orders_read_permitted on public.work_orders for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (
    (public.current_user_role()='technician' and public.technician_facility_read_permitted(facility_id))
    or (public.current_user_role()<>'technician' and (
      requested_by=auth.uid() or assigned_technician_id=auth.uid()
      or public.current_user_role() in ('administrator','finance')
      or public.approver_facility_permitted(facility_id)
      or public.supervisor_facility_permitted(facility_id)
      or public.facility_manager_facility_permitted(facility_id)
    ))
  )
);

create or replace function public.release1_work_order_visible(p_work_order_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and exists (
    select 1 from public.work_orders w where w.id=p_work_order_id and (
      (public.current_user_role()='technician' and public.technician_facility_read_permitted(w.facility_id))
      or (public.current_user_role()<>'technician' and (
        w.requested_by=auth.uid() or w.assigned_technician_id=auth.uid()
        or public.current_user_role() in ('administrator','finance')
        or public.approver_facility_permitted(w.facility_id)
        or public.supervisor_facility_permitted(w.facility_id)
        or public.facility_manager_facility_permitted(w.facility_id)
      ))
    )
  );
$function$;

-- 3. Administrator-only, versioned approval limits ------------------------------
create table public.work_order_approval_limit_versions (
  id uuid primary key default gen_random_uuid(),
  changed_by uuid references public.profiles(id) on delete restrict,
  change_reason text not null check (length(btrim(change_reason)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create table public.work_order_approval_limits (
  version_id uuid not null references public.work_order_approval_limit_versions(id) on delete restrict,
  role text not null check (role in ('approver','supervisor','facility_manager','administrator')),
  maximum_amount numeric(14,2) check (maximum_amount is null or (maximum_amount >= 0 and maximum_amount = round(maximum_amount,2))),
  primary key (version_id, role)
);
create table public.work_order_approval_limit_policy (
  singleton boolean primary key default true check (singleton),
  version_id uuid not null references public.work_order_approval_limit_versions(id) on delete restrict
);
with v as (
  insert into public.work_order_approval_limit_versions(changed_by,change_reason)
  values (null,'Initial limits from owner decisions D-02 and D-04 (20 Oct 2026)') returning id
), l as (
  insert into public.work_order_approval_limits(version_id,role,maximum_amount)
  select v.id, x.role, x.amount from v cross join (values
    ('approver',250000.00::numeric),('supervisor',250000.00),('facility_manager',500000.00),('administrator',null)) x(role,amount)
)
insert into public.work_order_approval_limit_policy(version_id) select id from v;

create function public.protect_approval_limit_history() returns trigger language plpgsql set search_path=pg_catalog as $function$
begin raise exception 'Approval limit history is immutable'; end;$function$;
create trigger protect_approval_limit_versions before update or delete on public.work_order_approval_limit_versions
  for each row execute function public.protect_approval_limit_history();
create trigger protect_approval_limits before update or delete on public.work_order_approval_limits
  for each row execute function public.protect_approval_limit_history();

alter table public.work_order_approval_limit_versions enable row level security;
alter table public.work_order_approval_limits enable row level security;
alter table public.work_order_approval_limit_policy enable row level security;
revoke all on public.work_order_approval_limit_versions, public.work_order_approval_limits, public.work_order_approval_limit_policy from public, anon, authenticated, service_role;
grant select on public.work_order_approval_limit_versions, public.work_order_approval_limits, public.work_order_approval_limit_policy to authenticated;
create policy approval_limit_versions_read on public.work_order_approval_limit_versions for select to authenticated using (public.pilot_account_ready(auth.uid()));
create policy approval_limits_read on public.work_order_approval_limits for select to authenticated using (public.pilot_account_ready(auth.uid()));
create policy approval_limit_policy_read on public.work_order_approval_limit_policy for select to authenticated using (public.pilot_account_ready(auth.uid()));

alter table public.work_orders add column approval_limit_version_id uuid references public.work_order_approval_limit_versions(id) on delete restrict;

-- Returns the limit (null = unlimited) for a role under a version; raises if role has no authority.
create function public.work_order_role_approval_limit(p_role text, p_version_id uuid default null)
returns numeric language plpgsql stable security definer set search_path=pg_catalog as $function$
declare v uuid; found_row boolean; amount numeric;
begin
  v:=coalesce(p_version_id,(select version_id from public.work_order_approval_limit_policy where singleton));
  select true, l.maximum_amount into found_row, amount from public.work_order_approval_limits l where l.version_id=v and l.role=p_role;
  if not coalesce(found_row,false) then return -1; end if;
  return amount;
end;$function$;

create function public.change_work_order_approval_limits(p_limits jsonb, p_reason text, p_expected_version uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); previous uuid; next_version uuid; r text; raw text; amount numeric; previous_limits jsonb;
begin
  if actor is null or actor->>'role'<>'administrator' then
    return public.work_order_result_error('ACCESS_DENIED','Only an Administrator may change approval limits.');
  end if;
  if p_limits is null or pg_catalog.jsonb_typeof(p_limits)<>'object' or nullif(pg_catalog.btrim(coalesce(p_reason,'')),'') is null or pg_catalog.length(pg_catalog.btrim(p_reason))>1000 then
    return public.work_order_result_error('VALIDATION_ERROR','Limits for Approver, Supervisor and Facility Manager and a bounded reason are required.');
  end if;
  select version_id into previous from public.work_order_approval_limit_policy where singleton for update;
  if p_expected_version is distinct from previous then
    return public.work_order_result_error('POLICY_CONFLICT','Approval limits changed; refresh before saving.');
  end if;
  foreach r in array array['approver','supervisor','facility_manager'] loop
    raw:=p_limits->>r;
    begin amount:=raw::numeric; exception when others then amount:=null; end;
    if raw is null or amount is null or amount::text in ('NaN','Infinity','-Infinity') or amount<0 or amount>999999999999.99 or amount<>pg_catalog.round(amount,2) then
      return public.work_order_result_error('VALIDATION_ERROR','Each limit must be a non-negative SGD amount with at most two decimal places.');
    end if;
  end loop;
  select pg_catalog.jsonb_object_agg(role,maximum_amount) into previous_limits from public.work_order_approval_limits where version_id=previous;
  insert into public.work_order_approval_limit_versions(changed_by,change_reason) values((actor->>'id')::uuid,pg_catalog.btrim(p_reason)) returning id into next_version;
  insert into public.work_order_approval_limits(version_id,role,maximum_amount) values
    (next_version,'approver',(p_limits->>'approver')::numeric),
    (next_version,'supervisor',(p_limits->>'supervisor')::numeric),
    (next_version,'facility_manager',(p_limits->>'facility_manager')::numeric),
    (next_version,'administrator',null);
  update public.work_order_approval_limit_policy set version_id=next_version where singleton;
  insert into public.activity_logs(user_id,action,actor,note)
  values((actor->>'id')::uuid,'approval_limits_changed',coalesce(actor->>'display_name','Administrator'),
    pg_catalog.jsonb_build_object('previous_version',previous,'version',next_version,'previous_limits',previous_limits,
      'limits',pg_catalog.jsonb_build_object('approver',(p_limits->>'approver')::numeric,'supervisor',(p_limits->>'supervisor')::numeric,'facility_manager',(p_limits->>'facility_manager')::numeric,'administrator',null),
      'currency','SGD','reason',pg_catalog.btrim(p_reason))::text);
  return pg_catalog.jsonb_build_object('ok',true,'version_id',next_version);
end;$function$;

-- 4. Quotation threshold becomes Administrator-only (D-03.4) -----------------------
CREATE OR REPLACE FUNCTION public.change_procurement_policy(p_threshold numeric, p_reason text, p_expected_version uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); previous uuid; next_version uuid; old_threshold numeric;
begin
  if actor is null or actor->>'role'<>'administrator' then
    return public.work_order_result_error('ACCESS_DENIED','Only an Administrator may change company procurement policy.');
  end if;
  if p_threshold is null or p_threshold::text in ('NaN','Infinity','-Infinity') or p_threshold<=0 or p_threshold>999999999999.99 or p_threshold<>round(p_threshold,2)
    or nullif(btrim(p_reason),'') is null or length(btrim(p_reason))>1000 then
    return public.work_order_result_error('VALIDATION_ERROR','A positive SGD threshold with at most two decimal places and a bounded reason are required.');
  end if;
  select version_id into previous from public.procurement_company_policy where singleton for update;
  if p_expected_version is distinct from previous then
    return public.work_order_result_error('POLICY_CONFLICT','Company policy changed; refresh before saving.');
  end if;
  select low_value_threshold into old_threshold from public.procurement_policy_versions where id=previous;
  if old_threshold=p_threshold then return public.work_order_result_error('VALIDATION_ERROR','Enter a different threshold.'); end if;
  insert into public.procurement_policy_versions(low_value_threshold,changed_by,change_reason)
  values(p_threshold,(actor->>'id')::uuid,btrim(p_reason)) returning id into next_version;
  insert into public.commercial_approval_rules(rule_code,minimum_amount,maximum_amount,minimum_quotations,policy_version_id)
  values('LOW_VALUE_'||next_version::text,0,p_threshold,1,next_version),
        ('STANDARD_'||next_version::text,p_threshold,null,3,next_version);
  update public.procurement_company_policy set version_id=next_version where singleton;
  insert into public.activity_logs(user_id,action,actor,note)
  values((actor->>'id')::uuid,'procurement_policy_changed',actor->>'name',jsonb_build_object('previous_version',previous,'version',next_version,'previous_threshold',old_threshold,'threshold',p_threshold,'currency','SGD','reason',btrim(p_reason))::text);
  return jsonb_build_object('ok',true,'version_id',next_version,'low_value_threshold',p_threshold);
end;$function$;



-- 5. Company terminology (role and stage labels) -----------------------------------
create table public.terminology_labels (
  code text primary key check (code ~ '^(role|status):[a-z_]+$'),
  label text not null check (length(btrim(label)) between 1 and 60),
  updated_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now()
);
alter table public.terminology_labels enable row level security;
revoke all on public.terminology_labels from public, anon, authenticated, service_role;
grant select on public.terminology_labels to authenticated;
create policy terminology_labels_read on public.terminology_labels for select to authenticated using (public.pilot_account_ready(auth.uid()));

create function public.set_terminology_label(p_code text, p_label text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); v_code text:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_code,''))); v_label text:=nullif(pg_catalog.btrim(coalesce(p_label,'')),''); previous text;
begin
  if actor is null or actor->>'role'<>'administrator' then return public.work_order_result_error('ACCESS_DENIED','Only an Administrator may rename roles and stages.'); end if;
  if v_code !~ '^(role|status):[a-z_]+$' then return public.work_order_result_error('VALIDATION_ERROR','A role or stage code is required.'); end if;
  if v_code like 'role:%' and pg_catalog.substr(v_code,6) not in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance') then
    return public.work_order_result_error('VALIDATION_ERROR','Unknown role.'); end if;
  if v_code like 'status:%' and pg_catalog.substr(v_code,8) not in ('draft','submitted','approved','assigned','in_progress','completed','reviewed','closed','cancelled') then
    return public.work_order_result_error('VALIDATION_ERROR','Unknown stage.'); end if;
  select t.label into previous from public.terminology_labels t where t.code=v_code;
  if v_label is null then
    delete from public.terminology_labels t where t.code=v_code;
  else
    if pg_catalog.length(v_label)>60 then return public.work_order_result_error('VALIDATION_ERROR','Labels are limited to 60 characters.'); end if;
    insert into public.terminology_labels(code,label,updated_by) values(v_code,v_label,(actor->>'id')::uuid)
    on conflict on constraint terminology_labels_pkey do update set label=excluded.label,updated_by=excluded.updated_by,updated_at=pg_catalog.now();
  end if;
  insert into public.activity_logs(user_id,action,actor,note)
  values((actor->>'id')::uuid,'terminology_label_changed',coalesce(actor->>'display_name','Administrator'),
    pg_catalog.jsonb_build_object('code',v_code,'previous',previous,'label',v_label)::text);
  return pg_catalog.jsonb_build_object('ok',true,'code',v_code,'label',v_label);
end;$function$;

-- 6. Work Order copied parties ----------------------------------------------------
create table public.work_order_copied_parties (
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  added_by uuid not null references public.profiles(id) on delete restrict,
  added_at timestamptz not null default now(),
  primary key (work_order_id, profile_id)
);
alter table public.work_order_copied_parties enable row level security;
revoke all on public.work_order_copied_parties from public, anon, authenticated, service_role;
grant select on public.work_order_copied_parties to authenticated;
create policy work_order_copied_parties_read on public.work_order_copied_parties for select to authenticated
  using (public.release1_work_order_visible(work_order_id));

-- 7. Single approval-authority rule (design §4) ------------------------------------
-- Returns null when the current user may approve this Work Order at p_amount, otherwise
-- a structured error. Independence: not the requester and not the assigned Technician,
-- except an Administrator who supplies p_override_reason.
create function public.work_order_approval_authority(p_work_order_id uuid, p_amount numeric, p_override_reason text default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; role text; actor_id uuid; cap numeric; reason text:=nullif(pg_catalog.btrim(coalesce(p_override_reason,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  role:=actor->>'role'; actor_id:=(actor->>'id')::uuid;
  if role not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Approval authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not public.approval_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility approval membership is required.'); end if;
  if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<0 then
    return public.work_order_result_error('VALIDATION_ERROR','A valid amount is required for approval.'); end if;
  cap:=public.work_order_role_approval_limit(role);
  if cap is not null and (cap<0 or p_amount>cap) then
    return public.work_order_result_error('APPROVAL_AUTHORITY_EXCEEDED','Your monetary approval authority is insufficient.'); end if;
  if actor_id=w.requested_by or actor_id=w.assigned_technician_id then
    if role<>'administrator' then return public.work_order_result_error('SELF_APPROVAL_DENIED','You cannot approve a Work Order you raised or are assigned to.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED','Administrator self-approval requires an audited reason.'); end if;
  end if;
  return null;
end;$function$;

-- 8. Function privileges -----------------------------------------------------------
revoke all on function public.approver_facility_permitted(uuid) from public, anon, service_role;
revoke all on function public.approval_facility_permitted(uuid) from public, anon, service_role;
revoke all on function public.work_order_role_approval_limit(text,uuid) from public, anon, service_role;
revoke all on function public.work_order_approval_authority(uuid,numeric,text) from public, anon, service_role;
revoke all on function public.change_work_order_approval_limits(jsonb,text,uuid) from public, anon, service_role;
revoke all on function public.set_terminology_label(text,text) from public, anon, service_role;
revoke all on function public.protect_approval_limit_history() from public, anon, authenticated, service_role;
grant execute on function public.approver_facility_permitted(uuid) to authenticated;
grant execute on function public.approval_facility_permitted(uuid) to authenticated;
grant execute on function public.work_order_role_approval_limit(text,uuid) to authenticated;
grant execute on function public.work_order_approval_authority(uuid,numeric,text) to authenticated;
grant execute on function public.change_work_order_approval_limits(jsonb,text,uuid) to authenticated;
grant execute on function public.set_terminology_label(text,text) to authenticated;

-- 9. Postconditions ---------------------------------------------------------------
do $post$
begin
  if (select count(*) from public.work_order_approval_limits l join public.work_order_approval_limit_policy p on p.version_id=l.version_id)<>4 then
    raise exception 'LC2-M1 approval limits not seeded';
  end if;
  if not exists(select 1 from pg_catalog.pg_proc where oid='public.change_procurement_policy(numeric,text,uuid)'::regprocedure and prosrc like '%actor->>''role''<>''administrator''%') then
    raise exception 'LC2-M1 procurement policy restriction missing';
  end if;
end;$post$;

commit;

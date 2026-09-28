-- Align the already-valid facility_manager role with the existing identity and
-- Work Order authorization contract. This migration changes no profile data,
-- readiness flags, passwords, or historical records.

begin;

do $preflight$
declare
  signature text;
  expected_search_path text;
  definition text;
begin
  if current_user <> 'postgres' then
    raise exception '0033 must be applied as postgres';
  end if;

  for signature, expected_search_path in
    select * from (values
      ('public.pilot_account_ready(uuid)', 'search_path=public, pg_temp'),
      ('public.admin_update_profile(uuid,jsonb)', 'search_path=public, pg_temp'),
      ('public.admin_finalize_provisioned_profile(uuid,jsonb,text)', 'search_path=public, pg_temp'),
      ('public.update_work_order(uuid,jsonb)', 'search_path=pg_catalog'),
      ('public.assign_work_order(uuid,text,uuid)', 'search_path=pg_catalog')
    ) as required(signature, expected_search_path)
  loop
    if pg_catalog.to_regprocedure(signature) is null then
      raise exception '0033 refused: required function is missing: %', signature;
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_proc as procedure
      where procedure.oid = pg_catalog.to_regprocedure(signature)
        and procedure.prosecdef
        and expected_search_path = any(procedure.proconfig)
    ) then
      raise exception '0033 refused: SECURITY DEFINER/search_path contract is unexpected: %', signature;
    end if;
  end loop;

  select pg_catalog.pg_get_functiondef('public.pilot_account_ready(uuid)'::pg_catalog.regprocedure)
  into definition;
  if pg_catalog.position('''reviewer'', ''initiator'', ''approver'', ''technician'',' in definition) = 0
     or pg_catalog.position('''supervisor'', ''administrator''' in definition) = 0
     or pg_catalog.position('''facility_manager''' in definition) > 0 then
    raise exception '0033 refused: pilot_account_ready role contract is unexpected';
  end if;

  select pg_catalog.pg_get_functiondef('public.admin_update_profile(uuid,jsonb)'::pg_catalog.regprocedure)
  into definition;
  if pg_catalog.position('''reviewer'',''initiator'',''approver'',''technician'',''supervisor'',''administrator''' in definition) = 0
     or pg_catalog.position('''facility_manager''' in definition) > 0 then
    raise exception '0033 refused: admin_update_profile role contract is unexpected';
  end if;

  select pg_catalog.pg_get_functiondef('public.admin_finalize_provisioned_profile(uuid,jsonb,text)'::pg_catalog.regprocedure)
  into definition;
  if pg_catalog.position('''reviewer'',''initiator'',''approver'',''technician'',''supervisor'',''administrator''' in definition) = 0
     or pg_catalog.position('''facility_manager''' in definition) > 0 then
    raise exception '0033 refused: admin_finalize_provisioned_profile role contract is unexpected';
  end if;

  select pg_catalog.pg_get_functiondef('public.update_work_order(uuid,jsonb)'::pg_catalog.regprocedure)
  into definition;
  if pg_catalog.position('actor_role <> ''administrator'' and not (actor_id = previous.requested_by' in definition) = 0 then
    raise exception '0033 refused: update_work_order authorization contract is unexpected';
  end if;

  select pg_catalog.pg_get_functiondef('public.assign_work_order(uuid,text,uuid)'::pg_catalog.regprocedure)
  into definition;
  if pg_catalog.position('actor_role not in (''approver'',''supervisor'',''administrator'')' in definition) = 0 then
    raise exception '0033 refused: assign_work_order authorization contract is unexpected';
  end if;
end;
$preflight$;

create or replace function public.pilot_account_ready(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select exists (
    select 1
    from public.profiles as profile
    where profile.id = p_user_id
      and profile.is_active = true
      and profile.deleted_at is null
      and profile.password_change_required = false
      and profile.role in (
        'reviewer', 'initiator', 'approver', 'technician',
        'supervisor', 'facility_manager', 'administrator'
      )
  )
$function$;

do $align_functions$
declare
  definition text;
begin
  select pg_catalog.pg_get_functiondef('public.admin_update_profile(uuid,jsonb)'::pg_catalog.regprocedure)
  into definition;
  execute pg_catalog.replace(
    definition,
    '''reviewer'',''initiator'',''approver'',''technician'',''supervisor'',''administrator''',
    '''reviewer'',''initiator'',''approver'',''technician'',''supervisor'',''facility_manager'',''administrator'''
  );

  select pg_catalog.pg_get_functiondef('public.admin_finalize_provisioned_profile(uuid,jsonb,text)'::pg_catalog.regprocedure)
  into definition;
  execute pg_catalog.replace(
    definition,
    '''reviewer'',''initiator'',''approver'',''technician'',''supervisor'',''administrator''',
    '''reviewer'',''initiator'',''approver'',''technician'',''supervisor'',''facility_manager'',''administrator'''
  );

  select pg_catalog.pg_get_functiondef('public.update_work_order(uuid,jsonb)'::pg_catalog.regprocedure)
  into definition;
  execute pg_catalog.replace(
    definition,
    'actor_role <> ''administrator'' and not (actor_id = previous.requested_by',
    'actor_role not in (''facility_manager'',''administrator'') and not (actor_id = previous.requested_by'
  );

  select pg_catalog.pg_get_functiondef('public.assign_work_order(uuid,text,uuid)'::pg_catalog.regprocedure)
  into definition;
  execute pg_catalog.replace(
    definition,
    'actor_role not in (''approver'',''supervisor'',''administrator'')',
    'actor_role not in (''approver'',''supervisor'',''facility_manager'',''administrator'')'
  );
end;
$align_functions$;

drop policy if exists work_orders_read_permitted on public.work_orders;
create policy work_orders_read_permitted
on public.work_orders
for select
to authenticated
using (
  public.pilot_account_ready(auth.uid())
  and (
    requested_by = auth.uid()
    or assigned_technician_id = auth.uid()
    or public.current_user_role() in ('approver','supervisor','facility_manager','administrator')
  )
);

do $postconditions$
declare
  signature text;
  definition text;
begin
  foreach signature in array array[
    'public.pilot_account_ready(uuid)',
    'public.admin_update_profile(uuid,jsonb)',
    'public.admin_finalize_provisioned_profile(uuid,jsonb,text)',
    'public.update_work_order(uuid,jsonb)',
    'public.assign_work_order(uuid,text,uuid)'
  ] loop
    select pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(signature)) into definition;
    if pg_catalog.position('''facility_manager''' in definition) = 0 then
      raise exception '0033 postcondition failed: facility_manager is absent from %', signature;
    end if;
  end loop;

  if not exists (
    select 1
    from pg_catalog.pg_policy as policy
    where policy.polrelid = 'public.work_orders'::pg_catalog.regclass
      and policy.polname = 'work_orders_read_permitted'
      and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) like '%facility_manager%'
  ) then
    raise exception '0033 postcondition failed: Work Order read policy is not aligned';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
      and trigger_record.tgname = 'protect_profile_authorization_fields'
      and trigger_record.tgenabled = 'O'
      and not trigger_record.tgisinternal
      and trigger_record.tgfoid = 'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
  ) then
    raise exception '0033 postcondition failed: profile authorization protection is unavailable';
  end if;
end;
$postconditions$;

revoke all on function public.pilot_account_ready(uuid) from public, anon, service_role;
grant execute on function public.pilot_account_ready(uuid) to authenticated;

commit;

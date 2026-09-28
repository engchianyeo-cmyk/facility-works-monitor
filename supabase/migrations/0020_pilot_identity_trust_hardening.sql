-- WP-PILOT-001: single-customer pilot identity and trust hardening.
-- Local implementation only. This migration is intentionally fail closed.

begin;

do $guard$
begin
  if pg_catalog.to_regclass('public.profiles') is null
    or pg_catalog.to_regclass('public.account_invitations') is null
    or pg_catalog.to_regclass('public.work_orders') is null
    or pg_catalog.to_regclass('public.incidents') is null
    or pg_catalog.to_regclass('public.assets') is null
    or pg_catalog.to_regclass('public.maintenance_requirements') is null
    or pg_catalog.to_regclass('public.notification_outbox') is null
    or pg_catalog.to_regprocedure('public.handle_new_auth_user()') is null
    or pg_catalog.to_regprocedure('public.current_user_role()') is null
  then
    raise exception 'WP-PILOT-001 requires the reconciled schema and migrations 0012 through 0019';
  end if;
end;
$guard$;

alter table public.profiles
  add column if not exists password_change_required boolean not null default false;

comment on column public.profiles.password_change_required is
  'Fail-closed operational gate. Cleared only after a trusted server-side password update is reconciled.';

create index if not exists profiles_account_readiness_idx
  on public.profiles (is_active, password_change_required, role)
  where deleted_at is null;

-- Accounts that can be identified as having originated in the retired public
-- registration path are quarantined for Administrator review. Invitation-created
-- accounts are retained but must change their password before operational access.
update public.profiles as profile
set
  is_active = false,
  password_change_required = true,
  updated_at = pg_catalog.now()
from auth.users as auth_user
where auth_user.id = profile.id
  and auth_user.raw_user_meta_data ? 'public_signup_role';

update public.profiles as profile
set
  password_change_required = true,
  updated_at = pg_catalog.now()
from auth.users as auth_user
where auth_user.id = profile.id
  and auth_user.raw_user_meta_data ? 'administrator_invitation_token'
  and profile.deleted_at is null;

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
        'supervisor', 'administrator'
      )
  )
$function$;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select profile.role
  from public.profiles as profile
  where profile.id = auth.uid()
    and public.pilot_account_ready(profile.id)
$function$;

create or replace function public.work_order_actor()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select pg_catalog.jsonb_build_object(
    'id', profile.id,
    'display_name', profile.display_name,
    'role', profile.role,
    'department_id', profile.department_id
  )
  from public.profiles as profile
  where profile.id = auth.uid()
    and public.pilot_account_ready(profile.id)
$function$;

-- New Auth records without a valid Administrator invitation can no longer gain
-- operational access. They receive an inactive quarantine profile only so that
-- external Auth configuration drift still fails closed.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  invitation_token text := new.raw_user_meta_data ->> 'administrator_invitation_token';
  invitation public.account_invitations%rowtype;
begin
  if invitation_token is not null then
    select *
    into invitation
    from public.account_invitations
    where token_hash = encode(digest(invitation_token, 'sha256'), 'hex')
      and lower(email) = lower(coalesce(new.email, ''))
      and is_active = true
      and used_at is null
      and expires_at > pg_catalog.now()
    for update;

    if invitation.id is null then
      raise exception 'Invalid, expired or previously used invitation';
    end if;

    insert into public.profiles (
      id, display_name, email, department, department_id,
      trade_discipline, contact_number, role, is_active,
      password_change_required, created_at, updated_at
    ) values (
      new.id,
      invitation.display_name,
      new.email,
      invitation.department,
      null,
      nullif(trim(new.raw_user_meta_data ->> 'trade_discipline'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'contact_number'), ''),
      invitation.assigned_role,
      false,
      true,
      coalesce(new.created_at, pg_catalog.now()),
      pg_catalog.now()
    ) on conflict (id) do nothing;

    update public.account_invitations
    set used_at = pg_catalog.now()
    where id = invitation.id;

    return new;
  end if;

  insert into public.profiles (
    id, display_name, email, department, trade_discipline,
    contact_number, role, is_active, password_change_required,
    created_at, updated_at
  ) values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Pending account'
    ),
    new.email,
    nullif(trim(new.raw_user_meta_data ->> 'department'), ''),
    null,
    null,
    'reviewer',
    false,
    true,
    coalesce(new.created_at, pg_catalog.now()),
    pg_catalog.now()
  ) on conflict (id) do nothing;

  return new;
end;
$function$;

create or replace function public.protect_profile_authorization_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  admin_rpc boolean := coalesce(current_setting('fmworks.profile_admin_rpc', true), '') = 'on';
  password_rpc boolean := coalesce(current_setting('fmworks.password_change_completion', true), '') = 'on';
  active_administrator_count integer;
begin
  if new.password_change_required is distinct from old.password_change_required
    and not admin_rpc and not password_rpc
  then
    raise exception 'Password readiness can only be changed by a trusted server operation';
  end if;

  if (
      new.role is distinct from old.role
      or new.is_active is distinct from old.is_active
      or new.deleted_at is distinct from old.deleted_at
    ) and not admin_rpc
  then
    raise exception 'Role, activation and archive changes require the audited Administrator operation';
  end if;

  if auth.uid() is distinct from old.id
    and not admin_rpc
    and not (
      password_rpc
      and new.password_change_required is distinct from old.password_change_required
      and new.display_name is not distinct from old.display_name
      and new.email is not distinct from old.email
      and new.department is not distinct from old.department
      and new.department_id is not distinct from old.department_id
      and new.trade_discipline is not distinct from old.trade_discipline
      and new.contact_number is not distinct from old.contact_number
      and new.role is not distinct from old.role
      and new.is_active is not distinct from old.is_active
      and new.deleted_at is not distinct from old.deleted_at
    )
  then
    raise exception 'Another user profile can only be changed by the audited Administrator operation';
  end if;

  if admin_rpc and auth.uid() = old.id and (
    new.role <> 'administrator'
    or new.is_active = false
    or new.deleted_at is not null
  ) then
    raise exception 'Administrators cannot demote, deactivate or archive their own account';
  end if;

  if old.role = 'administrator'
    and old.is_active = true
    and old.deleted_at is null
    and old.password_change_required = false
    and (
      new.role <> 'administrator'
      or new.is_active = false
      or new.deleted_at is not null
    )
  then
    perform pg_catalog.pg_advisory_xact_lock(6042026);
    select count(*) into active_administrator_count
    from public.profiles
    where role = 'administrator'
      and is_active = true
      and deleted_at is null
      and password_change_required = false;

    if active_administrator_count <= 1 then
      raise exception 'The final ready Administrator cannot be changed';
    end if;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

create or replace function public.admin_update_profile(
  p_target_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
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

  if next_role not in ('reviewer','initiator','approver','technician','supervisor','administrator')
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

create or replace function public.admin_finalize_provisioned_profile(
  p_target_id uuid,
  p_payload jsonb,
  p_event text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
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
  if target_role not in ('reviewer','initiator','approver','technician','supervisor','administrator')
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

create or replace function public.admin_archive_profile(
  p_target_id uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_profile public.profiles%rowtype;
  target_profile public.profiles%rowtype;
  result public.profiles%rowtype;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or not public.pilot_account_ready(actor_profile.id)
  then raise exception 'Administrator authorization required'; end if;

  select * into target_profile from public.profiles
  where id = p_target_id and deleted_at is null for update;
  if target_profile.id is null then raise exception 'Profile not found'; end if;
  if target_profile.id = actor_profile.id then raise exception 'Administrators cannot archive their own account'; end if;
  if lower(trim(coalesce(p_confirmation, ''))) not in (
    lower(trim(target_profile.display_name)), lower(trim(coalesce(target_profile.email, '')))
  ) then raise exception 'Archive confirmation does not match'; end if;
  if exists (
    select 1 from public.work_orders
    where assigned_technician_id = p_target_id
      and status not in ('done','completed','closed','rejected','cancelled')
  ) then raise exception 'Active work assignments must be reassigned before archive'; end if;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set
    is_active = false,
    deleted_at = pg_catalog.now(),
    password_change_required = false
  where id = p_target_id
  returning * into result;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    'user_admin_archived',
    actor_profile.display_name,
    pg_catalog.jsonb_build_object('target_profile_id', result.id, 'role', result.role)::text
  );

  return pg_catalog.to_jsonb(result);
end;
$function$;

create or replace function public.admin_prepare_permanent_profile_deletion(
  p_target_id uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_profile public.profiles%rowtype;
  target_profile public.profiles%rowtype;
  ready_administrator_count integer;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or not public.pilot_account_ready(actor_profile.id)
  then raise exception 'Administrator authorization required'; end if;

  select * into target_profile from public.profiles where id = p_target_id for update;
  if target_profile.id is null then raise exception 'Profile not found'; end if;
  if target_profile.id = actor_profile.id then
    raise exception 'Administrators cannot permanently delete their own account';
  end if;
  if lower(trim(coalesce(p_confirmation, ''))) not in (
    lower(trim(target_profile.display_name)), lower(trim(coalesce(target_profile.email, '')))
  ) then raise exception 'Permanent deletion confirmation does not match'; end if;
  if exists (
    select 1 from public.work_orders
    where assigned_technician_id = p_target_id
      and status not in ('closed','cancelled')
  ) then raise exception 'Active work assignments must be reassigned before permanent deletion'; end if;

  if target_profile.role = 'administrator'
    and target_profile.is_active = true
    and target_profile.deleted_at is null
    and target_profile.password_change_required = false
  then
    select count(*) into ready_administrator_count
    from public.profiles
    where role = 'administrator'
      and is_active = true
      and deleted_at is null
      and password_change_required = false;
    if ready_administrator_count <= 1 then
      raise exception 'The final ready Administrator cannot be permanently deleted';
    end if;
  end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    'user_admin_permanent_deletion_requested',
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', target_profile.id,
      'target_email', target_profile.email,
      'target_display_name', target_profile.display_name,
      'target_role', target_profile.role,
      'external_auth_status', 'pending'
    )::text
  );

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'target_profile_id', target_profile.id,
    'target_display_name', target_profile.display_name
  );
end;
$function$;

create or replace function public.admin_record_permanent_delete_result(
  p_actor_id uuid,
  p_target_id uuid,
  p_succeeded boolean,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_profile public.profiles%rowtype;
  safe_error_code text := nullif(pg_catalog.left(trim(coalesce(p_error_code, '')), 100), '');
begin
  select * into actor_profile from public.profiles where id = p_actor_id;
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or actor_profile.is_active is not true or actor_profile.deleted_at is not null
  then raise exception 'Administrator reconciliation actor is unavailable'; end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    case when p_succeeded
      then 'user_admin_permanent_deletion_completed'
      else 'user_admin_permanent_deletion_failed' end,
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', p_target_id,
      'external_auth_status', case when p_succeeded then 'deleted' else 'failed' end,
      'error_code', case when p_succeeded then null else safe_error_code end
    )::text
  );

  return pg_catalog.jsonb_build_object('ok', true, 'recorded', true);
end;
$function$;

create or replace function public.complete_password_change_trusted(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  target_profile public.profiles%rowtype;
  was_required boolean;
begin
  select * into target_profile from public.profiles
  where id = p_user_id and is_active = true and deleted_at is null for update;
  if target_profile.id is null then raise exception 'Active profile not found'; end if;

  was_required := target_profile.password_change_required;
  perform pg_catalog.set_config('fmworks.password_change_completion', 'on', true);
  update public.profiles set password_change_required = false where id = p_user_id;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    p_user_id,
    case when was_required then 'user_first_password_changed' else 'user_password_changed' end,
    target_profile.display_name,
    'Password value and recovery token are intentionally not recorded.'
  );

  return pg_catalog.jsonb_build_object('ok', true, 'was_required', was_required);
end;
$function$;

create or replace function public.record_user_presence(presence_route text default null)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  safe_route text;
begin
  if not public.pilot_account_ready(auth.uid()) then return false; end if;
  safe_route := case when left(trim(coalesce(presence_route, '')), 1) = '/'
    then left(split_part(trim(presence_route), '?', 1), 200) else null end;
  update public.profiles set
    last_active_at = pg_catalog.now(),
    last_seen_route = coalesce(safe_route, last_seen_route)
  where id = auth.uid()
    and (
      last_active_at is null
      or last_active_at < pg_catalog.now() - interval '90 seconds'
      or (safe_route is not null and last_seen_route is distinct from safe_route)
    );
  return found;
end;
$function$;

-- A final table-level guard protects against legacy SECURITY DEFINER routines
-- whose role comparison could otherwise treat SQL NULL as a false condition.
-- Trusted background/service operations have no end-user auth.uid() and remain
-- outside this browser-session guard.
create or replace function public.enforce_pilot_actor_ready()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if auth.uid() is not null and not public.pilot_account_ready(auth.uid()) then
    raise insufficient_privilege using message = 'Operational account readiness is required';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

-- Notification delivery outcomes are accepted only through the service-role
-- boundary below. Browser identity and client-supplied actor values are not
-- used to authorize or attribute provider results.
create or replace function public.record_incident_notification_result(
  p_incident_id uuid,
  p_channel text,
  p_delivered boolean,
  p_code text,
  p_provider text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  affected integer;
  safe_provider text := pg_catalog.left(coalesce(nullif(trim(p_provider), ''), 'none'), 100);
begin
  if p_channel not in ('sms','whatsapp')
    or p_code not in ('DELIVERED','NOT_CONFIGURED','DELIVERY_FAILED')
    or p_delivered is distinct from (p_code = 'DELIVERED')
  then return public.incident_result_error('VALIDATION_ERROR','Notification result is invalid.'); end if;
  if not exists(select 1 from public.incidents where id = p_incident_id) then
    return public.incident_result_error('NOT_FOUND','Incident was not found.');
  end if;

  update public.notification_outbox set
    delivery_status = case when p_delivered then 'sent' else 'failed' end,
    provider = safe_provider,
    attempted_at = pg_catalog.now(),
    delivered_at = case when p_delivered then pg_catalog.now() else null end,
    result_code = p_code,
    attempts = attempts + 1,
    retry_count = retry_count + 1,
    last_error_code = case when p_delivered then null else p_code end,
    last_error = null
  where incident_id = p_incident_id
    and channel = p_channel
    and delivery_status = 'pending';
  get diagnostics affected = row_count;

  insert into public.activity_logs(user_id, incident_id, action, actor, note)
  values (
    null,
    p_incident_id,
    'incident_notification_result',
    'Trusted notification worker',
    pg_catalog.jsonb_build_object(
      'channel', p_channel,
      'delivered', p_delivered,
      'code', p_code,
      'provider', safe_provider,
      'recipients', affected
    )::text
  );
  return pg_catalog.jsonb_build_object('ok', true, 'updated', affected);
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The notification result could not be recorded.');
end;
$function$;

do $triggers$
declare
  table_name text;
begin
  foreach table_name in array array[
    'work_orders','incidents','emergency_response_roster','evidence_items',
    'asset_systems','assets','maintenance_requirements',
    'maintenance_requirement_revisions','pm_occurrences','pm_occurrence_deferrals'
  ] loop
    execute pg_catalog.format('drop trigger if exists enforce_pilot_actor_ready on public.%I', table_name);
    execute pg_catalog.format(
      'create trigger enforce_pilot_actor_ready before insert or update or delete on public.%I for each row execute function public.enforce_pilot_actor_ready()',
      table_name
    );
  end loop;
end;
$triggers$;

create or replace function public.get_incident_operations(p_incident_id uuid default null)
returns table (
  incident_id uuid, responder_display_name text, responder_role text,
  team_name text, commander_display_name text, commander_role text,
  assignment_state text, sms_status text, whatsapp_status text
)
language sql stable security definer set search_path = public, pg_temp as $function$
  with visible_incidents as (
    select incident.* from public.incidents as incident
    where public.pilot_account_ready(auth.uid())
      and (p_incident_id is null or incident.id = p_incident_id)
      and (public.current_user_role() in ('approver','supervisor','administrator')
        or incident.reported_by = auth.uid() or incident.assigned_technician_id = auth.uid()
        or (incident.assigned_team_id is not null and exists (
          select 1 from public.maintenance_team_members as member
          where member.team_id=incident.assigned_team_id and member.profile_id=auth.uid() and member.is_active
        )))
  ), channel_summary as (
    select outbox.incident_id, outbox.channel,
      case
        when pg_catalog.bool_or(outbox.delivery_status='failed' and outbox.result_code='NOT_CONFIGURED') then 'not_configured'
        when pg_catalog.bool_or(outbox.delivery_status='failed') then 'failed'
        when pg_catalog.bool_or(outbox.delivery_status in ('pending','processing')) then 'pending'
        when pg_catalog.bool_and(outbox.delivery_status='sent') then 'delivered'
        else 'unavailable'
      end as channel_status
    from public.notification_outbox as outbox
    join visible_incidents as incident on incident.id=outbox.incident_id
    where outbox.channel in ('sms','whatsapp')
    group by outbox.incident_id,outbox.channel
  )
  select incident.id, technician.display_name, technician.role, team.name,
    commander.display_name, commander.role,
    case when incident.assigned_technician_id is not null then 'technician'
      when incident.assigned_team_id is not null then 'team' else 'unassigned' end,
    coalesce(sms.channel_status,'unavailable'),coalesce(whatsapp.channel_status,'unavailable')
  from visible_incidents as incident
  left join public.profiles as technician on technician.id=incident.assigned_technician_id
  left join public.maintenance_teams as team on team.id=incident.assigned_team_id
  left join public.profiles as commander on commander.id=incident.incident_commander_id
  left join channel_summary as sms on sms.incident_id=incident.id and sms.channel='sms'
  left join channel_summary as whatsapp on whatsapp.incident_id=incident.id and whatsapp.channel='whatsapp'
$function$;

create or replace function public.register_evidence_item(
  p_parent_type text,p_parent_id uuid,p_original_filename text,p_content_type text,
  p_byte_size bigint,p_category text,p_description text,p_storage_path text
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $function$
declare actor_id uuid:=auth.uid(); actor_name text; result public.evidence_items;
begin
  if actor_id is null then return jsonb_build_object('ok',false,'code','AUTHENTICATION_REQUIRED'); end if;
  if not public.pilot_account_ready(actor_id) then return jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  select display_name into actor_name from public.profiles where id=actor_id;
  if p_parent_type='work_order' then
    if not exists(select 1 from public.work_orders w where w.id=p_parent_id and (
      public.current_user_role() in ('approver','supervisor','administrator') or w.user_id=actor_id or w.requested_by=actor_id or w.assigned_technician_id=actor_id
    )) then return jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  elsif p_parent_type='incident' then
    if not exists(select 1 from public.incidents i where i.id=p_parent_id and (
      public.current_user_role() in ('approver','supervisor','administrator') or i.reported_by=actor_id or i.assigned_technician_id=actor_id
      or (i.assigned_team_id is not null and exists(select 1 from public.maintenance_team_members m where m.team_id=i.assigned_team_id and m.profile_id=actor_id and m.is_active))
    )) then return jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  else return jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;
  if p_storage_path not like 'evidence/'||replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%'
    or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path)
  then return jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT'); end if;
  insert into public.evidence_items(parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path)
  values(p_parent_type,case when p_parent_type='work_order' then p_parent_id end,case when p_parent_type='incident' then p_parent_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_category,nullif(btrim(p_description),''),p_storage_path)
  returning * into result;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note)
  values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,
    jsonb_build_object('evidence_id',result.id,'category',result.category,'parent_type',result.parent_type)::text);
  return jsonb_build_object('ok',true,'evidence',to_jsonb(result)-'storage_path');
exception when check_violation or invalid_text_representation then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
when unique_violation then return jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE');
when others then return jsonb_build_object('ok',false,'code','INTERNAL_ERROR'); end;
$function$;

-- Password-pending and inactive accounts retain only their own profile read so
-- the application can route them to recovery/setup. Operational data is gated.
drop policy if exists profiles_read_self_or_admin on public.profiles;
create policy profiles_read_self_or_admin on public.profiles for select to authenticated using (
  id = auth.uid() or public.current_user_role() = 'administrator'
);
drop policy if exists profiles_update_self_or_admin on public.profiles;
create policy profiles_update_self_or_admin on public.profiles for update to authenticated
  using (public.pilot_account_ready(auth.uid()) and (id = auth.uid() or public.current_user_role() = 'administrator'))
  with check (public.pilot_account_ready(auth.uid()) and (id = auth.uid() or public.current_user_role() = 'administrator'));

drop policy if exists departments_authenticated_read on public.departments;
create policy departments_authenticated_read on public.departments for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (deleted_at is null or public.current_user_role() = 'administrator')
);
drop policy if exists categories_read_authenticated on public.categories;
create policy categories_read_authenticated on public.categories for select to authenticated using (
  public.pilot_account_ready(auth.uid())
);
drop policy if exists work_orders_read_permitted on public.work_orders;
create policy work_orders_read_permitted on public.work_orders for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (
    requested_by = auth.uid()
    or assigned_technician_id = auth.uid()
    or public.current_user_role() in ('approver','supervisor','administrator')
  )
);
drop policy if exists vendors_authenticated_read on public.vendors;
create policy vendors_authenticated_read on public.vendors for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and active = true and deleted_at is null
);
drop policy if exists maintenance_teams_authenticated_read on public.maintenance_teams;
create policy maintenance_teams_authenticated_read on public.maintenance_teams for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and is_active = true and deleted_at is null
);
drop policy if exists maintenance_team_members_authenticated_read on public.maintenance_team_members;
create policy maintenance_team_members_authenticated_read on public.maintenance_team_members for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and is_active = true
);
drop policy if exists incidents_authenticated_read on public.incidents;
create policy incidents_authenticated_read on public.incidents for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (
    public.current_user_role() in ('approver','supervisor','administrator')
    or reported_by = auth.uid()
    or assigned_technician_id = auth.uid()
    or (assigned_team_id is not null and exists (
      select 1 from public.maintenance_team_members as member
      where member.team_id = assigned_team_id and member.profile_id = auth.uid() and member.is_active
    ))
  )
);
drop policy if exists emergency_roster_authenticated_read on public.emergency_response_roster;
create policy emergency_roster_authenticated_read on public.emergency_response_roster for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (
    public.current_user_role() in ('supervisor','administrator') or profile_id = auth.uid()
  )
);
drop policy if exists evidence_parent_authorized_read on public.evidence_items;
create policy evidence_parent_authorized_read on public.evidence_items for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (
    (evidence_items.work_order_id is not null and exists(select 1 from public.work_orders where id=evidence_items.work_order_id))
    or (evidence_items.incident_id is not null and exists(select 1 from public.incidents where id=evidence_items.incident_id))
  )
);

-- Policies introduced by 0018/0019 already use current_user_role(), which now
-- returns null unless the account is ready. Recreate the final audit projection
-- with an explicit readiness gate to avoid accidental owner-path regressions.
drop policy if exists activity_logs_read_permitted on public.activity_logs;
create policy activity_logs_read_permitted on public.activity_logs for select to authenticated using(
  public.pilot_account_ready(auth.uid()) and (
    (work_order_id is not null and exists(select 1 from public.work_orders w where w.id=activity_logs.work_order_id))
    or (incident_id is not null and exists(select 1 from public.incidents i where i.id=activity_logs.incident_id))
    or (asset_id is not null and exists(select 1 from public.assets a where a.id=activity_logs.asset_id))
    or (maintenance_requirement_id is not null and exists(select 1 from public.maintenance_requirements r where r.id=activity_logs.maintenance_requirement_id))
    or (pm_occurrence_id is not null and exists(select 1 from public.pm_occurrences o where o.id=activity_logs.pm_occurrence_id))
    or public.current_user_role()='administrator'
  )
);

-- The anonymous public work-order surface and browser-controlled notification
-- delivery results are retired. A future provider worker may use service_role.
revoke all on function public.list_public_work_orders() from public, anon, authenticated, service_role;
revoke all on function public.record_incident_notification_result(uuid,text,boolean,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_incident_notification_result(uuid,text,boolean,text,text)
  to service_role;

revoke all on function public.pilot_account_ready(uuid) from public, anon, service_role;
grant execute on function public.pilot_account_ready(uuid) to authenticated;
revoke all on function public.admin_update_profile(uuid,jsonb) from public, anon, service_role;
revoke all on function public.admin_finalize_provisioned_profile(uuid,jsonb,text) from public, anon, service_role;
revoke all on function public.admin_archive_profile(uuid,text) from public, anon, service_role;
revoke all on function public.admin_prepare_permanent_profile_deletion(uuid,text) from public, anon, service_role;
revoke all on function public.admin_record_permanent_delete_result(uuid,uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.admin_update_profile(uuid,jsonb) to authenticated;
grant execute on function public.admin_finalize_provisioned_profile(uuid,jsonb,text) to authenticated;
grant execute on function public.admin_archive_profile(uuid,text) to authenticated;
grant execute on function public.admin_prepare_permanent_profile_deletion(uuid,text) to authenticated;
grant execute on function public.admin_record_permanent_delete_result(uuid,uuid,boolean,text) to service_role;
revoke all on function public.complete_password_change_trusted(uuid) from public, anon, authenticated;
grant execute on function public.complete_password_change_trusted(uuid) to service_role;
revoke all on function public.enforce_pilot_actor_ready() from public, anon, authenticated, service_role;

comment on function public.admin_finalize_provisioned_profile(uuid,jsonb,text) is
  'Atomic Postgres reconciliation after an Auth invitation/create succeeds. Failure leaves the trigger-created profile inactive.';
comment on function public.complete_password_change_trusted(uuid) is
  'Service-only reconciliation after Supabase Auth has accepted the new password.';
comment on function public.admin_prepare_permanent_profile_deletion(uuid,text) is
  'Validates permanent deletion and records a pending external Auth action without claiming it succeeded.';
comment on function public.admin_record_permanent_delete_result(uuid,uuid,boolean,text) is
  'Service-only audit reconciliation after the external Supabase Auth deletion attempt finishes.';

commit;

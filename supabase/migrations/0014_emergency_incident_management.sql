begin;

create table if not exists public.incident_number_counters (
  reference_year integer primary key,
  last_value integer not null check (last_value > 0)
);

create table if not exists public.incidents (
  id uuid primary key default gen_random_uuid(),
  incident_number text unique not null,
  incident_type text not null check (incident_type in (
    'lift_entrapment','fire','flood','major_water_leak','electrical_failure',
    'gas_leak','chemical_spill','medical_emergency','security','other'
  )),
  severity text not null default 'emergency'
    check (severity in ('emergency','critical','high','medium','low')),
  status text not null default 'reported' check (status in (
    'reported','acknowledged','mobilising','on_site','rescue_in_progress',
    'safe','recovery','closed','cancelled'
  )),
  location text not null check (length(pg_catalog.btrim(location)) > 0),
  description text not null check (length(pg_catalog.btrim(description)) > 0),
  reported_by uuid not null references public.profiles(id) on delete restrict,
  reported_at timestamptz not null default pg_catalog.now(),
  incident_commander_id uuid references public.profiles(id) on delete restrict,
  assigned_technician_id uuid references public.profiles(id) on delete restrict,
  assigned_team_id uuid references public.maintenance_teams(id) on delete restrict,
  acknowledgement_deadline timestamptz not null,
  acknowledged_at timestamptz,
  mobilising_at timestamptz,
  on_site_at timestamptz,
  rescue_started_at timestamptz,
  safe_at timestamptz,
  recovery_started_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint incidents_one_primary_responder check (
    not (assigned_technician_id is not null and assigned_team_id is not null)
  )
);

comment on table public.incidents is
  'Authenticated emergency incident lifecycle, separate from corrective work orders.';

alter table public.profiles
  add column if not exists whatsapp_number text;

create table if not exists public.emergency_response_roster (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete cascade,
  team_id uuid references public.maintenance_teams(id) on delete cascade,
  receive_emergency_alerts boolean not null default true,
  sms_enabled boolean not null default true,
  whatsapp_enabled boolean not null default true,
  email_enabled boolean not null default false,
  escalation_order integer not null default 100 check (escalation_order >= 0),
  active_from timestamptz,
  active_to timestamptz,
  incident_type text check (incident_type is null or incident_type in (
    'lift_entrapment','fire','flood','major_water_leak','electrical_failure',
    'gas_leak','chemical_spill','medical_emergency','security','other'
  )),
  active boolean not null default true,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint emergency_roster_one_target check (
    (profile_id is not null)::integer + (team_id is not null)::integer = 1
  ),
  constraint emergency_roster_valid_window check (
    active_to is null or active_from is null or active_to > active_from
  )
);

alter table public.work_orders add column if not exists incident_id uuid;
alter table public.work_orders drop constraint if exists work_orders_incident_id_fkey;
alter table public.work_orders add constraint work_orders_incident_id_fkey
  foreign key (incident_id) references public.incidents(id) on delete set null not valid;
alter table public.work_orders validate constraint work_orders_incident_id_fkey;

alter table public.activity_logs add column if not exists incident_id uuid;
alter table public.activity_logs drop constraint if exists activity_logs_incident_id_fkey;
alter table public.activity_logs add constraint activity_logs_incident_id_fkey
  foreign key (incident_id) references public.incidents(id) on delete cascade not valid;
alter table public.activity_logs validate constraint activity_logs_incident_id_fkey;

alter table public.notification_outbox alter column work_order_id drop not null;
alter table public.notification_outbox add column if not exists incident_id uuid
  references public.incidents(id) on delete cascade;
alter table public.notification_outbox add column if not exists recipient_profile_id uuid
  references public.profiles(id) on delete restrict;
alter table public.notification_outbox add column if not exists channel text;
alter table public.notification_outbox add column if not exists provider text not null default 'none';
alter table public.notification_outbox add column if not exists attempted_at timestamptz;
alter table public.notification_outbox add column if not exists delivered_at timestamptz;
alter table public.notification_outbox add column if not exists result_code text;
alter table public.notification_outbox add column if not exists provider_reference text;
alter table public.notification_outbox add column if not exists retry_count integer not null default 0;
alter table public.notification_outbox add column if not exists last_error_code text;
alter table public.notification_outbox drop constraint if exists notification_outbox_channel_check;
alter table public.notification_outbox add constraint notification_outbox_channel_check
  check (channel is null or channel in ('sms','whatsapp','email','teams','push'));
alter table public.notification_outbox drop constraint if exists notification_outbox_target_check;
alter table public.notification_outbox add constraint notification_outbox_target_check
  check (work_order_id is not null or incident_id is not null);
alter table public.notification_outbox drop constraint if exists notification_outbox_event_recipient_key;
create unique index if not exists notification_outbox_event_recipient_channel_idx
  on public.notification_outbox (
    event_key, coalesce(recipient_profile_id, recipient_user_id),
    coalesce(recipient_email, ''), coalesce(channel, '')
  );

create index if not exists incidents_active_priority_idx
  on public.incidents (status, severity, reported_at desc)
  where status not in ('closed','cancelled');
create index if not exists incidents_ack_deadline_idx
  on public.incidents (acknowledgement_deadline)
  where acknowledged_at is null and status not in ('closed','cancelled');
create index if not exists incidents_technician_idx on public.incidents (assigned_technician_id, reported_at desc);
create index if not exists incidents_team_idx on public.incidents (assigned_team_id, reported_at desc);
create index if not exists work_orders_incident_idx on public.work_orders (incident_id) where incident_id is not null;
create index if not exists activity_logs_incident_idx on public.activity_logs (incident_id, created_at desc) where incident_id is not null;
create index if not exists emergency_roster_resolution_idx
  on public.emergency_response_roster (active, incident_type, escalation_order);
create index if not exists notification_outbox_incident_idx
  on public.notification_outbox (incident_id, channel, delivery_status, created_at desc)
  where incident_id is not null;

create or replace function public.next_incident_number(reference_time timestamptz default pg_catalog.now())
returns text language plpgsql security definer set search_path = public, pg_temp as $fn$
declare
  v_reference_year integer := extract(year from reference_time at time zone 'UTC');
  reference_value integer;
begin
  insert into public.incident_number_counters(reference_year,last_value)
  values(v_reference_year,1)
  on conflict(reference_year) do update
    set last_value=public.incident_number_counters.last_value+1
  returning last_value into reference_value;
  return 'INC-'||v_reference_year::text||'-'||pg_catalog.lpad(reference_value::text,6,'0');
end;
$fn$;

create or replace function public.assign_incident_number()
returns trigger language plpgsql set search_path = public, pg_temp as $fn$
begin
  if new.incident_number is null or pg_catalog.btrim(new.incident_number) = '' then
    new.incident_number := public.next_incident_number(coalesce(new.reported_at,pg_catalog.now()));
  end if;
  if new.acknowledgement_deadline is null then
    new.acknowledgement_deadline := coalesce(new.reported_at,pg_catalog.now()) + interval '5 minutes';
  end if;
  return new;
end;
$fn$;

create or replace function public.validate_emergency_roster_entry()
returns trigger language plpgsql set search_path = public, pg_temp as $fn$
declare target_role text;
begin
  if tg_op='INSERT' then new.created_by:=auth.uid();
  else new.created_by:=old.created_by; end if;
  if new.profile_id is not null then
    select role into target_role from public.profiles
      where id=new.profile_id and is_active and deleted_at is null;
    if target_role not in ('technician','supervisor','administrator') then
      raise exception using errcode='23514', message='Roster profile must be an active Technician, Supervisor, or Administrator.';
    end if;
  elsif not exists(select 1 from public.maintenance_teams where id=new.team_id and is_active and deleted_at is null) then
    raise exception using errcode='23514', message='Roster team must be active.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists assign_incident_number on public.incidents;
create trigger assign_incident_number before insert on public.incidents
  for each row execute function public.assign_incident_number();
drop trigger if exists set_incidents_updated_at on public.incidents;
create trigger set_incidents_updated_at before update on public.incidents
  for each row execute function public.set_row_updated_at();
drop trigger if exists set_emergency_roster_updated_at on public.emergency_response_roster;
create trigger set_emergency_roster_updated_at before update on public.emergency_response_roster
  for each row execute function public.set_row_updated_at();
drop trigger if exists validate_emergency_roster_entry on public.emergency_response_roster;
create trigger validate_emergency_roster_entry before insert or update on public.emergency_response_roster
  for each row execute function public.validate_emergency_roster_entry();

create or replace function public.incident_result_error(p_code text, p_message text)
returns jsonb language sql immutable set search_path = public, pg_temp as $fn$
  select pg_catalog.jsonb_build_object('ok', false, 'code', p_code, 'message', p_message)
$fn$;

create or replace function public.create_incident(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare
  actor_id uuid := auth.uid(); actor_role text := public.current_user_role();
  incident public.incidents; responder_profile uuid; responder_team uuid;
  roster_count integer; responder_sms boolean:=true; responder_whatsapp boolean:=true;
begin
  if actor_id is null or actor_role is null then
    return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.');
  end if;
  if actor_role = 'technician' then
    return public.incident_result_error('ACCESS_DENIED','Your role cannot report an incident.');
  end if;
  if pg_catalog.lower(coalesce(p_payload->>'incident_type','')) not in
    ('lift_entrapment','fire','flood','major_water_leak','electrical_failure','gas_leak','chemical_spill','medical_emergency','security','other') then
    return public.incident_result_error('VALIDATION_ERROR','Incident type is invalid.');
  end if;
  if pg_catalog.lower(coalesce(p_payload->>'severity','emergency')) not in ('emergency','critical','high','medium','low') then
    return public.incident_result_error('VALIDATION_ERROR','Incident severity is invalid.');
  end if;
  if pg_catalog.btrim(coalesce(p_payload->>'location','')) = '' or pg_catalog.btrim(coalesce(p_payload->>'description','')) = '' then
    return public.incident_result_error('VALIDATION_ERROR','Location and description are required.');
  end if;

  with valid_roster as (
    select r.* from public.emergency_response_roster r
    left join public.profiles p on p.id=r.profile_id
    left join public.maintenance_teams t on t.id=r.team_id
    where r.active and r.receive_emergency_alerts
      and (r.active_from is null or r.active_from<=pg_catalog.now())
      and (r.active_to is null or r.active_to>pg_catalog.now())
      and (r.incident_type is null or r.incident_type=pg_catalog.lower(p_payload->>'incident_type'))
      and ((p.id is not null and p.role='technician' and p.is_active and p.deleted_at is null)
        or (t.id is not null and t.is_active and t.deleted_at is null))
  )
  select count(*), (pg_catalog.array_agg(r.profile_id))[1], (pg_catalog.array_agg(r.team_id))[1],
    (pg_catalog.array_agg(r.sms_enabled))[1],(pg_catalog.array_agg(r.whatsapp_enabled))[1]
    into roster_count, responder_profile, responder_team,responder_sms,responder_whatsapp
  from valid_roster r where r.escalation_order=(select min(escalation_order) from valid_roster);
  if roster_count <> 1 then responder_profile:=null; responder_team:=null; responder_sms:=false; responder_whatsapp:=false; end if;

  insert into public.incidents (
    incident_number, incident_type, severity, location, description, reported_by,
    incident_commander_id, assigned_technician_id, assigned_team_id,
    acknowledgement_deadline
  ) values (
    null, pg_catalog.lower(p_payload->>'incident_type'),
    pg_catalog.lower(coalesce(p_payload->>'severity','emergency')),
    pg_catalog.btrim(p_payload->>'location'), pg_catalog.btrim(p_payload->>'description'), actor_id,
    case when actor_role in ('administrator','supervisor') then actor_id else null end,
    responder_profile, responder_team, pg_catalog.now() + interval '5 minutes'
  ) returning * into incident;

  insert into public.activity_logs (user_id, incident_id, action, from_status, to_status, actor, note)
  select actor_id, incident.id, 'incident_created', null, 'reported', p.display_name,
    pg_catalog.jsonb_build_object('severity',incident.severity,'incident_type',incident.incident_type,
      'assignment_state',case when responder_profile is null and responder_team is null then 'UNASSIGNED_EMERGENCY' else 'ASSIGNED' end)::text
  from public.profiles p where p.id = actor_id;

  insert into public.notification_outbox (
    incident_id,event_type,event_key,recipient_user_id,recipient_profile_id,
    recipient_email,channel,payload,delivery_status,provider,result_code
  )
  select incident.id,'emergency_incident_reported',incident.id::text||':emergency',recipient.id,recipient.id,
    recipient.email,channel.name,
    pg_catalog.jsonb_build_object('incident_number',incident.incident_number,'incident_path','/incidents/'||incident.id::text),
    'pending','none','PENDING'
  from (
    select p.id,p.email,true as sms_enabled,true as whatsapp_enabled from public.profiles p
      where p.is_active and p.deleted_at is null and p.role in ('administrator','supervisor')
    union
    select p.id,p.email,responder_sms,responder_whatsapp from public.profiles p where p.id=responder_profile
    union
    select p.id,p.email,responder_sms,responder_whatsapp from public.maintenance_team_members m join public.profiles p on p.id=m.profile_id
      where m.team_id=responder_team and m.is_active and p.is_active and p.deleted_at is null
  ) recipient cross join (values ('sms'),('whatsapp')) channel(name)
  where (channel.name='sms' and recipient.sms_enabled) or (channel.name='whatsapp' and recipient.whatsapp_enabled)
  on conflict do nothing;

  return pg_catalog.jsonb_build_object('ok',true,'incident',pg_catalog.to_jsonb(incident),
    'assignment_state',case when responder_profile is null and responder_team is null then 'UNASSIGNED_EMERGENCY' else 'ASSIGNED' end);
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The emergency incident could not be created.');
end;
$fn$;

create or replace function public.link_work_order_to_incident(p_work_order_id uuid,p_incident_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare actor_id uuid:=auth.uid(); actor_role text:=public.current_user_role(); work_order public.work_orders;
begin
  if actor_id is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if actor_role not in ('approver','supervisor','administrator') then
    return public.incident_result_error('ACCESS_DENIED','Your role cannot link corrective work.');
  end if;
  if not exists(select 1 from public.incidents where id=p_incident_id) then
    return public.incident_result_error('NOT_FOUND','Incident was not found.');
  end if;
  update public.work_orders set incident_id=p_incident_id,updated_at=pg_catalog.now()
    where id=p_work_order_id and status not in ('closed','cancelled') returning * into work_order;
  if work_order.id is null then return public.incident_result_error('NOT_FOUND','Active work order was not found.'); end if;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note)
    select actor_id,work_order.id,p_incident_id,'work_order_linked_to_incident',p.display_name,
      pg_catalog.jsonb_build_object('incident_id',p_incident_id)::text from public.profiles p where p.id=actor_id;
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(work_order));
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The corrective work order could not be linked.');
end;
$fn$;

create or replace function public.record_incident_notification_result(
  p_incident_id uuid, p_channel text, p_delivered boolean, p_code text, p_provider text
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare actor_id uuid := auth.uid(); affected integer;
begin
  if actor_id is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if p_channel not in ('sms','whatsapp') or p_code not in ('DELIVERED','NOT_CONFIGURED','DELIVERY_FAILED') then
    return public.incident_result_error('VALIDATION_ERROR','Notification result is invalid.');
  end if;
  if not exists(select 1 from public.incidents i where i.id=p_incident_id and (i.reported_by=actor_id or public.current_user_role() in ('administrator','supervisor'))) then
    return public.incident_result_error('ACCESS_DENIED','Notification result cannot be recorded.');
  end if;
  update public.notification_outbox set
    delivery_status=case when p_delivered then 'sent' when p_code='NOT_CONFIGURED' then 'failed' else 'failed' end,
    provider=pg_catalog.left(coalesce(nullif(p_provider,''),'none'),100), attempted_at=pg_catalog.now(),
    delivered_at=case when p_delivered then pg_catalog.now() else null end,
    result_code=p_code, attempts=attempts+1, retry_count=retry_count+1,
    last_error_code=case when p_delivered then null else p_code end,
    last_error=null
  where incident_id=p_incident_id and channel=p_channel and delivery_status='pending';
  get diagnostics affected = row_count;
  insert into public.activity_logs(user_id,incident_id,action,actor,note)
    select actor_id,p_incident_id,'incident_notification_result',p.display_name,
      pg_catalog.jsonb_build_object('channel',p_channel,'delivered',p_delivered,'code',p_code,'provider',pg_catalog.left(coalesce(p_provider,'none'),100),'recipients',affected)::text
    from public.profiles p where p.id=actor_id;
  return pg_catalog.jsonb_build_object('ok',true,'updated',affected);
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The notification result could not be recorded.');
end;
$fn$;

create or replace function public.assign_incident(p_incident_id uuid, p_assignment_type text, p_assignee_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare actor_id uuid := auth.uid(); actor_role text := public.current_user_role(); incident public.incidents;
begin
  if actor_id is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if actor_role not in ('supervisor','administrator') then return public.incident_result_error('ACCESS_DENIED','Roster authority is required.'); end if;
  if p_assignment_type = 'technician' and not exists(select 1 from public.profiles where id=p_assignee_id and role='technician' and is_active and deleted_at is null) then
    return public.incident_result_error('INVALID_ASSIGNMENT','Select a valid active technician.');
  elsif p_assignment_type = 'team' and not exists(select 1 from public.maintenance_teams where id=p_assignee_id and is_active and deleted_at is null) then
    return public.incident_result_error('INVALID_ASSIGNMENT','Select a valid active maintenance team.');
  elsif p_assignment_type not in ('technician','team') then
    return public.incident_result_error('INVALID_ASSIGNMENT','Assignment type is invalid.');
  end if;
  update public.incidents set
    assigned_technician_id=case when p_assignment_type='technician' then p_assignee_id else null end,
    assigned_team_id=case when p_assignment_type='team' then p_assignee_id else null end
  where id=p_incident_id and status not in ('closed','cancelled') returning * into incident;
  if incident.id is null then return public.incident_result_error('NOT_FOUND','Active incident was not found.'); end if;
  insert into public.activity_logs(user_id,incident_id,action,from_status,to_status,actor,note)
    select actor_id,incident.id,'incident_assigned',incident.status,incident.status,p.display_name,
      pg_catalog.jsonb_build_object('assignment_type',p_assignment_type,'assignee_id',p_assignee_id)::text
    from public.profiles p where p.id=actor_id;
  return pg_catalog.jsonb_build_object('ok',true,'incident',pg_catalog.to_jsonb(incident));
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The incident assignment could not be updated.');
end;
$fn$;

create or replace function public.transition_incident(p_incident_id uuid, p_action text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare actor_id uuid := auth.uid(); actor_role text := public.current_user_role(); previous public.incidents; incident public.incidents; target text; authorized boolean := false;
begin
  if actor_id is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  select * into previous from public.incidents where id=p_incident_id for update;
  if previous.id is null then return public.incident_result_error('NOT_FOUND','Incident was not found.'); end if;
  target := case pg_catalog.lower(p_action)
    when 'acknowledge' then 'acknowledged' when 'mobilise' then 'mobilising'
    when 'arrive' then 'on_site' when 'start_rescue' then 'rescue_in_progress'
    when 'make_safe' then 'safe' when 'start_recovery' then 'recovery'
    when 'close' then 'closed' when 'cancel' then 'cancelled' end;
  if not ((previous.status='reported' and target='acknowledged') or (previous.status='acknowledged' and target='mobilising')
    or (previous.status='mobilising' and target='on_site') or (previous.status='on_site' and target='rescue_in_progress')
    or (previous.status='rescue_in_progress' and target='safe') or (previous.status='safe' and target='recovery')
    or (previous.status='recovery' and target='closed') or (target='cancelled' and previous.status not in ('closed','cancelled'))) then
    return public.incident_result_error('INVALID_TRANSITION','The incident transition is not allowed.');
  end if;
  authorized := actor_role='administrator'
    or (actor_role='supervisor' and target in ('closed','cancelled'))
    or (actor_role='technician' and actor_id=previous.assigned_technician_id)
    or (actor_role='technician' and previous.assigned_team_id is not null and exists(
      select 1 from public.maintenance_team_members m where m.team_id=previous.assigned_team_id and m.profile_id=actor_id and m.is_active));
  if not authorized then return public.incident_result_error('ACCESS_DENIED','You cannot update this incident.'); end if;
  update public.incidents set status=target,
    acknowledged_at=case when target='acknowledged' then pg_catalog.now() else acknowledged_at end,
    mobilising_at=case when target='mobilising' then pg_catalog.now() else mobilising_at end,
    on_site_at=case when target='on_site' then pg_catalog.now() else on_site_at end,
    rescue_started_at=case when target='rescue_in_progress' then pg_catalog.now() else rescue_started_at end,
    safe_at=case when target='safe' then pg_catalog.now() else safe_at end,
    recovery_started_at=case when target='recovery' then pg_catalog.now() else recovery_started_at end,
    closed_at=case when target='closed' then pg_catalog.now() else closed_at end
    where id=p_incident_id returning * into incident;
  insert into public.activity_logs(user_id,incident_id,action,from_status,to_status,actor)
    select actor_id,incident.id,'incident_'||pg_catalog.lower(p_action),previous.status,target,p.display_name from public.profiles p where p.id=actor_id;
  return pg_catalog.jsonb_build_object('ok',true,'incident',pg_catalog.to_jsonb(incident));
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The incident transition could not be completed.');
end;
$fn$;

alter table public.incidents enable row level security;
alter table public.emergency_response_roster enable row level security;

create policy incidents_authenticated_read on public.incidents for select to authenticated using (
  public.current_user_role() in ('approver','supervisor','administrator')
  or reported_by=auth.uid() or assigned_technician_id=auth.uid()
  or (assigned_team_id is not null and exists(select 1 from public.maintenance_team_members m where m.team_id=assigned_team_id and m.profile_id=auth.uid() and m.is_active))
);
create policy emergency_roster_authenticated_read on public.emergency_response_roster for select to authenticated using (
  public.current_user_role() in ('supervisor','administrator') or profile_id=auth.uid()
);
create policy emergency_roster_manage on public.emergency_response_roster for all to authenticated
  using (public.current_user_role()='administrator' or (
    public.current_user_role()='supervisor' and (team_id is not null or exists(
      select 1 from public.profiles p where p.id=profile_id and p.role in ('technician','supervisor')
    ))
  ))
  with check (public.current_user_role()='administrator' or (
    public.current_user_role()='supervisor' and (team_id is not null or exists(
      select 1 from public.profiles p where p.id=profile_id and p.role in ('technician','supervisor')
    ))
  ));

drop policy if exists activity_logs_read_permitted on public.activity_logs;
create policy activity_logs_read_permitted on public.activity_logs for select to authenticated using (
  (work_order_id is not null and exists(select 1 from public.work_orders w where w.id=activity_logs.work_order_id))
  or (incident_id is not null and exists(select 1 from public.incidents i where i.id=activity_logs.incident_id))
  or public.current_user_role()='administrator'
);

revoke insert,update,delete on public.incidents from authenticated, anon;
revoke insert,update,delete on public.notification_outbox from authenticated, anon;
revoke all on public.emergency_response_roster from anon;
grant select on public.incidents, public.emergency_response_roster to authenticated;
grant insert,update,delete on public.emergency_response_roster to authenticated;
grant select on public.notification_outbox to authenticated;

revoke all on function public.assign_incident_number() from public,anon,authenticated,service_role;
revoke all on function public.next_incident_number(timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.validate_emergency_roster_entry() from public,anon,authenticated,service_role;
revoke all on function public.incident_result_error(text,text) from public,anon,authenticated,service_role;
revoke all on function public.create_incident(jsonb) from public,anon,service_role;
revoke all on function public.assign_incident(uuid,text,uuid) from public,anon,service_role;
revoke all on function public.transition_incident(uuid,text) from public,anon,service_role;
revoke all on function public.record_incident_notification_result(uuid,text,boolean,text,text) from public,anon,service_role;
revoke all on function public.link_work_order_to_incident(uuid,uuid) from public,anon,service_role;
grant execute on function public.create_incident(jsonb) to authenticated;
grant execute on function public.assign_incident(uuid,text,uuid) to authenticated;
grant execute on function public.transition_incident(uuid,text) to authenticated;
grant execute on function public.record_incident_notification_result(uuid,text,boolean,text,text) to authenticated;
grant execute on function public.link_work_order_to_incident(uuid,uuid) to authenticated;

commit;

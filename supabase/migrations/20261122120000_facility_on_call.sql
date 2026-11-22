-- M39 (owner D-81, D-82, 22 Nov 2026): the emergency on-call roster and emergency incidents belong to a facility.
-- Before this, both were company-wide (0014, built before facilities existed): an incident alerted the single
-- lowest-order on-call entry wherever that person worked, and every Supervisor in the company.
-- 1. emergency_response_roster.facility_id and incidents.facility_id. Existing entries take the facility their
--    Technician is staff of; existing incidents keep no facility.
-- 2. create_incident: the facility is chosen (or the reporter's only facility); alerts go to that facility's on-call
--    list, its Supervisors and Facility Manager, and the Super-Administrator.
-- 3. create_incident_with_asset passes the asset's facility when none was chosen.
-- 4. The roster: each entry names its facility; a Supervisor or Facility Manager manages their own facility's entries
--    (the Super-Administrator all); only that facility's Technicians may be chosen; the roster lists the facility.
begin;

alter table public.emergency_response_roster add column facility_id uuid references public.sites(id) on delete restrict;
alter table public.incidents add column facility_id uuid references public.sites(id) on delete restrict;
create index emergency_response_roster_facility_idx on public.emergency_response_roster(facility_id, active, escalation_order);
create index incidents_facility_idx on public.incidents(facility_id, reported_at desc);
comment on column public.emergency_response_roster.facility_id is 'M39: the facility this on-call entry covers (D-81).';
comment on column public.incidents.facility_id is 'M39: the facility of the incident; its on-call list is alerted (D-81).';

-- Existing entries: the facility the Technician is staff of (the first, by facility code).
update public.emergency_response_roster r set facility_id = (
  select m.facility_id from public.facility_memberships m join public.sites s on s.id = m.facility_id
  where m.profile_id = r.profile_id and m.membership_role = 'technician' and m.active order by s.code limit 1)
where r.facility_id is null and r.profile_id is not null;

create or replace function public.create_incident(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare
  actor_id uuid := auth.uid(); actor_role text := public.current_user_role();
  incident public.incidents; responder_profile uuid; responder_team uuid;
  roster_count integer; responder_sms boolean:=true; responder_whatsapp boolean:=true;
  v_facility uuid; v_choices integer;
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
  -- M39 (D-81): the incident belongs to a facility — the one chosen, else the reporter's only facility (or the only
  -- active facility for the Super-Administrator). Alerts go to that facility's on-call list.
  v_facility := nullif(p_payload->>'facility_id','')::uuid;
  if v_facility is null then
    if actor_role = 'administrator' then
      select count(*), (pg_catalog.array_agg(s.id))[1] into v_choices, v_facility from public.sites s where s.is_active;
    else
      select count(distinct m.facility_id), (pg_catalog.array_agg(m.facility_id))[1] into v_choices, v_facility
      from public.facility_memberships m where m.profile_id = actor_id and m.active
        and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now());
    end if;
    -- Several to choose from and none chosen: the facility stays unknown, and the alert falls back to the on-call
    -- entries with no facility and every Supervisor (the screen asks for the facility, so this is rare).
    if v_choices > 1 then v_facility := null; end if;
  end if;
  if v_facility is not null and not exists(select 1 from public.sites s where s.id = v_facility and s.is_active) then
    return public.incident_result_error('VALIDATION_ERROR','Facility not found.'); end if;
  if v_facility is not null and actor_role <> 'administrator' and not public.facility_member(v_facility) then
    return public.incident_result_error('ACCESS_DENIED','You can report incidents only at your own facility.'); end if;

  with valid_roster as (
    select r.* from public.emergency_response_roster r
    left join public.profiles p on p.id=r.profile_id
    left join public.maintenance_teams t on t.id=r.team_id
    where r.active and r.receive_emergency_alerts
      and (r.active_from is null or r.active_from<=pg_catalog.now())
      and (r.active_to is null or r.active_to>pg_catalog.now())
      and (r.incident_type is null or r.incident_type=pg_catalog.lower(p_payload->>'incident_type'))
      and (r.facility_id is null or r.facility_id is not distinct from v_facility)
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
    acknowledgement_deadline, facility_id
  ) values (
    null, pg_catalog.lower(p_payload->>'incident_type'),
    pg_catalog.lower(coalesce(p_payload->>'severity','emergency')),
    pg_catalog.btrim(p_payload->>'location'), pg_catalog.btrim(p_payload->>'description'), actor_id,
    case when actor_role in ('administrator','supervisor') then actor_id else null end,
    responder_profile, responder_team, pg_catalog.now() + interval '5 minutes', v_facility
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
    -- The Super-Administrator, and the Supervisors and Facility Manager of the incident's facility (all Supervisors
    -- when the facility is unknown).
    select p.id,p.email,true as sms_enabled,true as whatsapp_enabled from public.profiles p
      where p.is_active and p.deleted_at is null and (p.role = 'administrator' or (p.role in ('supervisor','facility_manager') and (
        (v_facility is null and p.role = 'supervisor') or exists(select 1 from public.facility_memberships m where m.profile_id = p.id and m.facility_id = v_facility and m.active
          and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now())))))
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
exception when invalid_text_representation then
  return public.incident_result_error('VALIDATION_ERROR','Facility reference is invalid.');
when others then
  return public.incident_result_error('INTERNAL_ERROR','The emergency incident could not be created.');
end;
$fn$;

create or replace function public.create_incident_with_asset(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); selected_asset uuid:=nullif(p_payload->>'asset_id','')::uuid; selected_tag text; selected_facility uuid; created jsonb; incident_row public.incidents; incident_id uuid; base jsonb;
begin
  if actor is null then return public.asset_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  if actor->>'role'='technician' then return public.asset_result_error('ACCESS_DENIED','Your role cannot report an Incident.'); end if;
  if selected_asset is null then return public.create_incident(p_payload-'asset_id'); end if;
  select asset_tag, facility_id into selected_tag, selected_facility from public.assets where id=selected_asset and lifecycle_status<>'decommissioned';
  if selected_tag is null then return public.asset_result_error('INVALID_REFERENCE','Selected Asset is unavailable.'); end if;
  -- M39: an incident at an asset is at the asset's facility unless the reporter chose one.
  base:=p_payload-'asset_id';
  if nullif(base->>'facility_id','') is null and selected_facility is not null then base:=base||pg_catalog.jsonb_build_object('facility_id',selected_facility); end if;
  created:=public.create_incident(base);
  if coalesce((created->>'ok')::boolean,false) is not true then return created; end if;
  incident_id:=(created#>>'{incident,id}')::uuid;
  update public.incidents set asset_id=selected_asset,updated_at=pg_catalog.now() where id=incident_id returning * into incident_row;
  insert into public.activity_logs(user_id,incident_id,asset_id,action,actor,note) values((actor->>'id')::uuid,incident_id,selected_asset,'incident_asset_linked',actor->>'name',pg_catalog.jsonb_build_object('before_asset','None','after_asset',selected_tag,'reason','Selected during Incident reporting')::text);
  return pg_catalog.jsonb_set(created,'{incident}',pg_catalog.to_jsonb(incident_row),true);
exception when invalid_text_representation then return public.asset_result_error('VALIDATION_ERROR','Asset reference is invalid.');
when others then return public.asset_result_error('INTERNAL_ERROR','The Incident could not be linked to the Asset.'); end;
$fn$;

drop function public.get_emergency_roster();
create function public.get_emergency_roster()
returns table (
  id uuid, profile_id uuid, profile_display_name text, profile_role text,
  team_id uuid, team_name text, receive_emergency_alerts boolean,
  sms_enabled boolean, whatsapp_enabled boolean, email_enabled boolean,
  escalation_order integer, active_from timestamptz, active_to timestamptz,
  incident_type text, active boolean, created_at timestamptz, updated_at timestamptz,
  facility_id uuid, facility_name text
)
language sql stable security definer set search_path = public, pg_temp as $fn$
  select r.id,r.profile_id,p.display_name,p.role,r.team_id,t.name,
    r.receive_emergency_alerts,r.sms_enabled,r.whatsapp_enabled,r.email_enabled,
    r.escalation_order,r.active_from,r.active_to,r.incident_type,r.active,r.created_at,r.updated_at,
    r.facility_id,s.name
  from public.emergency_response_roster r
  left join public.profiles p on p.id=r.profile_id
  left join public.maintenance_teams t on t.id=r.team_id
  left join public.sites s on s.id=r.facility_id
  where auth.uid() is not null and public.current_user_role() in ('approver','supervisor','facility_manager','administrator')
    and (public.current_user_role()='administrator' or (r.facility_id is not null and public.facility_member(r.facility_id)))
  order by s.name nulls last,r.active desc,r.escalation_order,r.created_at
$fn$;

drop function public.get_emergency_response_options();
create function public.get_emergency_response_options()
returns table (target_type text, target_id uuid, display_name text, role text, facility_id uuid)
language sql stable security definer set search_path = public, pg_temp as $fn$
  select 'technician',p.id,p.display_name,p.role,m.facility_id from public.profiles p
  join public.facility_memberships m on m.profile_id=p.id and m.membership_role='technician' and m.active
    and m.effective_from<=pg_catalog.now() and (m.effective_to is null or m.effective_to>pg_catalog.now())
  where auth.uid() is not null and public.current_user_role() in ('supervisor','facility_manager','administrator')
    and p.role='technician' and p.is_active and p.deleted_at is null
    and (public.current_user_role()='administrator' or public.facility_member(m.facility_id))
  union all
  select 'team',t.id,t.name,null,null from public.maintenance_teams t
  where auth.uid() is not null and public.current_user_role() in ('supervisor','facility_manager','administrator')
    and t.is_active and t.deleted_at is null
$fn$;

create or replace function public.upsert_emergency_roster(p_roster_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare actor_role text:=public.current_user_role(); target_profile uuid; target_team uuid; v_facility uuid;
  start_at timestamptz; end_at timestamptz; incident_category text; ranking integer; result public.emergency_response_roster;
begin
  if auth.uid() is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if actor_role not in ('supervisor','facility_manager','administrator') then return public.incident_result_error('ACCESS_DENIED','Roster management permission is required.'); end if;
  target_profile:=nullif(p_payload->>'profile_id','')::uuid; target_team:=nullif(p_payload->>'team_id','')::uuid;
  -- M39 (D-81): every on-call entry belongs to a facility; the Supervisor or Facility Manager manages their own.
  v_facility:=coalesce(nullif(p_payload->>'facility_id','')::uuid,(select facility_id from public.emergency_response_roster where id=p_roster_id));
  if v_facility is null or not exists(select 1 from public.sites where id=v_facility and is_active) then return public.incident_result_error('VALIDATION_ERROR','Choose the facility.'); end if;
  if actor_role<>'administrator' and not public.facility_member(v_facility) then return public.incident_result_error('ACCESS_DENIED','You manage the on-call roster of your own facility only.'); end if;
  if target_profile is not null and not public.active_facility_member(v_facility,'technician',target_profile) then return public.incident_result_error('INVALID_ASSIGNMENT','Choose a Technician of this facility.'); end if;
  if (target_profile is null)=(target_team is null) then return public.incident_result_error('VALIDATION_ERROR','Select one Technician or maintenance team.'); end if;
  if target_profile is not null and not exists(select 1 from public.profiles where id=target_profile and role='technician' and is_active and deleted_at is null) then return public.incident_result_error('INVALID_ASSIGNMENT','Select an active Technician.'); end if;
  if target_team is not null and not exists(select 1 from public.maintenance_teams where id=target_team and is_active and deleted_at is null) then return public.incident_result_error('INVALID_ASSIGNMENT','Select an active maintenance team.'); end if;
  start_at:=nullif(p_payload->>'active_from','')::timestamptz; end_at:=nullif(p_payload->>'active_to','')::timestamptz;
  if start_at is not null and end_at is not null and end_at<=start_at then return public.incident_result_error('VALIDATION_ERROR','Effective end must be after effective start.'); end if;
  incident_category:=nullif(pg_catalog.lower(p_payload->>'incident_type'),'');
  if incident_category is not null and incident_category not in ('lift_entrapment','fire','flood','major_water_leak','electrical_failure','gas_leak','chemical_spill','medical_emergency','security','other') then return public.incident_result_error('VALIDATION_ERROR','Incident type is invalid.'); end if;
  ranking:=coalesce((p_payload->>'escalation_order')::integer,100); if ranking<0 then return public.incident_result_error('VALIDATION_ERROR','Escalation order must not be negative.'); end if;
  if coalesce((p_payload->>'active')::boolean,true) and exists(select 1 from public.emergency_response_roster r where r.id is distinct from p_roster_id and r.active and r.facility_id is not distinct from v_facility and r.escalation_order=ranking and r.incident_type is not distinct from incident_category and r.profile_id is not distinct from target_profile and r.team_id is not distinct from target_team and tstzrange(coalesce(r.active_from,'-infinity'),coalesce(r.active_to,'infinity'),'[)') && tstzrange(coalesce(start_at,'-infinity'),coalesce(end_at,'infinity'),'[)')) then return public.incident_result_error('DUPLICATE_ROSTER','An overlapping active roster entry already exists for this target and ranking.'); end if;
  if p_roster_id is null then
    insert into public.emergency_response_roster(facility_id,profile_id,team_id,receive_emergency_alerts,sms_enabled,whatsapp_enabled,email_enabled,escalation_order,active_from,active_to,incident_type,active,created_by)
    values(v_facility,target_profile,target_team,coalesce((p_payload->>'receive_emergency_alerts')::boolean,true),coalesce((p_payload->>'sms_enabled')::boolean,true),coalesce((p_payload->>'whatsapp_enabled')::boolean,true),false,ranking,start_at,end_at,incident_category,coalesce((p_payload->>'active')::boolean,true),auth.uid()) returning * into result;
  else
    update public.emergency_response_roster set facility_id=v_facility,profile_id=target_profile,team_id=target_team,receive_emergency_alerts=coalesce((p_payload->>'receive_emergency_alerts')::boolean,true),sms_enabled=coalesce((p_payload->>'sms_enabled')::boolean,true),whatsapp_enabled=coalesce((p_payload->>'whatsapp_enabled')::boolean,true),email_enabled=false,escalation_order=ranking,active_from=start_at,active_to=end_at,incident_type=incident_category,active=coalesce((p_payload->>'active')::boolean,true)
    where id=p_roster_id returning * into result;
    if result.id is null then return public.incident_result_error('NOT_FOUND','Roster entry was not found.'); end if;
  end if;
  return pg_catalog.jsonb_build_object('ok',true,'roster',pg_catalog.to_jsonb(result));
exception when invalid_text_representation or datetime_field_overflow then return public.incident_result_error('VALIDATION_ERROR','Roster values are invalid.');
when others then return public.incident_result_error('INTERNAL_ERROR','The roster entry could not be saved.'); end;
$fn$;

create or replace function public.set_emergency_roster_active(p_roster_id uuid,p_active boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare result public.emergency_response_roster;
begin
  if auth.uid() is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if public.current_user_role() not in ('supervisor','facility_manager','administrator') then return public.incident_result_error('ACCESS_DENIED','Roster management permission is required.'); end if;
  if public.current_user_role()<>'administrator' and not exists(select 1 from public.emergency_response_roster r where r.id=p_roster_id and r.facility_id is not null and public.facility_member(r.facility_id)) then
    return public.incident_result_error('ACCESS_DENIED','You manage the on-call roster of your own facility only.'); end if;
  update public.emergency_response_roster set active=p_active where id=p_roster_id returning * into result;
  if result.id is null then return public.incident_result_error('NOT_FOUND','Roster entry was not found.'); end if;
  return pg_catalog.jsonb_build_object('ok',true,'roster',pg_catalog.to_jsonb(result));
exception when others then return public.incident_result_error('INTERNAL_ERROR','The roster entry could not be updated.'); end;
$fn$;

revoke all on function public.get_emergency_roster(), public.get_emergency_response_options(), public.upsert_emergency_roster(uuid,jsonb), public.set_emergency_roster_active(uuid,boolean), public.create_incident(jsonb), public.create_incident_with_asset(jsonb) from public, anon, service_role;
grant execute on function public.get_emergency_roster(), public.get_emergency_response_options(), public.upsert_emergency_roster(uuid,jsonb), public.set_emergency_roster_active(uuid,boolean), public.create_incident(jsonb), public.create_incident_with_asset(jsonb) to authenticated;

commit;

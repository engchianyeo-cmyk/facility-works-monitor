begin;

create or replace function public.get_incident_operations(p_incident_id uuid default null)
returns table (
  incident_id uuid, responder_display_name text, responder_role text,
  team_name text, commander_display_name text, commander_role text,
  assignment_state text, sms_status text, whatsapp_status text
)
language sql stable security definer set search_path = public, pg_temp as $fn$
  with visible_incidents as (
    select i.* from public.incidents i
    where auth.uid() is not null
      and (p_incident_id is null or i.id = p_incident_id)
      and (public.current_user_role() in ('approver','supervisor','administrator')
        or i.reported_by = auth.uid() or i.assigned_technician_id = auth.uid()
        or (i.assigned_team_id is not null and exists (
          select 1 from public.maintenance_team_members m
          where m.team_id=i.assigned_team_id and m.profile_id=auth.uid() and m.is_active
        )))
  ), channel_summary as (
    select n.incident_id, n.channel,
      case
        when pg_catalog.bool_or(n.delivery_status='failed' and n.result_code='NOT_CONFIGURED') then 'not_configured'
        when pg_catalog.bool_or(n.delivery_status='failed') then 'failed'
        when pg_catalog.bool_or(n.delivery_status in ('pending','processing')) then 'pending'
        when pg_catalog.bool_and(n.delivery_status='sent') then 'delivered'
        else 'unavailable'
      end as channel_status
    from public.notification_outbox n join visible_incidents i on i.id=n.incident_id
    where n.channel in ('sms','whatsapp') group by n.incident_id,n.channel
  )
  select i.id, technician.display_name, technician.role, team.name,
    commander.display_name, commander.role,
    case when i.assigned_technician_id is not null then 'technician'
      when i.assigned_team_id is not null then 'team' else 'unassigned' end,
    coalesce(sms.channel_status,'unavailable'),coalesce(whatsapp.channel_status,'unavailable')
  from visible_incidents i
  left join public.profiles technician on technician.id=i.assigned_technician_id
  left join public.maintenance_teams team on team.id=i.assigned_team_id
  left join public.profiles commander on commander.id=i.incident_commander_id
  left join channel_summary sms on sms.incident_id=i.id and sms.channel='sms'
  left join channel_summary whatsapp on whatsapp.incident_id=i.id and whatsapp.channel='whatsapp'
$fn$;

create or replace function public.get_emergency_roster()
returns table (
  id uuid, profile_id uuid, profile_display_name text, profile_role text,
  team_id uuid, team_name text, receive_emergency_alerts boolean,
  sms_enabled boolean, whatsapp_enabled boolean, email_enabled boolean,
  escalation_order integer, active_from timestamptz, active_to timestamptz,
  incident_type text, active boolean, created_at timestamptz, updated_at timestamptz
)
language sql stable security definer set search_path = public, pg_temp as $fn$
  select r.id,r.profile_id,p.display_name,p.role,r.team_id,t.name,
    r.receive_emergency_alerts,r.sms_enabled,r.whatsapp_enabled,r.email_enabled,
    r.escalation_order,r.active_from,r.active_to,r.incident_type,r.active,r.created_at,r.updated_at
  from public.emergency_response_roster r
  left join public.profiles p on p.id=r.profile_id
  left join public.maintenance_teams t on t.id=r.team_id
  where auth.uid() is not null and public.current_user_role() in ('approver','supervisor','administrator')
  order by r.active desc,r.escalation_order,r.created_at
$fn$;

create or replace function public.get_emergency_response_options()
returns table (target_type text, target_id uuid, display_name text, role text)
language sql stable security definer set search_path = public, pg_temp as $fn$
  select 'technician',p.id,p.display_name,p.role from public.profiles p
  where auth.uid() is not null and public.current_user_role() in ('supervisor','administrator')
    and p.role='technician' and p.is_active and p.deleted_at is null
  union all
  select 'team',t.id,t.name,null from public.maintenance_teams t
  where auth.uid() is not null and public.current_user_role() in ('supervisor','administrator')
    and t.is_active and t.deleted_at is null
$fn$;

create or replace function public.upsert_emergency_roster(p_roster_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare actor_role text:=public.current_user_role(); target_profile uuid; target_team uuid;
  start_at timestamptz; end_at timestamptz; incident_category text; ranking integer; result public.emergency_response_roster;
begin
  if auth.uid() is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if actor_role not in ('supervisor','administrator') then return public.incident_result_error('ACCESS_DENIED','Roster management permission is required.'); end if;
  target_profile:=nullif(p_payload->>'profile_id','')::uuid; target_team:=nullif(p_payload->>'team_id','')::uuid;
  if (target_profile is null)=(target_team is null) then return public.incident_result_error('VALIDATION_ERROR','Select one Technician or maintenance team.'); end if;
  if target_profile is not null and not exists(select 1 from public.profiles where id=target_profile and role='technician' and is_active and deleted_at is null) then return public.incident_result_error('INVALID_ASSIGNMENT','Select an active Technician.'); end if;
  if target_team is not null and not exists(select 1 from public.maintenance_teams where id=target_team and is_active and deleted_at is null) then return public.incident_result_error('INVALID_ASSIGNMENT','Select an active maintenance team.'); end if;
  start_at:=nullif(p_payload->>'active_from','')::timestamptz; end_at:=nullif(p_payload->>'active_to','')::timestamptz;
  if start_at is not null and end_at is not null and end_at<=start_at then return public.incident_result_error('VALIDATION_ERROR','Effective end must be after effective start.'); end if;
  incident_category:=nullif(pg_catalog.lower(p_payload->>'incident_type'),'');
  if incident_category is not null and incident_category not in ('lift_entrapment','fire','flood','major_water_leak','electrical_failure','gas_leak','chemical_spill','medical_emergency','security','other') then return public.incident_result_error('VALIDATION_ERROR','Incident type is invalid.'); end if;
  ranking:=coalesce((p_payload->>'escalation_order')::integer,100); if ranking<0 then return public.incident_result_error('VALIDATION_ERROR','Escalation order must not be negative.'); end if;
  if coalesce((p_payload->>'active')::boolean,true) and exists(select 1 from public.emergency_response_roster r where r.id is distinct from p_roster_id and r.active and r.escalation_order=ranking and r.incident_type is not distinct from incident_category and r.profile_id is not distinct from target_profile and r.team_id is not distinct from target_team and tstzrange(coalesce(r.active_from,'-infinity'),coalesce(r.active_to,'infinity'),'[)') && tstzrange(coalesce(start_at,'-infinity'),coalesce(end_at,'infinity'),'[)')) then return public.incident_result_error('DUPLICATE_ROSTER','An overlapping active roster entry already exists for this target and ranking.'); end if;
  if p_roster_id is null then
    insert into public.emergency_response_roster(profile_id,team_id,receive_emergency_alerts,sms_enabled,whatsapp_enabled,email_enabled,escalation_order,active_from,active_to,incident_type,active,created_by)
    values(target_profile,target_team,coalesce((p_payload->>'receive_emergency_alerts')::boolean,true),coalesce((p_payload->>'sms_enabled')::boolean,true),coalesce((p_payload->>'whatsapp_enabled')::boolean,true),false,ranking,start_at,end_at,incident_category,coalesce((p_payload->>'active')::boolean,true),auth.uid()) returning * into result;
  else
    update public.emergency_response_roster set profile_id=target_profile,team_id=target_team,receive_emergency_alerts=coalesce((p_payload->>'receive_emergency_alerts')::boolean,true),sms_enabled=coalesce((p_payload->>'sms_enabled')::boolean,true),whatsapp_enabled=coalesce((p_payload->>'whatsapp_enabled')::boolean,true),email_enabled=false,escalation_order=ranking,active_from=start_at,active_to=end_at,incident_type=incident_category,active=coalesce((p_payload->>'active')::boolean,true)
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
  if public.current_user_role() not in ('supervisor','administrator') then return public.incident_result_error('ACCESS_DENIED','Roster management permission is required.'); end if;
  update public.emergency_response_roster set active=p_active where id=p_roster_id returning * into result;
  if result.id is null then return public.incident_result_error('NOT_FOUND','Roster entry was not found.'); end if;
  return pg_catalog.jsonb_build_object('ok',true,'roster',pg_catalog.to_jsonb(result));
exception when others then return public.incident_result_error('INTERNAL_ERROR','The roster entry could not be updated.'); end;
$fn$;

revoke all on function public.get_incident_operations(uuid),public.get_emergency_roster(),public.get_emergency_response_options(),public.upsert_emergency_roster(uuid,jsonb),public.set_emergency_roster_active(uuid,boolean) from public,anon,service_role;
grant execute on function public.get_incident_operations(uuid),public.get_emergency_roster(),public.get_emergency_response_options(),public.upsert_emergency_roster(uuid,jsonb),public.set_emergency_roster_active(uuid,boolean) to authenticated;

commit;

\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.assert_true(value boolean,message text)
returns void language plpgsql as $$
begin
  if value is not true then raise exception 'Incident terminal authority regression failed: %',message; end if;
end;
$$;

do $test$
declare
  target_incident_id uuid;
  responder_id uuid;
  reporter_id uuid;
  supervisor_id uuid;
  administrator_id uuid;
  manager_id uuid;
  target_team_id uuid:=pg_catalog.gen_random_uuid();
  team_assignment boolean;
  terminal_action text;
  response_action text;
  before_state jsonb;
  before_audit bigint;
  result jsonb;
begin
  select id into strict responder_id from public.profiles where email='pilot.technician@example.test';
  select id into strict reporter_id from public.profiles where email='pilot.initiator@example.test';
  select id into strict supervisor_id from public.profiles where email='pilot.supervisor@example.test';
  select id into strict administrator_id from public.profiles where email='pilot.admin@example.test';
  insert into public.maintenance_teams(id,name) values(target_team_id,'Incident authority regression team');
  insert into public.maintenance_team_members(team_id,profile_id,is_active) values(target_team_id,responder_id,true);

  foreach team_assignment in array array[false,true] loop
    target_incident_id:=pg_catalog.gen_random_uuid();
    insert into public.incidents(id,incident_number,incident_type,severity,status,location,description,reported_by,assigned_technician_id,assigned_team_id,acknowledgement_deadline)
    values(target_incident_id,'INC-AUTH-'||target_incident_id,'other','medium','reported','Synthetic location','Terminal authority regression',reporter_id,
      case when not team_assignment then responder_id end,case when team_assignment then target_team_id end,pg_catalog.now()+interval '5 minutes');
    perform pg_catalog.set_config('request.jwt.claim.sub',responder_id::text,true);
    perform pg_catalog.set_config('request.jwt.claims',pg_catalog.jsonb_build_object('sub',responder_id,'role','authenticated')::text,true);

    select pg_catalog.to_jsonb(i) into before_state from public.incidents i where i.id=target_incident_id;
    if team_assignment then
      update public.maintenance_team_members set is_active=false where team_id=target_team_id and profile_id=responder_id;
      result:=public.transition_incident(target_incident_id,'acknowledge');
      perform pg_temp.assert_true(result->>'code'='ACCESS_DENIED','inactive team responder denied: '||result::text);
      perform pg_temp.assert_true(before_state=(select pg_catalog.to_jsonb(i) from public.incidents i where i.id=target_incident_id),'inactive-team denial preserves state');
      perform pg_temp.assert_true(not exists(select 1 from public.activity_logs a where a.incident_id=target_incident_id),'inactive-team denial preserves audit');
      update public.maintenance_team_members set is_active=true where team_id=target_team_id and profile_id=responder_id;
    end if;
    if not team_assignment then
      update public.incidents set assigned_technician_id=null where id=target_incident_id;
      select pg_catalog.to_jsonb(i) into before_state from public.incidents i where i.id=target_incident_id;
      result:=public.transition_incident(target_incident_id,'acknowledge');
      perform pg_temp.assert_true(result->>'code'='ACCESS_DENIED','unassigned Incident denies responder');
      perform pg_temp.assert_true(before_state=(select pg_catalog.to_jsonb(i) from public.incidents i where i.id=target_incident_id),'unassigned denial preserves state');
      perform pg_temp.assert_true(not exists(select 1 from public.activity_logs a where a.incident_id=target_incident_id),'unassigned denial preserves audit');
      update public.incidents set assigned_technician_id=responder_id where id=target_incident_id;
    end if;
    foreach response_action in array array['acknowledge','mobilise','arrive','start_rescue','make_safe','start_recovery'] loop
      result:=public.transition_incident(target_incident_id,response_action);
      perform pg_temp.assert_true((result->>'ok')::boolean,'assigned responder retains '||response_action);
    end loop;
    perform pg_temp.assert_true((select count(*)=6 from public.activity_logs a where a.incident_id=target_incident_id and a.user_id=responder_id),'six attributable response audit events');
    select pg_catalog.to_jsonb(i) into before_state from public.incidents i where i.id=target_incident_id;
    select count(*) into before_audit from public.activity_logs a where a.incident_id=target_incident_id;
    foreach terminal_action in array array['close','cancel'] loop
      result:=public.transition_incident(target_incident_id,terminal_action);
      perform pg_temp.assert_true(result->>'code'='ACCESS_DENIED','assigned responder denied '||terminal_action);
      perform pg_temp.assert_true(before_state=(select pg_catalog.to_jsonb(i) from public.incidents i where i.id=target_incident_id),'terminal denial preserves incident');
      perform pg_temp.assert_true(before_audit=(select count(*) from public.activity_logs a where a.incident_id=target_incident_id),'terminal denial preserves audit');
    end loop;
    result:=public.transition_incident(target_incident_id,'unrecognized');
    perform pg_temp.assert_true(result->>'code'='INVALID_TRANSITION','unknown action denied');
    perform pg_catalog.set_config('request.jwt.claim.sub',case when team_assignment then administrator_id else supervisor_id end::text,true);
    perform pg_catalog.set_config('request.jwt.claims',pg_catalog.jsonb_build_object('sub',case when team_assignment then administrator_id else supervisor_id end,'role','authenticated')::text,true);
    terminal_action:=case when team_assignment then 'cancel' else 'close' end;
    result:=public.transition_incident(target_incident_id,terminal_action);
    perform pg_temp.assert_true((result->>'ok')::boolean,'management terminal action succeeds');
    perform pg_temp.assert_true((select count(*)=1 from public.activity_logs a where a.incident_id=target_incident_id and a.action='incident_'||terminal_action and a.user_id=case when team_assignment then administrator_id else supervisor_id end),'management terminal audit attributable');
  end loop;
  foreach manager_id in array array[supervisor_id,administrator_id] loop
    foreach terminal_action in array array['close','cancel'] loop
      target_incident_id:=pg_catalog.gen_random_uuid();
      insert into public.incidents(id,incident_number,incident_type,severity,status,location,description,reported_by,acknowledgement_deadline)
      values(target_incident_id,'INC-MGMT-'||target_incident_id,'other','medium','recovery','Synthetic location','Management terminal matrix',reporter_id,pg_catalog.now()+interval '5 minutes');
      perform pg_catalog.set_config('request.jwt.claim.sub',manager_id::text,true);
      perform pg_catalog.set_config('request.jwt.claims',pg_catalog.jsonb_build_object('sub',manager_id,'role','authenticated')::text,true);
      result:=public.transition_incident(target_incident_id,terminal_action);
      perform pg_temp.assert_true((result->>'ok')::boolean,'both management roles retain both terminal actions');
      perform pg_temp.assert_true((select count(*)=1 from public.activity_logs a where a.incident_id=target_incident_id and a.user_id=manager_id and a.action='incident_'||terminal_action),'each management terminal action audited');
    end loop;
  end loop;
end;
$test$;
select pg_temp.assert_true(not has_function_privilege('anon','public.transition_incident(uuid,text)','EXECUTE'),'anonymous transition denied');
select pg_temp.assert_true(not has_function_privilege('service_role','public.transition_incident(uuid,text)','EXECUTE'),'service-role transition denied');
select pg_temp.assert_true(has_function_privilege('authenticated','public.transition_incident(uuid,text)','EXECUTE'),'authenticated RPC available');
rollback;

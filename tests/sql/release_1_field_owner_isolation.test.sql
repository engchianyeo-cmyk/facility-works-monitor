\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_true(value boolean, message text)
returns void language plpgsql as $$
begin
  if value is not true then
    raise exception 'Release-1 field-owner isolation regression failed: %', message;
  end if;
end;
$$;

do $test$
declare
  order_id uuid;
  facility_id uuid;
  technician_id uuid;
  supervisor_id uuid;
  facility_manager_id uuid;
  administrator_id uuid;
  actors uuid[];
  owners uuid[];
  actor_id uuid;
  owner_id uuid;
  before_order jsonb;
  after_order jsonb;
  before_activity jsonb;
  after_activity jsonb;
  before_evidence jsonb;
  after_evidence jsonb;
  completion_result jsonb;
  evidence_result jsonb;
  index integer;
begin
  select id into strict technician_id from public.profiles where email='pilot.technician@example.test';
  select id into strict supervisor_id from public.profiles where email='pilot.supervisor@example.test';
  select id into strict facility_manager_id from public.profiles where email='pilot.facility-manager@example.test';
  select id into strict administrator_id from public.profiles where email='pilot.admin@example.test';
  select id,facility_id into strict order_id,facility_id
  from public.work_orders where work_order_number='WO-TEST-003';

  insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
  values
    (facility_id,technician_id,'technician',administrator_id),
    (facility_id,supervisor_id,'supervisor',administrator_id),
    (facility_id,facility_manager_id,'facility_manager',administrator_id)
  on conflict do nothing;

  actors:=array[technician_id,supervisor_id,facility_manager_id,administrator_id];
  owners:=array[supervisor_id,facility_manager_id,administrator_id,technician_id];

  for index in 1..array_length(actors,1) loop
    actor_id:=actors[index];
    owner_id:=owners[index];
    update public.work_orders
    set assigned_technician_id=owner_id,status='in_progress',completed_at=null,updated_at=updated_at
    where id=order_id;

    select pg_catalog.to_jsonb(w) into before_order from public.work_orders w where id=order_id;
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) order by a.id),'[]'::jsonb)
      into before_activity from public.activity_logs a where a.work_order_id=order_id;
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(e) order by e.id),'[]'::jsonb)
      into before_evidence from public.evidence_items e where e.work_order_id=order_id;

    perform pg_catalog.set_config('request.jwt.claim.sub',actor_id::text,true);
    perform pg_catalog.set_config('request.jwt.claims',pg_catalog.jsonb_build_object('sub',actor_id,'role','authenticated')::text,true);
    completion_result:=public.submit_physical_completion(order_id,pg_catalog.jsonb_build_object(
      'completion_notes','Unauthorized completion attempt','actual_labour_hours',1
    ));
    evidence_result:=public.register_evidence_item(
      'work_order',order_id,'unauthorized.jpg','image/jpeg',10,'after','Unauthorized evidence attempt',
      'evidence/work-order/'||order_id::text||'/'||pg_catalog.gen_random_uuid()::text||'/unauthorized.jpg'
    );

    perform pg_temp.assert_true(
      completion_result->>'code'='ACCESS_DENIED',
      (select role from public.profiles where id=actor_id)||' submitted completion for another field owner'
    );
    perform pg_temp.assert_true(
      evidence_result->>'code'='EVIDENCE_READ_ONLY',
      (select role from public.profiles where id=actor_id)||' registered evidence for another field owner'
    );

    select pg_catalog.to_jsonb(w) into after_order from public.work_orders w where id=order_id;
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) order by a.id),'[]'::jsonb)
      into after_activity from public.activity_logs a where a.work_order_id=order_id;
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(e) order by e.id),'[]'::jsonb)
      into after_evidence from public.evidence_items e where e.work_order_id=order_id;
    perform pg_temp.assert_true(
      before_order=after_order and before_activity=after_activity and before_evidence=after_evidence,
      (select role from public.profiles where id=actor_id)||' denial mutated the Work Order or its audit/evidence records'
    );
  end loop;
end;
$test$;

rollback;

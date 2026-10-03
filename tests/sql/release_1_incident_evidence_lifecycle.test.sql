\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_true(value boolean, message text)
returns void language plpgsql as $$
begin
  if value is not true then raise exception 'Release-1 Incident evidence regression failed: %', message; end if;
end;
$$;

do $test$
declare
  incident_id uuid:=pg_catalog.gen_random_uuid();
  reporter_id uuid;
  reviewer_id uuid;
  supervisor_id uuid;
  evidence_id uuid;
  terminal_evidence_id uuid:=pg_catalog.gen_random_uuid();
  storage_path text;
  result jsonb;
  before_evidence jsonb;
  before_audit bigint;
begin
  select id into strict reporter_id from public.profiles where email='pilot.initiator@example.test';
  select id into strict reviewer_id from public.profiles where email='pilot.reviewer@example.test';
  select id into strict supervisor_id from public.profiles where email='pilot.supervisor@example.test';

  insert into public.incidents(id,incident_number,incident_type,severity,status,location,description,reported_by,acknowledgement_deadline)
  values(incident_id,'INC-EVIDENCE-TEST','other','medium','reported','Synthetic test location','Incident evidence lifecycle regression',reporter_id,pg_catalog.now()+interval '5 minutes');

  perform pg_catalog.set_config('request.jwt.claim.sub',reviewer_id::text,true);
  perform pg_catalog.set_config('request.jwt.claims',pg_catalog.jsonb_build_object('sub',reviewer_id,'role','authenticated')::text,true);
  result:=public.register_evidence_item('incident',incident_id,'denied.jpg','image/jpeg',10,'before','Denied','evidence/incident/'||incident_id||'/denied/denied.jpg');
  perform pg_temp.assert_true(result->>'code'='EVIDENCE_READ_ONLY','unrelated Reviewer cannot create Incident evidence');

  storage_path:='evidence/incident/'||incident_id||'/'||pg_catalog.gen_random_uuid()||'/before.jpg';
  insert into storage.objects(bucket_id,name) values('field-evidence',storage_path);
  perform pg_catalog.set_config('request.jwt.claim.sub',reporter_id::text,true);
  perform pg_catalog.set_config('request.jwt.claims',pg_catalog.jsonb_build_object('sub',reporter_id,'role','authenticated')::text,true);
  result:=public.register_evidence_item('incident',incident_id,'before.jpg','image/jpeg',10,'before','Reporter evidence',storage_path);
  perform pg_temp.assert_true((result->>'ok')::boolean,'authorized reporter can create active Incident evidence');
  evidence_id:=(result->'evidence'->>'id')::uuid;

  select pg_catalog.to_jsonb(e) into before_evidence from public.evidence_items e where e.id=evidence_id;
  select pg_catalog.count(*) into before_audit from public.activity_logs where incident_id=incident_id;
  perform pg_catalog.set_config('request.jwt.claim.sub',reviewer_id::text,true);
  result:=public.void_incident_evidence(evidence_id,'Unauthorized removal');
  perform pg_temp.assert_true(result->>'code'='ACCESS_DENIED','unrelated Reviewer cannot remove Incident evidence');
  perform pg_temp.assert_true(before_evidence=(select pg_catalog.to_jsonb(e) from public.evidence_items e where e.id=evidence_id),'denied removal does not mutate evidence');
  perform pg_temp.assert_true(before_audit=(select pg_catalog.count(*) from public.activity_logs where incident_id=incident_id),'denied removal does not write audit');

  perform pg_catalog.set_config('request.jwt.claim.sub',supervisor_id::text,true);
  perform pg_catalog.set_config('request.jwt.claims',pg_catalog.jsonb_build_object('sub',supervisor_id,'role','authenticated')::text,true);
  result:=public.void_incident_evidence(evidence_id,'Duplicate response photograph');
  perform pg_temp.assert_true((result->>'ok')::boolean,'authorized Supervisor can remove active Incident evidence');
  perform pg_temp.assert_true((select deleted_at is not null and deleted_by=supervisor_id and deletion_reason='Duplicate response photograph' from public.evidence_items where id=evidence_id),'removal retains attributable soft-delete metadata');
  perform pg_temp.assert_true((select count(*)=1 from public.activity_logs where incident_id=incident_id and action='incident_evidence_voided' and user_id=supervisor_id),'removal writes one attributable audit event');

  insert into public.evidence_items(id,parent_type,incident_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
  values(terminal_evidence_id,'incident',incident_id,reporter_id,'terminal.jpg','image/jpeg',10,'after','evidence/incident/'||incident_id||'/terminal/terminal.jpg');
  update public.incidents set status='closed',closed_at=pg_catalog.now() where id=incident_id;
  result:=public.void_incident_evidence(terminal_evidence_id,'Late removal');
  perform pg_temp.assert_true(result->>'code'='ACCESS_DENIED','closed Incident evidence cannot be removed');
  result:=public.register_evidence_item('incident',incident_id,'late.jpg','image/jpeg',10,'after','Late upload','evidence/incident/'||incident_id||'/late/late.jpg');
  perform pg_temp.assert_true(result->>'code'='EVIDENCE_READ_ONLY','closed Incident evidence cannot be added');
end;
$test$;

select pg_temp.assert_true(not has_function_privilege('anon','public.void_incident_evidence(uuid,text)','EXECUTE'),'anonymous Incident evidence removal is denied');
select pg_temp.assert_true(not has_function_privilege('service_role','public.void_incident_evidence(uuid,text)','EXECUTE'),'service role cannot bypass audited Incident evidence removal');
rollback;

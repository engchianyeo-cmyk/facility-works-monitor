\set ON_ERROR_STOP on
-- WP-LC2-M8 (D-14): 'Other supporting document' evidence category; it does not count as Before or After.
-- Self-contained synthetic identities and data; everything rolls back.
begin;
-- D-08 (M6): location markup and Before evidence, registered as postgres for rollback-only tests.
create function pg_temp.site(wo uuid) returns void language plpgsql security definer as $site$
declare who uuid;
begin
  select coalesce(assigned_technician_id,requested_by) into who from public.work_orders where id=wo;
  insert into public.work_order_markups(work_order_id,source_type,source_reference,drawing_revision,x_percent,y_percent,annotation_type,geometry,note,created_by)
  values(wo,'drawing','FW-001','A (25 May 2024)',23.1,37.4,'marker','{"points":[{"x":23.1,"y":37.4}]}','Work location',who);
  insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
  values('work_order',wo,who,'before.jpg','image/jpeg',100,'before','evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/before.jpg');
end;$site$;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Lifecycle v2 supporting document regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1c900000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 tech A, 2 tech B, 3 approver, 4 supervisor, 5 facility manager, 6 administrator,
-- 7 finance, 8 initiator, 9 reviewer, 10 non-member approver, 11 copied party (reviewer)
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'lc2m8.'||n||'@example.test',jsonb_build_object('display_name','LC2 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11),('finance',12)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11),('finance',12)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.sites(id,code,name,is_active) values ('1c900000-0000-4000-8000-0000000000f2','LC8-OTHER','LC2 Other Facility',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(6) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3),pg_temp.u(4),pg_temp.u(5));
insert into public.vendors(id,name,trade,active) values ('1c900000-0000-4000-8000-0000000000e1','LC2 Contractor','Mechanical',true);
insert into public.vendor_facility_eligibility(vendor_id,facility_id,procurement_prequalified,facility_confirmed,confirmation_basis,active)
values ('1c900000-0000-4000-8000-0000000000e1',(select facility_id from f),true,true,'LC2 rollback-only test',true);
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert, update on ids to authenticated;

-- Quotation helper: preparer prepares a S$650 draft; the document is registered as postgres; the preparer submits it.
create function pg_temp.quote(wo uuid, preparer uuid, amount numeric) returns uuid language plpgsql as $$
declare r jsonb; qid uuid;
begin
  perform pg_temp.act(preparer); set local role authenticated;
  r:=public.prepare_work_order_proposal(wo,jsonb_build_object('vendor_id','1c900000-0000-4000-8000-0000000000e1','proposed_amount',amount,'scope_summary','LC2 repair scope'));
  perform pg_temp.assert_true((r->>'ok')::boolean,'preparer prepares Draft quotation: '||coalesce(r->>'code',''));
  qid:=(r->'quotation'->>'id')::uuid;
  reset role;
  insert into public.work_order_commercial_documents(work_order_id,document_type,quotation_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
  values(wo,'quotation',qid,preparer,'quote.pdf','application/pdf',100,'commercial/work-order/'||wo::text||'/'||qid::text||'.pdf');
  set local role authenticated;
  r:=public.submit_work_order_proposal(wo,qid,'Authentic contractor quotation');
  perform pg_temp.assert_true((r->>'ok')::boolean,'preparer submits quotation: '||coalesce(r->>'code',''));
  reset role;
  return qid;
end;$$;
-- Other-facility Supervisor (13) for the facility-scope gap regression.
insert into auth.users(id,email,raw_user_meta_data) values (pg_temp.u(13),'lc2m8.13@example.test','{"display_name":"LC2 other supervisor"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='supervisor',is_active=true,password_change_required=false where id=pg_temp.u(13);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values ('1c900000-0000-4000-8000-0000000000f2',pg_temp.u(13),'supervisor',pg_temp.u(6));


do $test$
declare r jsonb; wo uuid; path text; path2 text;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(1));
  r:=public.create_work_order(jsonb_build_object('title','Panel inspection','location','Plant room','facility_id',(select facility_id from f),
    'description','Inspect the panel and file the inspection checklist.'));
  wo:=(r->'work_order'->>'id')::uuid;
  reset role;
  path:='evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/checklist.pdf';
  path2:='evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/misc.pdf';
  insert into storage.objects(bucket_id,name) values('field-evidence',path),('field-evidence',path2);
  set local role authenticated;
  r:=public.register_evidence_item('work_order',wo,'checklist.pdf','application/pdf',10,'document','Inspection checklist',path);
  perform pg_temp.assert_true((r->>'ok')::boolean and r->'evidence'->>'category'='document','assigned Technician files an Other supporting document: '||coalesce(r->>'code',''));
  r:=public.register_evidence_item('work_order',wo,'misc.pdf','application/pdf',10,'other','Misc',path2);
  perform pg_temp.assert_true(r->>'code'='INVALID_STORAGE_OBJECT','categories other than Before, After and Other supporting document are refused');
  perform pg_temp.assert_true(public.work_order_approval_summary(wo)->'missing_requirements' @> '["Before photo, video or voice note of the site"]','a supporting document does not count as Before evidence');
  reset role;
end;$test$;
-- D-15: a Draft whose due date has passed is listed and refused with a clear reason.
do $test$
declare r jsonb; wo uuid;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(1));
  r:=public.create_work_order(jsonb_build_object('title','Overdue Draft','location','Plant room','facility_id',(select facility_id from f),
    'description','Legacy Work Order converted with an old due date.'));
  wo:=(r->'work_order'->>'id')::uuid;
  reset role;
  update public.work_orders set created_at=now()-interval '60 days', due_date=(now()-interval '30 days')::date where id=wo;
  set local role authenticated;
  perform pg_temp.assert_true(public.work_order_approval_summary(wo)->'missing_requirements' @> '["Due date has passed — update the due date"]','readiness lists the passed due date');
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit','{}')->>'code'='DUE_DATE_PASSED','submission refused with DUE_DATE_PASSED, not a database error');
  reset role;
end;$test$;
rollback;

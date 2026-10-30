\set ON_ERROR_STOP on
-- WP-LC2-M5: in-house Work Orders (D-07) — same approvals, no pricing, automatic closure.
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
begin if value is not true then raise exception 'Lifecycle v2 in-house regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1c600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 tech A, 2 tech B, 3 approver, 4 supervisor, 5 facility manager, 6 administrator,
-- 7 finance, 8 initiator, 9 reviewer, 10 non-member approver, 11 copied party (reviewer)
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'lc2m5.'||n||'@example.test',jsonb_build_object('display_name','LC2 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11),('finance',12)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11),('finance',12)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.sites(id,code,name,is_active) values ('1c600000-0000-4000-8000-0000000000f2','LC5-OTHER','LC2 Other Facility',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(6) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3),pg_temp.u(4),pg_temp.u(5));
insert into public.vendors(id,name,trade,active) values ('1c600000-0000-4000-8000-0000000000e1','LC2 Contractor','Mechanical',true);
insert into public.vendor_facility_eligibility(vendor_id,facility_id,procurement_prequalified,facility_confirmed,confirmation_basis,active)
values ('1c600000-0000-4000-8000-0000000000e1',(select facility_id from f),true,true,'LC2 rollback-only test',true);
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert, update on ids to authenticated;

-- Quotation helper: preparer prepares a S$650 draft; the document is registered as postgres; the preparer submits it.
create function pg_temp.quote(wo uuid, preparer uuid, amount numeric) returns uuid language plpgsql as $$
declare r jsonb; qid uuid;
begin
  perform pg_temp.act(preparer); set local role authenticated;
  r:=public.prepare_work_order_proposal(wo,jsonb_build_object('vendor_id','1c600000-0000-4000-8000-0000000000e1','proposed_amount',amount,'scope_summary','LC2 repair scope'));
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
insert into auth.users(id,email,raw_user_meta_data) values (pg_temp.u(13),'lc2m5.13@example.test','{"display_name":"LC2 other supervisor"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='supervisor',is_active=true,password_change_required=false where id=pg_temp.u(13);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values ('1c600000-0000-4000-8000-0000000000f2',pg_temp.u(13),'supervisor',pg_temp.u(6));

-- Drive a Work Order from approval to "submitted for review" as its Technician.
create function pg_temp.execute(wo uuid, tech uuid, cost numeric) returns void language plpgsql as $$
declare r jsonb; path text;
begin
  perform pg_temp.act(tech); set local role authenticated;
  if (select status from public.work_orders where id=wo)='assigned' then
    r:=public.transition_work_order(wo,'start'); perform pg_temp.assert_true((r->>'ok')::boolean,'start: '||coalesce(r->>'code',''));
  end if;
  r:=public.record_work_order_execution(wo,'{"completion_notes":"Replaced bearing and realigned coupling.","actual_labour_hours":3}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'record work: '||coalesce(r->>'code',''));
  r:=public.manage_work_order_actual_cost(wo,null,jsonb_build_object('cost_type','service','description','Contractor repair','unit','job','quantity',1,'unit_rate',cost));
  perform pg_temp.assert_true((r->>'ok')::boolean,'actual cost line: '||coalesce(r->>'code',''));
  r:=public.manage_work_order_actual_cost(wo,null,'{"operation":"confirm"}');
  perform pg_temp.assert_true((r->>'ok')::boolean,'confirm costing: '||coalesce(r->>'code',''));
  reset role;
  path:='evidence/work-order/'||wo::text||'/'||gen_random_uuid()::text||'/after.jpg';
  insert into storage.objects(bucket_id,name) values('field-evidence',path);
  set local role authenticated;
  r:=public.register_evidence_item('work_order',wo,'after.jpg','image/jpeg',10,'after','After repair',path);
  perform pg_temp.assert_true((r->>'ok')::boolean,'After evidence: '||coalesce(r->>'code',''));
  -- D-11: the Technician enters the actual work times.
  r:=public.set_work_order_actual_times(wo,pg_catalog.now()-interval '3 hours',pg_catalog.now()-interval '1 hour');
  perform pg_temp.assert_true((r->>'ok')::boolean,'actual work times: '||coalesce(r->>'code',''));
  r:=public.submit_physical_completion(wo,'{"completion_notes":"Replaced bearing and realigned coupling.","actual_labour_hours":3}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='completed','submit for review: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
  -- D-11: a second Technician endorses the work as authentic before the review.
  perform pg_temp.act(pg_temp.u(2)); set local role authenticated;
  r:=public.endorse_work_order(wo,'Checked on site: work done as recorded.','{"supervised_work":true,"final_quotation":true,"field_evidence":true,"site_evidence":true,"quotation_scope":true,"award_basis":true,"award_basis_note":"Lowest compliant quotation from an eligible contractor"}'::jsonb);
  perform pg_temp.assert_true((r->>'ok')::boolean and r->'endorsement' is not null,'second Technician endorses: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  reset role;
end;$$;

create function pg_temp.final_cost(wo uuid, tech uuid, amount numeric) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform pg_temp.act(tech); set local role authenticated;
  r:=public.save_work_order_final_cost(wo,jsonb_build_object('final_contractor_amount',amount,'comments','Final contractor account',
    'variation_order',amount is distinct from (select coalesce(c.approved_budget,c.quoted_cost) from public.work_order_financial_controls c where c.work_order_id=wo),
    'variation_justification','Contractor revised the final account'));
  reset role; return r;
end;$$;

do $t$ declare r jsonb; wo uuid; em uuid; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.create_work_order(jsonb_build_object('title','Repaint plant room door','location','Plant room','facility_id',(select facility_id from f),
    'description','Door corroded; repaint by in-house team.','in_house_work',true));
  wo:=(r->'work_order'->>'id')::uuid; insert into ids values('wo',wo); perform pg_temp.site(wo);
  perform pg_temp.assert_true((r->'work_order'->>'in_house_work')::boolean,'in-house declared at creation');
  perform pg_temp.assert_true(public.prepare_work_order_proposal(wo,'{"vendor_id":"1c600000-0000-4000-8000-0000000000e1","proposed_amount":1,"scope_summary":"x"}')->>'code'='IN_HOUSE_NO_PRICING','no quotation for in-house work');
  perform pg_temp.assert_true((public.work_order_approval_summary(wo)->>'ready')::boolean,'in-house Draft is ready without quotation');
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->'work_order'->>'status'='submitted','in-house submitted without quotation');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.transition_work_order(wo,'approve')->>'code'='ACCESS_DENIED','Technician cannot approve');
  perform pg_temp.act(pg_temp.u(10));
  perform pg_temp.assert_true(public.transition_work_order(wo,'approve')->>'code'='ACCESS_DENIED','non-member Approver cannot approve in-house work');
  perform pg_temp.act(pg_temp.u(3));
  r:=public.transition_work_order(wo,'approve','{"note":"In-house team available"}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='assigned' and (r->>'approved_amount')::numeric=0,'Approver approves in-house work at S$0');
  -- Toggle only while Draft.
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(public.set_work_order_in_house(wo,false)->>'code'='INVALID_TRANSITION','cannot change after Draft');
  r:=public.create_work_order(jsonb_build_object('title','Toggle test','location','X','facility_id',(select facility_id from f)));
  perform pg_temp.assert_true((public.set_work_order_in_house((r->'work_order'->>'id')::uuid,true)->'work_order'->>'in_house_work')::boolean,'preparer declares in-house in Draft');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.set_work_order_in_house((r->'work_order'->>'id')::uuid,false)->>'code'='ACCESS_DENIED','other Technician cannot change it');
  -- Emergency in-house: starts immediately; no quotation afterwards.
  perform pg_temp.act(pg_temp.u(1));
  r:=public.create_work_order(jsonb_build_object('title','Clear blocked drain','location','Car park','facility_id',(select facility_id from f),'emergency_work',true,'in_house_work',true,'description','Flooding car park entrance; clear drain now.'));
  em:=(r->'work_order'->>'id')::uuid; insert into ids values('em',em); perform pg_temp.site(em);
  perform pg_temp.assert_true(public.transition_work_order(em,'submit')->'work_order'->>'status'='in_progress','emergency in-house starts immediately');
  reset role;
end;$t$;
select pg_temp.execute((select id from ids where name='wo'),pg_temp.u(1),0);
select pg_temp.execute((select id from ids where name='em'),pg_temp.u(1),0);
do $t$ declare r jsonb; begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(4));
  r:=public.verify_completed_work((select id from ids where name='wo'),'{"note":"Door repainted; photos verified."}');
  perform pg_temp.assert_true(r->'work_order'->>'status'='reviewed' and (r->>'work_order_closed')::boolean,'in-house review needs no final cost and closes automatically: '||coalesce(r->>'code','')||' '||coalesce(r->>'message',''));
  r:=public.verify_completed_work((select id from ids where name='em'),'{"note":"Drain cleared."}');
  perform pg_temp.assert_true((r->>'work_order_closed')::boolean,'emergency in-house closes without quotation');
  reset role;
  perform pg_temp.assert_true((select status='closed' from public.work_orders where id=(select id from ids where name='wo')),'in-house Work Order Closed');
  perform pg_temp.assert_true((select reason_code='in_house' and status='approved' and approved_by=pg_temp.u(4) from public.work_order_financial_dispositions where work_order_id=(select id from ids where name='wo')),'audited in-house no-payment disposition');
  perform pg_temp.assert_true(not exists(select 1 from public.contractor_payment_assessments where work_order_id in (select id from ids)),'no payable for in-house work');
end;$t$;
rollback;

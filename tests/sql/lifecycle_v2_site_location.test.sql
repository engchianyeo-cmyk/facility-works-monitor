\set ON_ERROR_STOP on
-- WP-LC2-M6 (D-08): location marked on the layout plan, Before evidence before submission,
-- and the contractor's final quotation when the final cost differs. Everything rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Lifecycle v2 site/location regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1c700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.before(wo uuid) returns void language plpgsql security definer as $b$
begin
  insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
  select 'work_order',w.id,w.assigned_technician_id,'before.jpg','image/jpeg',100,'before','evidence/work-order/'||w.id::text||'/'||gen_random_uuid()::text||'/before.jpg'
  from public.work_orders w where w.id=wo;
end;$b$;
create function pg_temp.pin() returns jsonb language sql immutable as $$
  select '{"source_type":"drawing","source_reference":"FW-001","drawing_revision":"A (25 May 2024)","annotation_type":"marker","note":"Pump P-02","geometry":{"points":[{"x":23.1,"y":37.4}]}}'::jsonb $$;

-- 1 tech A, 2 tech B, 3 approver, 4 supervisor
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'lc2m6.'||n||'@example.test',jsonb_build_object('display_name','LC2M6 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(4) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3),pg_temp.u(4));
-- Areas: one already placed on the layout plan, one unplaced, one at another facility.
insert into public.facility_areas(id,area_code,name,facility_id,drawing_reference,map_x,map_y,active) values
 ('1c700000-0000-4000-8000-0000000000a1','LC6-ELR','LC6 Electrical Room',(select facility_id from f),'FW-001',41.5,62.0,true),
 ('1c700000-0000-4000-8000-0000000000a2','LC6-UNP','LC6 Unplaced Store',(select facility_id from f),null,null,null,true);
insert into public.sites(id,code,name,is_active) values ('1c700000-0000-4000-8000-0000000000f2','LC6-OTHER','LC6 Other Facility',true);
insert into public.facility_areas(id,area_code,name,facility_id,active) values ('1c700000-0000-4000-8000-0000000000a3','LC6-OTH','LC6 Other Area','1c700000-0000-4000-8000-0000000000f2',true);
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert, update on ids to authenticated;

do $test$
declare r jsonb; wo uuid; s jsonb; mk uuid;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(1));
  r:=public.create_work_order(jsonb_build_object('title','Pump vibration','location','Plant room','facility_id',(select facility_id from f),'description','Pump P-02 vibration rising for two weeks.'));
  wo:=(r->'work_order'->>'id')::uuid; insert into ids values('wo',wo);
  s:=public.work_order_approval_summary(wo);
  perform pg_temp.assert_true(s->'missing_requirements' @> '["Location marked on the layout plan","Before photo, video or voice note of the site"]','summary lists location and Before evidence');
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='LOCATION_MARKUP_REQUIRED','submission needs the layout location');

  -- Only the preparer marks the layout while Draft.
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.record_work_order_markup(wo,pg_temp.pin())->>'code'='ACCESS_DENIED','other Technician cannot mark the Draft');
  perform pg_temp.act(pg_temp.u(3));
  perform pg_temp.assert_true(public.record_work_order_markup(wo,pg_temp.pin())->>'code'='ACCESS_DENIED','Approver who is not the preparer cannot mark the Draft');
  perform pg_temp.act(pg_temp.u(1));
  r:=public.record_work_order_markup(wo,pg_temp.pin());
  perform pg_temp.assert_true((r->>'ok')::boolean,'preparer marks the layout in Draft: '||coalesce(r->>'code',''));
  mk:=(r->'markup'->>'id')::uuid;
  perform pg_temp.assert_true((public.delete_work_order_markup(wo,mk)->>'ok')::boolean,'preparer may remove own Draft markup');
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='LOCATION_MARKUP_REQUIRED','removed markup no longer counts');
  perform pg_temp.assert_true((public.record_work_order_markup(wo,pg_temp.pin())->>'ok')::boolean,'preparer marks again');
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='BEFORE_EVIDENCE_REQUIRED','submission needs Before evidence');
  reset role;
  perform pg_temp.before(wo);
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(1));
  s:=public.work_order_approval_summary(wo);
  perform pg_temp.assert_true(not (s->'missing_requirements' @> '["Location marked on the layout plan"]') and not (s->'missing_requirements' @> '["Before photo, video or voice note of the site"]'),'site requirements satisfied');
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->>'code'='QUOTATION_REQUIRED','site checks pass; quotation rule still applies');

  -- Choosing an area already placed on the layout plan highlights it automatically.
  r:=public.create_work_order(jsonb_build_object('title','Switchboard trip','location','Electrical Room','facility_id',(select facility_id from f),'facility_area_id','1c700000-0000-4000-8000-0000000000a1','description','Main switchboard breaker tripping intermittently.'));
  perform pg_temp.assert_true(not (public.work_order_approval_summary((r->'work_order'->>'id')::uuid)->'missing_requirements' @> '["Location marked on the layout plan"]'),'placed area counts as marked');
  r:=public.create_work_order(jsonb_build_object('title','Store shelf','location','Store','facility_id',(select facility_id from f),'facility_area_id','1c700000-0000-4000-8000-0000000000a2','description','Shelf bracket broken in store room.'));
  perform pg_temp.assert_true(public.work_order_approval_summary((r->'work_order'->>'id')::uuid)->'missing_requirements' @> '["Location marked on the layout plan"]','unplaced area still needs a mark on the plan');
  perform pg_temp.assert_true(public.create_work_order(jsonb_build_object('title','Wrong area','location','X','facility_id',(select facility_id from f),'facility_area_id','1c700000-0000-4000-8000-0000000000a3'))->>'code'='VALIDATION_ERROR','area must belong to the facility');

  -- Emergency: starts without markup or Before evidence; the location is required before the review.
  r:=public.create_work_order(jsonb_build_object('title','Burst pipe','location','Level 3','facility_id',(select facility_id from f),'emergency_work',true,'description','Burst pipe flooding corridor; repair now.'));
  wo:=(r->'work_order'->>'id')::uuid; insert into ids values('em',wo);
  perform pg_temp.assert_true(public.transition_work_order(wo,'submit')->'work_order'->>'status'='in_progress','emergency starts without layout markup or Before evidence');
  reset role;
end;$test$;

-- Simulate the emergency awaiting review (status only) to check the pre-review rules.
update public.work_orders set status='completed',completed_at=now() where id=(select id from ids where name='em');
do $test$
declare wo uuid:=(select id from ids where name='em');
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.work_order_verification_readiness(wo)->'missing_requirements' @> '["Location marked on the layout plan","Before photo, video or voice note of the site"]','emergency review needs the layout location and Before evidence');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true((public.record_work_order_markup(wo,pg_temp.pin())->>'ok')::boolean,'assigned Technician marks the layout before the review');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(not (public.work_order_verification_readiness(wo)->'missing_requirements' @> '["Location marked on the layout plan"]'),'emergency location satisfied');
  reset role;
  perform pg_temp.before(wo);
  set local role authenticated;
  perform pg_temp.assert_true(not (public.work_order_verification_readiness(wo)->'missing_requirements' @> '["Before photo, video or voice note of the site"]'),'emergency Before evidence satisfied');
  reset role;
end;$test$;
rollback;

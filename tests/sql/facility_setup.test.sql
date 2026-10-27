\set ON_ERROR_STOP on
-- WP-FAC-01 (D-17): Administrator facility setup — facilities, areas, staff, drawings.
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
begin if value is not true then raise exception 'Facility setup regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1ca00000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 tech A, 2 tech B, 3 approver, 4 supervisor, 5 facility manager, 6 administrator,
-- 7 finance, 8 initiator, 9 reviewer, 10 non-member approver, 11 copied party (reviewer)
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'fac01.'||n||'@example.test',jsonb_build_object('display_name','LC2 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('supervisor',4),('facility_manager',5),('administrator',6),('finance',7),('initiator',8),('reviewer',9),('approver',10),('reviewer',11)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);


do $test$
declare r jsonb; fac uuid; fac2 uuid; path text; did uuid; wo uuid;
begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(5));
  perform pg_temp.assert_true(public.admin_save_facility(null,'NEW-01','New Plant','1 Test Road',true,true,'New site')->>'code'='ACCESS_DENIED','Facility Manager cannot add facilities');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(public.admin_save_facility(null,'x','New Plant',null,true,true,'New site')->>'code'='VALIDATION_ERROR','facility code validated');
  r:=public.admin_save_facility(null,'new-01','New Plant','1 Test Road, Singapore 600001',true,true,'Test launch facility');
  perform pg_temp.assert_true((r->>'ok')::boolean and (r->>'standard_areas_added')::int=25,'Administrator adds a facility with the 25 standard areas: '||coalesce(r->>'code',''));
  fac:=(r->'facility'->>'id')::uuid;
  perform pg_temp.assert_true(r->'facility'->>'code'='NEW-01','code stored in capitals');
  perform pg_temp.assert_true(public.admin_save_facility(null,'NEW-01','Again',null,true,false,'dup')->>'code'='VALIDATION_ERROR','facility code is unique');
  r:=public.admin_save_facility(null,'NEW-02','Second Plant',null,true,true,'Second site'); fac2:=(r->'facility'->>'id')::uuid;
  perform pg_temp.assert_true((select count(*) from public.facility_areas where area_code='ELR-01' and facility_id in (fac,fac2))=2,'the same area code is allowed at different facilities');
  perform pg_temp.assert_true((public.admin_add_facility_area(fac,'elr-02','Electrical Room 2','Level 2')->>'ok')::boolean,'Administrator adds an area');
  perform pg_temp.assert_true(public.admin_add_facility_area(fac,'ELR-02','Duplicate',null)->>'code'='VALIDATION_ERROR','area code unique per facility');
  r:=public.admin_save_facility(fac,'NEW-01','New Plant (renamed)','2 Test Road',true,false,'Renamed');
  perform pg_temp.assert_true(r->'facility'->>'name'='New Plant (renamed)','facility renamed');

  -- staff
  perform pg_temp.assert_true((public.admin_set_facility_membership(fac,pg_temp.u(1),true,'Joins the new plant')->>'ok')::boolean,'Technician added to the facility');
  perform pg_temp.assert_true(public.admin_set_facility_membership(fac,pg_temp.u(1),true,'Again')->>'code'='NO_CHANGE','adding twice is NO_CHANGE');
  perform pg_temp.assert_true(public.admin_set_facility_membership(fac,pg_temp.u(7),true,'Finance')->>'code'='VALIDATION_ERROR','Finance is not a facility member');
  perform pg_temp.assert_true(exists(select 1 from public.admin_facility_staff(fac) s where s.profile_id=pg_temp.u(1) and s.member),'staff list shows the member');
  perform pg_temp.assert_true((public.admin_set_facility_membership(fac,pg_temp.u(3),true,'Approver for the plant')->>'ok')::boolean,'Approver added');

  -- open Work Order blocks switching the facility off
  perform pg_temp.act(pg_temp.u(1));
  r:=public.create_work_order(jsonb_build_object('title','First job','location','Yard','facility_id',fac,'description','First job at the new plant.'));
  perform pg_temp.assert_true((r->>'ok')::boolean,'member Technician creates a Work Order at the new facility: '||coalesce(r->>'code',''));
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(public.admin_save_facility(fac,'NEW-01','New Plant (renamed)',null,false,false,'Close site')->>'code'='VALIDATION_ERROR','cannot switch off a facility with open Work Orders');
  perform pg_temp.assert_true((public.admin_set_facility_membership(fac,pg_temp.u(3),false,'Moved to another site')->>'ok')::boolean,'staff removed');
  perform pg_temp.assert_true(not exists(select 1 from public.facility_memberships m where m.facility_id=fac and m.profile_id=pg_temp.u(3) and m.active),'membership inactive');

  -- drawings
  reset role;
  path:='drawings/facility/'||fac::text||'/'||gen_random_uuid()::text||'-layout.png';
  insert into storage.objects(bucket_id,name) values('field-evidence',path),('field-evidence','drawings/facility/'||fac::text||'/plan.pdf'),('field-evidence','evidence/other.png');
  set local role authenticated; perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(public.admin_register_facility_drawing(fac,'NP-001','Ground floor',null,'layout.png','image/png',1000,null,null,path)->>'code'='VALIDATION_ERROR','image drawings need their size');
  perform pg_temp.assert_true(public.admin_register_facility_drawing(fac,'FW-001','Mock',null,'layout.png','image/png',1000,800,600,path)->>'code'='VALIDATION_ERROR','mock-up drawing numbers reserved');
  perform pg_temp.assert_true(public.admin_register_facility_drawing(fac,'NP-001','Ground floor',null,'layout.png','image/png',1000,800,600,'evidence/other.png')->>'code'='INVALID_STORAGE_OBJECT','file must be under the facility drawing folder');
  r:=public.admin_register_facility_drawing(fac,'np-001','Ground floor layout','A (27 Oct 2026)','layout.png','image/png',1000,1600,1000,path);
  perform pg_temp.assert_true((r->>'ok')::boolean and r->'drawing'->>'code'='NP-001','Administrator adds an image drawing: '||coalesce(r->>'code',''));
  did:=(r->'drawing'->>'id')::uuid;
  perform pg_temp.assert_true((public.admin_register_facility_drawing(fac,'NP-PDF','Site plan PDF',null,'plan.pdf','application/pdf',2000,null,null,'drawings/facility/'||fac::text||'/plan.pdf')->>'ok')::boolean,'PDF drawing stored without a size');
  perform pg_temp.assert_true(public.admin_register_facility_drawing(fac,'NP-001','Dup',null,'layout.png','image/png',1000,10,10,path)->>'code'='VALIDATION_ERROR','active drawing number unique per facility');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true((select count(*) from public.facility_drawings where facility_id=fac and active)=2,'staff can read facility drawings');
  perform pg_temp.assert_true(public.admin_remove_facility_drawing(did,'Superseded')->>'code'='ACCESS_DENIED','Technician cannot remove drawings');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true((public.admin_remove_facility_drawing(did,'Superseded by revision B')->>'ok')::boolean,'Administrator removes a drawing');
  reset role;
  perform pg_temp.assert_true((select count(*) from public.activity_logs where action like 'facility_%' and note like '%'||fac::text||'%')>=7,'every facility change is audited');
end;$test$;
rollback;

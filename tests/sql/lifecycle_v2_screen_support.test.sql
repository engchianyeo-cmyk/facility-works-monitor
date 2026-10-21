\set ON_ERROR_STOP on
-- WP-LC2-M4 screen helpers: directory exposes names/roles only; facility Technicians and approval
-- summary respect Work Order visibility. Synthetic and rolled back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Lifecycle v2 screen support regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1c500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'lc2m4.'||n||'@example.test',jsonb_build_object('display_name','LC4 '||role)
from (values ('technician',1),('technician',2),('supervisor',3),('approver',4)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Electrical' end
from (values ('technician',1),('technician',2),('supervisor',3),('approver',4)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
grant select on f to authenticated;
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(3) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(3));
set local role authenticated;
do $t$ declare r jsonb; wo uuid; begin
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true(exists(select 1 from public.work_order_people_directory() d where d.id=pg_temp.u(4) and d.role='approver'),'directory lists active users');
  r:=public.create_work_order(jsonb_build_object('title','Lighting fault','location','Car park','facility_id',(select facility_id from f)));
  wo:=(r->'work_order'->>'id')::uuid;
  perform pg_temp.assert_true(exists(select 1 from public.work_order_facility_technicians(wo) t where t.id=pg_temp.u(1)),'facility Technician listed');
  perform pg_temp.assert_true(not exists(select 1 from public.work_order_facility_technicians(wo) t where t.id=pg_temp.u(2)),'non-member Technician not listed');
  r:=public.work_order_approval_summary(wo);
  perform pg_temp.assert_true((r->>'ok')::boolean and not (r->>'ready')::boolean and r->'missing_requirements' ? 'Reason the work is needed','summary lists missing requirements');
  perform pg_temp.act(pg_temp.u(4));
  perform pg_temp.assert_true(public.work_order_approval_summary(wo)->>'code'='ACCESS_DENIED','non-member Approver cannot read summary');
  perform pg_temp.assert_true(not exists(select 1 from public.work_order_facility_technicians(wo)),'non-member cannot list facility Technicians');
end;$t$;
reset role;
select pg_temp.assert_true((select pg_get_function_result('public.work_order_people_directory()'::regprocedure))='TABLE(id uuid, display_name text, role text)','directory returns names and roles only');
rollback;

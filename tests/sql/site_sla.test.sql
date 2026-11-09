\set ON_ERROR_STOP on
-- D-45 (9 Nov 2026): every member of staff reads the approved Site SLA and the SLA clock of Work Orders they can see.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Site SLA regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d450000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'d45.'||n||'@example.test',jsonb_build_object('display_name','D45 '||role||' '||n)
from (values ('technician',1),('approver',3)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('approver',3)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(3) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(3));
grant select on f to authenticated;

insert into public.service_categories(code,name) select 'GENERAL','General' where not exists(select 1 from public.service_categories where code='GENERAL');
insert into public.sla_agreements(id,agreement_code,name,counterparty,created_by) values ('1d450000-0000-4000-8000-0000000000a1','D45-SLA','D45 Site SLA','Owner',pg_temp.u(3));
insert into public.sla_agreement_versions(id,agreement_id,version_number,effective_from,approval_status,approved_by,approved_at,created_by)
values ('1d450000-0000-4000-8000-0000000000b1','1d450000-0000-4000-8000-0000000000a1',1,current_date - 1,'approved',pg_temp.u(3),now(),pg_temp.u(3)),
       ('1d450000-0000-4000-8000-0000000000b2','1d450000-0000-4000-8000-0000000000a1',2,current_date - 1,'draft',null,null,pg_temp.u(3));
insert into public.sla_rules(version_id,service_category_id,priority_class,work_order_priority,acknowledgement_minutes,attendance_minutes,make_safe_minutes,rectification_minutes,kpi_target_percent,source_clause)
select v,(select id from public.service_categories where code='GENERAL'),'P2','high',30,120,240,480,95,'D45 clause'
from (values ('1d450000-0000-4000-8000-0000000000b1'::uuid),('1d450000-0000-4000-8000-0000000000b2'::uuid)) x(v);

do $t$ declare r jsonb; wo uuid; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  perform pg_temp.assert_true((select count(*) from public.sla_rules where source_clause='D45 clause')=1,'a Technician reads the approved rule only, not the draft one');
  perform pg_temp.assert_true(exists(select 1 from public.sla_agreements where agreement_code='D45-SLA'),'a Technician reads the agreement name');
  r:=public.create_work_order(jsonb_build_object('title','D45 job','location','Plant room','facility_id',(select facility_id from f),'priority','high'));
  wo:=(r->'work_order'->>'id')::uuid;
  perform pg_temp.assert_true(exists(select 1 from public.work_order_sla_clocks c where c.work_order_id=wo and c.attendance_deadline is not null),'the Technician sees the SLA clock of their own Work Order');
end;$t$;
rollback;

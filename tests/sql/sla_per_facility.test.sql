\set ON_ERROR_STOP on
-- M32: one standard SLA, a facility's own SLA used first, times set by the Super-Administrator. Rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'SLA per facility regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d320000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.rows(c int,h int,m int,l int) returns jsonb language sql immutable as $$ select jsonb_build_array(
  jsonb_build_object('priority','critical','acknowledgement_minutes',c,'attendance_minutes',c*2,'make_safe_minutes',c*8,'rectification_minutes',c*16,'kpi_target_percent',95),
  jsonb_build_object('priority','high','acknowledgement_minutes',h,'attendance_minutes',h*4,'make_safe_minutes',h*8,'rectification_minutes',h*48,'kpi_target_percent',95),
  jsonb_build_object('priority','medium','acknowledgement_minutes',m,'attendance_minutes',1440,'rectification_minutes',4320,'kpi_target_percent',90),
  jsonb_build_object('priority','low','acknowledgement_minutes',l,'attendance_minutes',4320,'rectification_minutes',14400,'kpi_target_percent',90)) $$;

insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m32.'||n||'@example.test',jsonb_build_object('display_name','M32 '||role||' '||n)
from (values ('administrator',1),('technician',2),('technician',3),('facility_manager',4)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Electrical' end
from (values ('administrator',1),('technician',2),('technician',3),('facility_manager',4)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.sites(id,code,name,is_active) values (pg_temp.u(101),'M32-F1','M32 Facility One',true),(pg_temp.u(102),'M32-F2','M32 Facility 2',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(101),pg_temp.u(2),'technician',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(3),'technician',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(4),'facility_manager',pg_temp.u(1));
insert into public.service_categories(code,name) select 'GENERAL','General' where not exists(select 1 from public.service_categories where code='GENERAL');

-- Only the Super-Administrator; reasons and complete, ordered times required.
select pg_temp.act(pg_temp.u(4));
select pg_temp.assert_true((public.admin_set_sla_times(null,pg_temp.rows(15,30,120,1440),'Standard SLA')->>'code')='ACCESS_DENIED','a Facility Manager cannot set SLA times');
select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((public.admin_set_sla_times(null,pg_temp.rows(15,30,120,1440),'no')->>'code')='VALIDATION_ERROR','a reason is required');
select pg_temp.assert_true((public.admin_set_sla_times(null,pg_temp.rows(15,30,120,1440)-3,'Standard SLA')->>'code')='VALIDATION_ERROR','all four priorities are required');
select pg_temp.assert_true((public.admin_set_sla_times(null,jsonb_set(pg_temp.rows(15,30,120,1440),'{0,acknowledgement_minutes}','500'),'Standard SLA')->>'code')='VALIDATION_ERROR','times may not run backwards');
select pg_temp.assert_true((public.admin_set_sla_times(null,pg_temp.rows(15,30,120,1440),'Standard SLA from the draft')->>'ok')::boolean,'the standard is set');
select pg_temp.assert_true((public.admin_set_sla_times(pg_temp.u(102),pg_temp.rows(10,15,60,1440),'Facility 2 runs tighter')->>'ok')::boolean,'Facility 2 gets its own SLA');
select pg_temp.assert_true((select count(*) from public.sla_agreements where is_active and facility_id is null)=1,'one active company standard');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where action='sla_times_set'),'changes are audited');

-- Clocks: Facility 2 uses its own times, Facility One the standard.
select pg_temp.act(pg_temp.u(3));
select public.create_work_order(jsonb_build_object('title','M32 freezer','location','Freezer','facility_id',pg_temp.u(102),'priority','critical')) as f2 \gset
select pg_temp.act(pg_temp.u(2));
select public.create_work_order(jsonb_build_object('title','M32 pump','location','Plant','facility_id',pg_temp.u(101),'priority','critical')) as f1 \gset
select pg_temp.assert_true((select acknowledgement_deadline-started_at from public.work_order_sla_clocks where work_order_id=((:'f2')::jsonb->'work_order'->>'id')::uuid)=interval '10 minutes','Facility 2 Work Order uses Facility 2 times');
select pg_temp.assert_true((select acknowledgement_deadline-started_at from public.work_order_sla_clocks where work_order_id=((:'f1')::jsonb->'work_order'->>'id')::uuid)=interval '15 minutes','Facility One Work Order uses the standard');

-- A change makes a new version; running clocks keep their times; Site SLA shows only current rules.
select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((public.admin_set_sla_times(pg_temp.u(102),pg_temp.rows(5,15,60,1440),'Even faster for cold chain')->>'ok')::boolean,'a second change is accepted');
select pg_temp.assert_true((select count(*) from public.sla_agreement_versions v join public.sla_agreements a on a.id=v.agreement_id where a.facility_id=pg_temp.u(102) and v.effective_to is not null and not exists(select 1 from public.sla_rules r where r.version_id=v.id and r.is_active))=1,'the earlier version is ended and its rules no longer apply');
select pg_temp.assert_true((select acknowledgement_deadline-started_at from public.work_order_sla_clocks where work_order_id=((:'f2')::jsonb->'work_order'->>'id')::uuid)=interval '10 minutes','a running clock keeps its times');
select pg_temp.assert_true((select count(*) from public.sla_rules r join public.sla_agreement_versions v on v.id=r.version_id join public.sla_agreements a on a.id=v.agreement_id where a.facility_id=pg_temp.u(102) and r.is_active)=4,'four current rules for Facility 2');

-- Back to the standard.
select pg_temp.assert_true((public.admin_use_standard_sla(pg_temp.u(102),'Trial over, use standard')->>'ok')::boolean,'a facility can go back to the standard');
select pg_temp.act(pg_temp.u(3));
select public.create_work_order(jsonb_build_object('title','M32 freezer 2','location','Freezer','facility_id',pg_temp.u(102),'priority','critical')) as f2b \gset
select pg_temp.assert_true((select acknowledgement_deadline-started_at from public.work_order_sla_clocks where work_order_id=((:'f2b')::jsonb->'work_order'->>'id')::uuid)=interval '15 minutes','after going back, the standard applies');

select 'sla_per_facility tests passed' as result;
rollback;

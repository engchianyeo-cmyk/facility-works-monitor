\set ON_ERROR_STOP on
-- M35: planned maintenance runs by itself (owner D-67). Rolls back.
-- Dates use public.pm_business_date() (Singapore), not current_date (UTC): between 00:00 and 08:00 SGT they differ.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'PM automation regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d350000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 super-administrator, 2 supervisor F2, 3 technician F2, 4 facility administrator F2, 5 supervisor F1
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m35.'||n||'@example.test',jsonb_build_object('display_name','M35 '||role||' '||n)
from (values ('administrator',1),('supervisor',2),('technician',3),('facility_administrator',4),('supervisor',5)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false
from (values ('administrator',1),('supervisor',2),('technician',3),('facility_administrator',4),('supervisor',5)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.sites(id,code,name,is_active) values (pg_temp.u(101),'M35-F1','M35 Facility One',true),(pg_temp.u(102),'M35-F2','M35 Facility 2',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(102),pg_temp.u(2),'supervisor',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(3),'technician',pg_temp.u(1)),
 (pg_temp.u(102),pg_temp.u(4),'facility_administrator',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(5),'supervisor',pg_temp.u(1));
insert into public.assets(id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,facility_id,created_by,updated_by) values
 (pg_temp.u(201),'M35-F2-FP-01','M35 sprinkler pump','Pump','critical','active','M35 Facility 2','Pump room',pg_temp.u(102),pg_temp.u(1),pg_temp.u(1)),
 (pg_temp.u(202),'M35-F2-AHU-01','M35 office AHU','AHU','high','active','M35 Facility 2','Plant room',pg_temp.u(102),pg_temp.u(1),pg_temp.u(1));

-- The window rule.
select pg_temp.assert_true(public.pm_window_days(1,'week')=1 and public.pm_window_days(1,'month')=3 and public.pm_window_days(3,'month')=7
  and public.pm_window_days(6,'month')=14 and public.pm_window_days(1,'year')=21 and public.pm_window_days(12,'month')=21 and public.pm_window_days(1,'day')=0,'windows match D-67 A');

-- A weekly task first due on a Saturday at least two days ahead; a monthly task due in 10 days.
select (public.pm_business_date() + ((6 - extract(isodow from public.pm_business_date())::int + 7) % 7) + case when ((6 - extract(isodow from public.pm_business_date())::int + 7) % 7) < 2 then 7 else 0 end)::date as sat \gset
select set_config('m35.sat',:'sat',true);
select pg_temp.act(pg_temp.u(1));
select public.create_pm_requirement(jsonb_build_object('asset_id',pg_temp.u(201),'title','Weekly pump run','scope','Run pump 30 min','maintenance_type','inspection','interval_value',1,'interval_unit','week','first_due_date',:'sat')) as w \gset
select public.create_pm_requirement(jsonb_build_object('asset_id',pg_temp.u(202),'title','Monthly AHU check','scope','Filters and belts','maintenance_type','preventive','interval_value',1,'interval_unit','month','first_due_date',(public.pm_business_date()+10)::text)) as m \gset
select set_config('m35.w',(:'w')::jsonb->'requirement'->>'id',true), set_config('m35.m',(:'m')::jsonb->'requirement'->>'id',true);
select pg_temp.assert_true((public.activate_pm_requirement(current_setting('m35.w')::uuid)->>'ok')::boolean and (public.activate_pm_requirement(current_setting('m35.m')::uuid)->>'ok')::boolean,'both tasks active');

-- New facilities start on Plan only: the daily run lists dates and moves the weekend, but creates no Work Orders.
select pg_temp.assert_true(public.facility_pm_mode(pg_temp.u(102))='plan_only','a facility starts on plan_only');
select set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claims','',true);
select public.pm_daily_run() as run1 \gset
select pg_temp.assert_true(((:'run1')::jsonb->>'ok')::boolean,'the daily run works: '||:'run1');
select pg_temp.assert_true((select count(*) from public.pm_occurrences where requirement_id in (current_setting('m35.w')::uuid,current_setting('m35.m')::uuid))>=5,'the next month is listed');
select pg_temp.assert_true((select current_due_date from public.pm_occurrences where requirement_id=current_setting('m35.w')::uuid and original_due_date=current_setting('m35.sat')::date)=current_setting('m35.sat')::date-1,'a Saturday weekly task moves to Friday (window ±1)');
select pg_temp.assert_true(exists(select 1 from public.pm_occurrence_reschedules s join public.pm_occurrences o on o.id=s.occurrence_id where o.requirement_id=current_setting('m35.w')::uuid and s.automatic),'the weekend move is recorded');
select pg_temp.assert_true((select count(*) from public.work_orders w join public.pm_occurrences o on o.id=w.pm_occurrence_id where o.asset_id in (pg_temp.u(201),pg_temp.u(202)))=0,'plan only creates no Work Orders');
select public.pm_daily_run() as run2 \gset
select pg_temp.assert_true(((:'run2')::jsonb->>'weekend_moves')::int=0,'a second run moves nothing again');

-- The setting: only the Super-Administrator, with a reason, recorded.
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((public.admin_set_pm_mode(pg_temp.u(102),'full','Supervisor tries')->>'code')='ACCESS_DENIED','a Supervisor cannot change the setting');
select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((public.admin_set_pm_mode(pg_temp.u(102),'full_critical','x')->>'code')='VALIDATION_ERROR','a reason is required');
select pg_temp.assert_true((public.admin_set_pm_mode(pg_temp.u(102),'full_critical','Owner D-67: Facility 2 trial, critical only')->>'ok')::boolean,'the Super-Administrator sets Full for critical only');
select pg_temp.assert_true(exists(select 1 from public.facility_settings_history where facility_id=pg_temp.u(102) and next->>'pm_mode'='full_critical'),'the change is recorded');

-- Full for critical only: on the due day the pump (critical) gets its Work Order; the AHU (high) does not.
select set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claims','',true);
select public.pm_daily_run(public.pm_business_date()+10) as run3 \gset
select pg_temp.assert_true((select count(*) from public.work_orders w join public.pm_occurrences o on o.id=w.pm_occurrence_id where o.asset_id=pg_temp.u(201))>=1,'the critical pump gets its Work Orders: '||:'run3');
select pg_temp.assert_true((select count(*) from public.work_orders w join public.pm_occurrences o on o.id=w.pm_occurrence_id where o.asset_id=pg_temp.u(202))=0,'the AHU stays a plan');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where action='pm_daily_run'),'each run is logged');

-- Moving a date: inside the window by the Supervisor, with a reason; beyond it only the Facility Administrator / Super-Admin.
select o.id as occ from public.pm_occurrences o where o.requirement_id=current_setting('m35.m')::uuid order by o.original_due_date limit 1 \gset
select set_config('m35.occ',:'occ',true);
select pg_temp.act(pg_temp.u(5));
select pg_temp.assert_true((public.reschedule_pm_occurrence(current_setting('m35.occ')::uuid,public.pm_business_date()+11,'Other facility')->>'code')='ACCESS_DENIED','another facility''s Supervisor cannot move it');
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((public.reschedule_pm_occurrence(current_setting('m35.occ')::uuid,public.pm_business_date()+11,'Technician')->>'code')='ACCESS_DENIED','a Technician cannot move it');
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((public.reschedule_pm_occurrence(current_setting('m35.occ')::uuid,public.pm_business_date()+8,'')->>'code')='REASON_REQUIRED','a reason is needed');
select pg_temp.assert_true((public.reschedule_pm_occurrence(current_setting('m35.occ')::uuid,public.pm_business_date()+8,'Shutdown booked that day')->>'ok')::boolean,'the Supervisor moves it 2 days earlier (inside ±3)');
select pg_temp.assert_true((public.reschedule_pm_occurrence(current_setting('m35.occ')::uuid,public.pm_business_date()+16,'Contractor away')->>'code')='BEYOND_WINDOW','6 days later is beyond the window for a Supervisor');
select pg_temp.assert_true((public.defer_pm_occurrence(current_setting('m35.occ')::uuid,public.pm_business_date()+30,'Defer past the window')->>'code')='BEYOND_WINDOW','deferring past the window is refused for a Supervisor too');
select pg_temp.act(pg_temp.u(4));
select pg_temp.assert_true((public.reschedule_pm_occurrence(current_setting('m35.occ')::uuid,public.pm_business_date()+16,'Contractor away; approved beyond window')->>'ok')::boolean,'the Facility Administrator approves beyond the window');
select pg_temp.assert_true((select beyond_window from public.pm_occurrence_reschedules where occurrence_id=current_setting('m35.occ')::uuid order by rescheduled_at desc, revised_due_date desc limit 1),'recorded as beyond the window');

-- Off: no new dates are listed for the facility.
select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((public.admin_set_pm_mode(pg_temp.u(102),'off','Paperwork pause during the trial')->>'ok')::boolean,'the planned maintenance can be switched off');
select count(*) as before_off from public.pm_occurrences o where o.asset_id in (pg_temp.u(201),pg_temp.u(202)) \gset
select set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claims','',true);
select public.pm_daily_run(public.pm_business_date()+40) as run4 \gset
select pg_temp.assert_true((select count(*) from public.pm_occurrences o where o.asset_id in (pg_temp.u(201),pg_temp.u(202)))=:before_off,'Off lists nothing new');

-- The daily run is for the scheduler only, not for signed-in users.
select pg_temp.assert_true(not has_function_privilege('authenticated','public.pm_daily_run(date)','execute'),'signed-in users cannot start the daily run');

select 'pm_automation tests passed' as result;
rollback;

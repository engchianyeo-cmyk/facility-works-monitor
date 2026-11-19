\set ON_ERROR_STOP on
-- M36: the Daily round (owner D-67 D-G). Rolls back. Dates use public.pm_business_date() (Singapore).
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Daily round regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d360000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 super-administrator, 2 supervisor F2, 3 technician 2 (F2), 4 technician 1 (F2), 5 technician F1, 6 approver F2
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m36.'||n||'@example.test',jsonb_build_object('display_name','M36 '||role||' '||n)
from (values ('administrator',1),('supervisor',2),('technician',3),('technician',4),('technician',5),('approver',6)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false
from (values ('administrator',1),('supervisor',2),('technician',3),('technician',4),('technician',5),('approver',6)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.sites(id,code,name,is_active) values (pg_temp.u(101),'M36-F1','M36 Facility One',true),(pg_temp.u(102),'M36-F2','M36 Facility 2',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(102),pg_temp.u(2),'supervisor',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(3),'technician',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(4),'technician',pg_temp.u(1)),
 (pg_temp.u(101),pg_temp.u(5),'technician',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(6),'approver',pg_temp.u(1));

-- Setting up: the Approver of the facility may; a Technician may not; Technicians must be staff of the facility.
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((public.save_daily_round_check(null,pg_temp.u(102),'Cold room 1','RU-CR1-A/B',10,true)->>'code')='ACCESS_DENIED','a Technician cannot change the checklist');
select pg_temp.act(pg_temp.u(6));
select public.save_daily_round_check(null,pg_temp.u(102),'Cold room 1','RU-CR1-A/B',10,true) as c1 \gset
select pg_temp.assert_true(((:'c1')::jsonb->>'ok')::boolean,'the Approver adds a check');
select set_config('m36.c1',(:'c1')::jsonb->>'id',true);
select public.save_daily_round_item(null,current_setting('m36.c1')::uuid,'Room temperature on the EMS','°C',10,true) as i1 \gset
select public.save_daily_round_item(null,current_setting('m36.c1')::uuid,'Units running, alarms clear',null,20,true) as i2 \gset
select set_config('m36.i1',(:'i1')::jsonb->>'id',true), set_config('m36.i2',(:'i2')::jsonb->>'id',true);
select pg_temp.assert_true((public.set_daily_round_settings(pg_temp.u(102),true,pg_temp.u(5),null,'07:00','10:00','Start')->>'code')='INVALID_REFERENCE','a Technician of another facility is refused');
select pg_temp.assert_true((public.set_daily_round_settings(pg_temp.u(102),true,pg_temp.u(3),pg_temp.u(4),'10:00','07:00','Start')->>'code')='VALIDATION_ERROR','due must be after ready');
select pg_temp.assert_true((public.set_daily_round_settings(pg_temp.u(102),true,pg_temp.u(3),pg_temp.u(4),'07:00','10:00','Owner D-67: Technician 2 does it, Technician 1 covers')->>'ok')::boolean,'the round is switched on');

-- The daily run creates one round per day, only where the setting creates Work Orders; none twice.
select pg_temp.act(pg_temp.u(1));
select public.admin_set_pm_mode(pg_temp.u(102),'full_critical','Trial: critical only') as m \gset
select set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claims','',true);
select public.pm_daily_run() as run1 \gset
select pg_temp.assert_true(((:'run1')::jsonb->>'daily_rounds')::int=1,'the daily run creates the round: '||:'run1');
select public.pm_daily_run() as run2 \gset
select pg_temp.assert_true(((:'run2')::jsonb->>'daily_rounds')::int=0,'not twice on the same day');
select id as wo, status, assigned_technician_id, in_house_work, source from public.work_orders where facility_id=pg_temp.u(102) and daily_round_date=public.pm_business_date() \gset
select set_config('m36.wo',:'wo',true);
select pg_temp.assert_true(:'status'='approved' and :'assigned_technician_id'::uuid=pg_temp.u(3) and :'in_house_work'::boolean and :'source'='inspection','ready to start, assigned to Technician 2, in-house');
select pg_temp.assert_true(not exists(select 1 from public.work_order_sla_clocks where work_order_id=current_setting('m36.wo')::uuid),'no SLA clock on the round');

-- Recording: another facility's Technician cannot; Technician 2 can; a reading and a reason for Not OK are required.
select pg_temp.act(pg_temp.u(5));
select pg_temp.assert_true((public.record_daily_round_item(current_setting('m36.wo')::uuid,current_setting('m36.i2')::uuid,true,null,null)->>'code')='ACCESS_DENIED','another facility''s Technician cannot record');
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((public.record_daily_round_item(current_setting('m36.wo')::uuid,current_setting('m36.i1')::uuid,true,'',null)->>'code')='VALIDATION_ERROR','the reading is required');
select pg_temp.assert_true((public.record_daily_round_item(current_setting('m36.wo')::uuid,current_setting('m36.i1')::uuid,true,'5.1',null)->>'ok')::boolean,'Technician 2 records a reading');
select pg_temp.assert_true((select status from public.work_orders where id=current_setting('m36.wo')::uuid)='in_progress','the first item starts the round');
select pg_temp.assert_true((public.complete_daily_round(current_setting('m36.wo')::uuid,null)->>'code')='INCOMPLETE','it cannot complete with items missing');
select pg_temp.assert_true((public.record_daily_round_item(current_setting('m36.wo')::uuid,current_setting('m36.i2')::uuid,false,null,'')->>'code')='VALIDATION_ERROR','Not OK needs a reason');
select pg_temp.act(pg_temp.u(4));
select pg_temp.assert_true((public.record_daily_round_item(current_setting('m36.wo')::uuid,current_setting('m36.i2')::uuid,false,null,'Unit B high-pressure alarm')->>'ok')::boolean,'the cover Technician can record too');
select public.complete_daily_round(current_setting('m36.wo')::uuid,'Unit B alarm reported') as done \gset
select pg_temp.assert_true(((:'done')::jsonb->>'ok')::boolean and ((:'done')::jsonb->>'faults')::int=1,'completed, one fault counted');
select pg_temp.assert_true((select status='closed' and closed_at is not null from public.work_orders where id=current_setting('m36.wo')::uuid),'the round is closed');
select pg_temp.assert_true((public.record_daily_round_item(current_setting('m36.wo')::uuid,current_setting('m36.i1')::uuid,true,'6',null)->>'code')='ROUND_CLOSED','a closed round cannot change');

-- Reading: staff of the facility see the checklist and results; another facility does not.
set local role authenticated;
select pg_temp.act(pg_temp.u(4));
select pg_temp.assert_true((select count(*) from public.daily_round_items)=2,'facility staff read the checklist');
select pg_temp.act(pg_temp.u(5));
select pg_temp.assert_true((select count(*) from public.daily_round_checks)=0,'another facility does not');
reset role;

-- Plan only: no round is created.
select pg_temp.act(pg_temp.u(1));
select public.admin_set_pm_mode(pg_temp.u(102),'plan_only','Back to plan only') as m2 \gset
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((public.create_daily_round(pg_temp.u(102),public.pm_business_date()+1)->>'ok')::boolean,'an editor can still start a round by hand');
select set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claims','',true);
select public.pm_daily_run(public.pm_business_date()+1) as run3 \gset
select pg_temp.assert_true(((:'run3')::jsonb->>'daily_rounds')::int=0,'plan only: the daily run creates no round');

select 'daily_round tests passed' as result;
rollback;

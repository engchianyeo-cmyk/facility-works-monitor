\set ON_ERROR_STOP on
-- M38: planned-maintenance Work Orders can be approved (in-house, no location mark / Before photo / quotation) and carry
-- no reaction SLA clock. Rolls back. Dates use public.pm_business_date() (Singapore).
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Planned work regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
-- The daily run moves weekend due dates to Friday or Monday; on a Saturday or Sunday (Singapore) the first visit is
-- set to the Friday just gone, so the run still makes its Work Order whatever day the test runs.
create function pg_temp.weekday() returns date language sql as $$
  select public.pm_business_date() - case extract(isodow from public.pm_business_date())::int when 6 then 1 when 7 then 2 else 0 end $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d380000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 super-administrator, 2 approver F2, 3 technician F2
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m38.'||n||'@example.test',jsonb_build_object('display_name','M38 '||role||' '||n)
from (values ('administrator',1),('approver',2),('technician',3)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false
from (values ('administrator',1),('approver',2),('technician',3)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.sites(id,code,name,is_active) values (pg_temp.u(102),'M38-F2','M38 Facility 2',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(102),pg_temp.u(2),'approver',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(3),'technician',pg_temp.u(1));
insert into public.assets(id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,facility_id,created_by,updated_by) values
 (pg_temp.u(201),'M38-FP-01','M38 sprinkler pump','Fire','critical','active','M38 Facility 2','Pump room',pg_temp.u(102),pg_temp.u(1),pg_temp.u(1));

select pg_temp.act(pg_temp.u(1));
select public.create_pm_requirement(jsonb_build_object('asset_id',pg_temp.u(201),'title','Weekly pump run','scope','Run pump 30 min','maintenance_type','inspection','interval_value',1,'interval_unit','week','first_due_date',public.pm_business_date()::text)) as r \gset
select set_config('m38.req',(:'r')::jsonb->'requirement'->>'id',true);
select public.activate_pm_requirement(current_setting('m38.req')::uuid) as a \gset
select public.assign_pm_technician(current_setting('m38.req')::uuid,pg_temp.u(3)) as t \gset
select public.admin_set_pm_mode(pg_temp.u(102),'full','M38 test') as m \gset
select set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claims','',true);
select public.pm_daily_run() as run0 \gset
update public.pm_occurrences set current_due_date=pg_temp.weekday() where requirement_id=current_setting('m38.req')::uuid and original_due_date=public.pm_business_date();
select public.pm_daily_run() as run \gset
select w.id as wo, w.in_house_work, w.status from public.work_orders w join public.pm_occurrences o on o.id=w.pm_occurrence_id where o.requirement_id=current_setting('m38.req')::uuid limit 1 \gset
select set_config('m38.wo',:'wo',true);
select pg_temp.assert_true(:'in_house_work'::boolean,'a planned-maintenance Work Order is in-house');
select pg_temp.assert_true(not exists(select 1 from public.work_order_sla_clocks where work_order_id=current_setting('m38.wo')::uuid),'it has no reaction SLA clock');

select pg_temp.act(pg_temp.u(2));
select public.work_order_approval_summary(current_setting('m38.wo')::uuid) as s \gset
select pg_temp.assert_true(not ((:'s')::jsonb->'missing_requirements') ? 'Location marked on the layout plan','no location mark is asked for: '||:'s');
select pg_temp.assert_true(not ((:'s')::jsonb->'missing_requirements') ? 'Before photo, video or voice note of the site','no Before photo is asked for');
select pg_temp.assert_true(((:'s')::jsonb->>'can_approve')::boolean,'the Approver can approve it: '||:'s');
select public.transition_work_order(current_setting('m38.wo')::uuid,'approve','{}'::jsonb) as ap \gset
select pg_temp.assert_true(((:'ap')::jsonb->>'ok')::boolean,'the Approver approves it: '||:'ap');

-- Our team: facility staff see their own facility's staff; others see nothing; the service key cannot read it.
insert into auth.users(id,email,raw_user_meta_data) values (pg_temp.u(4),'m38.4@example.test','{"display_name":"M38 finance 4"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='finance',is_active=true,password_change_required=false where id=pg_temp.u(4);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.sites(id,code,name,is_active) values (pg_temp.u(103),'M38-F3','M38 Facility 3',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values (pg_temp.u(103),pg_temp.u(4),'finance',pg_temp.u(1));
select pg_temp.act(pg_temp.u(2));
set local role authenticated;
select pg_temp.assert_true((select count(*) from public.visible_facility_memberships() where facility_id=pg_temp.u(102))=2,'the Approver sees both Facility 2 staff');
select pg_temp.assert_true(not exists(select 1 from public.visible_facility_memberships() where facility_id=pg_temp.u(103)),'the Approver does not see another facility''s staff');
select pg_temp.assert_true((select display_name from public.visible_facility_memberships() where profile_id=pg_temp.u(3))='M38 technician 3','a colleague''s name is shown, not just "Assigned"');
reset role;
select pg_temp.act(pg_temp.u(1));
set local role authenticated;
select pg_temp.assert_true((select count(*) from public.visible_facility_memberships() where facility_id in (pg_temp.u(102),pg_temp.u(103)))=3,'the Super-Administrator sees every facility');
reset role;
select pg_temp.assert_true(not has_function_privilege('service_role','public.visible_facility_memberships()','execute'),'the service key cannot list staff');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.finance_reminder_facilities(uuid[])','execute'),'signed-in users cannot call the reminder lookup');
select pg_temp.assert_true((select count(*) from public.finance_reminder_facilities(array[pg_temp.u(4),pg_temp.u(2)]))=1,'the reminder finds only Finance memberships');

-- The Facility Manager manages the emergency on-call roster (owner, 22 Nov 2026).
insert into auth.users(id,email,raw_user_meta_data) values (pg_temp.u(5),'m38.5@example.test','{"display_name":"M38 facility manager 5"}');
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles set role='facility_manager',is_active=true,password_change_required=false where id=pg_temp.u(5);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
select pg_temp.act(pg_temp.u(5));
select public.upsert_emergency_roster(null,jsonb_build_object('profile_id',pg_temp.u(3),'escalation_order',7)) as fmr \gset
select pg_temp.assert_true(((:'fmr')::jsonb->>'ok')::boolean,'the Facility Manager adds an on-call entry: '||:'fmr');
select pg_temp.assert_true(exists(select 1 from public.get_emergency_roster() where profile_id=pg_temp.u(3)),'the Facility Manager sees the roster');
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((public.upsert_emergency_roster(null,jsonb_build_object('profile_id',pg_temp.u(3),'escalation_order',8))->>'code')='ACCESS_DENIED','a Technician still cannot');
select 'planned_work_ready tests passed' as result;
rollback;

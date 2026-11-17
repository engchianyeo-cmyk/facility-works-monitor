\set ON_ERROR_STOP on
-- M29 (D-50, D-53, D-54, D-55): Facility Administrators, Finance per facility, removing a person's details.
-- Self-contained synthetic identities and data; everything rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Facility administrators regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d290000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

-- 1 super-administrator, 2 facility administrator (F2), 3 technician F1, 4 technician F2, 5 finance F1, 6 finance F2,
-- 7 new person (not yet in any facility), 8 approver F1, 9 a tester whose details are removed
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m29.'||n||'@example.test',jsonb_build_object('display_name','M29 '||role||' '||n)
from (values ('administrator',1),('facility_administrator',2),('technician',3),('technician',4),('finance',5),('finance',6),('technician',7),('approver',8),('approver',9)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('administrator',1),('facility_administrator',2),('technician',3),('technician',4),('finance',5),('finance',6),('technician',7),('approver',8),('approver',9)) a(role,n)
where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

insert into public.sites(id,code,name,is_active) values (pg_temp.u(101),'M29-F1','M29 Facility One',true),(pg_temp.u(102),'M29-F2','M29 Facility 2',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(101),pg_temp.u(3),'technician',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(5),'finance',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(8),'approver',pg_temp.u(1)),
 (pg_temp.u(102),pg_temp.u(4),'technician',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(6),'finance',pg_temp.u(1)),(pg_temp.u(102),pg_temp.u(9),'approver',pg_temp.u(1));
insert into public.work_orders(id,user_id,requested_by,assigned_technician_id,work_order_number,title,location,priority,status,source,facility_id,created_at,updated_at) values
 (pg_temp.u(201),pg_temp.u(3),pg_temp.u(3),pg_temp.u(3),'WO-M29-F1','Facility One job','Yard','medium','submitted','manual',pg_temp.u(101),now(),now()),
 (pg_temp.u(202),pg_temp.u(4),pg_temp.u(4),pg_temp.u(4),'WO-M29-F2','Facility 2 job','Dock','medium','submitted','manual',pg_temp.u(102),now(),now());
insert into public.activity_logs(user_id,work_order_id,action,actor,note) values (pg_temp.u(9),pg_temp.u(202),'work_order_approve','M29 approver 9','{"by":"M29 approver 9","email":"m29.9@example.test"}');

do $t$ declare r jsonb; begin
  set local role authenticated;
  -- the Super-Administrator appoints the Facility Administrator of Facility 2
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true((public.admin_set_facility_membership(pg_temp.u(102),pg_temp.u(2),true,'Appointed for Facility 2')->>'ok')::boolean,'Super-Administrator appoints a Facility Administrator');

  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.admin_save_facility(null,'M29-F3','New one',null,true,false,'try')->>'code'='ACCESS_DENIED','a Facility Administrator cannot add facilities');
  perform pg_temp.assert_true((public.admin_save_facility(pg_temp.u(102),'M29-F2','M29 Facility 2 — Pharma',null,true,false,'Rename')->>'ok')::boolean,'a Facility Administrator renames its own facility');
  perform pg_temp.assert_true(public.admin_save_facility(pg_temp.u(102),'M29-F2','M29 Facility 2',null,false,false,'Off')->>'code'='ACCESS_DENIED','a Facility Administrator cannot switch its facility off');
  perform pg_temp.assert_true(public.admin_save_facility(pg_temp.u(101),'M29-F1','Taken over',null,true,false,'x')->>'code'='ACCESS_DENIED','a Facility Administrator cannot change another facility');
  perform pg_temp.assert_true((public.admin_add_facility_area(pg_temp.u(102),'F2-1-01','Aircon Warehouse 1-1','Level 1')->>'ok')::boolean,'adds an area to its facility');
  perform pg_temp.assert_true(public.admin_add_facility_area(pg_temp.u(101),'F1-X','Elsewhere',null)->>'code'='ACCESS_DENIED','cannot add an area to another facility');
  perform pg_temp.assert_true((public.admin_set_facility_membership(pg_temp.u(102),pg_temp.u(7),true,'New Technician')->>'ok')::boolean,'adds a new person to its facility');
  perform pg_temp.assert_true(public.admin_set_facility_membership(pg_temp.u(101),pg_temp.u(7),true,'x')->>'code'='ACCESS_DENIED','cannot add staff to another facility');
  perform pg_temp.assert_true(public.admin_set_facility_membership(pg_temp.u(102),pg_temp.u(2),false,'x')->>'code' in ('ACCESS_DENIED'),'cannot remove itself');
  perform pg_temp.assert_true(not exists(select 1 from public.admin_facility_staff(pg_temp.u(102)) s where s.profile_id in (pg_temp.u(3),pg_temp.u(5),pg_temp.u(8))),'never sees Facility One staff');
  perform pg_temp.assert_true(exists(select 1 from public.admin_facility_staff(pg_temp.u(102)) s where s.profile_id=pg_temp.u(4) and s.member),'sees its own staff');
  perform pg_temp.assert_true(not exists(select 1 from public.admin_facility_staff(pg_temp.u(101))),'cannot list another facility''s staff');
  perform pg_temp.assert_true((public.set_facility_settings(pg_temp.u(102),pg_temp.u(9),'before_review','Designated Approver')->>'ok')::boolean,'sets its facility''s Designated Approver');
  perform pg_temp.assert_true(public.set_facility_settings(pg_temp.u(101),null,'before_review','x')->>'code'='ACCESS_DENIED','cannot change another facility''s settings');
  perform pg_temp.assert_true(exists(select 1 from public.facility_approver_candidates(pg_temp.u(102)) c where c.id=pg_temp.u(9)),'sees its Approvers as candidates');
  perform pg_temp.assert_true(not exists(select 1 from public.facility_approver_candidates(pg_temp.u(101))),'no candidates for another facility');
  perform pg_temp.assert_true(exists(select 1 from public.work_orders where id=pg_temp.u(202)),'reads its facility''s Work Orders');
  perform pg_temp.assert_true(not exists(select 1 from public.work_orders where id=pg_temp.u(201)),'does not read another facility''s Work Orders');

  -- Finance per facility
  perform pg_temp.act(pg_temp.u(5));
  perform pg_temp.assert_true(exists(select 1 from public.work_orders where id=pg_temp.u(201)) and not exists(select 1 from public.work_orders where id=pg_temp.u(202)),'Facility One Finance reads only Facility One');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true(exists(select 1 from public.work_orders where id=pg_temp.u(202)) and not exists(select 1 from public.work_orders where id=pg_temp.u(201)),'Facility 2 Finance reads only Facility 2');
  perform pg_temp.act(pg_temp.u(1));
  perform pg_temp.assert_true((select count(*) from public.work_orders where id in (pg_temp.u(201),pg_temp.u(202)))=2,'the Super-Administrator reads every facility');
  perform pg_temp.assert_true(public.admin_remove_personal_details(pg_temp.u(9),'wrong@example.test','Tester')->>'code'='VALIDATION_ERROR','removal needs the exact email typed');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true(public.admin_remove_personal_details(pg_temp.u(9),'m29.9@example.test','Tester')->>'code'='ACCESS_DENIED','only the Super-Administrator removes a person''s details');
end $t$;

-- notices and copied parties reach Finance only for its own facility
reset role;
insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status) values
 (pg_temp.u(202),'work_order_invoice_uploaded','m29:a',pg_temp.u(5),pg_temp.u(5),'m29.5@example.test','email','{}','pending'),
 (pg_temp.u(202),'work_order_invoice_uploaded','m29:b',pg_temp.u(6),pg_temp.u(6),'m29.6@example.test','email','{}','pending');
insert into public.work_order_copied_parties(work_order_id,profile_id,added_by) values (pg_temp.u(202),pg_temp.u(5),pg_temp.u(1)),(pg_temp.u(202),pg_temp.u(6),pg_temp.u(1));
select pg_temp.assert_true(not exists(select 1 from public.notification_outbox where event_key='m29:a'),'Facility One Finance is not notified about Facility 2');
select pg_temp.assert_true(exists(select 1 from public.notification_outbox where event_key='m29:b'),'Facility 2 Finance is notified');
select pg_temp.assert_true(not exists(select 1 from public.work_order_copied_parties where work_order_id=pg_temp.u(202) and profile_id=pg_temp.u(5)),'Facility One Finance is not copied on Facility 2');
select pg_temp.assert_true(exists(select 1 from public.work_order_copied_parties where work_order_id=pg_temp.u(202) and profile_id=pg_temp.u(6)),'Facility 2 Finance is copied');

-- a Facility Administrator creates an account for its facility only
insert into auth.users(id,email,raw_user_meta_data) values (pg_temp.u(10),'m29.10@example.test','{"display_name":"M29 new 10"}'),(pg_temp.u(11),'m29.11@example.test','{"display_name":"M29 new 11"}');
do $t$ declare r jsonb; ok boolean; begin
  set local role authenticated;
  perform pg_temp.act(pg_temp.u(2));
  r:=public.admin_finalize_provisioned_profile(pg_temp.u(10),jsonb_build_object('role','technician','display_name','F2 Tech','trade_discipline','Electrical','facility_id',pg_temp.u(102)),'user_admin_direct_created');
  perform pg_temp.assert_true(r->>'role'='technician','Facility Administrator creates a Technician');
  perform pg_temp.assert_true(public.active_facility_member(pg_temp.u(102),'technician',pg_temp.u(10)),'the new account joins Facility 2 at once');
  begin
    perform public.admin_finalize_provisioned_profile(pg_temp.u(11),jsonb_build_object('role','administrator','display_name','Sneaky','facility_id',pg_temp.u(102)),'user_admin_direct_created');
    ok:=false;
  exception when others then ok:=true; end;
  perform pg_temp.assert_true(ok,'a Facility Administrator cannot create an Administrator');
  begin
    perform public.admin_finalize_provisioned_profile(pg_temp.u(11),jsonb_build_object('role','technician','display_name','X','trade_discipline','M','facility_id',pg_temp.u(101)),'user_admin_direct_created');
    ok:=false;
  exception when others then ok:=true; end;
  perform pg_temp.assert_true(ok,'a Facility Administrator cannot create accounts for another facility');
  begin
    perform public.admin_update_profile(pg_temp.u(3),jsonb_build_object('display_name','Renamed'));
    ok:=false;
  exception when others then ok:=true; end;
  perform pg_temp.assert_true(ok,'a Facility Administrator cannot edit another facility''s staff');
  r:=public.admin_update_profile(pg_temp.u(4),jsonb_build_object('contact_number','61234567'));
  perform pg_temp.assert_true(r->>'contact_number'='61234567','a Facility Administrator edits its own staff');

  -- D-55: the Super-Administrator removes a tester's details; the records stay under a neutral name
  perform pg_temp.act(pg_temp.u(1));
  r:=public.admin_remove_personal_details(pg_temp.u(9),'M29.9@example.test ','Tester account after UAT');
  perform pg_temp.assert_true((r->>'ok')::boolean and r->>'label' like 'Former user %','details removed: '||coalesce(r->>'code',''));
  perform pg_temp.assert_true((select email like '%@removed.invalid' and display_name like 'Former user %' and not is_active and contact_number is null from public.profiles where id=pg_temp.u(9)),'profile anonymised and switched off');
  perform pg_temp.assert_true(not exists(select 1 from public.activity_logs where note like '%m29.9@example.test%' or actor='M29 approver 9' or note like '%M29 approver 9%'),'name and email removed from the history');
  perform pg_temp.assert_true(exists(select 1 from public.work_orders where id=pg_temp.u(202)),'the Work Order record stays');
  perform pg_temp.assert_true(not exists(select 1 from public.facility_memberships where profile_id=pg_temp.u(9) and active),'memberships ended');
  perform pg_temp.assert_true(public.admin_remove_personal_details(pg_temp.u(1),'m29.1@example.test','x')->>'code'='VALIDATION_ERROR','cannot remove one''s own details');
end $t$;

-- M30: the provisioning ticket accepts every role, including Facility Manager, Finance and Facility Administrator
reset role;
insert into public.account_invitations(email,display_name,department,assigned_role,is_active,token_hash,expires_at,created_by)
select 'm30.'||r||'@example.test','M30 '||r,'Facility',r,true,md5(r),now()+interval '10 minutes',pg_temp.u(1)
from unnest(array['facility_manager','finance','facility_administrator']) r;
select pg_temp.assert_true((select count(*) from public.account_invitations where email like 'm30.%@example.test')=3,'tickets for every role');

rollback;

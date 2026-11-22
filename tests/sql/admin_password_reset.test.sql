\set ON_ERROR_STOP on
-- M41a: the Super-Administrator, or a Facility Administrator for their own facility, sets a temporary password; the
-- person must change it at the next sign-in. Rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Password reset regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d410000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
-- 1 super-administrator, 2 facility administrator A, 3 facility manager A, 4 technician B, 5 second administrator
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m41a.'||n||'@example.test',jsonb_build_object('display_name','M41a '||role||' '||n)
from (values ('administrator',1),('facility_administrator',2),('facility_manager',3),('technician',4),('administrator',5)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false
from (values ('administrator',1),('facility_administrator',2),('facility_manager',3),('technician',4),('administrator',5)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.sites(id,code,name,is_active) values (pg_temp.u(101),'M41A-A','M41a Facility A',true),(pg_temp.u(102),'M41A-B','M41a Facility B',true);
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by) values
 (pg_temp.u(101),pg_temp.u(2),'facility_administrator',pg_temp.u(1)),(pg_temp.u(101),pg_temp.u(3),'facility_manager',pg_temp.u(1)),
 (pg_temp.u(102),pg_temp.u(4),'technician',pg_temp.u(1));

select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((public.admin_require_password_change(pg_temp.u(3),'')->>'code')='VALIDATION_ERROR','a reason is required');
select pg_temp.assert_true((public.admin_require_password_change(pg_temp.u(3),'forgot password')->>'ok')::boolean,'the Super-Administrator resets the Facility Manager');
select pg_temp.assert_true((select password_change_required from public.profiles where id=pg_temp.u(3)),'who must choose a new password at the next sign-in');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where action='user_password_reset_by_administrator' and note::jsonb->>'profile_id'=pg_temp.u(3)::text and note::jsonb->>'reason'='forgot password'),'the reset is recorded with its reason');
select pg_temp.assert_true((public.admin_require_password_change(pg_temp.u(5),'x y z')->>'code')='ACCESS_DENIED','not another administrator');
select pg_temp.assert_true((public.admin_require_password_change(pg_temp.u(1),'x y z')->>'code')='ACCESS_DENIED','not oneself');
select pg_temp.act(pg_temp.u(2));
select pg_temp.assert_true((public.admin_require_password_change(pg_temp.u(4),'forgot')->>'code')='ACCESS_DENIED','a Facility Administrator not for another facility''s staff');
select pg_temp.assert_true((public.admin_require_password_change(pg_temp.u(3),'forgot again')->>'ok')::boolean,'but for their own facility''s staff');
select pg_temp.act(pg_temp.u(3));
select pg_temp.assert_true((public.admin_require_password_change(pg_temp.u(4),'forgot')->>'code')='ACCESS_DENIED','a Facility Manager cannot reset passwords');
select pg_temp.assert_true(not has_function_privilege('anon','public.admin_require_password_change(uuid,text)','execute'),'not callable without signing in');
select 'admin_password_reset tests passed' as result;
rollback;

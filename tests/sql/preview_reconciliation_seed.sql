\set ON_ERROR_STOP on
-- DISPOSABLE DATABASE ONLY. No hosted identities or operational rows are copied.
begin;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_auth_user();
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('field-evidence','field-evidence',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']);
insert into public.sites(code,name) values('CLONE','Synthetic Preview facility');
insert into public.commercial_approval_rules(rule_code,minimum_amount,maximum_amount,minimum_quotations)
values('SGD_BELOW_1000_ONE_QUOTE',0,1000,1),('SGD_1000_AND_ABOVE_THREE_QUOTES',1000,null,3);
select set_config('fmworks.profile_admin_rpc','on',true);
select set_config('fmworks.password_change_completion','on',true);
do $roles$
declare item record;
begin
 for item in select * from (values('administrator','admin'),('supervisor','supervisor'),('approver','approver'),('initiator','initiator'),('technician','technician'),('facility_manager','facility-manager'),('reviewer','reviewer')) r(role,label) loop
  insert into auth.users(id,email) values(gen_random_uuid(),'pilot.'||item.label||'@example.test');
  update public.profiles set role=item.role,is_active=true,password_change_required=false where email='pilot.'||item.label||'@example.test';
 end loop;
end;$roles$;
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select s.id,p.id,p.role,(select id from public.profiles where email='pilot.admin@example.test')
from public.sites s cross join public.profiles p where p.role in ('technician','supervisor','facility_manager');
create schema supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
commit;

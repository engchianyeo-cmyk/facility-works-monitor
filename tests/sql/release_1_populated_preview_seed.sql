\set ON_ERROR_STOP on
-- Synthetic operational data on the pre-Release-1 schema, through 0027.
begin;
insert into auth.users(id,email,raw_user_meta_data,created_at) values
 ('91000000-0000-4000-8000-000000000001','upgrade.initiator@example.test','{"display_name":"Upgrade Initiator"}','2026-08-01T00:00:00Z'),
 ('91000000-0000-4000-8000-000000000002','upgrade.technician@example.test','{"display_name":"Upgrade Technician"}','2026-08-01T00:00:00Z'),
 ('91000000-0000-4000-8000-000000000003','upgrade.reviewer@example.test','{"display_name":"Upgrade Reviewer"}','2026-08-01T00:00:00Z');
set local fmworks.profile_admin_rpc='on';
set local fmworks.password_change_completion='on';
update public.profiles set role=case id
 when '91000000-0000-4000-8000-000000000001' then 'initiator'
 when '91000000-0000-4000-8000-000000000002' then 'technician'
 else 'reviewer' end,
 is_active=true,deleted_at=null,password_change_required=false
where id in ('91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000003');
set local fmworks.profile_admin_rpc='off';
set local fmworks.password_change_completion='off';
insert into public.work_orders(
 id,work_order_number,user_id,requested_by,title,description,location,site,
 priority,status,assigned_technician_id,assigned_at,accepted_at,started_at,
 completed_at,reviewed_at,closed_at,created_at,updated_at
) values
 ('92000000-0000-4000-8000-000000000001','WO-UPGRADE-001',
 '91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001',
 'Historical active repair','Preserve this populated assignment','Loading dock','Preview facility',
 'high','in_progress','91000000-0000-4000-8000-000000000002',
 '2026-08-02T01:00:00Z','2026-08-02T02:00:00Z','2026-08-02T03:00:00Z',
 null,null,null,'2026-08-01T01:00:00Z','2026-08-02T03:00:00Z'),
 ('92000000-0000-4000-8000-000000000002','WO-UPGRADE-002',
 '91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001',
 'Historical closed repair','Preserve this terminal record','Plant room','Preview facility',
 'medium','closed','91000000-0000-4000-8000-000000000002',
 '2026-08-03T01:00:00Z','2026-08-03T02:00:00Z','2026-08-03T03:00:00Z',
 '2026-08-03T04:00:00Z','2026-08-03T05:00:00Z','2026-08-03T06:00:00Z',
 '2026-08-01T02:00:00Z','2026-08-03T06:00:00Z');
insert into public.activity_logs(id,user_id,work_order_id,action,from_status,to_status,note,created_at) values
 ('93000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002',
 '92000000-0000-4000-8000-000000000001','work_order_start','assigned','in_progress','Historical start audit','2026-08-02T03:00:00Z'),
 ('93000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000001',
 '92000000-0000-4000-8000-000000000002','work_order_close','reviewed','closed','Historical closure audit','2026-08-03T06:00:00Z');
-- Persistent snapshots span separate psql migration sessions. No browser grant.
create schema populated_preview_regression;
create table populated_preview_regression.identities as
 select id,email,created_at,raw_user_meta_data from auth.users;
create table populated_preview_regression.profiles as
 select id,email,display_name,role,is_active,deleted_at,password_change_required from public.profiles;
create table populated_preview_regression.orders as
 select id,work_order_number,user_id,requested_by,title,description,location,site,
 priority,status,assigned_technician_id,assigned_at,accepted_at,started_at,
 completed_at,reviewed_at,closed_at,created_at from public.work_orders;
create table populated_preview_regression.audit as select * from public.activity_logs;
commit;

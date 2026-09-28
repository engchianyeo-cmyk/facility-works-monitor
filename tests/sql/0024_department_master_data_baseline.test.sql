\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $function$
begin
  if not coalesce(condition, false) then
    raise exception 'ASSERTION FAILED: %', message;
  end if;
end;
$function$;

create temp table baseline_snapshot as
select id, code, name
from public.departments
where code in ('FAC', 'OPS', 'ENG', 'FIN', 'HR', 'WH', 'PROC', 'ADMIN');

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 8 from baseline_snapshot)
  and not exists (
    select 1
    from public.departments
    where code in ('FAC', 'OPS', 'ENG', 'FIN', 'HR', 'WH', 'PROC', 'ADMIN')
      and (not is_active or deleted_at is not null)
  ),
  'fresh Department master data receives all eight active non-deleted baseline rows'
);

select pg_temp.assert_true(
  not exists (
    (values
      ('FAC', 'Facility'),
      ('OPS', 'Operations'),
      ('ENG', 'Engineering'),
      ('FIN', 'Finance'),
      ('HR', 'HR'),
      ('WH', 'Warehouse'),
      ('PROC', 'Procurement'),
      ('ADMIN', 'Administration')
    )
    except
    select code, name
    from public.departments
    where is_active and deleted_at is null
  ),
  'baseline codes and names match the approved FMWorks master data'
);

insert into public.departments (
  code, name, description, cost_centre, colour_tag, is_active
) values (
  'CUST', 'Customer Department', 'Customer-owned description', 'CC-777', '#123456', true
);

\ir ../../supabase/migrations/0024_department_master_data_baseline.sql

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 8
   from public.departments
   where code in ('FAC', 'OPS', 'ENG', 'FIN', 'HR', 'WH', 'PROC', 'ADMIN')
     and is_active and deleted_at is null)
  and not exists (
    select 1
    from baseline_snapshot as snapshot
    left join public.departments as department
      on department.id = snapshot.id
     and department.code = snapshot.code
     and department.name = snapshot.name
    where department.id is null
  ),
  'rerunning the baseline is idempotent and preserves baseline identities'
);

select pg_temp.assert_true(
  exists (
    select 1
    from public.departments
    where code = 'CUST'
      and name = 'Customer Department'
      and description = 'Customer-owned description'
      and cost_centre = 'CC-777'
      and colour_tag = '#123456'
      and is_active
      and deleted_at is null
  ),
  'existing customer-created Departments remain unchanged'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  '24000000-0000-4000-8000-000000000001',
  'department-baseline-admin@example.test',
  '{"display_name":"Department Baseline Administrator"}'::jsonb
);
set fmworks.profile_admin_rpc = 'on';
update public.profiles
set role = 'administrator', is_active = true, deleted_at = null
where id = '24000000-0000-4000-8000-000000000001';
reset fmworks.profile_admin_rpc;
set fmworks.password_change_completion = 'on';
update public.profiles
set password_change_required = false
where id = '24000000-0000-4000-8000-000000000001';
reset fmworks.password_change_completion;

set role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '24000000-0000-4000-8000-000000000001',
  false
);
select pg_temp.assert_true(
  (select pg_catalog.count(*) = 9
   from public.departments
   where is_active and deleted_at is null),
  'authenticated secured read exposes active baseline and customer Departments'
);
reset role;

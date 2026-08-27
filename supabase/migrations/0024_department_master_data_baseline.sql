-- Controlled FMWorks Department master-data baseline.
-- Existing exact baseline rows are reactivated; unrelated customer rows are
-- preserved. Ambiguous active code/name collisions fail closed for review.
begin;

do $preflight$
begin
  if exists (
    with baseline(code, name) as (
      values
        ('FAC', 'Facility'),
        ('OPS', 'Operations'),
        ('ENG', 'Engineering'),
        ('FIN', 'Finance'),
        ('HR', 'HR'),
        ('WH', 'Warehouse'),
        ('PROC', 'Procurement'),
        ('ADMIN', 'Administration')
    )
    select 1
    from baseline
    join public.departments as department
      on department.deleted_at is null
     and (
       pg_catalog.lower(department.code) = pg_catalog.lower(baseline.code)
       or pg_catalog.lower(department.name) = pg_catalog.lower(baseline.name)
     )
    where not (
      pg_catalog.lower(department.code) = pg_catalog.lower(baseline.code)
      and pg_catalog.lower(department.name) = pg_catalog.lower(baseline.name)
    )
  ) then
    raise exception using
      errcode = '23505',
      message = '0024 refused: an active Department conflicts with the FMWorks baseline';
  end if;
end;
$preflight$;

with baseline(code, name) as (
  values
    ('FAC', 'Facility'),
    ('OPS', 'Operations'),
    ('ENG', 'Engineering'),
    ('FIN', 'Finance'),
    ('HR', 'HR'),
    ('WH', 'Warehouse'),
    ('PROC', 'Procurement'),
    ('ADMIN', 'Administration')
), canonical as (
  select distinct on (baseline.code)
    department.id
  from baseline
  join public.departments as department
    on pg_catalog.lower(department.code) = pg_catalog.lower(baseline.code)
   and pg_catalog.lower(department.name) = pg_catalog.lower(baseline.name)
  order by
    baseline.code,
    (department.deleted_at is null) desc,
    department.created_at,
    department.id
)
update public.departments as department
set is_active = true,
    deleted_at = null
from canonical
where department.id = canonical.id
  and (not department.is_active or department.deleted_at is not null);

with baseline(code, name) as (
  values
    ('FAC', 'Facility'),
    ('OPS', 'Operations'),
    ('ENG', 'Engineering'),
    ('FIN', 'Finance'),
    ('HR', 'HR'),
    ('WH', 'Warehouse'),
    ('PROC', 'Procurement'),
    ('ADMIN', 'Administration')
)
insert into public.departments (code, name, description, is_active)
select
  baseline.code,
  baseline.name,
  'FMWorks controlled baseline department.',
  true
from baseline
where not exists (
  select 1
  from public.departments as department
  where department.deleted_at is null
    and pg_catalog.lower(department.code) = pg_catalog.lower(baseline.code)
    and pg_catalog.lower(department.name) = pg_catalog.lower(baseline.name)
);

do $postcondition$
begin
  if (
    with baseline(code, name) as (
      values
        ('FAC', 'Facility'),
        ('OPS', 'Operations'),
        ('ENG', 'Engineering'),
        ('FIN', 'Finance'),
        ('HR', 'HR'),
        ('WH', 'Warehouse'),
        ('PROC', 'Procurement'),
        ('ADMIN', 'Administration')
    )
    select pg_catalog.count(*)
    from baseline
    join public.departments as department
      on pg_catalog.lower(department.code) = pg_catalog.lower(baseline.code)
     and pg_catalog.lower(department.name) = pg_catalog.lower(baseline.name)
     and department.is_active
     and department.deleted_at is null
  ) <> 8 then
    raise exception using
      errcode = '55000',
      message = '0024 refused: FMWorks Department baseline postcondition failed';
  end if;
end;
$postcondition$;

commit;

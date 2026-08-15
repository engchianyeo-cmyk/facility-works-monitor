\set ON_ERROR_STOP on

begin transaction read only;

do $assertions$
declare
  missing text;
begin
  select pg_catalog.string_agg(required.object_name, ', ' order by required.object_name)
  into missing
  from (values
    ('public.profiles'),
    ('public.categories'),
    ('public.work_orders'),
    ('public.activity_logs'),
    ('public.account_invitations'),
    ('public.work_order_number_counters'),
    ('public.notification_outbox')
  ) as required(object_name)
  where pg_catalog.to_regclass(required.object_name) is null;

  if missing is not null then
    raise exception 'Missing bootstrap objects: %', missing;
  end if;

  if (select pg_catalog.count(*) from auth.users) <> 0
    or (select pg_catalog.count(*) from public.profiles) <> 0
    or (select pg_catalog.count(*) from public.categories) <> 0
    or (select pg_catalog.count(*) from public.work_orders) <> 0
    or (select pg_catalog.count(*) from public.activity_logs) <> 0
    or (select pg_catalog.count(*) from public.notification_outbox) <> 0 then
    raise exception 'Bootstrap introduced user, reference, or historical operational data';
  end if;

  if has_table_privilege('anon', 'public.work_orders', 'SELECT')
    or has_table_privilege('anon', 'public.work_orders', 'INSERT')
    or has_table_privilege('anon', 'public.work_orders', 'UPDATE')
    or has_table_privilege('anon', 'public.work_orders', 'DELETE')
    or has_table_privilege('authenticated', 'public.work_orders', 'INSERT')
    or has_table_privilege('authenticated', 'public.work_orders', 'UPDATE')
    or has_table_privilege('authenticated', 'public.work_orders', 'DELETE')
    or has_table_privilege('authenticated', 'public.notification_outbox', 'INSERT') then
    raise exception 'Bootstrap operational grants are broader than approved';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_default_acl as defaults
    cross join lateral pg_catalog.aclexplode(defaults.defaclacl) as privilege
    join pg_catalog.pg_roles as grantee on grantee.oid = privilege.grantee
    join pg_catalog.pg_namespace as namespace on namespace.oid = defaults.defaclnamespace
    where defaults.defaclrole = (select oid from pg_catalog.pg_roles where rolname = 'postgres')
      and namespace.nspname = 'public'
      and grantee.rolname in ('anon', 'authenticated')
      and privilege.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'EXECUTE', 'USAGE')
  ) then
    raise exception 'Migration-role default privileges remain broader than approved';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'auth.users'::regclass
      and tgname = 'on_auth_user_created'
      and not tgisinternal
  ) then
    raise exception 'Auth profile trigger is missing';
  end if;

  if pg_catalog.to_regprocedure('public.current_user_role()') is null
    or pg_catalog.to_regprocedure('public.handle_new_auth_user()') is null
    or pg_catalog.to_regprocedure('public.next_work_order_number(timestamp with time zone)') is null then
    raise exception 'Required bootstrap function is missing';
  end if;

  if exists (
    select 1 from storage.buckets
    where id in ('work-order-evidence', 'field-evidence')
  ) then
    raise exception 'Bootstrap must not create legacy or later evidence buckets';
  end if;
end;
$assertions$;

select 'fmworks_pre_0012_bootstrap' as suite, 12 as assertions_passed;

rollback;

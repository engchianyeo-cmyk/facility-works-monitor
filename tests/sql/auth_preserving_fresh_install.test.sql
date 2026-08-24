\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $function$
begin
  if not coalesce(condition, false) then
    raise exception 'ASSERTION FAILED: %', message;
  end if;
end;
$function$;

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 2 from auth.users)
  and (select pg_catalog.count(*) = 2 from pg_temp.fmworks_preserved_auth_ids)
  and not exists (
    select existing.id from auth.users existing
    except select allowed.id from pg_temp.fmworks_preserved_auth_ids allowed
  )
  and not exists (
    select allowed.id from pg_temp.fmworks_preserved_auth_ids allowed
    except select existing.id from auth.users existing
  ),
  'exactly two synthetic Auth identities are preserved'
);

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 2
   from public.profiles
   where role = 'reviewer'
     and is_active = false
     and password_change_required = true
     and deleted_at is null
     and department_id is null
     and trade_discipline is null
     and contact_number is null)
  and not exists (select 1 from public.profiles where role = 'administrator'),
  'preserved profiles use only quarantine defaults and infer no Administrator'
);

select pg_temp.assert_true(
  not exists (
    select 1 from pg_temp.fmworks_preserved_auth_ids allowed
    where public.pilot_account_ready(allowed.id)
  ),
  'preserved identities are not application-ready'
);

set role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000001', true);
select pg_temp.assert_true(public.current_user_role() is null, 'preserved user has no application role');
select pg_temp.assert_true(not public.record_user_presence('/operations'), 'preserved user cannot record presence');
reset role;

select pg_temp.assert_true(
  not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'INSERT')
  and not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'DELETE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.work_orders', 'INSERT')
  and not pg_catalog.has_table_privilege('authenticated', 'public.work_orders', 'UPDATE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.work_orders', 'DELETE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.activity_logs', 'INSERT')
  and not pg_catalog.has_table_privilege('authenticated', 'public.activity_logs', 'UPDATE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.activity_logs', 'DELETE'),
  'protected profile and operational DML remain denied'
);

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 0 from public.work_orders)
  and (select pg_catalog.count(*) = 0 from public.activity_logs)
  and (select pg_catalog.count(*) = 0 from public.incidents)
  and (select pg_catalog.count(*) = 0 from public.assets)
  and (select pg_catalog.count(*) = 0 from public.notification_outbox)
  and (select pg_catalog.count(*) = 0 from public.evidence_items)
  and (select pg_catalog.count(*) = 0 from storage.objects),
  'reconciliation creates no business records or Storage objects'
);

select 'auth-preserving fresh-install assertions passed' as result;

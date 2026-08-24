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

create or replace function pg_temp.assert_raises(
  statement text,
  expected_message text,
  assertion_message text
)
returns void
language plpgsql
as $function$
declare
  caught_message text;
begin
  begin
    execute statement;
  exception when others then
    caught_message := sqlerrm;
  end;

  if caught_message is null then
    raise exception 'ASSERTION FAILED: % (statement unexpectedly succeeded)', assertion_message;
  end if;
  if pg_catalog.strpos(caught_message, expected_message) = 0 then
    raise exception 'ASSERTION FAILED: % (unexpected error: %)', assertion_message, caught_message;
  end if;
end;
$function$;

create or replace function pg_temp.assert_all_public_tables_empty(message text)
returns void
language plpgsql
as $function$
declare
  relation_record record;
  contains_rows boolean;
begin
  for relation_record in
    select relation.oid as relation_oid
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relkind in ('r', 'p')
    order by relation.relname
  loop
    execute pg_catalog.format(
      'select exists(select 1 from %s limit 1)',
      relation_record.relation_oid::pg_catalog.regclass
    ) into contains_rows;

    if contains_rows then
      raise exception 'ASSERTION FAILED: % (rows found in %)',
        message,
        relation_record.relation_oid::pg_catalog.regclass;
    end if;
  end loop;
end;
$function$;

begin;

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 2
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'profiles'
     and (
       (column_name = 'last_active_at'
        and data_type = 'timestamp with time zone'
        and is_nullable = 'YES'
        and column_default is null)
       or
       (column_name = 'last_seen_route'
        and data_type = 'text'
        and is_nullable = 'YES'
        and column_default is null)
     )),
  'presence columns use the established nullable, no-default types'
);

select pg_temp.assert_true(
  exists(
    select 1
    from pg_catalog.pg_index as index_record
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_record.indexrelid
    join pg_catalog.pg_am as access_method
      on access_method.oid = index_relation.relam
    join pg_catalog.pg_attribute as indexed_column
      on indexed_column.attrelid = index_record.indrelid
      and indexed_column.attnum = index_record.indkey[0]
    where index_record.indexrelid = 'public.profiles_last_active_at_idx'::pg_catalog.regclass
      and index_record.indrelid = 'public.profiles'::pg_catalog.regclass
      and index_record.indisvalid
      and index_record.indisready
      and not index_record.indisunique
      and not index_record.indisprimary
      and index_record.indnkeyatts = 1
      and index_record.indnatts = 1
      and index_record.indexprs is null
      and indexed_column.attname = 'last_active_at'
      and (index_record.indoption[0] & 1) = 1
      and access_method.amname = 'btree'
      and pg_catalog.pg_get_indexdef(index_record.indexrelid) like '%(last_active_at DESC)%'
      and pg_catalog.pg_get_indexdef(index_record.indexrelid) like '%WHERE ((is_active = true) AND (deleted_at IS NULL))%'
  ),
  'presence index is the historical active, non-archived descending index'
);

select pg_temp.assert_true(
  (select pg_catalog.bool_and(
      procedure.prosecdef
      and procedure.proconfig = array['search_path=pg_catalog']::text[]
    )
   from pg_catalog.pg_proc as procedure
   where procedure.oid in (
     'public.record_user_presence(text)'::pg_catalog.regprocedure,
     'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure,
     'public.protect_profile_deletion()'::pg_catalog.regprocedure,
     'public.handle_new_auth_user()'::pg_catalog.regprocedure
   )),
  'all repaired functions are SECURITY DEFINER with the fixed pg_catalog path'
);

select pg_temp.assert_true(
  not pg_catalog.has_function_privilege('public', 'public.record_user_presence(text)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('anon', 'public.record_user_presence(text)', 'EXECUTE')
  and pg_catalog.has_function_privilege('authenticated', 'public.record_user_presence(text)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('service_role', 'public.record_user_presence(text)', 'EXECUTE'),
  'presence RPC execution is authenticated-only'
);

select pg_temp.assert_true(
  not pg_catalog.has_function_privilege('public', 'public.protect_profile_authorization_fields()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('anon', 'public.protect_profile_authorization_fields()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated', 'public.protect_profile_authorization_fields()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('service_role', 'public.protect_profile_authorization_fields()', 'EXECUTE'),
  'profile authorization trigger function has no client execution surface'
);

select pg_temp.assert_true(
  not pg_catalog.has_function_privilege('public', 'public.protect_profile_deletion()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('anon', 'public.protect_profile_deletion()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated', 'public.protect_profile_deletion()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('service_role', 'public.protect_profile_deletion()', 'EXECUTE'),
  'profile deletion trigger function has no client execution surface'
);

select pg_temp.assert_true(
  not pg_catalog.has_function_privilege('public', 'public.handle_new_auth_user()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('anon', 'public.handle_new_auth_user()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated', 'public.handle_new_auth_user()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('service_role', 'public.handle_new_auth_user()', 'EXECUTE'),
  'Auth provisioning trigger function has no client execution surface'
);

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 1
   from pg_catalog.pg_trigger as trigger_record
   where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
     and trigger_record.tgname = 'protect_profile_authorization_fields'
     and not trigger_record.tgisinternal
     and trigger_record.tgenabled <> 'D'
     and trigger_record.tgfoid = 'public.protect_profile_authorization_fields()'::pg_catalog.regprocedure
     and (trigger_record.tgtype & 1) = 1
     and (trigger_record.tgtype & 2) = 2
     and (trigger_record.tgtype & 16) = 16),
  'profile authorization trigger is attached before row updates'
);

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 1
   from pg_catalog.pg_trigger as trigger_record
   where trigger_record.tgrelid = 'public.profiles'::pg_catalog.regclass
     and trigger_record.tgname = 'protect_profile_deletion'
     and not trigger_record.tgisinternal
     and trigger_record.tgenabled <> 'D'
     and trigger_record.tgfoid = 'public.protect_profile_deletion()'::pg_catalog.regprocedure
     and (trigger_record.tgtype & 1) = 1
     and (trigger_record.tgtype & 2) = 2
     and (trigger_record.tgtype & 8) = 8),
  'profile deletion guard is attached before row deletes'
);

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 1
   from pg_catalog.pg_trigger as trigger_record
   where trigger_record.tgrelid = 'auth.users'::pg_catalog.regclass
     and trigger_record.tgname = 'on_auth_user_created'
     and not trigger_record.tgisinternal
     and trigger_record.tgenabled = 'O'
     and trigger_record.tgfoid = 'public.handle_new_auth_user()'::pg_catalog.regprocedure
     and (trigger_record.tgtype & 1) = 1
     and (trigger_record.tgtype & 2) = 0
     and (trigger_record.tgtype & 4) = 4
     and (trigger_record.tgtype & (8 | 16 | 32 | 64)) = 0),
  'Auth provisioning trigger is enabled for ordinary after-row inserts'
);

select pg_temp.assert_true(
  pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'public.handle_new_auth_user()'::pg_catalog.regprocedure
    ),
    'extensions.digest'
  ) > 0,
  'invitation provisioning explicitly resolves digest from extensions'
);

select pg_temp.assert_true(
  not pg_catalog.has_table_privilege('anon', 'public.profiles', 'SELECT,INSERT,UPDATE,DELETE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'INSERT,UPDATE,DELETE'),
  'existing profile table grants remain fail closed'
);

select pg_temp.assert_true(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.admin_record_permanent_delete_result(uuid,uuid,boolean,text)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'service_role',
    'public.admin_record_permanent_delete_result(uuid,uuid,boolean,text)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'public.complete_password_change_trusted(uuid)',
    'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'service_role',
    'public.complete_password_change_trusted(uuid)',
    'EXECUTE'
  ),
  '0020 service-only trust boundaries remain intact'
);

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 0 from auth.users)
  and (select pg_catalog.count(*) = 0 from storage.objects),
  'fresh repaired chain begins with empty Auth and Storage object state'
);
select pg_temp.assert_all_public_tables_empty(
  'fresh repaired chain begins with every public application table empty'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'a1000000-0000-4000-8000-000000000001',
  'administrator@example.test',
  '{}'::jsonb
);

select pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
update public.profiles
set
  display_name = 'UAT Administrator',
  role = 'administrator',
  is_active = true,
  password_change_required = false
where id = 'a1000000-0000-4000-8000-000000000001';
select pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'a1000000-0000-4000-8000-000000000002',
  'reviewer@example.test',
  '{}'::jsonb
);

set role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select public.record_user_presence('/operations?private=query') as result
\gset presence_
reset role;

select pg_temp.assert_true(
  :'presence_result'::boolean
  and (select last_active_at is not null and last_seen_route = '/operations'
       from public.profiles
       where id = 'a1000000-0000-4000-8000-000000000001')
  and (select last_active_at is null and last_seen_route is null
       from public.profiles
       where id = 'a1000000-0000-4000-8000-000000000002'),
  'presence derives its actor, sanitizes the route and updates only that profile'
);

grant update (role, password_change_required) on public.profiles to authenticated;
set role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select pg_temp.assert_raises(
  $sql$update public.profiles
       set role = 'supervisor'
       where id = 'a1000000-0000-4000-8000-000000000001'$sql$,
  'Role, activation and archive changes require the audited Administrator operation',
  'authorization trigger rejects a direct protected-field change'
);
select pg_temp.assert_raises(
  $sql$update public.profiles
       set password_change_required = true
       where id = 'a1000000-0000-4000-8000-000000000001'$sql$,
  'Password readiness can only be changed by a trusted server operation',
  'authorization trigger rejects a direct password-readiness change'
);
reset role;

select pg_temp.assert_true(
  (select role = 'administrator' and password_change_required = false
   from public.profiles
   where id = 'a1000000-0000-4000-8000-000000000001'),
  'rejected protected-field mutations leave authorization state unchanged'
);

set role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select public.admin_update_profile(
  'a1000000-0000-4000-8000-000000000002',
  pg_catalog.jsonb_build_object(
    'display_name', 'Reviewer Updated',
    'role', 'reviewer',
    'is_active', true
  )
);
reset role;
select pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);

select pg_temp.assert_true(
  (select display_name = 'Reviewer Updated' and is_active = true
   from public.profiles
   where id = 'a1000000-0000-4000-8000-000000000002')
  and exists(
    select 1
    from public.activity_logs
    where action = 'user_admin_profile_updated'
      and note like '%a1000000-0000-4000-8000-000000000002%'
  ),
  'approved Administrator profile mutation and audit still succeed atomically'
);

set role service_role;
select public.complete_password_change_trusted(
  'a1000000-0000-4000-8000-000000000002'
);
reset role;
select pg_catalog.set_config('fmworks.password_change_completion', 'off', true);

select pg_temp.assert_true(
  (select password_change_required = false
   from public.profiles
   where id = 'a1000000-0000-4000-8000-000000000002'),
  'trusted password completion remains compatible with the restored trigger'
);

set role service_role;
select pg_temp.assert_raises(
  $sql$delete from public.profiles
       where id = 'a1000000-0000-4000-8000-000000000002'$sql$,
  'Profiles can only be permanently deleted through the trusted Auth deletion workflow',
  'service-role direct profile deletion cannot bypass the Auth workflow'
);
reset role;

select pg_temp.assert_raises(
  $sql$delete from auth.users
       where id = 'a1000000-0000-4000-8000-000000000001'$sql$,
  'The final ready Administrator cannot be permanently deleted',
  'Auth cascade cannot delete the final ready Administrator'
);

select pg_temp.assert_true(
  exists(select 1 from auth.users where id = 'a1000000-0000-4000-8000-000000000001')
  and exists(select 1 from public.profiles where id = 'a1000000-0000-4000-8000-000000000001'),
  'rejected final-Administrator cascade rolls back both Auth and profile deletion'
);

insert into public.work_orders (
  id,
  user_id,
  requested_by,
  title,
  location,
  priority,
  status,
  assigned_technician_id,
  assigned_by_user_id,
  work_order_number,
  submitted_at,
  approved_at,
  assigned_at
) values (
  'a2000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  '0021 active-assignment guard fixture',
  'Disposable test location',
  'medium',
  'assigned',
  'a1000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000001',
  'FW-2099-000001',
  pg_catalog.now(),
  pg_catalog.now(),
  pg_catalog.now()
);

select pg_temp.assert_raises(
  $sql$delete from auth.users
       where id = 'a1000000-0000-4000-8000-000000000002'$sql$,
  'Active work assignments must be reassigned before permanent deletion',
  'Auth cascade cannot delete a profile with an active Work Order assignment'
);
select pg_temp.assert_true(
  exists(select 1 from auth.users where id = 'a1000000-0000-4000-8000-000000000002')
  and exists(select 1 from public.profiles where id = 'a1000000-0000-4000-8000-000000000002')
  and exists(select 1 from public.work_orders
             where id = 'a2000000-0000-4000-8000-000000000001'
               and assigned_technician_id = 'a1000000-0000-4000-8000-000000000002'),
  'rejected assigned-profile cascade leaves Auth, profile and Work Order intact'
);

update public.work_orders
set assigned_technician_id = null
where id = 'a2000000-0000-4000-8000-000000000001';

set role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
select public.admin_prepare_permanent_profile_deletion(
  'a1000000-0000-4000-8000-000000000002',
  'reviewer@example.test'
);
reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

delete from auth.users
where id = 'a1000000-0000-4000-8000-000000000002';

select pg_temp.assert_true(
  not exists(select 1 from auth.users where id = 'a1000000-0000-4000-8000-000000000002')
  and not exists(select 1 from public.profiles where id = 'a1000000-0000-4000-8000-000000000002'),
  'approved non-Administrator Auth deletion cascades through the profile guard'
);

set role service_role;
select public.admin_record_permanent_delete_result(
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000002',
  true,
  null
);
reset role;

select pg_temp.assert_true(
  exists(
    select 1
    from public.activity_logs
    where action = 'user_admin_permanent_deletion_completed'
      and note like '%a1000000-0000-4000-8000-000000000002%'
  ),
  'service-only permanent-delete result audit remains available'
);

insert into public.account_invitations (
  email,
  display_name,
  department,
  assigned_role,
  is_active,
  token_hash,
  expires_at,
  created_by
) values (
  'invited-technician@example.test',
  'Invited Technician',
  'Engineering',
  'technician',
  true,
  pg_catalog.encode(extensions.digest('uat-005-invitation-token', 'sha256'), 'hex'),
  pg_catalog.now() + interval '10 minutes',
  'a1000000-0000-4000-8000-000000000001'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'a1000000-0000-4000-8000-000000000003',
  'invited-technician@example.test',
  pg_catalog.jsonb_build_object(
    'administrator_invitation_token', 'uat-005-invitation-token',
    'trade_discipline', 'Electrical',
    'contact_number', '+65 6000 0000'
  )
);

select pg_temp.assert_true(
  (select
     display_name = 'Invited Technician'
     and role = 'technician'
     and is_active = false
     and password_change_required = true
     and trade_discipline = 'Electrical'
   from public.profiles
   where id = 'a1000000-0000-4000-8000-000000000003')
  and (select used_at is not null
       from public.account_invitations
       where email = 'invited-technician@example.test'),
  'invitation provisioning resolves extensions.digest and creates a quarantined profile'
);

rollback;

select pg_temp.assert_true(
  (select pg_catalog.count(*) = 0 from auth.users)
  and (select pg_catalog.count(*) = 0 from storage.objects),
  'focused assertions roll back all Auth and Storage object fixtures'
);
select pg_temp.assert_all_public_tables_empty(
  'focused assertions roll back every public application-table fixture'
);

select '0021 fresh-install trust-contract assertions passed' as result;

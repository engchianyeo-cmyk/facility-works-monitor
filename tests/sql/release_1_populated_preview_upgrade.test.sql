\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.assert_true(value boolean,message text)
returns void language plpgsql as $$
begin
 if value is not true then raise exception 'Populated Preview upgrade regression failed: %',message; end if;
end;
$$;
select pg_temp.assert_true((select count(*)=3 from populated_preview_regression.identities),'pre-upgrade identity fixture is populated');
select pg_temp.assert_true((select count(*)=2 from populated_preview_regression.orders),'pre-upgrade operational fixture is populated');
select pg_temp.assert_true(not exists(
 select 1 from populated_preview_regression.identities s
 left join auth.users u on u.id=s.id
 where u.id is null or to_jsonb(s) is distinct from
 jsonb_build_object('id',u.id,'email',u.email,'created_at',u.created_at,'raw_user_meta_data',u.raw_user_meta_data)
),'Auth identity/history preservation');
select pg_temp.assert_true(not exists(
 select 1 from populated_preview_regression.profiles s
 left join public.profiles p on p.id=s.id
 where p.id is null or to_jsonb(s) is distinct from
 jsonb_build_object('id',p.id,'email',p.email,'display_name',p.display_name,'role',p.role,
 'is_active',p.is_active,'deleted_at',p.deleted_at,'password_change_required',p.password_change_required)
),'profile identity and authorization preservation');
select pg_temp.assert_true(not exists(
 select 1 from populated_preview_regression.orders s
 left join public.work_orders w on w.id=s.id
 where w.id is null or to_jsonb(s) is distinct from
 (select jsonb_object_agg(k,to_jsonb(w)->k) from jsonb_object_keys(to_jsonb(s)) k)
),'Work Order content, ownership, lifecycle and assignment timestamp preservation');
select pg_temp.assert_true(not exists(
 select 1 from populated_preview_regression.audit s
 left join public.activity_logs a on a.id=s.id
 where a.id is null or to_jsonb(s) is distinct from to_jsonb(a)
),'historical audit preservation');
select pg_temp.assert_true((select count(*)=2 from public.work_orders w
 join public.sites s on s.id=w.facility_id
 where w.id in ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002')
 and s.code='UAT-FAC-001' and s.is_active),'active and terminal Work Order facility backfill');
select pg_temp.assert_true(exists(select 1 from public.facility_memberships m
 join public.sites s on s.id=m.facility_id
 where m.profile_id='91000000-0000-4000-8000-000000000002'
 and m.membership_role='technician' and m.active and s.code='UAT-FAC-001'),
 'historical assignment backfills Technician facility membership');
select pg_temp.assert_true(has_table_privilege('authenticated','public.work_orders','SELECT')
 and not has_table_privilege('anon','public.work_orders','SELECT')
 and not has_table_privilege('authenticated','public.work_orders','INSERT')
 and not has_table_privilege('authenticated','public.work_orders','UPDATE')
 and not has_table_privilege('authenticated','public.work_orders','DELETE'),
 'direct privileges preserve scoped reads and prevent workflow bypass');
select pg_temp.assert_true((select relrowsecurity from pg_class where oid='public.work_orders'::regclass),'Work Order RLS remains enabled');
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((select count(*)=2 from public.work_orders
 where id in ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002')),
 'Initiator retains visibility of own historical Work Orders');
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=2 from public.work_orders
 where id in ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002')),
 'assigned Technician retains facility-scoped historical visibility');
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.work_orders
 where id in ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002')),
 'unrelated Reviewer cannot read historical Work Orders');
reset role;
rollback;

\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Commercial scope regression: %',message; end if; end;$$;
insert into auth.users(id,email,raw_user_meta_data)
select ('ca000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'scope.'||role||'@example.test',jsonb_build_object('display_name',role)
from (values ('reviewer',1),('initiator',2),('supervisor',3),('facility_manager',4),('technician',5),('approver',6),('administrator',7)) actors(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false
from (values ('reviewer',1),('initiator',2),('supervisor',3),('facility_manager',4),('technician',5),('approver',6),('administrator',7)) a(role,n)
where p.id=('ca000000-0000-4000-8000-'||lpad(a.n::text,12,'0'))::uuid;
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
insert into public.work_order_cost_lines(work_order_id,cost_type,description,quantity,unit,unit_rate,entered_by,cost_phase)
select id,'service','Scope test',1,'job',620,requested_by,'actual' from public.work_orders where work_order_number='WO-TEST-003';
insert into public.work_order_financial_controls(work_order_id,estimated_cost,cost_status)
select id,650,'draft' from public.work_orders where work_order_number='WO-TEST-003';
insert into public.contractor_payment_assessments(work_order_id,vendor_id,assessed_amount)
select id,'08000000-0000-4000-8000-000000000203',620 from public.work_orders where work_order_number='WO-TEST-003';
create temp table scope_audit_snapshot as select count(*) amount from public.activity_logs where work_order_id='08000000-0000-4000-8000-000000000003';

set local role authenticated;
do $test$
declare actor uuid; function_row record; call_arguments text; result jsonb; actor_number integer;
begin
  for actor_number in 1..5 loop
    actor:=('ca000000-0000-4000-8000-'||lpad(actor_number::text,12,'0'))::uuid;
    perform set_config('request.jwt.claim.sub',actor::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
    perform pg_temp.assert_true(not public.release1_work_order_visible('08000000-0000-4000-8000-000000000003'),'unrelated actor cannot see Work Order');
    perform pg_temp.assert_true(not exists(select 1 from public.work_order_cost_lines where work_order_id='08000000-0000-4000-8000-000000000003'),'unrelated actor cannot read actual costs');
    perform pg_temp.assert_true(not exists(select 1 from public.work_order_financial_controls where work_order_id='08000000-0000-4000-8000-000000000003'),'unrelated actor cannot read financial controls');
    perform pg_temp.assert_true(not exists(select 1 from public.contractor_payment_assessments where work_order_id='08000000-0000-4000-8000-000000000003'),'unrelated actor cannot read payments');
    -- Exercise every wrapped read/mutation entry point before any malformed
    -- subordinate record or payload could reveal information or change data.
    for function_row in
      select p.proname,p.proargtypes from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname like '%\_r1\_scope\_core' escape '\'
    loop
      select string_agg(case t.typname
        when 'uuid' then quote_literal('08000000-0000-4000-8000-000000000003')||'::uuid'
        when 'jsonb' then quote_literal('{}')||'::jsonb'
        when 'text' then quote_literal('Synthetic cross-scope attempt')||'::text'
        when 'int8' then '10::bigint'
        else 'null::'||format_type(t.oid,null) end,', ' order by ordinal)
        into call_arguments from unnest(function_row.proargtypes) with ordinality args(type_id,ordinal)
        join pg_type t on t.oid=args.type_id;
      execute format('select public.%I(%s)',regexp_replace(function_row.proname,'_r1_scope_core$',''),call_arguments) into result;
      perform pg_temp.assert_true(result->>'code'='ACCESS_DENIED',function_row.proname||' must deny unrelated actor');
    end loop;
  end loop;
end;
$test$;
reset role;
select pg_temp.assert_true((select count(*)=(select amount from scope_audit_snapshot) from public.activity_logs where work_order_id='08000000-0000-4000-8000-000000000003'),'denied RPC family creates no audit');
select pg_temp.assert_true((select estimated_cost=650 from public.work_order_financial_controls where work_order_id='08000000-0000-4000-8000-000000000003'),'denied family preserves financial control');

-- Requesters retain their own financial reads; authorized managers retain theirs.
update public.work_orders set requested_by='ca000000-0000-4000-8000-000000000001' where id='08000000-0000-4000-8000-000000000003';
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select w.facility_id,p.id,p.role,'ca000000-0000-4000-8000-000000000007' from public.work_orders w cross join public.profiles p
where w.id='08000000-0000-4000-8000-000000000003' and p.id in ('ca000000-0000-4000-8000-000000000003','ca000000-0000-4000-8000-000000000004','ca000000-0000-4000-8000-000000000005');
set local role authenticated;
do $test$
declare actor_number integer; actor uuid;
begin
  foreach actor_number in array array[1,3,4,5,6,7] loop
    actor:=('ca000000-0000-4000-8000-'||lpad(actor_number::text,12,'0'))::uuid;
    perform set_config('request.jwt.claim.sub',actor::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
    perform pg_temp.assert_true(public.release1_work_order_visible('08000000-0000-4000-8000-000000000003'),'authorized actor retains Work Order visibility');
    perform pg_temp.assert_true((select count(*)=1 from public.work_order_cost_lines where work_order_id='08000000-0000-4000-8000-000000000003'),'authorized actor reads actual costs');
    perform pg_temp.assert_true((select count(*)=1 from public.work_order_financial_controls where work_order_id='08000000-0000-4000-8000-000000000003'),'authorized actor reads financial controls');
    perform pg_temp.assert_true((select count(*)=1 from public.contractor_payment_assessments where work_order_id='08000000-0000-4000-8000-000000000003'),'authorized actor reads payment');
    perform pg_temp.assert_true((public.work_order_closure_readiness('08000000-0000-4000-8000-000000000003')->>'ok')::boolean,'authorized readiness remains available');
  end loop;
end;
$test$;
reset role;
rollback;

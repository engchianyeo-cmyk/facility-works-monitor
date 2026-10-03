\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Procurement policy regression: %',message; end if; end;$$;

-- Synthetic identities only; all mutations roll back.
insert into auth.users(id,email,raw_user_meta_data)
select ('aa000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,role||'@policy.example.test',jsonb_build_object('display_name',role)
from unnest(array['reviewer','initiator','approver','technician','supervisor','facility_manager','administrator']) with ordinality as roles(role,n);
select set_config('fmworks.profile_admin_rpc','on',true);
select set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=roles.role,is_active=true,password_change_required=false
from unnest(array['reviewer','initiator','approver','technician','supervisor','facility_manager','administrator']) with ordinality as roles(role,n)
where p.id=('aa000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
select set_config('fmworks.profile_admin_rpc','off',true);
select set_config('fmworks.password_change_completion','off',true);

do $test$
declare version uuid; next_version uuid; result jsonb; actor uuid; n integer; old_order uuid; new_order uuid; old_rule uuid; old_control jsonb; audit_count integer;
begin
  select version_id into version from public.procurement_company_policy;
  perform pg_temp.assert_true((select low_value_threshold=1000 from public.procurement_policy_versions where id=version),'initial S$1,000 policy');
  for n in 1..5 loop
    actor:=('aa000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
    perform set_config('request.jwt.claim.sub',actor::text,true);
    result:=public.change_procurement_policy(2000,'Unauthorized attempt',version);
    perform pg_temp.assert_true(result->>'code'='ACCESS_DENIED','non-FM/non-Administrator policy change denied');
  end loop;
  actor:='aa000000-0000-4000-8000-000000000007';
  perform set_config('request.jwt.claim.sub',actor::text,true);
  result:=public.create_work_order('{"title":"Historical procurement","location":"Synthetic test"}'::jsonb);
  perform pg_temp.assert_true((result->>'ok')::boolean,'create historical order');
  old_order:=(result->'work_order'->>'id')::uuid;
  insert into public.work_order_financial_controls(work_order_id,estimated_cost) values(old_order,1000) returning rule_id into old_rule;
  select to_jsonb(c) into old_control from public.work_order_financial_controls c where work_order_id=old_order;
  perform pg_temp.assert_true((select minimum_quotations=3 from public.commercial_approval_rules where id=old_rule),'boundary requires three quotes');
  perform pg_temp.assert_true(public.change_procurement_policy(0,'Invalid threshold',version)->>'code'='VALIDATION_ERROR','zero denied');
  perform pg_temp.assert_true(public.change_procurement_policy(2000,'',version)->>'code'='VALIDATION_ERROR','missing reason denied');
  perform pg_temp.assert_true(public.change_procurement_policy(2000.001,'Invalid precision',version)->>'code'='VALIDATION_ERROR','fractional cent denied');
  perform pg_temp.assert_true(public.change_procurement_policy('NaN'::numeric,'Invalid number',version)->>'code'='VALIDATION_ERROR','NaN denied');
  perform set_config('request.jwt.claim.sub','aa000000-0000-4000-8000-000000000006',true);
  result:=public.change_procurement_policy(2000,'Updated company procurement policy',version);
  perform pg_temp.assert_true((result->>'ok')::boolean,'Facility Manager changes policy');
  next_version:=(result->>'version_id')::uuid;
  perform pg_temp.assert_true((select to_jsonb(c)=old_control from public.work_order_financial_controls c where work_order_id=old_order),'historical control unchanged');
  perform pg_temp.assert_true(public.change_procurement_policy(3000,'Stale edit',version)->>'code'='POLICY_CONFLICT','stale change denied');
  perform set_config('request.jwt.claim.sub',actor::text,true);
  result:=public.create_work_order('{"title":"New procurement","location":"Synthetic test"}'::jsonb);
  new_order:=(result->'work_order'->>'id')::uuid;
  -- A forged historical version is ignored for new controls.
  insert into public.work_order_financial_controls(work_order_id,estimated_cost,policy_version_id,rule_id) values(new_order,1000,version,old_rule);
  perform pg_temp.assert_true((select c.policy_version_id=next_version and r.minimum_quotations=1 from public.work_order_financial_controls c join public.commercial_approval_rules r on r.id=c.rule_id where c.work_order_id=new_order),'new control uses current policy');
  update public.work_order_financial_controls set estimated_cost=1999.99 where work_order_id=new_order;
  perform pg_temp.assert_true((select r.minimum_quotations=1 from public.work_order_financial_controls c join public.commercial_approval_rules r on r.id=c.rule_id where c.work_order_id=new_order),'below threshold requires one');
  update public.work_order_financial_controls set estimated_cost=2000 where work_order_id=new_order;
  perform pg_temp.assert_true((select r.minimum_quotations=3 from public.work_order_financial_controls c join public.commercial_approval_rules r on r.id=c.rule_id where c.work_order_id=new_order),'at threshold requires three');
  update public.work_order_financial_controls set policy_version_id=next_version where work_order_id=old_order;
  perform pg_temp.assert_true((select policy_version_id=version and rule_id=old_rule from public.work_order_financial_controls where work_order_id=old_order),'existing policy cannot be rebound');
  result:=public.change_procurement_policy(3000,'Administrator policy update',next_version);
  perform pg_temp.assert_true((result->>'ok')::boolean,'Administrator changes policy');
  select count(*) into audit_count from public.activity_logs where action='procurement_policy_changed' and user_id in ('aa000000-0000-4000-8000-000000000006','aa000000-0000-4000-8000-000000000007');
  perform pg_temp.assert_true(audit_count=2,'each successful change audited');
  begin update public.commercial_approval_rules set minimum_quotations=1 where id=old_rule; raise exception 'immutable rule modified'; exception when insufficient_privilege then null; end;
  begin update public.procurement_policy_versions set low_value_threshold=500 where id=version; raise exception 'immutable policy modified'; exception when insufficient_privilege then null; end;
end;$test$;

-- Failure to audit must roll back both pointer and version/band insertions.
create function pg_temp.reject_policy_audit() returns trigger language plpgsql as $$
begin if new.action='procurement_policy_changed' then raise exception 'Synthetic audit failure'; end if; return new; end;$$;
create trigger reject_policy_audit before insert on public.activity_logs for each row execute function pg_temp.reject_policy_audit();
do $test$
declare previous uuid; versions integer;
begin
 select version_id into previous from public.procurement_company_policy;
 select count(*) into versions from public.procurement_policy_versions;
 begin perform public.change_procurement_policy(4000,'Audit rollback test',previous); raise exception 'audit failure swallowed'; exception when raise_exception then if sqlerrm<>'Synthetic audit failure' then raise; end if; end;
 perform pg_temp.assert_true((select version_id=previous from public.procurement_company_policy),'audit failure retains pointer');
 perform pg_temp.assert_true((select count(*)=versions from public.procurement_policy_versions),'audit failure removes new version');
end;$test$;
set local role authenticated;
do $test$ begin
 begin update public.procurement_company_policy set version_id='10000000-0000-4000-8000-000000000001'; raise exception 'direct DML allowed'; exception when insufficient_privilege then null; end;
end;$test$;
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.change_procurement_policy(numeric,text,uuid)','execute'),'anonymous RPC denied');
select pg_temp.assert_true(not has_function_privilege('service_role','public.change_procurement_policy(numeric,text,uuid)','execute'),'service RPC denied');
rollback;

\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Contractor audit regression: %',message; end if; end;$$;
insert into auth.users(id,email,raw_user_meta_data)
select ('cc000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,role||'@contractor.example.test',jsonb_build_object('display_name',role)
from unnest(array['reviewer','initiator','approver','technician','supervisor','facility_manager','administrator']) with ordinality as roles(role,n);
select set_config('fmworks.profile_admin_rpc','on',true);
select set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=roles.role,is_active=true,password_change_required=false
from unnest(array['reviewer','initiator','approver','technician','supervisor','facility_manager','administrator']) with ordinality as roles(role,n)
where p.id=('cc000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
select set_config('fmworks.profile_admin_rpc','off',true);
select set_config('fmworks.password_change_completion','off',true);
do $test$
declare result jsonb; vendor_id uuid; rate_id uuid; n integer; payload jsonb;
begin
 for n in 1..4 loop
  perform set_config('request.jwt.claim.sub',('cc000000-0000-4000-8000-'||lpad(n::text,12,'0')),true);
  perform pg_temp.assert_true(public.create_contractor_master('{"kind":"vendor","name":"Denied contractor"}')->>'code'='ACCESS_DENIED','unauthorized master write denied');
 end loop;
 for n in 5..7 loop
  perform set_config('request.jwt.claim.sub',('cc000000-0000-4000-8000-'||lpad(n::text,12,'0')),true);
  result:=public.create_contractor_master(jsonb_build_object('kind','vendor','name','Synthetic audit contractor '||n,'payment_terms_days',30));
  perform pg_temp.assert_true((result->>'ok')::boolean,'authorized contractor create');
  vendor_id:=(result->>'vendor_id')::uuid;
  perform pg_temp.assert_true((select count(*)=1 from public.activity_logs where action='contractor_created' and note::jsonb->>'vendor_id'=vendor_id::text),'one vendor audit');
 end loop;
 payload:=jsonb_build_object('kind','rate','vendor_id',vendor_id,'cost_type','service','description','Inspection','unit','visit','normal_unit_rate',75,'effective_from','2026-01-01','effective_to','2026-06-30');
 result:=public.create_contractor_master(payload);
 perform pg_temp.assert_true((result->>'ok')::boolean,'rate created');
 rate_id:=(result->>'rate_item_id')::uuid;
 perform pg_temp.assert_true((select count(*)=1 from public.activity_logs where action='contractor_rate_created' and note::jsonb->>'rate_item_id'=rate_id::text),'one rate audit');
 perform pg_temp.assert_true(public.create_contractor_master(payload||'{"effective_from":"2026-06-30","effective_to":"2026-12-31"}'::jsonb)->>'code'='RATE_PERIOD_OVERLAP','inclusive overlap denied');
 perform pg_temp.assert_true((public.create_contractor_master(payload||'{"effective_from":"2026-07-01","effective_to":"2026-12-31"}'::jsonb)->>'ok')::boolean,'non-overlapping successor accepted');
 perform pg_temp.assert_true(public.create_contractor_master(payload||'{"normal_unit_rate":"NaN"}'::jsonb)->>'code'='VALIDATION_ERROR','NaN rate denied');
 perform pg_temp.assert_true(public.create_contractor_master(payload||'{"effective_from":"wrong"}'::jsonb)->>'code'='VALIDATION_ERROR','bad date controlled');
end;$test$;
create function pg_temp.reject_contractor_audit() returns trigger language plpgsql as $$
begin if new.action in ('contractor_created','contractor_rate_created') then raise exception 'Synthetic audit failure'; end if; return new; end;$$;
create trigger reject_contractor_audit before insert on public.activity_logs for each row execute function pg_temp.reject_contractor_audit();
select pg_temp.assert_true(public.create_contractor_master('{"kind":"vendor","name":"Rollback contractor"}')->>'code'='INTERNAL_ERROR','audit failure controlled');
select pg_temp.assert_true(not exists(select 1 from public.vendors where name='Rollback contractor'),'audit failure rolls back vendor');
select pg_temp.assert_true(not has_function_privilege('anon','public.create_contractor_master(jsonb)','execute'),'anonymous RPC denied');
select pg_temp.assert_true(not has_function_privilege('service_role','public.create_contractor_master(jsonb)','execute'),'service RPC denied');
rollback;

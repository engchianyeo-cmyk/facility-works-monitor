-- One customer/company per dedicated Pilot deployment.
-- Policy versions and their quotation bands are immutable. Existing controls retain
-- their policy version when the current company threshold changes.
begin;

create table public.procurement_policy_versions (
  id uuid primary key default gen_random_uuid(),
  low_value_threshold numeric(14,2) not null check(low_value_threshold>0),
  currency text not null default 'SGD' check(currency='SGD'),
  changed_by uuid references public.profiles(id) on delete restrict,
  change_reason text not null check(length(btrim(change_reason)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create table public.procurement_company_policy (
  singleton boolean primary key default true check(singleton),
  version_id uuid not null references public.procurement_policy_versions(id) on delete restrict
);
insert into public.procurement_policy_versions(id,low_value_threshold,change_reason)
values('10000000-0000-4000-8000-000000000001',1000,'Initial company policy: one quotation below S$1,000; three at or above.');
insert into public.procurement_company_policy(version_id)
values('10000000-0000-4000-8000-000000000001');
alter table public.commercial_approval_rules add column policy_version_id uuid references public.procurement_policy_versions(id) on delete restrict;
update public.commercial_approval_rules set policy_version_id='10000000-0000-4000-8000-000000000001';
alter table public.commercial_approval_rules alter column policy_version_id set not null;
alter table public.work_order_financial_controls add column policy_version_id uuid references public.procurement_policy_versions(id) on delete restrict;
update public.work_order_financial_controls c set policy_version_id=r.policy_version_id from public.commercial_approval_rules r where r.id=c.rule_id;
update public.work_order_financial_controls set policy_version_id='10000000-0000-4000-8000-000000000001' where policy_version_id is null;
alter table public.work_order_financial_controls alter column policy_version_id set not null;

alter table public.procurement_policy_versions enable row level security;
alter table public.procurement_company_policy enable row level security;
revoke all on public.procurement_policy_versions,public.procurement_company_policy from public,anon,authenticated,service_role;
grant select on public.procurement_policy_versions,public.procurement_company_policy to authenticated;
create policy procurement_policy_versions_read on public.procurement_policy_versions for select to authenticated using(public.pilot_account_ready());
create policy procurement_company_policy_read on public.procurement_company_policy for select to authenticated using(public.pilot_account_ready());

create function public.protect_procurement_policy_history()
returns trigger language plpgsql set search_path=pg_catalog as $function$
begin
  raise exception using errcode='42501',message='Procurement policy history is immutable; create a new version.';
end;$function$;
create trigger procurement_policy_version_immutable before update or delete on public.procurement_policy_versions for each row execute function public.protect_procurement_policy_history();
create trigger procurement_policy_rule_immutable before update or delete on public.commercial_approval_rules for each row execute function public.protect_procurement_policy_history();
revoke all on function public.protect_procurement_policy_history() from public,anon,authenticated,service_role;

create function public.pin_work_order_procurement_policy()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
begin
  if tg_op='UPDATE' then
    new.policy_version_id:=old.policy_version_id;
  else
    -- Caller-supplied policy/rule identifiers cannot choose an obsolete policy.
    select version_id into new.policy_version_id from public.procurement_company_policy where singleton for share;
  end if;
  select id into new.rule_id from public.commercial_approval_rules
  where policy_version_id=new.policy_version_id and active
    and new.estimated_cost>=minimum_amount
    and (maximum_amount is null or new.estimated_cost<maximum_amount)
  order by minimum_amount desc limit 1;
  if new.rule_id is null then raise exception 'No quotation band covers the pinned policy and estimate'; end if;
  return new;
end;$function$;
create trigger work_order_procurement_policy_pin before insert or update on public.work_order_financial_controls for each row execute function public.pin_work_order_procurement_policy();
revoke all on function public.pin_work_order_procurement_policy() from public,anon,authenticated,service_role;

create function public.change_procurement_policy(p_threshold numeric,p_reason text,p_expected_version uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); previous uuid; next_version uuid; old_threshold numeric;
begin
  if actor is null or actor->>'role' not in ('facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Only Facility Manager and Administrator may change company procurement policy.');
  end if;
  if p_threshold is null or p_threshold::text in ('NaN','Infinity','-Infinity') or p_threshold<=0 or p_threshold>999999999999.99 or p_threshold<>round(p_threshold,2)
    or nullif(btrim(p_reason),'') is null or length(btrim(p_reason))>1000 then
    return public.work_order_result_error('VALIDATION_ERROR','A positive SGD threshold with at most two decimal places and a bounded reason are required.');
  end if;
  select version_id into previous from public.procurement_company_policy where singleton for update;
  if p_expected_version is distinct from previous then
    return public.work_order_result_error('POLICY_CONFLICT','Company policy changed; refresh before saving.');
  end if;
  select low_value_threshold into old_threshold from public.procurement_policy_versions where id=previous;
  if old_threshold=p_threshold then return public.work_order_result_error('VALIDATION_ERROR','Enter a different threshold.'); end if;
  insert into public.procurement_policy_versions(low_value_threshold,changed_by,change_reason)
  values(p_threshold,(actor->>'id')::uuid,btrim(p_reason)) returning id into next_version;
  insert into public.commercial_approval_rules(rule_code,minimum_amount,maximum_amount,minimum_quotations,policy_version_id)
  values('LOW_VALUE_'||next_version::text,0,p_threshold,1,next_version),
        ('STANDARD_'||next_version::text,p_threshold,null,3,next_version);
  update public.procurement_company_policy set version_id=next_version where singleton;
  insert into public.activity_logs(user_id,action,actor,note)
  values((actor->>'id')::uuid,'procurement_policy_changed',actor->>'name',jsonb_build_object('previous_version',previous,'version',next_version,'previous_threshold',old_threshold,'threshold',p_threshold,'currency','SGD','reason',btrim(p_reason))::text);
  return jsonb_build_object('ok',true,'version_id',next_version,'low_value_threshold',p_threshold);
end;$function$;
revoke all on function public.change_procurement_policy(numeric,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.change_procurement_policy(numeric,text,uuid) to authenticated;

create or replace function public.prepare_work_order_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
  control public.work_order_financial_controls%rowtype; vendor uuid; amount numeric; governed_estimate numeric; scope_text text; rule uuid;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare a proposal.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Proposal preparation requires active assigned work.'); end if;
  begin vendor:=(p_payload->>'vendor_id')::uuid; amount:=(p_payload->>'proposed_amount')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Eligible contractor and proposed amount are required.'); end;
  scope_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'scope_summary','')),'');
  if amount is null or amount<0 or scope_text is null or length(scope_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','Repair scope and non-negative proposed amount are required.'); end if;
  if not exists(select 1 from public.vendor_facility_eligibility e join public.vendors v on v.id=e.vendor_id where e.vendor_id=vendor and e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and v.active and v.deleted_at is null) then return public.work_order_result_error('CONTRACTOR_INELIGIBLE','Select a Procurement-prequalified, Facility-confirmed contractor.'); end if;
  if exists(select 1 from public.contractor_quotations x where x.work_order_id=w.id and x.vendor_id=vendor and x.status in ('draft','submitted','approved')) then return public.work_order_result_error('DUPLICATE_CONTRACTOR_QUOTATION','A current quotation for this contractor already exists.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  governed_estimate:=greatest(coalesce(control.estimated_cost,0),amount);
  select id into rule from public.commercial_approval_rules where policy_version_id=coalesce(control.policy_version_id,(select version_id from public.procurement_company_policy where singleton)) and active and governed_estimate>=minimum_amount and (maximum_amount is null or governed_estimate<maximum_amount) order by minimum_amount desc limit 1;
  if rule is null then return public.work_order_result_error('COMMERCIAL_RULE_REQUIRED','No commercial approval rule covers this amount.'); end if;
  insert into public.work_order_financial_controls(work_order_id,estimated_cost,rule_id,cost_status)
  values(w.id,governed_estimate,rule,'draft') on conflict(work_order_id) do update set estimated_cost=governed_estimate,rule_id=rule,cost_status='draft',quoted_cost=null,approved_budget=null,recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now();
  insert into public.contractor_quotations(work_order_id,vendor_id,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary)
  values(w.id,vendor,coalesce((select max(version_no)+1 from public.contractor_quotations where work_order_id=w.id),1),'draft','SGD',amount,actor_id,pg_catalog.now(),pg_catalog.now(),scope_text) returning * into q;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_competing_quotation_prepared',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('vendor_id',vendor,'quotation_id',q.id,'quoted_amount',amount,'governed_estimate',governed_estimate,'decision_pending',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$;


create or replace function public.save_work_order_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $function$
declare
  result jsonb;
  prior_estimate numeric;
  pinned_version uuid;
  quotation_amount numeric;
  governed_estimate numeric;
  governed_rule_id uuid;
begin
  -- Serialize before reading the prior estimate to prevent concurrent draft saves
  -- from lowering the governed estimate. The private core still authorizes the actor.
  perform 1 from public.work_orders where id=p_work_order_id for update;
  select estimated_cost,policy_version_id
    into prior_estimate,pinned_version
    from public.work_order_financial_controls
   where work_order_id=p_work_order_id;

  result:=public.save_work_order_proposal_20260924_core(p_work_order_id,p_payload);
  if not coalesce((result->>'ok')::boolean,false) then
    return result;
  end if;

  quotation_amount:=(result->'quotation'->>'total_amount')::numeric;
  governed_estimate:=greatest(coalesce(prior_estimate,0),coalesce(quotation_amount,0));

  select id
    into governed_rule_id
    from public.commercial_approval_rules
   where policy_version_id=coalesce(pinned_version,(select version_id from public.procurement_company_policy where singleton)) and active
     and governed_estimate>=minimum_amount
     and (maximum_amount is null or governed_estimate<maximum_amount)
   order by minimum_amount desc
   limit 1;

  update public.work_order_financial_controls
     set estimated_cost=governed_estimate,
         rule_id=governed_rule_id,
         updated_at=pg_catalog.now()
   where work_order_id=p_work_order_id;

  return result || pg_catalog.jsonb_build_object(
    'governed_estimate',governed_estimate,
    'commercial_rule_id',governed_rule_id
  );
end;
$function$;


commit;

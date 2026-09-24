begin;

alter function public.save_work_order_proposal(uuid,jsonb)
  rename to save_work_order_proposal_20260924_core;

create function public.save_work_order_proposal(p_work_order_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $function$
declare
  result jsonb;
  prior_estimate numeric;
  quotation_amount numeric;
  governed_estimate numeric;
  governed_rule_id uuid;
begin
  select estimated_cost
    into prior_estimate
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
   where active
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

revoke all on function public.save_work_order_proposal_20260924_core(uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.save_work_order_proposal(uuid,jsonb) from public,anon,service_role;
grant execute on function public.save_work_order_proposal(uuid,jsonb) to authenticated;

commit;

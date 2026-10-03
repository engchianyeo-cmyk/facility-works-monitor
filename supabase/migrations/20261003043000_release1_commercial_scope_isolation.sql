begin;
-- Match the established Work Order SELECT policy for privileged RPCs, which
-- otherwise execute with table-owner privileges and bypass ordinary row RLS.
create function public.release1_work_order_visible(p_work_order_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and exists (
    select 1 from public.work_orders w where w.id=p_work_order_id and (
      (public.current_user_role()='technician' and public.technician_facility_read_permitted(w.facility_id))
      or (public.current_user_role()<>'technician' and (
        w.requested_by=auth.uid() or w.assigned_technician_id=auth.uid()
        or public.current_user_role() in ('approver','administrator')
        or public.supervisor_facility_permitted(w.facility_id)
        or public.facility_manager_facility_permitted(w.facility_id)
      ))
    )
  );
$function$;
revoke all on function public.release1_work_order_visible(uuid) from public,anon,authenticated,service_role;
grant execute on function public.release1_work_order_visible(uuid) to authenticated;

-- Restrictive policies intersect the earlier broad active-account policies.
-- They cannot be overridden by adding another permissive SELECT policy.
create policy release1_work_order_scope on public.work_order_cost_lines as restrictive
for select to authenticated using (exists(select 1 from public.work_orders w where w.id=work_order_id));
create policy release1_work_order_scope on public.work_order_financial_controls as restrictive
for select to authenticated using (exists(select 1 from public.work_orders w where w.id=work_order_id));
create policy release1_work_order_scope on public.contractor_payment_assessments as restrictive
for select to authenticated using (exists(select 1 from public.work_orders w where w.id=work_order_id));

-- Preserve each current domain implementation and signature/defaults behind
-- a private core. Add the missing scope boundary to the financial RPC family.
do $wrappers$
declare function_name text; implementation record; core_name text; call_arguments text; core_signature text;
begin
  foreach function_name in array array[
    'work_order_financial_documentation_readiness','work_order_closure_readiness',
    'work_order_contractor_quotations','work_order_contractor_rate_items','work_order_eligible_contractors',
    'record_work_order_markup','record_work_order_procurement',
    'prepare_work_order_proposal','save_work_order_proposal','submit_work_order_proposal',
    'recommend_work_order_quotation','approve_work_order_proposal','return_work_order_proposal',
    'save_work_order_final_cost','approve_work_order_final_cost_variance',
    'save_work_order_payment_proposal','submit_work_order_payment_proposal','approve_work_order_payment',
    'record_work_order_finance_payment','return_work_order_payment','reopen_work_order_payment_for_correction',
    'propose_work_order_no_payment','approve_work_order_no_payment',
    'register_work_order_commercial_document','register_work_order_final_cost_document',
    'open_work_order_document_correction','close_work_order_document_correction',
    'start_work_order_quotation_revision','void_work_order_supporting_document',
    'preview_contractor_actual_import','confirm_contractor_actual_import'
  ] loop
    select p.oid,p.proargnames,pg_get_function_arguments(p.oid) arguments,
      pg_get_function_identity_arguments(p.oid) identity_arguments
      into strict implementation
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=function_name and p.prorettype='jsonb'::regtype
      and p.proargnames[1]='p_work_order_id';
    if not has_function_privilege('authenticated',implementation.oid,'EXECUTE') then
      raise exception 'Expected authenticated Release-1 RPC prerequisite missing: %',function_name;
    end if;
    core_name:=function_name||'_r1_scope_core';
    core_signature:=format('public.%I(%s)',core_name,implementation.identity_arguments);
    if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=core_name) then raise exception 'Scope core already exists: %',core_name; end if;
    select string_agg(format('%I',argument),', ' order by ordinal) into call_arguments
    from unnest(implementation.proargnames) with ordinality args(argument,ordinal);
    execute format('alter function public.%I(%s) rename to %I',function_name,implementation.identity_arguments,core_name);
    execute format('revoke all on function %s from public,anon,authenticated,service_role',core_signature);
    execute format($definition$
      create function public.%I(%s) returns jsonb language plpgsql security definer set search_path=pg_catalog as $body$
      begin
        if not public.release1_work_order_visible(p_work_order_id) then
          return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.');
        end if;
        return public.%I(%s);
      end;
      $body$;
    $definition$,function_name,implementation.arguments,core_name,call_arguments);
    execute format('revoke all on function public.%I(%s) from public,anon,authenticated,service_role',function_name,implementation.identity_arguments);
    execute format('grant execute on function public.%I(%s) to authenticated',function_name,implementation.identity_arguments);
  end loop;
end;
$wrappers$;
commit;

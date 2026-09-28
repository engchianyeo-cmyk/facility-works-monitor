-- Release-1 reconciliation: fail closed if either authoritative history is incomplete.
-- This migration intentionally adds no Production data and is safe only after the full
-- canonical non-Production replay manifest has applied both histories in order.
begin;

do $reconciliation$
declare
  authority_definition text;
  required_relation text;
  required_function text;
begin
  select pg_catalog.pg_get_functiondef('public.field_work_facility_permitted(uuid)'::regprocedure)
    into authority_definition;
  if authority_definition not like '%technician%'
    or authority_definition not like '%supervisor%'
    or authority_definition not like '%facility_manager%'
    or authority_definition not like '%administrator%' then
    raise exception 'Release-1 reconciliation requires all four governed field roles';
  end if;

  foreach required_relation in array array[
    'public.facility_memberships',
    'public.evidence_items',
    'public.work_order_markups',
    'public.contractor_quotations',
    'public.contractor_quotation_lines',
    'public.contractor_actual_imports',
    'public.contractor_actual_import_lines',
    'public.work_order_final_cost_submissions',
    'public.contractor_payment_assessments'
  ] loop
    if pg_catalog.to_regclass(required_relation) is null then
      raise exception 'Release-1 reconciliation relation missing: %', required_relation;
    end if;
  end loop;

  foreach required_function in array array[
    'public.accept_work_responsibility(uuid)',
    'public.submit_physical_completion(uuid,jsonb)',
    'public.verify_completed_work(uuid,jsonb)',
    'public.register_evidence_item(text,uuid,text,text,bigint,text,text,text)',
    'public.void_work_order_evidence(uuid,text)',
    'public.record_work_order_markup(uuid,jsonb)',
    'public.prepare_work_order_proposal(uuid,jsonb)',
    'public.approve_work_order_proposal(uuid,uuid,text)',
    'public.preview_contractor_actual_import(uuid,jsonb)',
    'public.confirm_contractor_actual_import(uuid,text,text,text,jsonb)',
    'public.work_order_contractor_rate_items(uuid)',
    'public.save_work_order_final_cost(uuid,jsonb)',
    'public.record_work_order_finance_payment(uuid,jsonb)'
  ] loop
    if pg_catalog.to_regprocedure(required_function) is null then
      raise exception 'Release-1 reconciliation function missing: %', required_function;
    end if;
  end loop;

  if pg_catalog.has_function_privilege('anon', 'public.submit_physical_completion(uuid,jsonb)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.record_work_order_finance_payment(uuid,jsonb)', 'EXECUTE') then
    raise exception 'Release-1 governed functions must not be executable by anon';
  end if;
end;
$reconciliation$;

commit;

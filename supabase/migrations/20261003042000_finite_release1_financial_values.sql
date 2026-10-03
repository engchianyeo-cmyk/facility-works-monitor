-- Reject PostgreSQL special numeric values at the persisted domain boundary.
-- Existing valid historical decisions are unchanged; corrupt data fails validation.
begin;
do $constraints$
declare table_name text; predicate text;
begin
  foreach table_name in array array[
    'work_orders','work_order_financial_controls','work_order_cost_lines',
    'contractor_rate_items','contractor_quotations','contractor_quotation_lines',
    'work_order_final_cost_submissions','contractor_payment_assessments',
    'work_order_procurement_commitments'
  ] loop
    select string_agg(format('(%I is null or %I::text not in (''NaN'',''Infinity'',''-Infinity''))',a.attname,a.attname),' and ' order by a.attnum)
      into predicate
    from pg_attribute a join pg_type t on t.oid=a.atttypid
    where a.attrelid=format('public.%I',table_name)::regclass and a.attnum>0 and not a.attisdropped
      and t.typname in ('numeric','float4','float8');
    if predicate is null then raise exception 'Financial numeric prerequisite missing: %',table_name; end if;
    execute format('alter table public.%I add constraint release1_finite_numeric_values check (%s)',table_name,predicate);
  end loop;
end;
$constraints$;
commit;

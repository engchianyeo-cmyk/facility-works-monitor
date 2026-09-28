-- WP-FMW-027: governed lookup of the assigned contractor's effective rates.
-- Used by the Work Order CSV import API to translate stable rate codes to IDs.
create or replace function public.work_order_contractor_rate_items(p_work_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb:=public.work_order_actor();
  w public.work_orders%rowtype;
  result jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','Assign a contractor first.'); end if;
  if not public.field_work_facility_permitted(w.facility_id) and actor->>'role' not in ('approver','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Contractor rate access is denied.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'item_code',r.item_code,'cost_type',r.cost_type,'description',r.description,
    'unit',r.unit,'normal_unit_rate',r.normal_unit_rate,'emergency_unit_rate',r.emergency_unit_rate,
    'currency',r.currency,'effective_from',r.effective_from,'effective_to',r.effective_to
  ) order by r.cost_type,r.item_code,r.description),'[]'::jsonb)
  into result
  from public.contractor_rate_items r
  where r.vendor_id=w.assigned_vendor_id and r.active
    and r.effective_from<=current_date and (r.effective_to is null or r.effective_to>=current_date);
  return jsonb_build_object('ok',true,'vendor_id',w.assigned_vendor_id,'rates',result);
end;
$function$;
revoke all on function public.work_order_contractor_rate_items(uuid) from public,anon,service_role;
grant execute on function public.work_order_contractor_rate_items(uuid) to authenticated;

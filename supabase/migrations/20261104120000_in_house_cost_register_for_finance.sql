begin;
-- D-31 (4 Nov 2026): in-house Work Orders have no contractor payment, but Finance keeps them for reference. Finance
-- (and the Administrator) can list completed in-house Work Orders with their confirmed actual cost (materials,
-- labour, equipment and services). Finance is already copied and notified when any Work Order is Completed (D-11).

create function public.work_order_in_house_cost_register()
returns table(work_order_id uuid, work_order_number text, title text, facility_name text, status text,
  reviewed_at timestamptz, closed_at timestamptz, actual_costs_confirmed_at timestamptz,
  materials numeric, labour numeric, equipment numeric, services numeric, total numeric, line_count integer)
language sql stable security definer set search_path=pg_catalog as $function$
  select w.id, w.work_order_number, w.title, s.name, w.status, w.reviewed_at, w.closed_at, w.actual_costs_confirmed_at,
    coalesce(sum(c.amount) filter (where c.cost_type='material'),0),
    coalesce(sum(c.amount) filter (where c.cost_type='labour'),0),
    coalesce(sum(c.amount) filter (where c.cost_type='equipment'),0),
    coalesce(sum(c.amount) filter (where c.cost_type in ('service','callout')),0),
    coalesce(sum(c.amount),0),
    count(c.id)::integer
  from public.work_orders w
  left join public.sites s on s.id=w.facility_id
  left join public.work_order_cost_lines c on c.work_order_id=w.id and c.cost_phase='actual'
  where public.current_user_role() in ('finance','administrator') and public.pilot_account_ready(auth.uid())
    and w.in_house_work and w.status in ('reviewed','closed')
  group by w.id, s.name
  order by coalesce(w.closed_at, w.reviewed_at) desc nulls last
$function$;
revoke all on function public.work_order_in_house_cost_register() from public, anon, service_role;
grant execute on function public.work_order_in_house_cost_register() to authenticated;

do $postcheck$
begin
  if to_regprocedure('public.work_order_in_house_cost_register()') is null then
    raise exception 'D-31 in-house cost register was not installed';
  end if;
end;$postcheck$;
commit;

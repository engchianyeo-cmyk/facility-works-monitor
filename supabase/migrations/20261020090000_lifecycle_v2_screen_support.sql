-- WP-LC2-M4: read-only helpers for the Lifecycle v2 screens.
-- * work_order_people_directory: names and roles of active users, for choosing copied parties
--   (profiles RLS otherwise shows users only themselves). No emails or other personal data.
-- * work_order_facility_technicians: active Technicians at a visible Work Order's facility.
-- * work_order_approval_summary: v2 approval readiness for a visible Work Order — quotation
--   state, amount, the role level whose limit covers it, and whether the caller may approve.

begin;

do $preflight$
begin
  if current_user <> 'postgres' then raise exception 'LC2-M4 must be applied as postgres'; end if;
  if pg_catalog.to_regprocedure('public.verify_completed_work(uuid,jsonb)') is null
    or pg_catalog.to_regprocedure('public.register_work_order_invoice(uuid,text,text,text,bigint,text,numeric)') is null then
    raise exception 'LC2-M4 requires LC2-M3'; end if;
  if pg_catalog.to_regprocedure('public.work_order_people_directory()') is not null then
    raise exception 'LC2-M4 conflicting or partial state already exists'; end if;
end;$preflight$;

create function public.work_order_people_directory()
returns table(id uuid, display_name text, role text)
language sql stable security definer set search_path=pg_catalog as $function$
  select p.id, p.display_name, p.role from public.profiles p
  where public.pilot_account_ready(auth.uid()) and public.pilot_account_ready(p.id)
  order by p.display_name
$function$;

create function public.work_order_facility_technicians(p_work_order_id uuid)
returns table(id uuid, display_name text, trade_discipline text)
language sql stable security definer set search_path=pg_catalog as $function$
  select p.id, p.display_name, p.trade_discipline
  from public.work_orders w
  join public.facility_memberships fm on fm.facility_id=w.facility_id and fm.membership_role='technician' and fm.active
    and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
  join public.profiles p on p.id=fm.profile_id and p.role='technician' and public.pilot_account_ready(p.id)
  where w.id=p_work_order_id and public.release1_work_order_visible(p_work_order_id)
  order by p.display_name
$function$;

create function public.work_order_approval_summary(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare w public.work_orders%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer;
  amount numeric; level text; authority jsonb; missing jsonb:='[]'::jsonb;
begin
  if not public.release1_work_order_visible(p_work_order_id) then
    return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into control from public.work_order_financial_controls where work_order_id=w.id;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id;
  select pg_catalog.count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  amount:=control.quoted_cost;
  if pg_catalog.length(pg_catalog.btrim(coalesce(w.description,'')))<10 then missing:=missing||'"Reason the work is needed"'::jsonb; end if;
  if w.assigned_technician_id is null then missing:=missing||'"Field-witness Technician"'::jsonb; end if;
  if not w.emergency_work then
    if collected_count<coalesce(required_count,1) then missing:=missing||pg_catalog.to_jsonb(pg_catalog.format('Quotations: %s of %s submitted',collected_count,coalesce(required_count,1))); end if;
    if control.work_order_id is null or control.cost_status<>'recommended' or amount is null then missing:=missing||'"Recommended contractor quotation"'::jsonb; end if;
  end if;
  select l.role into level from public.work_order_approval_limits l join public.work_order_approval_limit_policy p on p.version_id=l.version_id
    where amount is not null and (l.maximum_amount is null or l.maximum_amount>=amount)
    order by l.maximum_amount nulls last, case l.role when 'approver' then 1 when 'supervisor' then 2 when 'facility_manager' then 3 else 4 end limit 1;
  if amount is not null and w.status='submitted' then authority:=public.work_order_approval_authority(w.id,amount,null); end if;
  return pg_catalog.jsonb_build_object('ok',true,'status',w.status,'emergency_work',w.emergency_work,
    'quoted_cost',amount,'approved_budget',control.approved_budget,'cost_status',control.cost_status,
    'required_quotations',coalesce(required_count,1),'collected_quotations',collected_count,
    'missing_requirements',missing,'ready',pg_catalog.jsonb_array_length(missing)=0,
    'lowest_authority',level,'board_approval_required',coalesce(amount,0)>1000000,
    'can_approve',w.status='submitted' and amount is not null and authority is null,
    'approval_blocker',authority->>'code','approval_blocker_message',authority->>'message');
end;$function$;

revoke all on function public.work_order_people_directory() from public, anon, service_role;
revoke all on function public.work_order_facility_technicians(uuid) from public, anon, service_role;
revoke all on function public.work_order_approval_summary(uuid) from public, anon, service_role;
grant execute on function public.work_order_people_directory() to authenticated;
grant execute on function public.work_order_facility_technicians(uuid) to authenticated;
grant execute on function public.work_order_approval_summary(uuid) to authenticated;

commit;

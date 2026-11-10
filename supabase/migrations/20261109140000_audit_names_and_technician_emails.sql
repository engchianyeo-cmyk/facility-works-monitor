begin;
-- UAT 9 Nov 2026: several audited actions (for example the actual costing confirmation) record the person as
-- "Unknown user", because they read the actor's "name" while work_order_actor() only returned "display_name".
-- work_order_actor() now returns both keys with the same value, which fixes every such action at once.
-- (Also: the Technician list returns emails; see below.)
-- Earlier log entries recorded as "Unknown user" are given the person's display name from their user id.

create or replace function public.work_order_actor()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select pg_catalog.jsonb_build_object(
    'id', profile.id,
    'display_name', profile.display_name,
    'name', profile.display_name,
    'role', profile.role,
    'department_id', profile.department_id
  )
  from public.profiles as profile
  where profile.id = auth.uid()
    and public.pilot_account_ready(profile.id)
$function$;

update public.activity_logs a
   set actor = p.display_name
  from public.profiles p
 where a.actor = 'Unknown user' and a.user_id = p.id and p.display_name is not null;

-- UAT 9 Nov 2026: two Technicians with near-identical names were confused when choosing Technician 1. The list of a
-- facility's Technicians now also returns each person's email, shown beside the name in the picker.
drop function if exists public.work_order_facility_technicians(uuid);
create function public.work_order_facility_technicians(p_work_order_id uuid)
returns table(id uuid, display_name text, trade_discipline text, email text)
language sql stable security definer set search_path=pg_catalog as $function$
  select p.id, p.display_name, p.trade_discipline, p.email
  from public.work_orders w
  join public.facility_memberships fm on fm.facility_id=w.facility_id and fm.membership_role='technician' and fm.active
    and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
  join public.profiles p on p.id=fm.profile_id and p.role='technician' and public.pilot_account_ready(p.id)
  where w.id=p_work_order_id and public.release1_work_order_visible(p_work_order_id)
  order by p.display_name
$function$;
revoke all on function public.work_order_facility_technicians(uuid) from public, anon, service_role;
grant execute on function public.work_order_facility_technicians(uuid) to authenticated;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.work_order_actor()'::regprocedure), '''name'', profile.display_name') = 0 then
    raise exception 'work_order_actor() does not return the name key';
  end if;
end;
$postcheck$;
commit;

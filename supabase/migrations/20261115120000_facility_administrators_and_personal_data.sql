-- M29 (D-50, D-53, D-54, D-55; owner 12-15 Nov 2026): Facility Administrators, Finance per facility, and removal of
-- a person's details before a client handover.
-- * The existing Administrator role is the Super-Administrator (all facilities; unchanged everywhere).
-- * New role facility_administrator: through its facility memberships it sets up only its own facilities (details,
--   areas, drawings, staff, settings), creates accounts for them and reads their Work Orders. It never approves,
--   executes or pays Work Orders and never adds facilities.
-- * Finance belongs to facilities like other staff: it reads and is notified about only its facilities' Work Orders.
-- * admin_remove_personal_details: the Super-Administrator removes a person's name, email and contact number for
--   good; the records stay under "Former user NNNN".
begin;

-- 1. Roles -----------------------------------------------------------------------------------------------------
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role = any (array[
  'reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance','facility_administrator']));
alter table public.facility_memberships drop constraint facility_memberships_membership_role_check;
alter table public.facility_memberships add constraint facility_memberships_membership_role_check
  check (membership_role = any (array['technician','approver','supervisor','facility_manager','finance','facility_administrator']));

create or replace function public.pilot_account_ready(p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select exists (
    select 1 from public.profiles profile
    where profile.id=p_user_id
      and profile.is_active=true
      and profile.deleted_at is null
      and profile.password_change_required=false
      and profile.role in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance','facility_administrator')
  )
$function$;

-- 2. Facility scope helpers --------------------------------------------------------------------------------------
create or replace function public.active_facility_member(p_facility_id uuid, p_role text, p_profile_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select p_facility_id is not null and exists(select 1 from public.facility_memberships m join public.sites s on s.id = m.facility_id
    where m.facility_id = p_facility_id and m.profile_id = p_profile_id and m.membership_role = p_role and m.active
      and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now()))
$function$;

-- The Super-Administrator for any facility (and for a new one); a Facility Administrator only for its own facilities.
create or replace function public.facility_admin_actor_for(p_facility_id uuid)
returns jsonb language sql stable security definer set search_path = pg_catalog as $function$
  select a from (select public.work_order_actor() a) x
  where a->>'role' = 'administrator'
     or (a->>'role' = 'facility_administrator' and public.active_facility_member(p_facility_id, 'facility_administrator', (a->>'id')::uuid))
$function$;

-- Written as CASE so the common case (any other role) stops after one cheap role lookup; these run inside row policies.
create or replace function public.facility_administrator_facility_permitted(p_facility_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select case when public.current_user_role() is distinct from 'facility_administrator' then false
              else public.pilot_account_ready(auth.uid()) and public.active_facility_member(p_facility_id, 'facility_administrator') end
$function$;

-- Finance and the Super-Administrator read finance registers; Finance only for its facilities.
create or replace function public.facility_finance_permitted(p_facility_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select case public.current_user_role()
           when 'administrator' then public.pilot_account_ready(auth.uid())
           when 'finance' then public.pilot_account_ready(auth.uid()) and public.active_facility_member(p_facility_id, 'finance')
           else false end
$function$;

revoke all on function public.active_facility_member(uuid,text,uuid), public.facility_admin_actor_for(uuid),
  public.facility_administrator_facility_permitted(uuid), public.facility_finance_permitted(uuid) from public, anon, service_role;
grant execute on function public.active_facility_member(uuid,text,uuid), public.facility_admin_actor_for(uuid),
  public.facility_administrator_facility_permitted(uuid), public.facility_finance_permitted(uuid) to authenticated;

-- 3. Work Order visibility ---------------------------------------------------------------------------------------
drop policy work_orders_read_permitted on public.work_orders;
create policy work_orders_read_permitted on public.work_orders for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (
    (public.current_user_role()='technician' and public.technician_facility_read_permitted(facility_id))
    or (public.current_user_role()<>'technician' and (
      requested_by=auth.uid() or assigned_technician_id=auth.uid()
      or public.current_user_role() = 'administrator'
      or public.facility_finance_permitted(facility_id)
      or public.facility_administrator_facility_permitted(facility_id)
      or public.approver_facility_permitted(facility_id)
      or public.supervisor_facility_permitted(facility_id)
      or public.facility_manager_facility_permitted(facility_id)
    ))
  )
);

create or replace function public.release1_work_order_visible(p_work_order_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and exists (
    select 1 from public.work_orders w where w.id=p_work_order_id and (
      (public.current_user_role()='technician' and public.technician_facility_read_permitted(w.facility_id))
      or (public.current_user_role()<>'technician' and (
        w.requested_by=auth.uid() or w.assigned_technician_id=auth.uid()
        or public.current_user_role() = 'administrator'
        or public.facility_finance_permitted(w.facility_id)
        or public.facility_administrator_facility_permitted(w.facility_id)
        or public.approver_facility_permitted(w.facility_id)
        or public.supervisor_facility_permitted(w.facility_id)
        or public.facility_manager_facility_permitted(w.facility_id)
      ))
    )
  );
$function$;

-- 4. Finance registers: only the Finance member's facilities -------------------------------------------------

create or replace function public.work_order_in_house_cost_register()
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
  where public.facility_finance_permitted(w.facility_id)
    and w.in_house_work and w.status in ('reviewed','closed')
  group by w.id, s.name
  order by coalesce(w.closed_at, w.reviewed_at) desc nulls last
$function$;
create or replace function public.work_order_finance_tracker()
 RETURNS TABLE(work_order_id uuid, work_order_number text, title text, facility_id uuid, vendor_id uuid, vendor_name text, approved_amount numeric, completed_at timestamp with time zone, invoice_reference text, invoice_amount numeric, invoice_uploaded_at timestamp with time zone, invoice_received_at timestamp with time zone, payment_due_at timestamp with time zone, paid_at timestamp with time zone, paid_amount numeric, payment_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select w.id,w.work_order_number,w.title,w.facility_id,p.vendor_id,v.name,p.assessed_amount,w.reviewed_at,p.invoice_reference,p.invoice_amount,
    p.invoice_uploaded_at,p.invoice_received_at,p.payment_due_at,p.paid_at,p.paid_amount,
    case when p.status='paid' then 'paid'
         when p.invoice_received_at is not null and p.payment_due_at<pg_catalog.now() then 'overdue'
         when p.invoice_received_at is not null then 'invoice_received'
         when p.invoice_uploaded_at is not null then 'invoice_uploaded'
         else 'awaiting_invoice' end
  from public.contractor_payment_assessments p
  join public.work_orders w on w.id=p.work_order_id
  left join public.vendors v on v.id=p.vendor_id
  where public.facility_finance_permitted(w.facility_id) and p.status in ('approved_for_payment','paid') and not exists(select 1 from public.work_order_test_data td where td.work_order_id=w.id)
  order by case when p.status='paid' then 1 else 0 end, p.payment_due_at nulls last, w.reviewed_at
$function$;
create or replace function public.finance_completed_work_register(p_work_order_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(work_order_id uuid, work_order_number text, title text, facility_name text, status text, in_house_work boolean, emergency_work boolean, contractor_name text, technician_name text, approved_by_name text, approved_at timestamp with time zone, completed_by_name text, completed_at timestamp with time zone, closed_at timestamp with time zone, work_performed text, actual_labour_hours numeric, actual_work_started_at timestamp with time zone, actual_work_ended_at timestamp with time zone, approved_amount numeric, final_amount numeric, invoice_reference text, invoice_amount numeric, invoice_uploaded_at timestamp with time zone, invoice_received_at timestamp with time zone, payment_due_at timestamp with time zone, payment_terms_days integer, paid_at timestamp with time zone, paid_amount numeric, payment_reference text, register_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select w.id, w.work_order_number, w.title, s.name, w.status, coalesce(w.in_house_work, false), coalesce(w.emergency_work, false),
    v.name, t.display_name, ap.actor, ap.created_at, cp.actor, coalesce(cp.created_at, w.reviewed_at), w.closed_at,
    w.completion_notes, w.actual_labour_hours, w.actual_work_started_at, w.actual_work_ended_at,
    fc.approved_budget,
    case when coalesce(w.in_house_work, false)
         then (select coalesce(sum(c.amount), 0) from public.work_order_cost_lines c where c.work_order_id = w.id and c.cost_phase = 'actual')
         else p.assessed_amount end,
    p.invoice_reference, p.invoice_amount, p.invoice_uploaded_at, p.invoice_received_at, p.payment_due_at, v.payment_terms_days,
    p.paid_at, p.paid_amount, p.payment_reference,
    case when coalesce(w.in_house_work, false) then 'in_house'
         when p.status = 'paid' or p.paid_at is not null then 'paid'
         when p.invoice_received_at is not null and p.payment_due_at < now() then 'overdue'
         when p.invoice_received_at is not null then 'invoice_received'
         when p.invoice_uploaded_at is not null then 'invoice_uploaded'
         when w.status = 'closed' then 'closed_no_payment'
         else 'awaiting_invoice' end
  from public.work_orders w
  left join public.sites s on s.id = w.facility_id
  left join public.contractor_payment_assessments p on p.work_order_id = w.id
  left join public.vendors v on v.id = coalesce(p.vendor_id, w.assigned_vendor_id)
  left join public.profiles t on t.id = w.assigned_technician_id
  left join public.work_order_financial_controls fc on fc.work_order_id = w.id
  left join lateral (select a.actor, a.created_at from public.activity_logs a
    where a.work_order_id = w.id and a.from_status = 'submitted' and a.to_status in ('approved', 'assigned', 'in_progress')
    order by a.created_at desc limit 1) ap on true
  left join lateral (select a.actor, a.created_at from public.activity_logs a
    where a.work_order_id = w.id and a.action = 'work_order_review' and a.to_status = 'reviewed'
    order by a.created_at desc limit 1) cp on true
  where public.facility_finance_permitted(w.facility_id)
    and w.status in ('reviewed', 'closed') and (p_work_order_id is null or w.id = p_work_order_id) and (p_work_order_id is not null or not exists (select 1 from public.work_order_test_data td where td.work_order_id = w.id))
  order by coalesce(cp.created_at, w.reviewed_at) desc nulls last
$function$;

-- Finance is copied and notified only about its own facilities' Work Orders (every function that copies or notifies
-- Finance goes through these two tables, so one guard each covers them all).
create or replace function public.guard_finance_facility_recipient() returns trigger
language plpgsql security definer set search_path = pg_catalog as $function$
declare person uuid; fac uuid;
begin
  if TG_TABLE_NAME = 'work_order_copied_parties' then person := NEW.profile_id;
  else person := coalesce(NEW.recipient_profile_id, NEW.recipient_user_id); end if;
  if person is null or NEW.work_order_id is null then return NEW; end if;
  if not exists(select 1 from public.profiles p where p.id = person and p.role in ('finance','facility_administrator')) then return NEW; end if;
  select w.facility_id into fac from public.work_orders w where w.id = NEW.work_order_id;
  if fac is null or exists(select 1 from public.profiles p where p.id = person
       and public.active_facility_member(fac, p.role, p.id)) then return NEW; end if;
  return null;   -- not a member of this Work Order's facility: not copied, not notified
end;$function$;
revoke all on function public.guard_finance_facility_recipient() from public, anon, authenticated, service_role;
drop trigger if exists guard_finance_facility_recipient on public.notification_outbox;
create trigger guard_finance_facility_recipient before insert on public.notification_outbox
  for each row execute function public.guard_finance_facility_recipient();
drop trigger if exists guard_finance_facility_recipient on public.work_order_copied_parties;
create trigger guard_finance_facility_recipient before insert on public.work_order_copied_parties
  for each row execute function public.guard_finance_facility_recipient();

-- 5. Facility set-up by the Super-Administrator or the facility's own Facility Administrator ------------------------

create or replace function public.admin_save_facility(p_facility_id uuid, p_code text, p_name text, p_address text, p_active boolean, p_seed_standard_areas boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor_for(p_facility_id); v_code text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_code,'')));
  v_name text := pg_catalog.btrim(coalesce(p_name,'')); before public.sites%rowtype; result public.sites%rowtype; seeded integer := 0;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator, or this facility''s Facility Administrator, may change it.'); end if;
  if actor->>'role' = 'facility_administrator' and not coalesce(p_active, true) then
    return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator may switch a facility off.'); end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{1,19}$' then return public.work_order_result_error('VALIDATION_ERROR','Facility code: 2 to 20 letters, numbers or dashes.'); end if;
  if pg_catalog.length(v_name) not between 2 and 120 then return public.work_order_result_error('VALIDATION_ERROR','Enter the facility name (2 to 120 characters).'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason for the change.'); end if;
  if exists(select 1 from public.sites s where s.code = v_code and s.id is distinct from p_facility_id) then
    return public.work_order_result_error('VALIDATION_ERROR','Another facility already uses that code.'); end if;
  if p_facility_id is null then
    insert into public.sites(code, name, address, is_active) values (v_code, v_name, nullif(pg_catalog.btrim(coalesce(p_address,'')),''), true) returning * into result;
    if coalesce(p_seed_standard_areas, true) then
      insert into public.facility_areas(facility_id, area_code, name)
      select result.id, a.code, a.name from (values ('REC-01','Reception'),('OFF-01','Office'),('MTR-01','Meeting Room'),('PAN-01','Pantry'),('TLT-01','Toilet'),
        ('WHS-01','Warehouse'),('LDB-01','Loading / Unloading Bay'),('ELR-01','Electrical Room'),('TFR-01','Transformer Room'),('ITR-01','Server / IT Room'),
        ('AHR-01','AHU Room'),('GNR-01','Generator Room'),('PMR-01','Pump Room'),('FPR-01','Fire Pump Room'),('MWS-01','Maintenance Workshop'),('STR-01','Staircase'),
        ('LFT-01','Lift'),('LBY-01','Lift Lobby'),('COR-01','Corridor'),('ROF-01','Roof'),('CPK-01','Car Park'),('GDH-01','Guard House'),
        ('RHA-01','Rubbish Holding Area'),('LSZ-01','Landscape Zone'),('SYD-01','External / Service Yard')) a(code, name);
      get diagnostics seeded = row_count;
    end if;
  else
    select * into before from public.sites where id = p_facility_id for update;
    if before.id is null then return public.work_order_result_error('NOT_FOUND','Facility not found.'); end if;
    if not coalesce(p_active, true) and exists(select 1 from public.work_orders w where w.facility_id = before.id and w.status not in ('closed','cancelled')) then
      return public.work_order_result_error('VALIDATION_ERROR','Close or cancel this facility''s open Work Orders before switching it off.'); end if;
    update public.sites set code = v_code, name = v_name, address = nullif(pg_catalog.btrim(coalesce(p_address,'')),''), is_active = coalesce(p_active, true), updated_at = pg_catalog.now()
     where id = before.id returning * into result;
  end if;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, case when p_facility_id is null then 'facility_created' else 'facility_updated' end, actor->>'display_name',
    pg_catalog.jsonb_build_object('facility_id', result.id, 'previous', case when before.id is null then null else pg_catalog.to_jsonb(before) end,
      'next', pg_catalog.to_jsonb(result), 'standard_areas_added', seeded, 'reason', pg_catalog.btrim(p_reason))::text);
  return pg_catalog.jsonb_build_object('ok', true, 'facility', pg_catalog.to_jsonb(result), 'standard_areas_added', seeded);
end;$function$;
create or replace function public.admin_add_facility_area(p_facility_id uuid, p_area_code text, p_name text, p_level text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor_for(p_facility_id); v_code text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_area_code,''))); result public.facility_areas%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator or this facility''s Facility Administrator may add areas.'); end if;
  if not exists(select 1 from public.sites s where s.id = p_facility_id and s.is_active) then return public.work_order_result_error('NOT_FOUND','Active facility not found.'); end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{1,19}$' then return public.work_order_result_error('VALIDATION_ERROR','Area code: 2 to 20 letters, numbers or dashes, e.g. ELR-02.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_name,''))) not between 2 and 120 then return public.work_order_result_error('VALIDATION_ERROR','Enter the area name.'); end if;
  if exists(select 1 from public.facility_areas a where a.facility_id = p_facility_id and a.area_code = v_code) then
    return public.work_order_result_error('VALIDATION_ERROR','This facility already has an area with that code.'); end if;
  insert into public.facility_areas(facility_id, area_code, name, level)
  values (p_facility_id, v_code, pg_catalog.btrim(p_name), nullif(pg_catalog.btrim(coalesce(p_level,'')),'')) returning * into result;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, 'facility_area_added', actor->>'display_name', pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'area', pg_catalog.to_jsonb(result))::text);
  return pg_catalog.jsonb_build_object('ok', true, 'area', pg_catalog.to_jsonb(result));
end;$function$;
create or replace function public.admin_set_facility_membership(p_facility_id uuid, p_profile_id uuid, p_active boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor_for(p_facility_id); person public.profiles%rowtype; changed integer := 0;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator or this facility''s Facility Administrator may change its staff.'); end if;
  if not exists(select 1 from public.sites s where s.id = p_facility_id) then return public.work_order_result_error('NOT_FOUND','Facility not found.'); end if;
  select * into person from public.profiles where id = p_profile_id;
  if person.id is null or person.deleted_at is not null then return public.work_order_result_error('NOT_FOUND','Person not found.'); end if;
  if person.role not in ('technician','approver','supervisor','facility_manager','finance','facility_administrator') then
    return public.work_order_result_error('VALIDATION_ERROR','Technicians, Approvers, Supervisors, Facility Managers, Finance and Facility Administrators belong to facilities; the Super-Administrator sees all.'); end if;
  if person.role = 'facility_administrator' and actor->>'role' <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator appoints or removes a Facility Administrator.'); end if;
  if person.id = (actor->>'id')::uuid and actor->>'role' <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED','You cannot change your own facility membership.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason for the change.'); end if;
  if coalesce(p_active, true) then
    if not exists(select 1 from public.sites s where s.id = p_facility_id and s.is_active) then return public.work_order_result_error('VALIDATION_ERROR','The facility is switched off.'); end if;
    if exists(select 1 from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = person.id and m.membership_role = person.role and m.active) then
      return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE'); end if;
    insert into public.facility_memberships(facility_id, profile_id, membership_role, created_by) values (p_facility_id, person.id, person.role, (actor->>'id')::uuid);
    changed := 1;
  else
    update public.facility_memberships set active = false, effective_to = greatest(pg_catalog.now(), effective_from + interval '1 millisecond'), updated_at = pg_catalog.now()
     where facility_id = p_facility_id and profile_id = person.id and active;
    get diagnostics changed = row_count;
    if changed = 0 then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE'); end if;
  end if;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, case when coalesce(p_active, true) then 'facility_staff_added' else 'facility_staff_removed' end, actor->>'display_name',
    pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'profile_id', person.id, 'display_name', person.display_name, 'role', person.role, 'reason', pg_catalog.btrim(p_reason))::text);
  return pg_catalog.jsonb_build_object('ok', true, 'changed', changed);
end;$function$;
create or replace function public.admin_facility_staff(p_facility_id uuid)
returns table(profile_id uuid, display_name text, email text, role text, member boolean, member_since timestamptz)
language sql stable security definer set search_path = pg_catalog as $function$
  select p.id, p.display_name, p.email, p.role,
    exists(select 1 from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = p.id and m.membership_role = p.role and m.active),
    (select pg_catalog.min(m.effective_from) from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = p.id and m.active)
  from public.profiles p
  where public.facility_admin_actor_for(p_facility_id) is not null and p.is_active and p.deleted_at is null
    and p.role in ('technician','approver','supervisor','facility_manager','finance','facility_administrator')
    -- a Facility Administrator sees its own staff and people not yet in any facility, never other facilities' staff
    and (public.current_user_role() = 'administrator'
      or exists(select 1 from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = p.id and m.active)
      or not exists(select 1 from public.facility_memberships m where m.profile_id = p.id and m.active))
  order by case p.role when 'facility_administrator' then 0 when 'technician' then 1 when 'approver' then 2 when 'supervisor' then 3 when 'facility_manager' then 4 else 5 end, p.display_name
$function$;
create or replace function public.admin_register_facility_drawing_revision(p_facility_id uuid, p_code text, p_title text, p_revision text,
  p_original_filename text, p_content_type text, p_byte_size bigint, p_width integer, p_height integer, p_storage_path text,
  p_pin_image_path text, p_pin_width integer, p_pin_height integer)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare
  actor jsonb := public.facility_admin_actor_for(p_facility_id);
  v_code text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_code, '')));
  v_revision text := nullif(pg_catalog.btrim(coalesce(p_revision, '')), '');
  v_pdf boolean := p_content_type = 'application/pdf';
  previous public.facility_drawings%rowtype;
  result public.facility_drawings%rowtype;
  prefix text := 'drawings/facility/' || p_facility_id::text || '/';
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'Only the Super-Administrator or this facility''s Facility Administrator may add drawings.'); end if;
  if not exists (select 1 from public.sites s where s.id = p_facility_id and s.is_active) then
    return public.work_order_result_error('NOT_FOUND', 'Active facility not found.'); end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{0,23}$' then
    return public.work_order_result_error('VALIDATION_ERROR', 'Drawing number: letters, numbers and dashes, e.g. ABC-001.'); end if;
  if v_code in ('FW-001', 'FW-002', 'FW-003', 'FW-004', 'FW-005') then
    return public.work_order_result_error('VALIDATION_ERROR', 'FW-001 to FW-005 are the mock-up drawings; choose another drawing number.'); end if;
  if p_storage_path is null or p_storage_path not like prefix || '%'
     or not exists (select 1 from storage.objects o where o.bucket_id = 'field-evidence' and o.name = p_storage_path) then
    return public.work_order_result_error('INVALID_STORAGE_OBJECT', 'The uploaded drawing file could not be verified.'); end if;
  if p_pin_image_path is not null and (not v_pdf or p_pin_image_path not like prefix || '%'
     or not exists (select 1 from storage.objects o where o.bucket_id = 'field-evidence' and o.name = p_pin_image_path)) then
    return public.work_order_result_error('INVALID_STORAGE_OBJECT', 'The pin image made from the PDF could not be verified.'); end if;

  select * into previous from public.facility_drawings d
   where d.facility_id = p_facility_id and d.code = v_code and d.active for update;
  if previous.id is not null then
    if pg_catalog.lower(coalesce(previous.revision, '')) = pg_catalog.lower(coalesce(v_revision, '')) then
      return public.work_order_result_error('VALIDATION_ERROR', pg_catalog.format(
        '%s %s is already the current revision. Enter the new revision (e.g. Rev B) to replace it.', v_code, coalesce(previous.revision, '(no revision)')));
    end if;
    update public.facility_drawings
       set active = false, removed_by = (actor ->> 'id')::uuid, removed_at = pg_catalog.now(), superseded_at = pg_catalog.now(),
           removal_reason = pg_catalog.format('Superseded by %s', coalesce(v_revision, 'a new upload'))
     where id = previous.id;
  end if;

  insert into public.facility_drawings(facility_id, code, title, revision, original_filename, content_type, byte_size, width, height,
    storage_path, uploaded_by, pin_image_path, pin_width, pin_height)
  values (p_facility_id, v_code, pg_catalog.btrim(p_title), v_revision, p_original_filename, p_content_type, p_byte_size,
    case when v_pdf then null else p_width end, case when v_pdf then null else p_height end, p_storage_path, (actor ->> 'id')::uuid,
    case when v_pdf then p_pin_image_path end, case when v_pdf and p_pin_image_path is not null then p_pin_width end,
    case when v_pdf and p_pin_image_path is not null then p_pin_height end)
  returning * into result;
  if previous.id is not null then update public.facility_drawings set superseded_by = result.id where id = previous.id; end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor ->> 'id')::uuid, case when previous.id is null then 'facility_drawing_added' else 'facility_drawing_revised' end, actor ->> 'display_name',
    pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'drawing_id', result.id, 'code', result.code, 'title', result.title,
      'revision', result.revision, 'filename', result.original_filename, 'pin_image', result.pin_image_path is not null,
      'superseded_drawing_id', previous.id, 'superseded_revision', previous.revision)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'drawing', pg_catalog.to_jsonb(result), 'superseded_revision', previous.revision,
    'superseded', previous.id is not null);
exception when check_violation or unique_violation then
  return public.work_order_result_error('VALIDATION_ERROR', 'Drawing details are invalid (title 2–200 characters; PNG, JPG, WebP or PDF up to 50 MB).');
end;
$function$;
create or replace function public.admin_remove_facility_drawing(p_drawing_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor_for((select d.facility_id from public.facility_drawings d where d.id = p_drawing_id)); result public.facility_drawings%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator or this facility''s Facility Administrator may remove drawings.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason for removing the drawing.'); end if;
  update public.facility_drawings set active = false, removed_by = (actor->>'id')::uuid, removed_at = pg_catalog.now(), removal_reason = pg_catalog.btrim(p_reason)
   where id = p_drawing_id and active returning * into result;
  if result.id is null then return public.work_order_result_error('NOT_FOUND','Active drawing not found.'); end if;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, 'facility_drawing_removed', actor->>'display_name',
    pg_catalog.jsonb_build_object('facility_id', result.facility_id, 'drawing_id', result.id, 'code', result.code, 'reason', result.removal_reason)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'drawing', pg_catalog.to_jsonb(result));
end;$function$;
create or replace function public.set_facility_settings(p_facility_id uuid, p_designated_approver_id uuid, p_endorsement_stage text, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor_for(p_facility_id); actor_id uuid; before jsonb; after public.facility_settings%rowtype; approver public.profiles%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator or this facility''s Facility Administrator may change its settings.'); end if;
  actor_id := (actor->>'id')::uuid;
  if not exists(select 1 from public.sites s where s.id = p_facility_id) then return public.work_order_result_error('NOT_FOUND','Facility not found.'); end if;
  if p_endorsement_stage is null or p_endorsement_stage not in ('before_submission','before_review','both') then
    return public.work_order_result_error('VALIDATION_ERROR','Choose when the second Technician endorses.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason for the change.'); end if;
  if p_designated_approver_id is not null then
    select * into approver from public.profiles where id = p_designated_approver_id;
    if approver.id is null or not public.pilot_account_ready(approver.id) or approver.role not in ('approver','supervisor','facility_manager','administrator') then
      return public.work_order_result_error('VALIDATION_ERROR','The designated Approver must be an active Approver, Supervisor, Facility Manager or Administrator.'); end if;
    if approver.role <> 'administrator' and not exists(select 1 from public.facility_memberships m where m.profile_id = approver.id and m.facility_id = p_facility_id
         and m.active and m.membership_role = approver.role and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now())) then
      return public.work_order_result_error('VALIDATION_ERROR','The designated Approver must belong to this facility.'); end if;
  end if;
  select pg_catalog.to_jsonb(s) into before from public.facility_settings s where s.facility_id = p_facility_id;
  insert into public.facility_settings(facility_id, designated_approver_id, endorsement_stage, updated_by, updated_at)
  values (p_facility_id, p_designated_approver_id, p_endorsement_stage, actor_id, pg_catalog.now())
  on conflict (facility_id) do update set designated_approver_id = excluded.designated_approver_id, endorsement_stage = excluded.endorsement_stage,
    updated_by = excluded.updated_by, updated_at = excluded.updated_at
  returning * into after;
  insert into public.facility_settings_history(facility_id, previous, next, reason, changed_by)
  values (p_facility_id, before, pg_catalog.to_jsonb(after), pg_catalog.btrim(p_reason), actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'settings',pg_catalog.to_jsonb(after));
end;$function$;
create or replace function public.facility_approver_candidates(p_facility_id uuid)
returns table(id uuid, display_name text, role text)
language sql stable security definer set search_path = pg_catalog as $function$
  select p.id, p.display_name, p.role from public.profiles p
  where public.facility_admin_actor_for(p_facility_id) is not null and public.pilot_account_ready(p.id)
    and (p.role = 'administrator' or (p.role in ('approver','supervisor','facility_manager') and exists(
      select 1 from public.facility_memberships m where m.profile_id = p.id and m.facility_id = p_facility_id and m.active and m.membership_role = p.role
        and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now()))))
  order by case p.role when 'approver' then 1 when 'supervisor' then 2 when 'facility_manager' then 3 else 4 end, p.display_name
$function$;

-- 6. Accounts: a Facility Administrator creates and edits accounts for its own facility only -----------------------

create or replace function public.admin_finalize_provisioned_profile(p_target_id uuid, p_payload jsonb, p_event text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  target_profile public.profiles%rowtype;
  result public.profiles%rowtype;
  target_role text := lower(trim(coalesce(p_payload ->> 'role', '')));
  target_name text := trim(coalesce(p_payload ->> 'display_name', ''));
  target_trade text := nullif(trim(coalesce(p_payload ->> 'trade_discipline', '')), '');
  target_department_id uuid := nullif(p_payload ->> 'department_id', '')::uuid;
  target_active boolean := coalesce((p_payload ->> 'is_active')::boolean, true);
  target_facility uuid := nullif(p_payload ->> 'facility_id', '')::uuid;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role not in ('administrator','facility_administrator')
    or not public.pilot_account_ready(actor_profile.id)
  then raise exception 'Administrator authorization required'; end if;
  if actor_profile.role = 'facility_administrator' then
    if target_facility is null or not public.active_facility_member(target_facility, 'facility_administrator', actor_profile.id) then
      raise exception 'Facility Administrators create accounts only for their own facility'; end if;
    if target_role not in ('technician','approver','supervisor','facility_manager','finance') then
      raise exception 'Facility Administrators may create Technician, Approver, Supervisor, Facility Manager or Finance accounts only'; end if;
  end if;
  if target_facility is not null and not exists(select 1 from public.sites s where s.id = target_facility and s.is_active) then
    raise exception 'Facility is unavailable'; end if;
  if p_event not in ('user_admin_invited','user_admin_direct_created','user_admin_pending_activated')
  then raise exception 'Unsupported provisioning event'; end if;

  select * into target_profile from public.profiles where id = p_target_id for update;
  if target_profile.id is null then raise exception 'Quarantine profile was not created'; end if;
  if target_role not in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance','facility_administrator')
    or target_name = ''
  then raise exception 'Invalid profile values'; end if;
  if target_role = 'technician' and target_trade is null then
    raise exception 'Technicians require a trade or discipline';
  end if;
  if target_department_id is not null and not exists (
    select 1 from public.departments where id = target_department_id and deleted_at is null
  ) then raise exception 'Department is unavailable'; end if;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set
    display_name = target_name,
    department_id = target_department_id,
    trade_discipline = case when target_role = 'technician' then target_trade else null end,
    contact_number = nullif(trim(coalesce(p_payload ->> 'contact_number', '')), ''),
    role = target_role,
    is_active = target_active,
    deleted_at = null,
    password_change_required = true
  where id = p_target_id
  returning * into result;

  -- D-54: an account created for a facility joins it at once (not for the Super-Administrator role itself).
  if target_facility is not null and target_role in ('technician','approver','supervisor','facility_manager','finance','facility_administrator')
     and not exists(select 1 from public.facility_memberships m where m.facility_id = target_facility and m.profile_id = result.id and m.membership_role = target_role and m.active) then
    insert into public.facility_memberships(facility_id, profile_id, membership_role, created_by) values (target_facility, result.id, target_role, actor_profile.id);
  end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    p_event,
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', result.id,
      'role', result.role,
      'is_active', result.is_active,
      'facility_id', target_facility,
      'password_change_required', true
    )::text
  );

  return pg_catalog.to_jsonb(result);
end;
$function$;
create or replace function public.admin_update_profile(p_target_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  previous_profile public.profiles%rowtype;
  result public.profiles%rowtype;
  next_role text;
  next_display_name text;
  next_trade text;
  next_active boolean;
  next_department_id uuid;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role not in ('administrator','facility_administrator')
    or not public.pilot_account_ready(actor_profile.id)
  then
    raise exception 'Administrator authorization required';
  end if;

  select * into previous_profile from public.profiles
  where id = p_target_id and deleted_at is null for update;
  if previous_profile.id is null then raise exception 'Profile not found'; end if;

  next_role := lower(trim(coalesce(p_payload ->> 'role', previous_profile.role)));
  next_display_name := trim(coalesce(p_payload ->> 'display_name', previous_profile.display_name));
  next_trade := nullif(trim(case when p_payload ? 'trade_discipline'
    then coalesce(p_payload ->> 'trade_discipline', '')
    else coalesce(previous_profile.trade_discipline, '') end), '');
  next_active := case when p_payload ? 'is_active'
    then (p_payload ->> 'is_active')::boolean else previous_profile.is_active end;
  next_department_id := case when p_payload ? 'department_id'
    then nullif(p_payload ->> 'department_id', '')::uuid
    else previous_profile.department_id end;

  if next_role not in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance','facility_administrator')
    or next_display_name = ''
  then raise exception 'Invalid profile values'; end if;
  if next_role = 'technician' and next_trade is null then
    raise exception 'Technicians require a trade or discipline';
  end if;
  -- D-54: a Facility Administrator edits only its own facility's staff, never itself, and never into or out of an
  -- administrator role.
  if actor_profile.role = 'facility_administrator' then
    if previous_profile.id = actor_profile.id then raise exception 'You cannot change your own account here'; end if;
    if previous_profile.role in ('administrator','facility_administrator') or next_role not in ('technician','approver','supervisor','facility_manager','finance') then
      raise exception 'Facility Administrators manage Technician, Approver, Supervisor, Facility Manager and Finance accounts only'; end if;
    if not exists(select 1 from public.facility_memberships m join public.facility_memberships mine on mine.facility_id = m.facility_id
        where m.profile_id = previous_profile.id and m.active and mine.profile_id = actor_profile.id and mine.membership_role = 'facility_administrator' and mine.active) then
      raise exception 'This person is not staff of your facility'; end if;
  end if;
  if next_department_id is not null and not exists (
    select 1 from public.departments where id = next_department_id and deleted_at is null
  ) then raise exception 'Department is unavailable'; end if;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set
    display_name = next_display_name,
    department_id = next_department_id,
    trade_discipline = case when next_role = 'technician' then next_trade else null end,
    contact_number = case when p_payload ? 'contact_number'
      then nullif(trim(coalesce(p_payload ->> 'contact_number', '')), '')
      else contact_number end,
    role = next_role,
    is_active = next_active
  where id = p_target_id
  returning * into result;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    'user_admin_profile_updated',
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', result.id,
      'previous_role', previous_profile.role,
      'role', result.role,
      'previous_active', previous_profile.is_active,
      'is_active', result.is_active
    )::text
  );

  return pg_catalog.to_jsonb(result);
end;
$function$;

-- 7. D-55: remove a person's details for good (Super-Administrator only); records stay under "Former user NNNN" --------
create sequence if not exists public.former_user_seq;
create or replace function public.admin_remove_personal_details(p_target_id uuid, p_confirmation text, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor_profile public.profiles%rowtype; target public.profiles%rowtype; label text; placeholder text; ready_admins integer;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator' or not public.pilot_account_ready(actor_profile.id) then
    return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator may remove a person''s details.'); end if;
  select * into target from public.profiles where id = p_target_id for update;
  if target.id is null then return public.work_order_result_error('NOT_FOUND','Person not found.'); end if;
  if target.id = actor_profile.id then return public.work_order_result_error('VALIDATION_ERROR','You cannot remove your own details.'); end if;
  if target.email like '%@removed.invalid' then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE'); end if;
  if pg_catalog.lower(pg_catalog.btrim(coalesce(p_confirmation,''))) not in (pg_catalog.lower(pg_catalog.btrim(coalesce(target.email,''))), pg_catalog.lower(pg_catalog.btrim(coalesce(target.display_name,'')))) then
    return public.work_order_result_error('VALIDATION_ERROR','Type the person''s email exactly to confirm.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason.'); end if;
  if exists(select 1 from public.work_orders w where w.assigned_technician_id = target.id and w.status not in ('closed','cancelled','reviewed')) then
    return public.work_order_result_error('VALIDATION_ERROR','Reassign this person''s open Work Orders first.'); end if;
  if target.role = 'administrator' then
    select count(*) into ready_admins from public.profiles where role = 'administrator' and is_active and deleted_at is null and id <> target.id;
    if ready_admins < 1 then return public.work_order_result_error('VALIDATION_ERROR','The last Super-Administrator cannot be removed.'); end if;
  end if;
  label := 'Former user ' || pg_catalog.lpad(pg_catalog.nextval('public.former_user_seq')::text, 4, '0');
  placeholder := 'former-' || pg_catalog.replace(target.id::text, '-', '') || '@removed.invalid';
  -- the person's name and email are taken out of the history as well
  update public.activity_logs set actor = label where user_id = target.id or actor = target.display_name;
  update public.activity_logs set note = pg_catalog.replace(pg_catalog.replace(note, target.email, placeholder), target.display_name, label)
   where note is not null and (pg_catalog.strpos(note, target.email) > 0 or pg_catalog.strpos(note, target.display_name) > 0);
  update public.notification_outbox set recipient_email = null where recipient_profile_id = target.id or recipient_user_id = target.id;
  update public.facility_memberships set active = false, effective_to = greatest(pg_catalog.now(), effective_from + interval '1 millisecond'), updated_at = pg_catalog.now()
   where profile_id = target.id and active;
  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set display_name = label, email = placeholder, contact_number = null, trade_discipline = null,
    is_active = false, deleted_at = coalesce(deleted_at, pg_catalog.now()) where id = target.id;
  insert into public.activity_logs(user_id, action, actor, note)
  values (actor_profile.id, 'user_admin_personal_details_removed', actor_profile.display_name,
    pg_catalog.jsonb_build_object('target_profile_id', target.id, 'now_shown_as', label, 'previous_role', target.role, 'reason', pg_catalog.btrim(p_reason))::text);
  return pg_catalog.jsonb_build_object('ok', true, 'label', label, 'placeholder_email', placeholder);
end;$function$;
revoke all on function public.admin_remove_personal_details(uuid,text,text) from public, anon, service_role;
grant execute on function public.admin_remove_personal_details(uuid,text,text) to authenticated;

commit;

-- WP-WO-009: Completed Work evidence, Facility Manager authority, contractor costing and area controls.
-- Apply only after migrations 0012-0023 on the FMWorks Preview/UAT chain.
begin;

do $preflight$
begin
  if current_user <> 'postgres' then raise exception '0024 must be applied as postgres'; end if;
  if to_regclass('public.work_orders') is null
    or to_regclass('public.profiles') is null
    or to_regclass('public.vendors') is null
    or to_regclass('public.evidence_items') is null
    or to_regprocedure('public.transition_work_order(uuid,text,jsonb)') is null
  then raise exception '0024 prerequisite missing'; end if;
end;
$preflight$;

-- Facility Manager is an authorised operational approval role.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in (
  'reviewer','initiator','approver','technician','supervisor','facility_manager','administrator'
));
alter table public.account_invitations drop constraint if exists account_invitations_role_check;
alter table public.account_invitations add constraint account_invitations_role_check check (assigned_role in (
  'reviewer','initiator','approver','technician','supervisor','facility_manager','administrator'
));

-- Evidence categories are intentionally limited to Before and After.
-- Existing legacy categories are retained for historical records but cannot be newly inserted.
alter table public.evidence_items drop constraint if exists evidence_items_category_check;
alter table public.evidence_items add constraint evidence_items_category_check
  check (category in ('before','after','completion','document','other'));

-- Contractor master data and pre-agreed service/rate schedules.
alter table public.vendors add column if not exists company_registration_no text;
alter table public.vendors add column if not exists vendor_type text not null default 'specialist_contractor';
alter table public.vendors add column if not exists emergency_available boolean not null default false;
alter table public.vendors add column if not exists payment_terms_days integer not null default 30 check (payment_terms_days > 0);

create table if not exists public.contractor_service_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.contractor_service_categories(code,name) values
 ('LIFT','Lift Maintenance'),('HVAC','HVAC'),('FIRE_ALARM','Fire Alarm Testing'),
 ('FIRE_PROTECTION','Fire Protection System'),('PLUMBING','Plumbing and Sanitary'),
 ('TRANSFORMER','Electrical - Transformer'),('SWITCHGEAR','Electrical - Switchgear'),
 ('ELECTRICAL','Electrical - General'),('SOLAR','Solar Power System'),('CLEANING','Cleaning Systems'),
 ('FUMIGATION','Fumigation Service'),('LANDSCAPING','Landscaping'),('FITOUT','Building Fit-out / Interior Finishes'),
 ('LIGHTING_CONTROL','Lighting Control System'),('BMS','Building Management System'),
 ('PUMPS','Pumps / Rotating Equipment'),('GENERATOR_UPS','Generator / UPS'),('OTHER','Other')
on conflict(code) do nothing;

create table if not exists public.contractor_services (
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  service_category_id uuid not null references public.contractor_service_categories(id) on delete restrict,
  is_nominated boolean not null default true,
  emergency_dispatch boolean not null default false,
  effective_from date,
  effective_to date,
  primary key(vendor_id,service_category_id)
);

create table if not exists public.contractor_rate_items (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  service_category_id uuid references public.contractor_service_categories(id) on delete restrict,
  cost_type text not null check(cost_type in ('labour','material','equipment','service','callout')),
  item_code text,
  description text not null,
  unit text not null,
  normal_unit_rate numeric(14,2) not null check(normal_unit_rate >= 0),
  emergency_unit_rate numeric(14,2) check(emergency_unit_rate is null or emergency_unit_rate >= 0),
  currency text not null default 'SGD',
  effective_from date not null,
  effective_to date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check(effective_to is null or effective_to >= effective_from)
);

create table if not exists public.work_order_cost_lines (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  vendor_id uuid references public.vendors(id) on delete restrict,
  rate_item_id uuid references public.contractor_rate_items(id) on delete restrict,
  worker_name text,
  cost_type text not null check(cost_type in ('labour','material','equipment','service','callout')),
  description text not null,
  quantity numeric(14,2) not null check(quantity >= 0),
  unit text not null,
  unit_rate numeric(14,2) not null check(unit_rate >= 0),
  amount numeric(14,2) generated always as (quantity * unit_rate) stored,
  entered_by uuid not null references public.profiles(id) on delete restrict,
  technician_certified_at timestamptz,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.contractor_payment_assessments (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null unique references public.work_orders(id) on delete restrict,
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  status text not null default 'draft' check(status in ('draft','awaiting_approval','approved_for_payment','paid','returned')),
  assessed_amount numeric(14,2) not null default 0 check(assessed_amount >= 0),
  completed_work_accepted_at timestamptz,
  invoice_received_at timestamptz,
  payment_due_at timestamptz,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Location master supports area codes and later plan/map coordinates.
create table if not exists public.facility_areas (
  id uuid primary key default gen_random_uuid(),
  area_code text not null unique,
  name text not null,
  level text,
  zone text,
  description text,
  drawing_reference text,
  map_x numeric,
  map_y numeric,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.facility_areas(area_code,name) values
 ('REC-01','Reception'),('OFF-01','Office'),('MTR-01','Meeting Room'),('PAN-01','Pantry'),
 ('TLT-01','Toilet'),('WHS-01','Warehouse'),('LDB-01','Loading / Unloading Bay'),
 ('ELR-01','Electrical Room'),('TFR-01','Transformer Room'),('ITR-01','Server / IT Room'),
 ('AHR-01','AHU Room'),('CPR-01','Chiller Plant Room'),('PMR-01','Pump Room'),
 ('FPR-01','Fire Pump Room'),('MWS-01','Maintenance Workshop'),('STR-01','Staircase'),
 ('LFT-01','Lift'),('LBY-01','Lift Lobby'),('COR-01','Corridor'),('ROF-01','Roof'),
 ('CPK-01','Car Park'),('GDH-01','Guard House'),('RHA-01','Rubbish Holding Area'),
 ('LSZ-01','Landscape Zone'),('SYD-01','External / Service Yard')
on conflict(area_code) do nothing;

alter table public.work_orders add column if not exists facility_area_id uuid references public.facility_areas(id) on delete set null;
alter table public.work_orders add column if not exists emergency_work boolean not null default false;
alter table public.work_orders add column if not exists costing_deferred boolean not null default false;

-- Authorised liaison personnel for pre-agreed contractor proposals/rates.
create table if not exists public.authorised_work_liaisons (
  id uuid primary key default gen_random_uuid(),
  discipline text not null check(discipline in ('building_fitout_landscaping','electrical_mechanical')),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  is_primary boolean not null default true,
  effective_from date not null default current_date,
  effective_to date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check(effective_to is null or effective_to >= effective_from)
);

-- RLS: authenticated operational reads; mutations remain through controlled server/admin paths.
foreach_dummy: do $$
declare t text;
begin
  foreach t in array array['contractor_service_categories','contractor_services','contractor_rate_items','work_order_cost_lines','contractor_payment_assessments','facility_areas','authorised_work_liaisons'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
    execute format('grant select on table public.%I to authenticated',t);
    execute format('drop policy if exists authenticated_read on public.%I',t);
    execute format('create policy authenticated_read on public.%I for select to authenticated using (public.pilot_account_ready())',t);
  end loop;
end;
$$;

-- Override the latest transition contract: assigned TIC may mark work Completed directly
-- after emergency/reactive field work, but After evidence is mandatory. Only Supervisor,
-- Facility Manager or Administrator may accept Completed Work.
create or replace function public.transition_work_order(
  p_work_order_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=pg_catalog
as $function$
declare
  actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  previous public.work_orders%rowtype; result public.work_orders%rowtype;
  action text:=pg_catalog.lower(coalesce(p_action,'')); target_status text; reason text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'reason','')),'');
  requested_hours numeric; evidence_ids jsonb:='[]'::jsonb; completion_actor_id uuid;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name',actor->>'display_name'); actor_role:=actor->>'role';
  select * into previous from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if previous.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE','Closed and cancelled work orders are immutable.'); end if;
  target_status:=case action when 'submit' then 'submitted' when 'approve' then 'approved' when 'accept' then 'assigned' when 'start' then 'in_progress' when 'complete' then 'completed' when 'return_for_rework' then 'in_progress' when 'review' then 'reviewed' when 'close' then 'closed' when 'cancel' then 'cancelled' end;
  if target_status is null or not((action='submit' and previous.status='draft') or (action='approve' and previous.status='submitted') or (action='accept' and previous.status='assigned' and previous.accepted_at is null) or (action='start' and previous.status='assigned') or (action='complete' and previous.status in ('assigned','in_progress')) or (action='return_for_rework' and previous.status='completed') or (action='review' and previous.status='completed') or (action='close' and previous.status='reviewed') or (action='cancel' and previous.status in ('draft','submitted','approved','assigned','in_progress','completed','reviewed'))) then return public.work_order_result_error('INVALID_TRANSITION','The requested workflow transition is not allowed.'); end if;
  if action='submit' and not(actor_id=previous.requested_by and actor_role in ('reviewer','initiator','approver','supervisor','facility_manager')) and actor_role<>'administrator' then return public.work_order_result_error('ACCESS_DENIED','Only the requester may submit this work order.'); end if;
  if action='approve' and actor_role not in ('approver','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Approver, Facility Manager or Administrator authority is required.'); end if;
  if action='approve' and actor_id=previous.requested_by and actor_role<>'administrator' then return public.work_order_result_error('SELF_APPROVAL_DENIED','Requesters cannot approve their own work orders.'); end if;
  if action in ('accept','start','complete') and actor_role<>'administrator' and not(actor_role='technician' and actor_id=previous.assigned_technician_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned Technician-in-Charge or an Administrator may perform this action.'); end if;
  if action in ('review','return_for_rework','close') and actor_role not in ('supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Supervisor, Facility Manager or Administrator authority is required.'); end if;
  if action='cancel' and actor_role not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Your role cannot cancel work orders.'); end if;
  if action='cancel' and reason is null then return public.work_order_result_error('CANCELLATION_REASON_REQUIRED','A cancellation reason is required.'); end if;
  if action='return_for_rework' and reason is null then return public.work_order_result_error('REWORK_REASON_REQUIRED','A rework reason is required.'); end if;
  if action='complete' then
    begin requested_hours:=nullif(p_payload->>'actual_labour_hours','')::numeric; exception when others then requested_hours:=null; end;
    if nullif(pg_catalog.btrim(coalesce(p_payload->>'completion_notes','')),'') is null or requested_hours is null or requested_hours<0 then return public.work_order_result_error('COMPLETED_DETAILS_REQUIRED','Work performed statement and non-negative labour hours are required.'); end if;
    if not exists(select 1 from public.evidence_items e where e.work_order_id=previous.id and e.category='after') then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','Upload After photo or PDF evidence before marking this Work Order Completed.'); end if;
    select coalesce(pg_catalog.jsonb_agg(e.id order by e.uploaded_at,e.id),'[]'::jsonb) into evidence_ids from public.evidence_items e where e.work_order_id=previous.id;
  end if;
  if action='review' then
    select l.user_id into completion_actor_id from public.activity_logs l where l.work_order_id=previous.id and l.action='work_order_complete' order by l.created_at desc,l.id desc limit 1;
    if actor_id=completion_actor_id then return public.work_order_result_error('SELF_REVIEW_DENIED','Completed Work must be accepted by a different authorised person.'); end if;
  end if;
  update public.work_orders set status=target_status,
    submitted_at=case when action='submit' then now() else submitted_at end,
    approved_at=case when action='approve' then now() else approved_at end,
    accepted_at=case when action='accept' then now() else accepted_at end,
    started_at=case when action='start' then now() when action='complete' and started_at is null then now() else started_at end,
    completed_at=case when action='complete' then now() when action='return_for_rework' then null else completed_at end,
    reviewed_at=case when action='review' then now() else reviewed_at end,
    closed_at=case when action='close' then now() else closed_at end,
    cancelled_at=case when action='cancel' then now() else cancelled_at end,
    completion_notes=case when action='complete' then pg_catalog.btrim(p_payload->>'completion_notes') else completion_notes end,
    actual_labour_hours=case when action='complete' then requested_hours else actual_labour_hours end,
    cancellation_reason=case when action='cancel' then reason else cancellation_reason end, updated_at=now()
  where id=previous.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,result.id,'work_order_'||action,previous.status,result.status,actor_name,pg_catalog.jsonb_build_object('reason',reason,'payload',p_payload,'evidence_ids',case when action='complete' then evidence_ids else '[]'::jsonb end,'direct_completed_from_assigned',action='complete' and previous.status='assigned')::text);
  if action='review' and result.assigned_vendor_id is not null then
    insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,payment_due_at)
    values(result.id,result.assigned_vendor_id,'awaiting_approval',coalesce((select sum(amount) from public.work_order_cost_lines where work_order_id=result.id),0),now(),now()+interval '30 days')
    on conflict(work_order_id) do update set status='awaiting_approval',assessed_amount=excluded.assessed_amount,completed_work_accepted_at=excluded.completed_work_accepted_at,payment_due_at=excluded.payment_due_at,updated_at=now();
  end if;
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
exception when others then return public.work_order_result_error('INTERNAL_ERROR','Work-order transition failed.'); end;
$function$;

revoke all on function public.transition_work_order(uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.transition_work_order(uuid,text,jsonb) to authenticated;

commit;

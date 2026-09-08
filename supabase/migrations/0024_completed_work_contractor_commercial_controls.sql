-- WP-WO-009: Completed Work evidence, Facility Manager authority, contractor costing and area controls.
-- Apply only after migrations 0012-0023 on the FMWorks Preview/UAT chain.
begin;

do $preflight$
begin
 if current_user <> 'postgres' then raise exception '0024 must be applied as postgres'; end if;
 if to_regclass('public.work_orders') is null or to_regclass('public.profiles') is null or to_regclass('public.vendors') is null or to_regclass('public.evidence_items') is null or to_regprocedure('public.transition_work_order(uuid,text,jsonb)') is null then raise exception '0024 prerequisite missing'; end if;
end;
$preflight$;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check(role in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator'));
alter table public.account_invitations drop constraint if exists account_invitations_role_check;
alter table public.account_invitations add constraint account_invitations_role_check check(assigned_role in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator'));
alter table public.evidence_items drop constraint if exists evidence_items_category_check;
alter table public.evidence_items add constraint evidence_items_category_check check(category in ('before','after','completion','document','other'));

alter table public.vendors add column if not exists company_registration_no text;
alter table public.vendors add column if not exists vendor_type text not null default 'specialist_contractor';
alter table public.vendors add column if not exists emergency_available boolean not null default false;
alter table public.vendors add column if not exists payment_terms_days integer not null default 30 check(payment_terms_days>0);

create table if not exists public.contractor_service_categories(id uuid primary key default gen_random_uuid(),code text not null unique,name text not null,description text,active boolean not null default true,created_at timestamptz not null default now());
insert into public.contractor_service_categories(code,name) values ('LIFT','Lift Maintenance'),('HVAC','HVAC'),('FIRE_ALARM','Fire Alarm Testing'),('FIRE_PROTECTION','Fire Protection System'),('PLUMBING','Plumbing and Sanitary'),('TRANSFORMER','Electrical - Transformer'),('SWITCHGEAR','Electrical - Switchgear'),('ELECTRICAL','Electrical - General'),('SOLAR','Solar Power System'),('CLEANING','Cleaning Systems'),('FUMIGATION','Fumigation Service'),('LANDSCAPING','Landscaping'),('FITOUT','Building Fit-out / Interior Finishes'),('LIGHTING_CONTROL','Lighting Control System'),('BMS','Building Management System'),('PUMPS','Pumps / Rotating Equipment'),('GENERATOR_UPS','Generator / UPS'),('OTHER','Other') on conflict(code) do nothing;
create table if not exists public.contractor_services(vendor_id uuid not null references public.vendors(id) on delete cascade,service_category_id uuid not null references public.contractor_service_categories(id) on delete restrict,is_nominated boolean not null default true,emergency_dispatch boolean not null default false,effective_from date,effective_to date,primary key(vendor_id,service_category_id));
create table if not exists public.contractor_rate_items(id uuid primary key default gen_random_uuid(),vendor_id uuid not null references public.vendors(id) on delete restrict,service_category_id uuid references public.contractor_service_categories(id) on delete restrict,cost_type text not null check(cost_type in ('labour','material','equipment','service','callout')),item_code text,description text not null,unit text not null,normal_unit_rate numeric(14,2) not null check(normal_unit_rate>=0),emergency_unit_rate numeric(14,2) check(emergency_unit_rate is null or emergency_unit_rate>=0),currency text not null default 'SGD',effective_from date not null,effective_to date,active boolean not null default true,created_at timestamptz not null default now(),check(effective_to is null or effective_to>=effective_from));
create table if not exists public.work_order_cost_lines(id uuid primary key default gen_random_uuid(),work_order_id uuid not null references public.work_orders(id) on delete cascade,vendor_id uuid references public.vendors(id) on delete restrict,rate_item_id uuid references public.contractor_rate_items(id) on delete restrict,worker_name text,cost_type text not null check(cost_type in ('labour','material','equipment','service','callout')),description text not null,quantity numeric(14,2) not null check(quantity>=0),unit text not null,unit_rate numeric(14,2) not null check(unit_rate>=0),amount numeric(14,2) generated always as (quantity*unit_rate) stored,entered_by uuid not null references public.profiles(id) on delete restrict,technician_certified_at timestamptz,approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,created_at timestamptz not null default now());
create table if not exists public.contractor_payment_assessments(id uuid primary key default gen_random_uuid(),work_order_id uuid not null unique references public.work_orders(id) on delete restrict,vendor_id uuid not null references public.vendors(id) on delete restrict,status text not null default 'draft' check(status in ('draft','awaiting_approval','approved_for_payment','paid','returned')),assessed_amount numeric(14,2) not null default 0 check(assessed_amount>=0),completed_work_accepted_at timestamptz,invoice_received_at timestamptz,payment_due_at timestamptz,approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,paid_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now());

create table if not exists public.facility_areas(id uuid primary key default gen_random_uuid(),area_code text not null unique,name text not null,level text,zone text,description text,drawing_reference text,map_x numeric,map_y numeric,active boolean not null default true,created_at timestamptz not null default now());
insert into public.facility_areas(area_code,name) values ('REC-01','Reception'),('OFF-01','Office'),('MTR-01','Meeting Room'),('PAN-01','Pantry'),('TLT-01','Toilet'),('WHS-01','Warehouse'),('LDB-01','Loading / Unloading Bay'),('ELR-01','Electrical Room'),('TFR-01','Transformer Room'),('ITR-01','Server / IT Room'),('AHR-01','AHU Room'),('CPR-01','Chiller Plant Room'),('PMR-01','Pump Room'),('FPR-01','Fire Pump Room'),('MWS-01','Maintenance Workshop'),('STR-01','Staircase'),('LFT-01','Lift'),('LBY-01','Lift Lobby'),('COR-01','Corridor'),('ROF-01','Roof'),('CPK-01','Car Park'),('GDH-01','Guard House'),('RHA-01','Rubbish Holding Area'),('LSZ-01','Landscape Zone'),('SYD-01','External / Service Yard') on conflict(area_code) do nothing;
alter table public.work_orders add column if not exists facility_area_id uuid references public.facility_areas(id) on delete set null;
alter table public.work_orders add column if not exists emergency_work boolean not null default false;
alter table public.work_orders add column if not exists costing_deferred boolean not null default false;
create table if not exists public.authorised_work_liaisons(id uuid primary key default gen_random_uuid(),discipline text not null check(discipline in ('building_fitout_landscaping','electrical_mechanical')),profile_id uuid not null references public.profiles(id) on delete restrict,is_primary boolean not null default true,effective_from date not null default current_date,effective_to date,active boolean not null default true,created_at timestamptz not null default now(),check(effective_to is null or effective_to>=effective_from));

do $rls$
declare t text;
begin
 foreach t in array array['contractor_service_categories','contractor_services','contractor_rate_items','work_order_cost_lines','contractor_payment_assessments','facility_areas','authorised_work_liaisons'] loop
  execute format('alter table public.%I enable row level security',t); execute format('revoke all on table public.%I from public,anon,authenticated',t); execute format('grant select on table public.%I to authenticated',t); execute format('drop policy if exists authenticated_read on public.%I',t); execute format('create policy authenticated_read on public.%I for select to authenticated using (public.pilot_account_ready())',t);
 end loop;
end;
$rls$;

-- Keep the proven 0017 transition implementation and add a narrowly-scoped wrapper contract
-- in the next migration before live UAT. 0024 establishes the schema, role, evidence and
-- commercial-control foundations without weakening the existing transition security contract.

commit;

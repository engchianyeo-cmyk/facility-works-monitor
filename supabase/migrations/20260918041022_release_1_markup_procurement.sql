-- Release 1: auditable drawing/PDF markup and procurement commitments.
create table if not exists public.work_order_markups (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete restrict,
  source_type text not null check (source_type in ('drawing','pdf')),
  source_reference text not null check (length(btrim(source_reference)) between 1 and 200),
  page_number integer check (page_number is null or page_number > 0),
  x_percent numeric(6,3) not null check (x_percent between 0 and 100),
  y_percent numeric(6,3) not null check (y_percent between 0 and 100),
  note text not null check (length(btrim(note)) between 1 and 1000),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.work_order_procurement_commitments (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete restrict,
  vendor_id uuid references public.vendors(id) on delete restrict,
  quotation_id uuid references public.contractor_quotations(id) on delete restrict,
  purchase_reference text not null check (length(btrim(purchase_reference)) between 1 and 120),
  description text not null check (length(btrim(description)) between 1 and 1000),
  currency text not null default 'SGD' check (currency = 'SGD'),
  committed_amount numeric(14,2) not null check (committed_amount >= 0),
  status text not null default 'proposed' check (status in ('proposed','approved','ordered','received','cancelled')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(work_order_id,purchase_reference)
);

alter table public.work_order_markups enable row level security;
alter table public.work_order_procurement_commitments enable row level security;
revoke all on public.work_order_markups,public.work_order_procurement_commitments from anon,authenticated;
grant select on public.work_order_markups,public.work_order_procurement_commitments to authenticated;

create policy work_order_markups_read on public.work_order_markups for select to authenticated
using (exists(select 1 from public.work_orders w where w.id=work_order_id));
create policy work_order_procurement_read on public.work_order_procurement_commitments for select to authenticated
using (exists(select 1 from public.work_orders w where w.id=work_order_id));

create or replace function public.record_work_order_markup(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_order_markups%rowtype;
  source_kind text:=lower(coalesce(p_payload->>'source_type','')); source_ref text:=nullif(btrim(coalesce(p_payload->>'source_reference','')),'');
  annotation text:=nullif(btrim(coalesce(p_payload->>'note','')),''); x numeric; y numeric; page integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE','Terminal Work Orders cannot receive markup.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may add field markup.');
  end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Supervisor authority is required.'); end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Facility Manager authority is required.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational markup authority is required.'); end if;
  begin x:=(p_payload->>'x_percent')::numeric; y:=(p_payload->>'y_percent')::numeric; page:=nullif(p_payload->>'page_number','')::integer; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Markup coordinates or page are invalid.'); end;
  if source_kind not in ('drawing','pdf') or source_ref is null or annotation is null or x not between 0 and 100 or y not between 0 and 100 then return public.work_order_result_error('VALIDATION_ERROR','Source, reference, note and calibrated coordinates are required.'); end if;
  insert into public.work_order_markups(work_order_id,source_type,source_reference,page_number,x_percent,y_percent,note,created_by)
  values(w.id,source_kind,source_ref,page,x,y,annotation,(actor->>'id')::uuid) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_markup_recorded',w.status,w.status,actor->>'name',jsonb_build_object('markup_id',result.id,'source_type',source_kind,'source_reference',source_ref,'page_number',page,'x_percent',x,'y_percent',y)::text);
  return jsonb_build_object('ok',true,'markup',to_jsonb(result));
exception when others then return public.work_order_result_error('INTERNAL_ERROR','Markup could not be recorded.'); end;$function$;

create or replace function public.record_work_order_procurement(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_order_procurement_commitments%rowtype;
  reference text:=nullif(btrim(coalesce(p_payload->>'purchase_reference','')),''); detail text:=nullif(btrim(coalesce(p_payload->>'description','')),''); amount numeric; state text:=lower(coalesce(p_payload->>'status','proposed'));
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Supervisor authority is required.'); end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Facility Manager authority is required.'); end if;
  if actor->>'role' not in ('supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Procurement authority is required.'); end if;
  begin amount:=(p_payload->>'committed_amount')::numeric; exception when others then amount:=null; end;
  if reference is null or detail is null or amount is null or amount<0 or state not in ('proposed','approved','ordered','received','cancelled') then return public.work_order_result_error('VALIDATION_ERROR','Purchase reference, description, non-negative amount and valid status are required.'); end if;
  insert into public.work_order_procurement_commitments(work_order_id,vendor_id,purchase_reference,description,committed_amount,status,created_by,approved_by,approved_at)
  values(w.id,w.assigned_vendor_id,reference,detail,amount,state,(actor->>'id')::uuid,case when state in ('approved','ordered','received') then (actor->>'id')::uuid end,case when state in ('approved','ordered','received') then now() end)
  returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_procurement_recorded',w.status,w.status,actor->>'name',jsonb_build_object('commitment_id',result.id,'purchase_reference',reference,'committed_amount',amount,'currency','SGD','status',state)::text);
  return jsonb_build_object('ok',true,'commitment',to_jsonb(result));
exception when unique_violation then return public.work_order_result_error('VALIDATION_ERROR','Purchase reference already exists for this Work Order.'); when others then return public.work_order_result_error('INTERNAL_ERROR','Procurement commitment could not be recorded.'); end;$function$;

revoke all on function public.record_work_order_markup(uuid,jsonb),public.record_work_order_procurement(uuid,jsonb) from public,anon,service_role;
grant execute on function public.record_work_order_markup(uuid,jsonb),public.record_work_order_procurement(uuid,jsonb) to authenticated;

-- WP-FMW-027: governed contractor quotation contract.
-- Quotations are submitted against the Work Order's assigned contractor and the
-- contractor's effective agreed rate schedule. Rate exceptions are explicit.

create table if not exists public.contractor_quotations (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  quotation_ref text not null,
  quotation_date date not null,
  version_no integer not null default 1 check (version_no > 0),
  status text not null default 'submitted' check (status in ('submitted','approved','rejected','superseded')),
  currency text not null default 'SGD' check (currency = 'SGD'),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  source_filename text,
  source_sha256 text,
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz not null default now(),
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  approval_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(work_order_id, quotation_ref, version_no)
);

create table if not exists public.contractor_quotation_lines (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.contractor_quotations(id) on delete cascade,
  line_no integer not null check (line_no > 0),
  rate_item_id uuid not null references public.contractor_rate_items(id) on delete restrict,
  cost_type text not null check (cost_type in ('labour','material','equipment','service','callout')),
  item_code text,
  description text not null,
  unit text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  agreed_unit_rate numeric(14,2) not null check (agreed_unit_rate >= 0),
  quoted_unit_rate numeric(14,2) not null check (quoted_unit_rate >= 0),
  amount numeric(14,2) generated always as (round(quantity * quoted_unit_rate, 2)) stored,
  rate_exception boolean not null default false,
  exception_reason text,
  worker_name text,
  remarks text,
  created_at timestamptz not null default now(),
  unique(quotation_id, line_no),
  check ((not rate_exception and quoted_unit_rate = agreed_unit_rate and exception_reason is null)
      or (rate_exception and quoted_unit_rate <> agreed_unit_rate and nullif(btrim(exception_reason),'') is not null))
);

create index if not exists contractor_quotations_work_order_idx
  on public.contractor_quotations(work_order_id, status, quotation_date desc);
create index if not exists contractor_quotation_lines_quote_idx
  on public.contractor_quotation_lines(quotation_id, line_no);

alter table public.contractor_quotations enable row level security;
alter table public.contractor_quotation_lines enable row level security;

revoke all on public.contractor_quotations from public, anon, authenticated, service_role;
revoke all on public.contractor_quotation_lines from public, anon, authenticated, service_role;

create or replace function public.record_contractor_quotation(
  p_work_order_id uuid,
  p_quotation_ref text,
  p_quotation_date date,
  p_lines jsonb,
  p_source_filename text default null,
  p_source_sha256 text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  w public.work_orders%rowtype;
  q public.contractor_quotations%rowtype;
  line jsonb;
  item public.contractor_rate_items%rowtype;
  qty numeric;
  agreed numeric;
  quoted numeric;
  exception_reason text;
  is_exception boolean;
  line_no integer := 0;
  total numeric := 0;
  next_version integer;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.');
  end if;
  actor_id := (actor->>'id')::uuid;
  actor_name := coalesce(actor->>'display_name', actor->>'name', 'Recorded user');

  select * into w from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.assigned_vendor_id is null then
    return public.work_order_result_error('CONTRACTOR_REQUIRED','Assign a contractor before recording a contractor quotation.');
  end if;
  if w.status not in ('draft','submitted','approved','assigned') then
    return public.work_order_result_error('INVALID_TRANSITION','Contractor quotations must be recorded before active field execution.');
  end if;
  if not public.field_work_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Same-facility field-work authority is required.');
  end if;
  if nullif(btrim(coalesce(p_quotation_ref,'')),'') is null then
    return public.work_order_result_error('VALIDATION_ERROR','Quotation reference is required.');
  end if;
  if p_quotation_date is null then
    return public.work_order_result_error('VALIDATION_ERROR','Quotation date is required.');
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    return public.work_order_result_error('VALIDATION_ERROR','At least one quotation line is required.');
  end if;

  select coalesce(max(version_no),0)+1 into next_version
  from public.contractor_quotations
  where work_order_id=w.id and quotation_ref=btrim(p_quotation_ref);

  update public.contractor_quotations
     set status='superseded', updated_at=now()
   where work_order_id=w.id and vendor_id=w.assigned_vendor_id and status='submitted';

  insert into public.contractor_quotations(
    work_order_id,vendor_id,quotation_ref,quotation_date,version_no,status,currency,
    source_filename,source_sha256,submitted_by
  ) values (
    w.id,w.assigned_vendor_id,btrim(p_quotation_ref),p_quotation_date,next_version,'submitted','SGD',
    nullif(btrim(coalesce(p_source_filename,'')),''),nullif(btrim(coalesce(p_source_sha256,'')),''),actor_id
  ) returning * into q;

  for line in select value from jsonb_array_elements(p_lines)
  loop
    line_no := line_no + 1;
    begin qty := (line->>'quantity')::numeric; exception when others then qty := null; end;
    if qty is null or qty <= 0 then
      raise exception using errcode='22023', message='Quotation quantity must be greater than zero.';
    end if;

    select * into item from public.contractor_rate_items
      where id=(line->>'rate_item_id')::uuid
        and vendor_id=w.assigned_vendor_id
        and active
        and effective_from <= p_quotation_date
        and (effective_to is null or effective_to >= p_quotation_date);
    if not found then
      raise exception using errcode='22023', message='Quotation line does not match an effective agreed contractor rate item.';
    end if;

    agreed := case when w.emergency_work and item.emergency_unit_rate is not null
                   then item.emergency_unit_rate else item.normal_unit_rate end;
    begin quoted := coalesce(nullif(line->>'quoted_unit_rate','')::numeric, agreed); exception when others then quoted := null; end;
    if quoted is null or quoted < 0 then
      raise exception using errcode='22023', message='Quoted unit rate is invalid.';
    end if;
    is_exception := quoted <> agreed;
    exception_reason := nullif(btrim(coalesce(line->>'exception_reason','')),'');
    if is_exception and exception_reason is null then
      raise exception using errcode='22023', message='A rate exception reason is required when the quotation differs from the agreed rate.';
    end if;

    insert into public.contractor_quotation_lines(
      quotation_id,line_no,rate_item_id,cost_type,item_code,description,unit,quantity,
      agreed_unit_rate,quoted_unit_rate,rate_exception,exception_reason,worker_name,remarks
    ) values (
      q.id,line_no,item.id,item.cost_type,item.item_code,item.description,item.unit,qty,
      agreed,quoted,is_exception,case when is_exception then exception_reason end,
      nullif(btrim(coalesce(line->>'worker_name','')),''),nullif(btrim(coalesce(line->>'remarks','')),'')
    );
    total := total + round(qty * quoted,2);
  end loop;

  update public.contractor_quotations set total_amount=total,updated_at=now() where id=q.id returning * into q;

  insert into public.activity_logs(user_id,work_order_id,action,actor,note)
  values(actor_id,w.id,'contractor_quotation_recorded',actor_name,
    jsonb_build_object('quotation_id',q.id,'quotation_ref',q.quotation_ref,'version_no',q.version_no,
      'vendor_id',q.vendor_id,'total_amount',q.total_amount,'currency',q.currency,'line_count',line_no,
      'source_filename',q.source_filename)::text);

  return jsonb_build_object('ok',true,'quotation',to_jsonb(q),'line_count',line_no);
exception
  when invalid_text_representation or check_violation or foreign_key_violation or numeric_value_out_of_range or sqlstate '22023' then
    return public.work_order_result_error('VALIDATION_ERROR',sqlerrm);
  when unique_violation then
    return public.work_order_result_error('DUPLICATE_QUOTATION','That contractor quotation version already exists.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR','Contractor quotation could not be recorded.');
end;
$function$;

create or replace function public.work_order_contractor_quotations(p_work_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb := public.work_order_actor();
  facility uuid;
  result jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select facility_id into facility from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not public.field_work_facility_permitted(facility)
     and actor->>'role' not in ('approver','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Work order quotation access is denied.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'quotation_ref',q.quotation_ref,'quotation_date',q.quotation_date,'version_no',q.version_no,
    'status',q.status,'currency',q.currency,'total_amount',q.total_amount,'vendor_id',q.vendor_id,
    'source_filename',q.source_filename,'submitted_by',q.submitted_by,'submitted_at',q.submitted_at,
    'lines',(select coalesce(jsonb_agg(to_jsonb(l) - 'quotation_id' order by l.line_no),'[]'::jsonb)
             from public.contractor_quotation_lines l where l.quotation_id=q.id)
  ) order by q.quotation_date desc,q.version_no desc),'[]'::jsonb)
  into result
  from public.contractor_quotations q where q.work_order_id=p_work_order_id;

  return jsonb_build_object('ok',true,'quotations',result);
end;
$function$;

revoke all on function public.record_contractor_quotation(uuid,text,date,jsonb,text,text) from public, anon, service_role;
grant execute on function public.record_contractor_quotation(uuid,text,date,jsonb,text,text) to authenticated;
revoke all on function public.work_order_contractor_quotations(uuid) from public, anon, service_role;
grant execute on function public.work_order_contractor_quotations(uuid) to authenticated;

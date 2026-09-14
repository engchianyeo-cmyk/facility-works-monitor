-- WP-FMW-027: governed contractor actual-cost CSV import contract.
-- CSV parsing happens in the application. The database accepts normalized rows,
-- validates them against the assigned contractor's agreed rates, requires the
-- responsible field actor, and records confirmed actuals separately from the
-- pre-work quotation / approval basis.

create table if not exists public.contractor_actual_imports (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  quotation_id uuid references public.contractor_quotations(id) on delete restrict,
  source_filename text not null,
  source_sha256 text,
  import_kind text not null check (import_kind in ('personnel','materials','equipment_services','mixed')),
  currency text not null default 'SGD' check (currency='SGD'),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  exception_count integer not null default 0 check (exception_count >= 0),
  confirmed_by uuid not null references public.profiles(id) on delete restrict,
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists contractor_actual_imports_source_uq
  on public.contractor_actual_imports(work_order_id, source_sha256)
  where source_sha256 is not null;
create index if not exists contractor_actual_imports_work_order_idx
  on public.contractor_actual_imports(work_order_id, confirmed_at desc);

create table if not exists public.contractor_actual_import_lines (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.contractor_actual_imports(id) on delete cascade,
  line_no integer not null check (line_no > 0),
  rate_item_id uuid not null references public.contractor_rate_items(id) on delete restrict,
  cost_type text not null check (cost_type in ('labour','material','equipment','service','callout')),
  item_code text,
  description text not null,
  unit text not null,
  worker_name text,
  worker_id text,
  work_date date,
  quantity numeric(14,3) not null check (quantity > 0),
  agreed_unit_rate numeric(14,2) not null check (agreed_unit_rate >= 0),
  actual_unit_rate numeric(14,2) not null check (actual_unit_rate >= 0),
  amount numeric(14,2) generated always as (round(quantity * actual_unit_rate,2)) stored,
  rate_exception boolean not null default false,
  exception_reason text,
  remarks text,
  created_at timestamptz not null default now(),
  unique(import_id,line_no),
  check ((not rate_exception and actual_unit_rate = agreed_unit_rate and exception_reason is null)
      or (rate_exception and actual_unit_rate <> agreed_unit_rate and nullif(btrim(exception_reason),'') is not null))
);

create index if not exists contractor_actual_import_lines_import_idx
  on public.contractor_actual_import_lines(import_id,line_no);

alter table public.contractor_actual_imports enable row level security;
alter table public.contractor_actual_import_lines enable row level security;
revoke all on public.contractor_actual_imports from public, anon, authenticated, service_role;
revoke all on public.contractor_actual_import_lines from public, anon, authenticated, service_role;

create or replace function public.preview_contractor_actual_import(
  p_work_order_id uuid,
  p_lines jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  w public.work_orders%rowtype;
  line jsonb;
  item public.contractor_rate_items%rowtype;
  qty numeric;
  agreed numeric;
  actual numeric;
  line_date date;
  exception_reason text;
  is_exception boolean;
  normalized jsonb := '[]'::jsonb;
  total numeric := 0;
  exceptions integer := 0;
  line_no integer := 0;
  q public.contractor_quotations%rowtype;
  quoted_total numeric := 0;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id := (actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','Assign a contractor before importing contractor actuals.'); end if;
  if w.status not in ('assigned','in_progress') then
    return public.work_order_result_error('INVALID_TRANSITION','Contractor actuals may be imported only while field work is active.');
  end if;
  if w.assigned_technician_id is null or w.assigned_technician_id<>actor_id or not public.field_work_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','The responsible same-facility field actor is required to import contractor actuals.');
  end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    return public.work_order_result_error('VALIDATION_ERROR','At least one actual-cost row is required.');
  end if;

  select * into q from public.contractor_quotations
   where work_order_id=w.id and vendor_id=w.assigned_vendor_id and status in ('approved','submitted')
   order by case when status='approved' then 0 else 1 end, quotation_date desc, version_no desc limit 1;
  if found then quoted_total:=q.total_amount; end if;

  for line in select value from jsonb_array_elements(p_lines)
  loop
    line_no:=line_no+1;
    begin qty:=(line->>'quantity')::numeric; exception when others then qty:=null; end;
    if qty is null or qty<=0 then raise exception using errcode='22023',message='Actual quantity/hours must be greater than zero.'; end if;
    begin line_date:=coalesce(nullif(line->>'work_date','')::date,current_date); exception when others then line_date:=null; end;
    if line_date is null then raise exception using errcode='22023',message='Work date is invalid.'; end if;

    select * into item from public.contractor_rate_items
     where id=(line->>'rate_item_id')::uuid
       and vendor_id=w.assigned_vendor_id and active
       and effective_from<=line_date and (effective_to is null or effective_to>=line_date);
    if not found then raise exception using errcode='22023',message='Actual-cost row does not match an effective agreed contractor rate item.'; end if;

    agreed:=case when w.emergency_work and item.emergency_unit_rate is not null then item.emergency_unit_rate else item.normal_unit_rate end;
    begin actual:=coalesce(nullif(line->>'actual_unit_rate','')::numeric,agreed); exception when others then actual:=null; end;
    if actual is null or actual<0 then raise exception using errcode='22023',message='Actual unit rate is invalid.'; end if;
    is_exception:=actual<>agreed;
    exception_reason:=nullif(btrim(coalesce(line->>'exception_reason','')),'');
    if is_exception and exception_reason is null then
      raise exception using errcode='22023',message='A rate exception reason is required when actual rate differs from agreed rate.';
    end if;

    if item.cost_type='labour' and nullif(btrim(coalesce(line->>'worker_name','')),'') is null then
      raise exception using errcode='22023',message='Personnel name is required for labour rows.';
    end if;

    normalized:=normalized||jsonb_build_array(jsonb_build_object(
      'line_no',line_no,'rate_item_id',item.id,'cost_type',item.cost_type,'item_code',item.item_code,
      'description',item.description,'unit',item.unit,
      'worker_name',nullif(btrim(coalesce(line->>'worker_name','')),''),
      'worker_id',nullif(btrim(coalesce(line->>'worker_id','')),''),'work_date',line_date,
      'quantity',qty,'agreed_unit_rate',agreed,'actual_unit_rate',actual,
      'amount',round(qty*actual,2),'rate_exception',is_exception,
      'exception_reason',case when is_exception then exception_reason end,
      'remarks',nullif(btrim(coalesce(line->>'remarks','')),'')));
    total:=total+round(qty*actual,2);
    if is_exception then exceptions:=exceptions+1; end if;
  end loop;

  return jsonb_build_object(
    'ok',true,'work_order_id',w.id,'vendor_id',w.assigned_vendor_id,
    'quotation_id',case when q.id is null then null else q.id end,
    'quotation_status',case when q.id is null then null else q.status end,
    'quoted_total',quoted_total,'actual_total',total,
    'variance_amount',round(total-quoted_total,2),
    'variance_percent',case when quoted_total=0 then null else round(((total-quoted_total)/quoted_total)*100,2) end,
    'exception_count',exceptions,'lines',normalized);
exception
  when invalid_text_representation or check_violation or numeric_value_out_of_range or sqlstate '22023' then
    return public.work_order_result_error('VALIDATION_ERROR',sqlerrm);
  when others then return public.work_order_result_error('INTERNAL_ERROR','Contractor actual-cost preview failed.');
end;
$function$;

create or replace function public.confirm_contractor_actual_import(
  p_work_order_id uuid,
  p_import_kind text,
  p_source_filename text,
  p_source_sha256 text,
  p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb:=public.work_order_actor();
  actor_id uuid;
  actor_name text;
  preview jsonb;
  w public.work_orders%rowtype;
  imp public.contractor_actual_imports%rowtype;
  line jsonb;
  line_count integer:=0;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  actor_name:=coalesce(actor->>'display_name',actor->>'name','Recorded user');
  if p_import_kind not in ('personnel','materials','equipment_services','mixed') then
    return public.work_order_result_error('VALIDATION_ERROR','Actual-cost import kind is invalid.');
  end if;
  if nullif(btrim(coalesce(p_source_filename,'')),'') is null then
    return public.work_order_result_error('VALIDATION_ERROR','Source CSV filename is required.');
  end if;

  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;

  preview:=public.preview_contractor_actual_import(p_work_order_id,p_lines);
  if not coalesce((preview->>'ok')::boolean,false) then return preview; end if;

  insert into public.contractor_actual_imports(
    work_order_id,vendor_id,quotation_id,source_filename,source_sha256,import_kind,currency,
    total_amount,exception_count,confirmed_by
  ) values(
    w.id,w.assigned_vendor_id,nullif(preview->>'quotation_id','')::uuid,btrim(p_source_filename),
    nullif(btrim(coalesce(p_source_sha256,'')),''),p_import_kind,'SGD',
    (preview->>'actual_total')::numeric,(preview->>'exception_count')::integer,actor_id
  ) returning * into imp;

  for line in select value from jsonb_array_elements(preview->'lines')
  loop
    line_count:=line_count+1;
    insert into public.contractor_actual_import_lines(
      import_id,line_no,rate_item_id,cost_type,item_code,description,unit,worker_name,worker_id,work_date,
      quantity,agreed_unit_rate,actual_unit_rate,rate_exception,exception_reason,remarks
    ) values(
      imp.id,(line->>'line_no')::integer,(line->>'rate_item_id')::uuid,line->>'cost_type',line->>'item_code',
      line->>'description',line->>'unit',line->>'worker_name',line->>'worker_id',(line->>'work_date')::date,
      (line->>'quantity')::numeric,(line->>'agreed_unit_rate')::numeric,(line->>'actual_unit_rate')::numeric,
      (line->>'rate_exception')::boolean,line->>'exception_reason',line->>'remarks');
  end loop;

  insert into public.activity_logs(user_id,work_order_id,action,actor,note)
  values(actor_id,w.id,'contractor_actual_cost_import_confirmed',actor_name,
    jsonb_build_object('import_id',imp.id,'import_kind',imp.import_kind,'source_filename',imp.source_filename,
      'total_amount',imp.total_amount,'exception_count',imp.exception_count,'line_count',line_count,
      'quotation_id',imp.quotation_id,'variance_amount',preview->'variance_amount',
      'variance_percent',preview->'variance_percent')::text);

  return jsonb_build_object('ok',true,'import',to_jsonb(imp),'line_count',line_count,
    'quoted_total',preview->'quoted_total','actual_total',preview->'actual_total',
    'variance_amount',preview->'variance_amount','variance_percent',preview->'variance_percent');
exception
  when unique_violation then return public.work_order_result_error('DUPLICATE_IMPORT','This CSV file has already been confirmed for the Work Order.');
  when invalid_text_representation or check_violation or foreign_key_violation or numeric_value_out_of_range then
    return public.work_order_result_error('VALIDATION_ERROR','Contractor actual-cost import is invalid.');
  when others then return public.work_order_result_error('INTERNAL_ERROR','Contractor actual-cost import could not be confirmed.');
end;
$function$;

create or replace function public.work_order_contractor_cost_variance(p_work_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb:=public.work_order_actor();
  w public.work_orders%rowtype;
  q public.contractor_quotations%rowtype;
  actual numeric:=0;
  exceptions integer:=0;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not public.field_work_facility_permitted(w.facility_id) and actor->>'role' not in ('approver','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Work order contractor-cost access is denied.');
  end if;

  select * into q from public.contractor_quotations
   where work_order_id=w.id and vendor_id=w.assigned_vendor_id and status in ('approved','submitted')
   order by case when status='approved' then 0 else 1 end,quotation_date desc,version_no desc limit 1;
  select coalesce(sum(total_amount),0),coalesce(sum(exception_count),0) into actual,exceptions
   from public.contractor_actual_imports where work_order_id=w.id and vendor_id=w.assigned_vendor_id;

  return jsonb_build_object('ok',true,'work_order_id',w.id,'vendor_id',w.assigned_vendor_id,
    'quotation_id',case when q.id is null then null else q.id end,
    'quotation_status',case when q.id is null then null else q.status end,
    'quoted_total',coalesce(q.total_amount,0),'actual_total',actual,
    'variance_amount',round(actual-coalesce(q.total_amount,0),2),
    'variance_percent',case when coalesce(q.total_amount,0)=0 then null else round(((actual-q.total_amount)/q.total_amount)*100,2) end,
    'exception_count',exceptions);
end;
$function$;

revoke all on function public.preview_contractor_actual_import(uuid,jsonb) from public, anon, service_role;
grant execute on function public.preview_contractor_actual_import(uuid,jsonb) to authenticated;
revoke all on function public.confirm_contractor_actual_import(uuid,text,text,text,jsonb) from public, anon, service_role;
grant execute on function public.confirm_contractor_actual_import(uuid,text,text,text,jsonb) to authenticated;
revoke all on function public.work_order_contractor_cost_variance(uuid) from public, anon, service_role;
grant execute on function public.work_order_contractor_cost_variance(uuid) to authenticated;

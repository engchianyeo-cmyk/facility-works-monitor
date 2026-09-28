begin;

alter table public.work_order_markups
  add column if not exists drawing_revision text,
  add column if not exists annotation_type text,
  add column if not exists geometry jsonb,
  add column if not exists deleted_by uuid references public.profiles(id) on delete restrict;

update public.work_order_markups
set drawing_revision=coalesce(drawing_revision,'A'),
    annotation_type=coalesce(annotation_type,'marker'),
    geometry=coalesce(geometry,jsonb_build_object('points',jsonb_build_array(jsonb_build_object('x',x_percent,'y',y_percent))))
where drawing_revision is null or annotation_type is null or geometry is null;

alter table public.work_order_markups
  alter column drawing_revision set not null,
  alter column annotation_type set not null,
  alter column geometry set not null,
  add constraint work_order_markups_annotation_type_check check(annotation_type in ('marker','arrow','circle','rectangle','freehand','text')),
  add constraint work_order_markups_drawing_revision_check check(length(btrim(drawing_revision)) between 1 and 80),
  add constraint work_order_markups_geometry_check check(jsonb_typeof(geometry)='object' and octet_length(geometry::text)<=20000);

create table public.commercial_approval_rules(
  id uuid primary key default gen_random_uuid(),
  rule_code text not null unique,
  currency text not null default 'SGD' check(currency='SGD'),
  minimum_amount numeric(14,2) not null check(minimum_amount>=0),
  maximum_amount numeric(14,2) check(maximum_amount is null or maximum_amount>minimum_amount),
  minimum_quotations integer not null check(minimum_quotations>0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.commercial_approval_rules(rule_code,minimum_amount,maximum_amount,minimum_quotations)
values('SGD_BELOW_1000_ONE_QUOTE',0,1000,1);

create table public.work_order_financial_controls(
  work_order_id uuid primary key references public.work_orders(id) on delete restrict,
  currency text not null default 'SGD' check(currency='SGD'),
  estimated_cost numeric(14,2) not null default 0 check(estimated_cost>=0),
  quoted_cost numeric(14,2) check(quoted_cost is null or quoted_cost>=0),
  approved_budget numeric(14,2) check(approved_budget is null or approved_budget>=0),
  rule_id uuid references public.commercial_approval_rules(id) on delete restrict,
  cost_status text not null default 'draft' check(cost_status in ('draft','quotation_recorded','recommended','approved','returned')),
  recommended_by uuid references public.profiles(id) on delete restrict,
  recommended_at timestamptz,
  recommendation_note text,
  financial_approved_by uuid references public.profiles(id) on delete restrict,
  financial_approved_at timestamptz,
  financial_approval_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check((recommended_by is null and recommended_at is null) or (recommended_by is not null and recommended_at is not null)),
  check((financial_approved_by is null and financial_approved_at is null) or (financial_approved_by is not null and financial_approved_at is not null)),
  check(financial_approved_by is null or financial_approved_by is distinct from recommended_by)
);

alter table public.commercial_approval_rules enable row level security;
alter table public.work_order_financial_controls enable row level security;
revoke all on public.commercial_approval_rules,public.work_order_financial_controls from public,anon,authenticated;
grant select on public.commercial_approval_rules,public.work_order_financial_controls to authenticated;
create policy commercial_approval_rules_read on public.commercial_approval_rules for select to authenticated using(public.pilot_account_ready());
create policy work_order_financial_controls_read on public.work_order_financial_controls for select to authenticated
using(exists(select 1 from public.work_orders w where w.id=work_order_id));

create or replace function public.record_work_order_markup(p_work_order_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_order_markups%rowtype;
  source_kind text:=pg_catalog.lower(coalesce(p_payload->>'source_type','drawing'));
  source_ref text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'source_reference','')),'');
  revision text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'drawing_revision','')),'');
  annotation text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'note','')),'');
  kind text:=pg_catalog.lower(coalesce(p_payload->>'annotation_type',''));
  shape jsonb:=p_payload->'geometry'; first_point jsonb; x numeric; y numeric; page integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('MARKUP_READ_ONLY','Markup is editable only during active assigned work.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may add field markup.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Supervisor authority is required.'); end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Facility Manager authority is required.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational markup authority is required.'); end if;
  if shape is null or pg_catalog.jsonb_typeof(shape)<>'object' or pg_catalog.jsonb_typeof(shape->'points')<>'array' or pg_catalog.jsonb_array_length(shape->'points')=0 or pg_catalog.octet_length(shape::text)>20000 then return public.work_order_result_error('VALIDATION_ERROR','Markup geometry is invalid.'); end if;
  first_point:=shape->'points'->0;
  begin x:=(first_point->>'x')::numeric; y:=(first_point->>'y')::numeric; page:=nullif(p_payload->>'page_number','')::integer; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Markup coordinates or page are invalid.'); end;
  if source_kind not in ('drawing','pdf') or source_ref is null or revision is null or annotation is null or kind not in ('marker','arrow','circle','rectangle','freehand','text') or x not between 0 and 100 or y not between 0 and 100 then return public.work_order_result_error('VALIDATION_ERROR','Drawing revision, annotation, note and calibrated geometry are required.'); end if;
  insert into public.work_order_markups(work_order_id,source_type,source_reference,drawing_revision,page_number,x_percent,y_percent,annotation_type,geometry,note,created_by)
  values(w.id,source_kind,source_ref,revision,page,x,y,kind,shape,annotation,(actor->>'id')::uuid) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_markup_recorded',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('markup_id',result.id,'drawing',source_ref,'revision',revision,'annotation_type',kind)::text);
  return pg_catalog.jsonb_build_object('ok',true,'markup',pg_catalog.to_jsonb(result));
exception when others then return public.work_order_result_error('INTERNAL_ERROR','Markup could not be recorded.'); end;$function$;

create or replace function public.delete_work_order_markup(p_work_order_id uuid,p_markup_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; m public.work_order_markups%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into m from public.work_order_markups where id=p_markup_id and work_order_id=p_work_order_id and deleted_at is null;
  if w.id is null or m.id is null then return public.work_order_result_error('NOT_FOUND','Markup not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('MARKUP_READ_ONLY','Markup is editable only during active assigned work.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or m.created_by is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Technicians may delete only their own active-assignment markup.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational markup authority is required.'); end if;
  update public.work_order_markups set deleted_at=pg_catalog.now(),deleted_by=(actor->>'id')::uuid where id=m.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_markup_deleted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('markup_id',m.id,'drawing',m.source_reference,'revision',m.drawing_revision)::text);
  return pg_catalog.jsonb_build_object('ok',true,'markup_id',m.id);
end;$function$;

create or replace function public.record_contractor_quotation(p_work_order_id uuid,p_quotation_ref text,p_quotation_date date,p_lines jsonb,p_source_filename text default null,p_source_sha256 text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
  line jsonb; item public.contractor_rate_items%rowtype; qty numeric; quoted numeric; agreed numeric; line_number integer:=0; total numeric:=0; next_version integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','Assign a contractor before recording a quotation.'); end if;
  if w.status not in ('draft','submitted','approved','assigned','in_progress') then return public.work_order_result_error('QUOTATION_READ_ONLY','Quotations are read-only outside planning and active execution.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or w.status not in ('assigned','in_progress') or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may record this quotation.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Quotation recording authority is required.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_quotation_ref,'')),'') is null or p_quotation_date is null or p_lines is null or pg_catalog.jsonb_typeof(p_lines)<>'array' or pg_catalog.jsonb_array_length(p_lines)=0 then return public.work_order_result_error('VALIDATION_ERROR','Quotation reference, date and at least one line are required.'); end if;
  select coalesce(pg_catalog.max(version_no),0)+1 into next_version from public.contractor_quotations where work_order_id=w.id and quotation_ref=pg_catalog.btrim(p_quotation_ref);
  update public.contractor_quotations set status='superseded',updated_at=pg_catalog.now() where work_order_id=w.id and vendor_id=w.assigned_vendor_id and status='submitted';
  insert into public.contractor_quotations(work_order_id,vendor_id,quotation_ref,quotation_date,version_no,status,currency,source_filename,source_sha256,submitted_by)
  values(w.id,w.assigned_vendor_id,pg_catalog.btrim(p_quotation_ref),p_quotation_date,next_version,'submitted','SGD',nullif(pg_catalog.btrim(coalesce(p_source_filename,'')),''),nullif(pg_catalog.btrim(coalesce(p_source_sha256,'')),''),actor_id) returning * into q;
  for line in select value from pg_catalog.jsonb_array_elements(p_lines) loop
    line_number:=line_number+1;
    begin qty:=(line->>'quantity')::numeric; quoted:=(line->>'quoted_unit_rate')::numeric; exception when others then qty:=null; quoted:=null; end;
    select * into item from public.contractor_rate_items where id=(line->>'rate_item_id')::uuid and vendor_id=w.assigned_vendor_id and active and effective_from<=p_quotation_date and (effective_to is null or effective_to>=p_quotation_date);
    if item.id is null or qty is null or qty<=0 or quoted is null or quoted<0 then raise exception using errcode='22023',message='Quotation line is invalid.'; end if;
    agreed:=case when w.emergency_work and item.emergency_unit_rate is not null then item.emergency_unit_rate else item.normal_unit_rate end;
    if quoted<>agreed and nullif(pg_catalog.btrim(coalesce(line->>'exception_reason','')),'') is null then raise exception using errcode='22023',message='A rate exception reason is required.'; end if;
    insert into public.contractor_quotation_lines(quotation_id,line_no,rate_item_id,cost_type,item_code,description,unit,quantity,agreed_unit_rate,quoted_unit_rate,rate_exception,exception_reason,worker_name,remarks)
    values(q.id,line_number,item.id,item.cost_type,item.item_code,item.description,item.unit,qty,agreed,quoted,quoted<>agreed,case when quoted<>agreed then pg_catalog.btrim(line->>'exception_reason') end,nullif(pg_catalog.btrim(coalesce(line->>'worker_name','')),''),nullif(pg_catalog.btrim(coalesce(line->>'remarks','')),''));
    total:=total+pg_catalog.round(qty*quoted,2);
  end loop;
  update public.contractor_quotations set total_amount=total,updated_at=pg_catalog.now() where id=q.id returning * into q;
  update public.work_order_financial_controls set quoted_cost=total,cost_status='quotation_recorded',recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_quotation_recorded',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'quotation_ref',q.quotation_ref,'total_amount',total,'recorded_by_role',actor->>'role')::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q),'line_count',line_number);
exception when invalid_text_representation or check_violation or foreign_key_violation or numeric_value_out_of_range or sqlstate '22023' then return public.work_order_result_error('VALIDATION_ERROR',sqlerrm); when unique_violation then return public.work_order_result_error('DUPLICATE_QUOTATION','That quotation version already exists.'); when others then return public.work_order_result_error('INTERNAL_ERROR','Contractor quotation could not be recorded.'); end;$function$;

create or replace function public.recommend_work_order_cost(p_work_order_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; control public.work_order_financial_controls%rowtype; quote_total numeric; quote_count integer; required_count integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or w.status not in ('assigned','in_progress') or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may recommend this cost.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Cost recommendation authority is required.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  if not found then return public.work_order_result_error('FINANCIAL_CONTROL_REQUIRED','Financial control is not configured.'); end if;
  select coalesce(count(*),0),coalesce(max(total_amount),0) into quote_count,quote_total from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  if quote_count<coalesce(required_count,1) then return public.work_order_result_error('QUOTATION_COUNT_REQUIRED','The configured quotation requirement has not been met.'); end if;
  update public.work_order_financial_controls set quoted_cost=quote_total,cost_status='recommended',recommended_by=(actor->>'id')::uuid,recommended_at=pg_catalog.now(),recommendation_note=nullif(pg_catalog.btrim(p_note),''),financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id returning * into control;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_cost_recommended',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quoted_cost',quote_total,'quotation_count',quote_count,'required_quotations',required_count)::text);
  return pg_catalog.jsonb_build_object('ok',true,'financial',pg_catalog.to_jsonb(control),'quotation_count',quote_count,'required_quotations',required_count);
end;$function$;

create or replace function public.approve_work_order_financial(p_work_order_id uuid,p_approved_budget numeric,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; control public.work_order_financial_controls%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into control from public.work_order_financial_controls where work_order_id=p_work_order_id for update;
  if w.id is null or control.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Financial control not found.'); end if;
  if actor->>'role'='technician' then return public.work_order_result_error('SELF_APPROVAL_DENIED','Technicians cannot approve expenditure.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Supervisor authority is required.'); end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Facility Manager authority is required.'); end if;
  if actor->>'role' not in ('supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent financial approval authority is required.'); end if;
  if control.cost_status<>'recommended' or control.recommended_by is null then return public.work_order_result_error('COST_RECOMMENDATION_REQUIRED','A cost recommendation is required first.'); end if;
  if control.recommended_by=(actor->>'id')::uuid then return public.work_order_result_error('SELF_APPROVAL_DENIED','The recommender cannot approve the same expenditure.'); end if;
  if p_approved_budget is null or p_approved_budget<0 or nullif(pg_catalog.btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('VALIDATION_ERROR','Approved budget and approval note are required.'); end if;
  update public.work_order_financial_controls set approved_budget=p_approved_budget,cost_status='approved',financial_approved_by=(actor->>'id')::uuid,financial_approved_at=pg_catalog.now(),financial_approval_note=pg_catalog.btrim(p_note),updated_at=pg_catalog.now() where work_order_id=w.id returning * into control;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_financial_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('approved_budget',p_approved_budget,'recommended_by',control.recommended_by)::text);
  return pg_catalog.jsonb_build_object('ok',true,'financial',pg_catalog.to_jsonb(control));
end;$function$;

revoke all on function public.record_work_order_markup(uuid,jsonb),public.delete_work_order_markup(uuid,uuid),public.record_contractor_quotation(uuid,text,date,jsonb,text,text),public.recommend_work_order_cost(uuid,text),public.approve_work_order_financial(uuid,numeric,text) from public,anon,service_role;
grant execute on function public.record_work_order_markup(uuid,jsonb),public.delete_work_order_markup(uuid,uuid),public.record_contractor_quotation(uuid,text,date,jsonb,text,text),public.recommend_work_order_cost(uuid,text),public.approve_work_order_financial(uuid,numeric,text) to authenticated;

do $uat$
declare target_work_order uuid; yang uuid; loading_bay uuid; rule uuid; facility uuid;
begin
  select id,facility_id into target_work_order,facility from public.work_orders where work_order_number='WO-TEST-012';
  select id into yang from public.profiles where email='koi.kpr@gmail.com' and role='technician' and is_active and deleted_at is null;
  select id into loading_bay from public.facility_areas where facility_id=facility and area_code='LDB-01';
  select id into rule from public.commercial_approval_rules where rule_code='SGD_BELOW_1000_ONE_QUOTE';
  if target_work_order is null or yang is null or loading_bay is null or rule is null then raise exception 'WO-TEST-012 UAT prerequisite missing'; end if;
  update public.facility_areas set drawing_reference='FW-001',map_x=30,map_y=55 where id=loading_bay;
  update public.work_orders set assigned_technician_id=yang,assigned_to=(select display_name from public.profiles where id=yang),facility_area_id=loading_bay,updated_at=pg_catalog.now() where id=target_work_order;
  insert into public.work_order_financial_controls(work_order_id,estimated_cost,rule_id,cost_status)
  values(target_work_order,650,rule,'draft') on conflict(work_order_id) do update set estimated_cost=excluded.estimated_cost,rule_id=excluded.rule_id,updated_at=pg_catalog.now();
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(yang,target_work_order,'uat_work_order_012_repaired','in_progress','in_progress','Preview UAT remediation',pg_catalog.jsonb_build_object('assigned_technician_id',yang,'facility_area_id',loading_bay,'drawing_reference','FW-001','map_x',30,'map_y',55,'estimated_cost',650,'rule','SGD_BELOW_1000_ONE_QUOTE')::text);
end;$uat$;

commit;

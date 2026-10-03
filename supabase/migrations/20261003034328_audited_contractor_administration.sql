-- Preserve existing contractor-administration roles, with database authorization
-- and atomic domain audit instead of service-role table writes.
begin;
create function public.create_contractor_master(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); vendor public.vendors%rowtype; rate public.contractor_rate_items%rowtype;
  kind text:=p_payload->>'kind'; company text:=nullif(btrim(p_payload->>'name'),''); terms integer;
  selected_vendor_id uuid; rate_description text; rate_unit text; normal_rate numeric; emergency_rate numeric; start_date date; end_date date; category_id uuid;
begin
  if actor is null or actor->>'role' not in ('supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Contractor administration authority is required.');
  end if;
  if kind='vendor' then
    terms:=coalesce(nullif(p_payload->>'payment_terms_days','')::integer,30);
    if company is null or length(company)>200 or terms<1 or terms>3650 then return public.work_order_result_error('VALIDATION_ERROR','A bounded company name and payment terms from 1 to 3650 days are required.'); end if;
    insert into public.vendors(name,trade,contact_name,contact_email,contact_phone,vendor_type,emergency_available,payment_terms_days)
    values(company,nullif(btrim(p_payload->>'trade'),''),nullif(btrim(p_payload->>'contact_name'),''),nullif(btrim(p_payload->>'contact_email'),''),nullif(btrim(p_payload->>'contact_phone'),''),
      case when p_payload->>'vendor_type'='manpower_provider' then 'manpower_provider' else 'specialist_contractor' end,
      coalesce(nullif(p_payload->>'emergency_available','')::boolean,false),terms) returning * into vendor;
    insert into public.activity_logs(user_id,action,actor,note)
    values((actor->>'id')::uuid,'contractor_created',actor->>'name',jsonb_build_object('vendor_id',vendor.id,'name',vendor.name,'vendor_type',vendor.vendor_type,'emergency_available',vendor.emergency_available,'payment_terms_days',terms)::text);
    return jsonb_build_object('ok',true,'vendor_id',vendor.id);
  elsif kind='rate' then
    selected_vendor_id:=(p_payload->>'vendor_id')::uuid;
    rate_description:=nullif(btrim(p_payload->>'description'),''); rate_unit:=nullif(btrim(p_payload->>'unit'),'');
    normal_rate:=nullif(p_payload->>'normal_unit_rate','')::numeric;
    emergency_rate:=nullif(p_payload->>'emergency_unit_rate','')::numeric;
    start_date:=nullif(p_payload->>'effective_from','')::date; end_date:=nullif(p_payload->>'effective_to','')::date;
    category_id:=nullif(p_payload->>'service_category_id','')::uuid;
    if rate_description is null or length(rate_description)>1000 or rate_unit is null or length(rate_unit)>80 or p_payload->>'cost_type' is null or p_payload->>'cost_type' not in ('labour','material','equipment','service','callout')
      or normal_rate is null or normal_rate::text in ('NaN','Infinity','-Infinity') or normal_rate<0 or normal_rate>999999999999.99
      or emergency_rate::text in ('NaN','Infinity','-Infinity') or emergency_rate<0 or emergency_rate>999999999999.99
      or start_date is null or end_date<start_date then return public.work_order_result_error('VALIDATION_ERROR','Complete valid rates, description, unit and effective dates.'); end if;
    -- Serialize rate creation per vendor so concurrent overlapping inserts cannot pass.
    select * into vendor from public.vendors where id=selected_vendor_id and active and deleted_at is null for update;
    if vendor.id is null then return public.work_order_result_error('INACTIVE_REFERENCE','Select an active contractor.'); end if;
    if category_id is not null and not exists(select 1 from public.contractor_service_categories where id=category_id and active) then return public.work_order_result_error('INACTIVE_REFERENCE','Select an active service category.'); end if;
    if exists(select 1 from public.contractor_rate_items r where r.vendor_id=selected_vendor_id and r.active and r.cost_type=p_payload->>'cost_type'
      and lower(btrim(r.description))=lower(rate_description) and lower(btrim(r.unit))=lower(rate_unit) and r.service_category_id is not distinct from category_id
      and r.effective_from<=coalesce(end_date,'infinity'::date) and coalesce(r.effective_to,'infinity'::date)>=start_date) then
      return public.work_order_result_error('RATE_PERIOD_OVERLAP','An agreed rate for this item already covers these dates.');
    end if;
    insert into public.contractor_rate_items(vendor_id,service_category_id,cost_type,description,unit,normal_unit_rate,emergency_unit_rate,effective_from,effective_to)
    values(selected_vendor_id,category_id,p_payload->>'cost_type',rate_description,rate_unit,normal_rate,emergency_rate,start_date,end_date) returning * into rate;
    insert into public.activity_logs(user_id,action,actor,note)
    values((actor->>'id')::uuid,'contractor_rate_created',actor->>'name',jsonb_build_object('rate_item_id',rate.id,'vendor_id',selected_vendor_id,'cost_type',rate.cost_type,'description',rate_description,'unit',rate_unit,'normal_unit_rate',rate.normal_unit_rate,'emergency_unit_rate',rate.emergency_unit_rate,'currency',rate.currency,'effective_from',start_date,'effective_to',end_date)::text);
    return jsonb_build_object('ok',true,'rate_item_id',rate.id);
  end if;
  return public.work_order_result_error('VALIDATION_ERROR','Unsupported contractor administration action.');
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range or check_violation or foreign_key_violation then
  return public.work_order_result_error('VALIDATION_ERROR','Contractor or rate details are invalid.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Contractor details could not be saved.');
end;$function$;
revoke all on function public.create_contractor_master(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.create_contractor_master(jsonb) to authenticated;
commit;

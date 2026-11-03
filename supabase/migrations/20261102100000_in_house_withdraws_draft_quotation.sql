begin;
-- UAT 2 Nov 2026 (D-29): the preparer may switch a Draft to in-house services even after starting a contractor
-- quotation. Declaring in-house withdraws the Draft's open quotations (draft, submitted or returned): they are kept,
-- marked 'withdrawn', logged, and no longer listed. Approved and superseded quotations are untouched.

alter table public.contractor_quotations drop constraint if exists contractor_quotations_status_check;
alter table public.contractor_quotations add constraint contractor_quotations_status_check
  check(status in ('draft','submitted','approved','returned','rejected','superseded','withdrawn'));

create or replace function public.set_work_order_in_house(p_work_order_id uuid, p_in_house boolean)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_orders%rowtype; withdrawn jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not public.work_order_preparer_permitted(w.id) then return public.work_order_result_error('ACCESS_DENIED','Only the Work Order preparer may change this.'); end if;
  if w.status<>'draft' then return public.work_order_result_error('INVALID_TRANSITION','In-house services can be declared only while Draft.'); end if;
  if p_in_house is null then return public.work_order_result_error('VALIDATION_ERROR','Choose in-house or contractor.'); end if;
  if w.in_house_work=p_in_house then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
  if p_in_house then
    with changed as (
      update public.contractor_quotations q set status='withdrawn', updated_at=pg_catalog.now()
      where q.work_order_id=w.id and q.status in ('draft','submitted','returned')
      returning q.id, q.quotation_ref, q.total_amount)
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',id,'quotation_ref',quotation_ref,'total_amount',total_amount)),'[]'::jsonb) into withdrawn from changed;
    if pg_catalog.jsonb_array_length(withdrawn) > 0 then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values((actor->>'id')::uuid,w.id,'work_order_quotation_withdrawn',w.status,w.status,coalesce(actor->>'display_name','Unknown user'),
        pg_catalog.jsonb_build_object('reason','Declared in-house services','quotations',withdrawn)::text);
    end if;
  end if;
  update public.work_orders set in_house_work=p_in_house,updated_at=pg_catalog.now() where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values((actor->>'id')::uuid,w.id,'work_order_in_house_declared',w.status,w.status,coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('in_house_work',p_in_house)::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'withdrawn_quotations',coalesce(withdrawn,'[]'::jsonb));
end;$function$;
revoke all on function public.set_work_order_in_house(uuid,boolean) from public, anon, service_role;
grant execute on function public.set_work_order_in_house(uuid,boolean) to authenticated;

-- The list leaves out withdrawn quotations. (The public function is the scope wrapper from 20261003043000; the
-- implementation is its private core.)
create or replace function public.work_order_contractor_quotations_r1_scope_core(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); facility uuid; result jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select facility_id into facility from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if not public.field_work_facility_permitted(facility) and actor->>'role' not in ('approver','administrator') then return public.work_order_result_error('ACCESS_DENIED','Work Order quotation access is denied.'); end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',q.id,'quotation_ref',q.quotation_ref,'quotation_date',q.quotation_date,'version_no',q.version_no,'status',q.status,'currency',q.currency,'total_amount',q.total_amount,'vendor_id',q.vendor_id,'source_filename',q.source_filename,'prepared_by',q.prepared_by,'prepared_at',q.prepared_at,'draft_saved_at',q.draft_saved_at,'scope_summary',q.scope_summary,'contractor_legal_name',q.contractor_legal_name,'gst_treatment',q.gst_treatment,'itemization_note',q.itemization_note,'submitted_by',q.submitted_by,'submitted_at',q.submitted_at,'approved_by',q.approved_by,'approved_at',q.approved_at,'approval_note',q.approval_note,'lines',(select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(l)-'quotation_id' order by l.line_no),'[]'::jsonb) from public.contractor_quotation_lines l where l.quotation_id=q.id)) order by q.created_at desc,q.version_no desc),'[]'::jsonb) into result from public.contractor_quotations q where q.work_order_id=p_work_order_id and q.status<>'withdrawn';
  return pg_catalog.jsonb_build_object('ok',true,'quotations',result);
end;$function$;

revoke all on function public.work_order_contractor_quotations_r1_scope_core(uuid) from public,anon,authenticated,service_role;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.set_work_order_in_house(uuid,boolean)'::regprocedure), 'work_order_quotation_withdrawn') = 0
    or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.work_order_contractor_quotations_r1_scope_core(uuid)'::regprocedure), '<>''withdrawn''') = 0
    or pg_catalog.strpos(pg_catalog.pg_get_constraintdef((select oid from pg_catalog.pg_constraint where conname='contractor_quotations_status_check')), 'withdrawn') = 0 then
    raise exception 'D-29 in-house withdrawal was not installed';
  end if;
end;$postcheck$;
commit;

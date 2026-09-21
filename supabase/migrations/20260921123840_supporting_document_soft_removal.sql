begin;
create or replace function public.void_work_order_supporting_document(p_work_order_id uuid,p_document_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; commercial public.work_order_commercial_documents%rowtype;
  final_doc public.work_order_final_cost_documents%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); record_editable boolean:=false;
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into w from public.work_orders where id=p_work_order_id for update;
 if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
 if reason is null or length(reason)>500 then return public.work_order_result_error('VALIDATION_ERROR','A bounded removal reason is required.'); end if;
 if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may remove editable supporting documents.'); end if;
 select * into commercial from public.work_order_commercial_documents where id=p_document_id and work_order_id=w.id and deleted_at is null for update;
 if commercial.id is not null then
   if commercial.document_type='quotation' then record_editable:=exists(select 1 from public.contractor_quotations q where q.id=commercial.quotation_id and q.status in ('draft','returned'));
   elsif commercial.document_type='invoice' then record_editable:=exists(select 1 from public.contractor_payment_assessments p where p.id=commercial.payment_assessment_id and p.status in ('draft','returned'));
   end if;
   if not record_editable then return public.work_order_result_error('APPROVED_DOCUMENT_IMMUTABLE','Submitted or approved supporting documents require a controlled revision.'); end if;
   update public.work_order_commercial_documents set deleted_at=pg_catalog.now(),superseded_by_user=actor_id where id=commercial.id;
 else
   select * into final_doc from public.work_order_final_cost_documents where id=p_document_id and work_order_id=w.id and deleted_at is null for update;
   if final_doc.id is null then return public.work_order_result_error('NOT_FOUND','Supporting document was not found.'); end if;
   if w.status not in ('assigned','in_progress') and not exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open') then return public.work_order_result_error('CORRECTION_REQUIRED','Authorized document correction is required.'); end if;
   update public.work_order_final_cost_documents set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason=reason where id=final_doc.id;
 end if;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_supporting_document_voided',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',p_document_id,'reason',reason,'soft_deleted',true)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$;
revoke all on function public.void_work_order_supporting_document(uuid,uuid,text) from public,anon,service_role;
grant execute on function public.void_work_order_supporting_document(uuid,uuid,text) to authenticated;
commit;

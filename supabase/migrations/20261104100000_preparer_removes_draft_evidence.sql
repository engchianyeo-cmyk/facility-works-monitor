begin;
-- D-30 (4 Nov 2026): while drafting (Draft or Submitted), the preparer may remove a photo, video, voice note or
-- document added by mistake, with a reason; it is voided (kept in the audit history), as for the field owner later.

create or replace function public.void_work_order_evidence(p_evidence_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; item public.evidence_items%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into item from public.evidence_items where id=p_evidence_id and deleted_at is null for update; if item.id is null or item.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Active Work Order evidence was not found.'); end if;
 select * into w from public.work_orders where id=item.work_order_id for update;
 if reason is null or length(reason)>500 then return public.work_order_result_error('VALIDATION_ERROR','A bounded removal reason is required.'); end if;
 -- UAT 4 Nov 2026 (D-30): the preparer may remove evidence added by mistake while drafting (Draft or Submitted),
 -- matching who may add it then (lib/evidence.ts canMutateWorkOrderEvidence).
 if w.status in ('draft','submitted') and public.work_order_preparer_permitted(w.id) then
   null;
 elsif (w.assigned_technician_id is distinct from actor_id or not public.field_work_facility_permitted(w.facility_id) or not (w.status in ('assigned','in_progress') or exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open'))) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned field owner may remove evidence while the record is editable.');
 elsif actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Evidence removal authority is required.'); end if;
 if item.category='after' and w.status in ('completed','reviewed','closed') and not exists(select 1 from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null and e.id<>item.id) then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','Upload replacement After evidence before removing the last mandatory item.'); end if;
 update public.evidence_items set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason=reason where id=item.id;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'evidence_voided',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('evidence_id',item.id,'filename',item.original_filename,'original_category',item.category,'reason',reason)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$;

revoke all on function public.void_work_order_evidence(uuid,text) from public,anon,service_role;
grant execute on function public.void_work_order_evidence(uuid,text) to authenticated;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.void_work_order_evidence(uuid,text)'::regprocedure), 'work_order_preparer_permitted(w.id)') = 0 then
    raise exception 'D-30 preparer evidence removal was not installed';
  end if;
end;$postcheck$;
commit;

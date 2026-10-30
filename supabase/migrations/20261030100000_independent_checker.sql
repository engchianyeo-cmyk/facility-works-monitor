begin;
-- D-25 (30 Oct 2026): the second Technician acts as the independent checker. The endorsement records the minimum
-- checks ticked (supervised work against materials and labour, the contractor's final quotation, the site field
-- evidence, and, with competing quotations, the awarded quotation against the competitors with the basis of the
-- award). The endorsing Technician is copied on the Work Order and stays copied.

alter table public.work_order_endorsements add column if not exists checklist jsonb;

drop function public.endorse_work_order(uuid, text);
create function public.endorse_work_order(p_work_order_id uuid, p_statement text, p_checklist jsonb default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; stage text; result public.work_order_endorsements%rowtype; block jsonb;
  competitors integer; required text[]; missing text[]; note text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id := (actor->>'id')::uuid;
  if not public.release1_work_order_visible(p_work_order_id) then return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.'); end if;
  select * into w from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role' <> 'technician' or not public.technician_facility_read_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Only a Technician of this facility may endorse a Work Order.'); end if;
  if actor_id = w.assigned_technician_id or actor_id = w.requested_by then
    return public.work_order_result_error('ACCESS_DENIED','A second Technician, not the one responsible for this Work Order, must endorse it.'); end if;
  stage := case w.status when 'draft' then 'submission' when 'completed' then 'review' else null end;
  if stage is null then return public.work_order_result_error('INVALID_TRANSITION','Endorsement is given while the Work Order is a Draft or Submitted for Review.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_statement,''))) < 10 then
    return public.work_order_result_error('VALIDATION_ERROR','State what you checked (at least 10 characters).'); end if;
  if not public.work_order_endorsement_missing(w.id, stage) then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','message','No endorsement is required at this stage, or it has already been given.'); end if;
  if stage = 'review' then
    block := public.work_order_review_endorsement_block(w.id);
    if block is not null then return public.work_order_result_error(block->>'code', block->>'message'); end if;
  end if;
  -- D-25: the independent checker confirms each minimum check; with competing quotations, the basis of the award too.
  select pg_catalog.count(distinct q.vendor_id) into competitors from public.contractor_quotations q
   where q.work_order_id = w.id and q.status in ('submitted','approved','superseded');
  required := case when stage = 'review' then
      array['supervised_work','field_evidence'] || case when w.in_house_work then array[]::text[] else array['final_quotation'] end
    else array['site_evidence','quotation_scope'] end
    || case when competitors > 1 then array['award_basis'] else array[]::text[] end;
  select pg_catalog.array_agg(k) into missing from pg_catalog.unnest(required) k
   where coalesce((p_checklist->>k)::boolean, false) is not true;
  note := nullif(pg_catalog.btrim(coalesce(p_checklist->>'award_basis_note','')),'');
  if missing is not null then
    return public.work_order_result_error('CHECKLIST_REQUIRED','Tick every check in your independent checker list before endorsing.'); end if;
  if competitors > 1 and (note is null or pg_catalog.length(note) not between 10 and 1000) then
    return public.work_order_result_error('AWARD_BASIS_REQUIRED','State the basis of the award: why this contractor''s quotation was chosen over the competing quotations.'); end if;
  insert into public.work_order_endorsements(work_order_id, stage, endorsed_by, statement, cycle, final_cost_fingerprint, checklist)
  values (w.id, stage, actor_id, pg_catalog.btrim(p_statement), public.work_order_endorsement_cycle(w.id, stage),
    case when stage = 'review' then public.work_order_final_cost_fingerprint(w.id) end,
    pg_catalog.jsonb_build_object('checks', pg_catalog.to_jsonb(required), 'award_basis_note', note)) returning * into result;
  -- D-25: the independent checker is copied on the Work Order from now on.
  insert into public.work_order_copied_parties(work_order_id, profile_id, added_by) values (w.id, actor_id, actor_id) on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values (actor_id, w.id, 'work_order_endorsed', w.status, w.status, coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('endorsement_id',result.id,'stage',stage,'statement',result.statement,'checks',pg_catalog.to_jsonb(required),'award_basis_note',note,
      'final_cost', case when stage = 'review' then (select pg_catalog.jsonb_build_object('final_contractor_amount',fc.final_contractor_amount,
        'variation_order',fc.variation_order,'variation_justification',fc.variation_justification)
        from public.work_order_final_cost_submissions fc where fc.work_order_id = w.id) end)::text);
  perform public.work_order_notify(w.id, 'work_order_endorsed', false, true, actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'endorsement',pg_catalog.to_jsonb(result));
end;$function$;
revoke all on function public.endorse_work_order(uuid, text, jsonb) from public, anon, service_role;
grant execute on function public.endorse_work_order(uuid, text, jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.set_work_order_copied_parties(p_work_order_id uuid, p_profile_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; party uuid; previous uuid[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE','Closed and cancelled work orders are immutable.'); end if;
  if not (public.work_order_preparer_permitted(w.id)
    or (actor->>'role' in ('approver','supervisor','facility_manager','administrator') and public.approval_facility_permitted(w.facility_id))) then
    return public.work_order_result_error('ACCESS_DENIED','Only the preparer or an approval authority may change copied parties.'); end if;
  if coalesce(pg_catalog.array_length(p_profile_ids,1),0)>50 then return public.work_order_result_error('VALIDATION_ERROR','At most 50 copied parties.'); end if;
  foreach party in array coalesce(p_profile_ids,'{}'::uuid[]) loop
    if not public.pilot_account_ready(party) then return public.work_order_result_error('INACTIVE_REFERENCE','A copied party is not an active user.'); end if;
  end loop;
  select pg_catalog.array_agg(profile_id order by profile_id) into previous from public.work_order_copied_parties where work_order_id=w.id;
  -- D-11: Finance is copied automatically at Completed; it is neither chosen nor removed here.
  delete from public.work_order_copied_parties c where c.work_order_id=w.id and not (c.profile_id = any(coalesce(p_profile_ids,'{}'::uuid[])))
    and not exists(select 1 from public.profiles p where p.id=c.profile_id and p.role='finance')
    -- D-25: the endorsing (independent checker) Technician stays copied.
    and not exists(select 1 from public.work_order_endorsements e where e.work_order_id=w.id and e.endorsed_by=c.profile_id);
  insert into public.work_order_copied_parties(work_order_id,profile_id,added_by)
    select w.id,x,(actor->>'id')::uuid from pg_catalog.unnest(coalesce(p_profile_ids,'{}'::uuid[])) x
    where not exists(select 1 from public.profiles p where p.id=x and p.role='finance') on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values((actor->>'id')::uuid,w.id,'work_order_copied_parties_changed',w.status,w.status,coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('previous',previous,'copied_party_ids',p_profile_ids)::text);
  return pg_catalog.jsonb_build_object('ok',true,'copied_party_ids',to_jsonb(coalesce(p_profile_ids,'{}'::uuid[])));
end;$function$;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.endorse_work_order(uuid,text,jsonb)'::regprocedure), 'CHECKLIST_REQUIRED') = 0
    or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.set_work_order_copied_parties(uuid,uuid[])'::regprocedure), 'e.endorsed_by=c.profile_id') = 0 then
    raise exception 'D-25 independent checker was not installed';
  end if;
end;$postcheck$;
commit;

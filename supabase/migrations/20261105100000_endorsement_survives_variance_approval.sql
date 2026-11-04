begin;
-- D-33 (5 Nov 2026): Technician 2's endorsement must stop counting only when what was endorsed changes (the final
-- charge, the variation answer and justification, the confirmed actual cost, the attached quotation, or the final
-- cost being reopened to draft). The fingerprint also included the exact final-cost status, so the Approver's
-- "Authorize Final Cost Variance" (variance_pending -> variance_approved) wrongly cancelled the endorsement. The
-- status now counts only as saved or draft. Endorsements already given for an unchanged final cost are carried
-- over to the new fingerprint.

create or replace function public.work_order_final_cost_fingerprint(p_work_order_id uuid) returns text
language sql stable security definer set search_path = pg_catalog as $function$
  select pg_catalog.md5(pg_catalog.concat_ws('|', fc.final_contractor_amount::text, fc.variation_order::text, fc.variation_justification,
    fc.confirmed_actual_cost::text, case when fc.status = 'draft' then 'draft' else 'saved' end,
    (select pg_catalog.string_agg(d.id::text, ',' order by d.id) from public.work_order_final_cost_documents d
      where d.final_cost_submission_id = fc.id and d.deleted_at is null)))
  from public.work_order_final_cost_submissions fc where fc.work_order_id = p_work_order_id
$function$;
revoke all on function public.work_order_final_cost_fingerprint(uuid) from public, anon, authenticated, service_role;

-- Carry over: a review endorsement whose stored fingerprint matches the final cost as it is now under any saved
-- status of the previous fingerprint (so only the status moved) is re-keyed to the new fingerprint.
do $carry$
declare carried integer;
begin
  with current_cost as (
    select fc.work_order_id, fc.status, s.candidate,
      pg_catalog.md5(pg_catalog.concat_ws('|', fc.final_contractor_amount::text, fc.variation_order::text, fc.variation_justification,
        fc.confirmed_actual_cost::text, s.candidate,
        (select pg_catalog.string_agg(d.id::text, ',' order by d.id) from public.work_order_final_cost_documents d
          where d.final_cost_submission_id = fc.id and d.deleted_at is null))) as previous_fingerprint
    from public.work_order_final_cost_submissions fc
    cross join (values ('confirmed'),('variance_pending'),('variance_approved')) s(candidate)
    where fc.status <> 'draft'
  ), matched as (
    update public.work_order_endorsements e
       set final_cost_fingerprint = public.work_order_final_cost_fingerprint(e.work_order_id)
      from current_cost c
     where e.work_order_id = c.work_order_id and e.stage = 'review' and e.final_cost_fingerprint = c.previous_fingerprint
    returning e.id
  )
  select pg_catalog.count(*) into carried from matched;
  raise notice 'D-33: % review endorsement(s) carried over to the new fingerprint', carried;
end;$carry$;

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.work_order_final_cost_fingerprint(uuid)'::regprocedure), 'else ''saved'' end') = 0 then
    raise exception 'D-33 endorsement fingerprint was not installed';
  end if;
end;$postcheck$;
commit;

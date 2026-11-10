begin;
-- D-49 (owner, 10 Nov 2026): Technician 2, the independent checker, is named on the Work Order. Until now any other
-- Technician of the facility could endorse, and nobody was told in advance; Technician 2 heard nothing until after
-- endorsing. Now:
--   * an Approver, Supervisor, Facility Manager or Administrator of the facility names Technician 2 (a different active
--     Technician of the same facility, not Technician 1 and not the person who raised the Work Order);
--   * Technician 2 is notified when named ("work with Technician 1") and again when the endorsement is due, and is
--     copied on the Work Order from then on;
--   * only the named Technician 2 may endorse. Work Orders with no Technician 2 named work as before.

alter table public.work_orders add column if not exists second_technician_id uuid references public.profiles(id) on delete set null;
create index if not exists work_orders_second_technician_idx on public.work_orders(second_technician_id) where second_technician_id is not null;

-- One notice to one person (internal helper; not callable by users).
create or replace function public.work_order_notify_person(p_work_order_id uuid, p_event text, p_profile_id uuid)
returns integer language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare w public.work_orders%rowtype; n integer;
begin
  select * into w from public.work_orders where id = p_work_order_id;
  if not found or p_profile_id is null then return 0; end if;
  insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
  select w.id, p_event, 'work_order:'||w.id::text||':'||p_event||':'||p.id::text||':'||pg_catalog.to_char(pg_catalog.clock_timestamp(),'YYYYMMDDHH24MISSUS'),
    p.id, p.id, p.email, 'email',
    pg_catalog.jsonb_build_object('work_order_id',w.id,'work_order_number',w.work_order_number,'status',w.status,'event',p_event),'pending'
  from public.profiles p
  where p.id = p_profile_id and p.is_active and p.deleted_at is null
    and not exists(select 1 from public.notification_outbox o where o.work_order_id=w.id and o.event_type=p_event
      and o.recipient_profile_id=p.id and o.created_at>=pg_catalog.now())
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;$function$;
revoke all on function public.work_order_notify_person(uuid, text, uuid) from public, anon, authenticated, service_role;

-- Name (or change) Technician 2.
create or replace function public.set_work_order_second_technician(p_work_order_id uuid, p_technician_id uuid)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb := public.work_order_actor(); w public.work_orders%rowtype; result public.work_orders%rowtype; due boolean := false;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','An Approver, Supervisor, Facility Manager or Administrator names Technician 2.'); end if;
  select * into w from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not public.approval_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility approval membership is required.'); end if;
  if w.status not in ('draft','submitted','approved','assigned','in_progress','completed') then
    return public.work_order_result_error('INVALID_TRANSITION','Technician 2 can be named until the work has been approved as Completed.'); end if;
  if w.status = 'completed' and not public.work_order_endorsement_missing(w.id, 'review') then
    return public.work_order_result_error('INVALID_TRANSITION','Technician 2 has already endorsed this Work Order for review.'); end if;
  if p_technician_id is null then return public.work_order_result_error('VALIDATION_ERROR','Choose Technician 2.'); end if;
  if p_technician_id = w.assigned_technician_id then
    return public.work_order_result_error('VALIDATION_ERROR','Technician 2 must be a different Technician from Technician 1.'); end if;
  if p_technician_id = w.requested_by then
    return public.work_order_result_error('VALIDATION_ERROR','Technician 2 cannot be the person who raised this Work Order.'); end if;
  if not exists (
    select 1 from public.profiles p join public.facility_memberships fm on fm.profile_id=p.id
    where p.id=p_technician_id and p.role='technician' and p.is_active and p.deleted_at is null and not p.password_change_required
      and fm.facility_id=w.facility_id and fm.membership_role='technician' and fm.active
      and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
  ) then return public.work_order_result_error('INACTIVE_REFERENCE','Choose an active Technician who belongs to this facility.'); end if;
  if w.second_technician_id = p_technician_id then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
  update public.work_orders set second_technician_id = p_technician_id, updated_at = pg_catalog.now() where id = w.id returning * into result;
  -- The previous Technician 2 stops being copied unless they already endorsed it.
  if w.second_technician_id is not null then
    delete from public.work_order_copied_parties c where c.work_order_id = w.id and c.profile_id = w.second_technician_id
      and not exists(select 1 from public.work_order_endorsements e where e.work_order_id = w.id and e.endorsed_by = w.second_technician_id);
  end if;
  insert into public.work_order_copied_parties(work_order_id, profile_id, added_by) values (w.id, p_technician_id, (actor->>'id')::uuid) on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values ((actor->>'id')::uuid, w.id, 'work_order_second_technician_set', w.status, w.status, coalesce(actor->>'name', actor->>'display_name', 'Unknown user'),
    pg_catalog.jsonb_build_object('previous_second_technician_id', w.second_technician_id, 'second_technician_id', p_technician_id,
      'technician_1_id', w.assigned_technician_id)::text);
  perform public.work_order_notify_person(w.id, 'work_order_second_technician_named', p_technician_id);
  due := (w.status = 'draft' and public.work_order_endorsement_missing(w.id, 'submission'))
      or (w.status = 'completed' and public.work_order_endorsement_missing(w.id, 'review'));
  if due then perform public.work_order_notify_person(w.id, 'work_order_endorsement_due', p_technician_id); end if;
  return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result), 'endorsement_due', due);
end;$function$;
revoke all on function public.set_work_order_second_technician(uuid, uuid) from public, anon, service_role;
grant execute on function public.set_work_order_second_technician(uuid, uuid) to authenticated;

-- Technician 1 cannot be the named Technician 2 (same function as before, plus that check).
create or replace function public.set_work_order_technician(p_work_order_id uuid, p_technician_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Approval authority is required to assign a Technician.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not public.approval_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility approval membership is required.'); end if;
  if w.status not in ('draft','submitted') then
    return public.work_order_result_error('INVALID_TRANSITION','Use assignment after approval.'); end if;
  if p_technician_id is not null and p_technician_id = w.second_technician_id then
    return public.work_order_result_error('VALIDATION_ERROR','This Technician is named as Technician 2. Choose another Technician 1, or change Technician 2 first.'); end if;
  if not exists (
    select 1 from public.profiles p join public.facility_memberships fm on fm.profile_id=p.id
    where p.id=p_technician_id and p.role='technician' and p.is_active and p.deleted_at is null and not p.password_change_required
      and fm.facility_id=w.facility_id and fm.membership_role='technician' and fm.active
      and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
  ) then return public.work_order_result_error('INACTIVE_REFERENCE','Assign an active Technician who belongs to this facility.'); end if;
  if w.assigned_technician_id=p_technician_id then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
  update public.work_orders set assigned_technician_id=p_technician_id,assigned_at=pg_catalog.now(),accepted_at=null,updated_at=pg_catalog.now()
    where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values((actor->>'id')::uuid,w.id,'work_order_technician_set',w.status,w.status,coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('previous_technician_id',w.assigned_technician_id,'technician_id',p_technician_id)::text);
  perform public.work_order_notify(w.id,'work_order_technician_assigned',false,true,(actor->>'id')::uuid);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
end;$function$;

-- Only the named Technician 2 may endorse (same function as before, plus that check).
create or replace function public.endorse_work_order(p_work_order_id uuid, p_statement text, p_checklist jsonb DEFAULT NULL::jsonb)
 returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb := public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; stage text; result public.work_order_endorsements%rowtype; block jsonb;
  competitors integer; required text[]; missing text[]; note text; named text;
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
  -- D-49: once Technician 2 is named, only they may endorse.
  if w.second_technician_id is not null and actor_id <> w.second_technician_id then
    select display_name into named from public.profiles where id = w.second_technician_id;
    return public.work_order_result_error('ACCESS_DENIED','Only the named Technician 2 ('||coalesce(named,'another Technician')||') may endorse this Work Order. A Supervisor, Facility Manager or Administrator can change Technician 2.'); end if;
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

-- The endorsement-due notice to Technician 2 when the work is submitted for review, or a Draft goes back for changes
-- at a facility that endorses before submission.
create or replace function public.notify_second_technician_endorsement_due()
returns trigger language plpgsql security definer set search_path to 'pg_catalog' as $function$
begin
  if new.second_technician_id is not null and new.status is distinct from old.status then
    if (new.status = 'completed' and public.work_order_endorsement_missing(new.id, 'review'))
       or (new.status = 'draft' and public.work_order_endorsement_missing(new.id, 'submission')) then
      perform public.work_order_notify_person(new.id, 'work_order_endorsement_due', new.second_technician_id);
    end if;
  end if;
  return null;
end;$function$;
revoke all on function public.notify_second_technician_endorsement_due() from public, anon, authenticated, service_role;
drop trigger if exists notify_second_technician_endorsement_due on public.work_orders;
create trigger notify_second_technician_endorsement_due after update of status on public.work_orders
  for each row execute function public.notify_second_technician_endorsement_due();

do $postcheck$
begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_orders' and column_name='second_technician_id')
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.endorse_work_order(uuid,text,jsonb)'::regprocedure), 'second_technician_id') = 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.set_work_order_technician(uuid,uuid)'::regprocedure), 'second_technician_id') = 0
     or to_regprocedure('public.set_work_order_second_technician(uuid,uuid)') is null
     or not exists(select 1 from pg_trigger where tgname='notify_second_technician_endorsement_due' and not tgisinternal) then
    raise exception 'D-49 named Technician 2 postcheck failed';
  end if;
end;
$postcheck$;
commit;

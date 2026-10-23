-- WP-LC2-M7: UAT feedback (owner decision D-11, 22 October 2026).
-- 1. Facility settings (Administrator): designated Approver and the stage at which a second
--    Technician endorses the Work Order as authentic (before submission, before the review, or
--    both; default before the review).
-- 2. Second-Technician endorsement: a different Technician of the same facility endorses; enforced
--    at the configured stage. Emergency work (which starts on submission) is endorsed before the
--    review whenever the facility requires any endorsement.
-- 3. Actual start and end times entered (and correctable) by the assigned Technician, required
--    before the review; the system's own Start work / completion timestamps remain for audit.
-- 4. Finance is not a selectable copied party; every active Finance user is copied automatically
--    when the Work Order is approved as Completed.

begin;

do $preflight$
begin
  if current_user <> 'postgres' then raise exception 'LC2-M7 must be applied as postgres'; end if;
  if pg_catalog.to_regprocedure('public.work_order_location_marked(uuid)') is null then raise exception 'LC2-M7 requires LC2-M6'; end if;
  if pg_catalog.to_regclass('public.facility_settings') is not null then raise exception 'LC2-M7 conflicting or partial state already exists'; end if;
end;$preflight$;

create table public.facility_settings (
  facility_id uuid primary key references public.sites(id) on delete cascade,
  designated_approver_id uuid references public.profiles(id),
  endorsement_stage text not null default 'before_review' check (endorsement_stage in ('before_submission','before_review','both')),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default pg_catalog.now()
);
comment on table public.facility_settings is 'D-11: per-facility configuration set by the Administrator.';
create table public.facility_settings_history (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.sites(id) on delete cascade,
  previous jsonb, next jsonb not null, reason text,
  changed_by uuid not null references public.profiles(id),
  changed_at timestamptz not null default pg_catalog.now()
);
create table public.work_order_endorsements (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  stage text not null check (stage in ('submission','review')),
  endorsed_by uuid not null references public.profiles(id),
  statement text not null check (pg_catalog.length(pg_catalog.btrim(statement)) between 10 and 1000),
  cycle integer not null default 0 check (cycle >= 0),
  endorsed_at timestamptz not null default pg_catalog.now()
);
create index work_order_endorsements_work_order_idx on public.work_order_endorsements(work_order_id, stage, endorsed_at desc);
alter table public.work_orders add column actual_work_started_at timestamptz, add column actual_work_ended_at timestamptz;
alter table public.work_orders add constraint work_orders_actual_work_times_check
  check (actual_work_ended_at is null or (actual_work_started_at is not null and actual_work_ended_at >= actual_work_started_at));
comment on column public.work_orders.actual_work_started_at is 'D-11: actual start of the work, entered by the assigned Technician.';
comment on column public.work_orders.actual_work_ended_at is 'D-11: actual end of the work, entered by the assigned Technician.';

alter table public.facility_settings enable row level security;
alter table public.facility_settings_history enable row level security;
alter table public.work_order_endorsements enable row level security;
create policy facility_settings_read on public.facility_settings for select to authenticated using (public.pilot_account_ready(auth.uid()));
create policy facility_settings_history_read on public.facility_settings_history for select to authenticated using (public.current_user_role() = 'administrator');
create policy work_order_endorsements_read on public.work_order_endorsements for select to authenticated using (public.release1_work_order_visible(work_order_id));
revoke all on public.facility_settings, public.facility_settings_history, public.work_order_endorsements from public, anon, authenticated, service_role;
grant select on public.facility_settings, public.facility_settings_history, public.work_order_endorsements to authenticated;

create function public.work_order_endorsement_stage(p_facility_id uuid) returns text
language sql stable security definer set search_path = pg_catalog as $function$
  select coalesce((select s.endorsement_stage from public.facility_settings s where s.facility_id = p_facility_id), 'before_review')
$function$;

-- Endorsement cycles are counted, not timed (several steps can share one timestamp):
-- 'submission' = number of returns to Draft so far; 'review' = number of completion submissions.
create function public.work_order_endorsement_cycle(p_work_order_id uuid, p_stage text) returns integer
language sql stable security definer set search_path = pg_catalog as $function$
  select case when p_stage = 'submission' then
      (select pg_catalog.count(*)::integer from public.activity_logs l where l.work_order_id = p_work_order_id and l.to_status = 'draft' and l.from_status is distinct from 'draft')
    else (select pg_catalog.count(*)::integer from public.activity_logs l where l.work_order_id = p_work_order_id and l.action = 'work_order_complete') end
$function$;

-- Required and not yet given for the current cycle.
create function public.work_order_endorsement_missing(p_work_order_id uuid, p_stage text) returns boolean
language sql stable security definer set search_path = pg_catalog as $function$
  with w as (select wo.*, public.work_order_endorsement_stage(wo.facility_id) as setting from public.work_orders wo where wo.id = p_work_order_id)
  select coalesce((select case
      when p_stage = 'submission' then not w.emergency_work and w.setting in ('before_submission','both')
      when p_stage = 'review' then w.setting in ('before_review','both') or (w.emergency_work and w.setting = 'before_submission')
      else false end
    and not exists(select 1 from public.work_order_endorsements e where e.work_order_id = w.id and e.stage = p_stage
      and e.cycle = public.work_order_endorsement_cycle(w.id, p_stage)) from w), false)
$function$;

create function public.endorse_work_order(p_work_order_id uuid, p_statement text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; stage text; result public.work_order_endorsements%rowtype;
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
  insert into public.work_order_endorsements(work_order_id, stage, endorsed_by, statement, cycle)
  values (w.id, stage, actor_id, pg_catalog.btrim(p_statement), public.work_order_endorsement_cycle(w.id, stage)) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values (actor_id, w.id, 'work_order_endorsed', w.status, w.status, coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('endorsement_id',result.id,'stage',stage,'statement',result.statement)::text);
  perform public.work_order_notify(w.id, 'work_order_endorsed', false, true, actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'endorsement',pg_catalog.to_jsonb(result));
end;$function$;

create function public.set_facility_settings(p_facility_id uuid, p_designated_approver_id uuid, p_endorsement_stage text, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); actor_id uuid; before jsonb; after public.facility_settings%rowtype; approver public.profiles%rowtype;
begin
  if actor is null or actor->>'role' <> 'administrator' then return public.work_order_result_error('ACCESS_DENIED','Only the Administrator may change facility settings.'); end if;
  actor_id := (actor->>'id')::uuid;
  if not exists(select 1 from public.sites s where s.id = p_facility_id) then return public.work_order_result_error('NOT_FOUND','Facility not found.'); end if;
  if p_endorsement_stage is null or p_endorsement_stage not in ('before_submission','before_review','both') then
    return public.work_order_result_error('VALIDATION_ERROR','Choose when the second Technician endorses.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason for the change.'); end if;
  if p_designated_approver_id is not null then
    select * into approver from public.profiles where id = p_designated_approver_id;
    if approver.id is null or not public.pilot_account_ready(approver.id) or approver.role not in ('approver','supervisor','facility_manager','administrator') then
      return public.work_order_result_error('VALIDATION_ERROR','The designated Approver must be an active Approver, Supervisor, Facility Manager or Administrator.'); end if;
    if approver.role <> 'administrator' and not exists(select 1 from public.facility_memberships m where m.profile_id = approver.id and m.facility_id = p_facility_id
         and m.active and m.membership_role = approver.role and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now())) then
      return public.work_order_result_error('VALIDATION_ERROR','The designated Approver must belong to this facility.'); end if;
  end if;
  select pg_catalog.to_jsonb(s) into before from public.facility_settings s where s.facility_id = p_facility_id;
  insert into public.facility_settings(facility_id, designated_approver_id, endorsement_stage, updated_by, updated_at)
  values (p_facility_id, p_designated_approver_id, p_endorsement_stage, actor_id, pg_catalog.now())
  on conflict (facility_id) do update set designated_approver_id = excluded.designated_approver_id, endorsement_stage = excluded.endorsement_stage,
    updated_by = excluded.updated_by, updated_at = excluded.updated_at
  returning * into after;
  insert into public.facility_settings_history(facility_id, previous, next, reason, changed_by)
  values (p_facility_id, before, pg_catalog.to_jsonb(after), pg_catalog.btrim(p_reason), actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'settings',pg_catalog.to_jsonb(after));
end;$function$;

-- Candidates for the designated Approver of a facility (Administrator form).
create function public.facility_approver_candidates(p_facility_id uuid)
returns table(id uuid, display_name text, role text)
language sql stable security definer set search_path = pg_catalog as $function$
  select p.id, p.display_name, p.role from public.profiles p
  where public.current_user_role() = 'administrator' and public.pilot_account_ready(auth.uid()) and public.pilot_account_ready(p.id)
    and (p.role = 'administrator' or (p.role in ('approver','supervisor','facility_manager') and exists(
      select 1 from public.facility_memberships m where m.profile_id = p.id and m.facility_id = p_facility_id and m.active and m.membership_role = p.role
        and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now()))))
  order by case p.role when 'approver' then 1 when 'supervisor' then 2 when 'facility_manager' then 3 else 4 end, p.display_name
$function$;

create function public.set_work_order_actual_times(p_work_order_id uuid, p_started_at timestamptz, p_ended_at timestamptz)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id := (actor->>'id')::uuid;
  select * into w from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.assigned_technician_id is distinct from actor_id or not public.field_work_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned Technician may record the actual work times.'); end if;
  if w.status not in ('assigned','in_progress','completed') then
    return public.work_order_result_error('INVALID_TRANSITION','Actual work times are recorded during the work or before the review.'); end if;
  if p_started_at is null then return public.work_order_result_error('VALIDATION_ERROR','Enter the date and time the work started.'); end if;
  if p_started_at > pg_catalog.now() + interval '5 minutes' or (p_ended_at is not null and p_ended_at > pg_catalog.now() + interval '5 minutes') then
    return public.work_order_result_error('VALIDATION_ERROR','Work times cannot be in the future.'); end if;
  if p_ended_at is not null and p_ended_at < p_started_at then
    return public.work_order_result_error('VALIDATION_ERROR','The end time must be after the start time.'); end if;
  update public.work_orders set actual_work_started_at = p_started_at, actual_work_ended_at = p_ended_at, updated_at = pg_catalog.now()
   where id = w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values (actor_id, w.id, 'work_order_actual_times_recorded', w.status, w.status, coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('previous_started_at',w.actual_work_started_at,'previous_ended_at',w.actual_work_ended_at,
      'started_at',p_started_at,'ended_at',p_ended_at)::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
end;$function$;

revoke all on function public.work_order_endorsement_stage(uuid), public.work_order_endorsement_cycle(uuid,text), public.work_order_endorsement_missing(uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.endorse_work_order(uuid,text), public.set_facility_settings(uuid,uuid,text,text),
  public.facility_approver_candidates(uuid), public.set_work_order_actual_times(uuid,timestamptz,timestamptz) from public, anon, service_role;
grant execute on function public.endorse_work_order(uuid,text), public.set_facility_settings(uuid,uuid,text,text),
  public.facility_approver_candidates(uuid), public.set_work_order_actual_times(uuid,timestamptz,timestamptz) to authenticated;

-- transition: submission endorsement where the facility requires it
CREATE OR REPLACE FUNCTION public.transition_work_order(p_work_order_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; role text;
  action text:=pg_catalog.lower(coalesce(p_action,'')); payload jsonb:=coalesce(p_payload,'{}'::jsonb);
  reason text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'reason','')),'');
  w public.work_orders%rowtype; result public.work_orders%rowtype; control public.work_order_financial_controls%rowtype;
  q public.contractor_quotations%rowtype; required_count integer; collected_count integer; amount numeric; authority jsonb; r jsonb;
  limit_version uuid; note_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; role:=actor->>'role'; actor_name:=coalesce(actor->>'display_name','Unknown user');
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;

  -- LC2-M3: the only path to Completed is the v2 review (work + cost + documents within limit).
  if action='review' then return public.verify_completed_work(p_work_order_id,p_payload); end if;

  if action not in ('submit','approve','return') then
    if role='approver' and not public.approver_facility_permitted(w.facility_id) then
      return public.work_order_result_error('ACCESS_DENIED','Active same-facility Approver membership is required.'); end if;
    return public.transition_work_order_20261020_core(p_work_order_id,p_action,p_payload);
  end if;

  if action='submit' then
    if w.status='submitted' or (w.emergency_work and w.status='in_progress' and w.submitted_at is not null) then
      return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
    if w.status<>'draft' then return public.work_order_result_error('INVALID_TRANSITION','Only a Draft may be submitted.'); end if;
    if not public.work_order_preparer_permitted(w.id) then
      return public.work_order_result_error('ACCESS_DENIED','Only the Work Order preparer may submit it.'); end if;
    if w.assigned_technician_id is null then
      return public.work_order_result_error('TECHNICIAN_REQUIRED','Assign the Technician who will witness the work before submitting.'); end if;
    if pg_catalog.length(pg_catalog.btrim(coalesce(w.description,'')))<10 then
      return public.work_order_result_error('JUSTIFICATION_REQUIRED','Explain why the work is needed (at least 10 characters) before submitting.'); end if;
    if not w.emergency_work and not public.work_order_location_marked(w.id) then
      return public.work_order_result_error('LOCATION_MARKUP_REQUIRED','Mark the work location on the layout plan before submitting.'); end if;
    if not w.emergency_work and not public.work_order_before_evidence_present(w.id) then
      return public.work_order_result_error('BEFORE_EVIDENCE_REQUIRED','Add at least one Before photo, video or voice note of the site before submitting.'); end if;
    if public.work_order_endorsement_missing(w.id,'submission') then
      return public.work_order_result_error('ENDORSEMENT_REQUIRED','A second Technician of this facility must endorse the Work Order as authentic before it is submitted.'); end if;
    if w.emergency_work then
      update public.work_orders set status='in_progress',submitted_at=pg_catalog.now(),submitted_by=actor_name,
        accepted_at=coalesce(accepted_at,pg_catalog.now()),started_at=coalesce(started_at,pg_catalog.now()),updated_at=pg_catalog.now()
        where id=w.id returning * into result;
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,w.id,'work_order_emergency_started','draft','in_progress',actor_name,
        pg_catalog.jsonb_build_object('emergency_work',true,'quotation','to_follow_after_work','reason',reason)::text);
      perform public.work_order_notify(w.id,'work_order_emergency_started',true,true,actor_id);
      return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'emergency',true);
    end if;
    if w.in_house_work then
      update public.work_orders set status='submitted',submitted_at=pg_catalog.now(),submitted_by=actor_name,updated_at=pg_catalog.now()
        where id=w.id returning * into result;
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,w.id,'work_order_submit','draft','submitted',actor_name,pg_catalog.jsonb_build_object('in_house_work',true,'pricing','waived')::text);
      perform public.work_order_notify(w.id,'work_order_submitted_for_approval',true,false,actor_id);
      return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
    end if;
    select * into control from public.work_order_financial_controls where work_order_id=w.id;
    select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
    select pg_catalog.count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
    if control.work_order_id is null or control.cost_status<>'recommended' or control.quoted_cost is null or w.recommended_vendor_id is null then
      return public.work_order_result_error('QUOTATION_REQUIRED','Submit and recommend the contractor quotation before submitting the Work Order.'); end if;
    if collected_count<coalesce(required_count,1) then
      return public.work_order_result_error('INSUFFICIENT_QUOTATIONS','The company quotation count has not been met.'); end if;
    update public.work_orders set status='submitted',submitted_at=pg_catalog.now(),submitted_by=actor_name,updated_at=pg_catalog.now()
      where id=w.id returning * into result;
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_submit','draft','submitted',actor_name,
      pg_catalog.jsonb_build_object('quoted_cost',control.quoted_cost,'recommended_vendor_id',w.recommended_vendor_id,
        'quotations',collected_count,'required_quotations',coalesce(required_count,1))::text);
    perform public.work_order_notify(w.id,'work_order_submitted_for_approval',true,false,actor_id);
    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
  end if;

  if action='return' then
    if w.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only a Work Order awaiting approval may be returned.'); end if;
    authority:=public.work_order_approval_authority(w.id,0,reason);
    if authority is not null then return authority; end if;
    if reason is null or pg_catalog.length(reason)>2000 then return public.work_order_result_error('VALIDATION_ERROR','A reason for returning the Work Order is required.'); end if;
    update public.contractor_quotations set status='returned',approval_note=reason,updated_at=pg_catalog.now() where work_order_id=w.id and status='submitted';
    update public.work_order_financial_controls set cost_status='returned',financial_approved_by=null,financial_approved_at=null,financial_approval_note=reason,updated_at=pg_catalog.now() where work_order_id=w.id;
    update public.work_orders set status='draft',updated_at=pg_catalog.now() where id=w.id returning * into result;
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_returned_to_draft','submitted','draft',actor_name,pg_catalog.jsonb_build_object('reason',reason)::text);
    perform public.work_order_notify(w.id,'work_order_returned_to_draft',false,true,actor_id);
    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
  end if;

  -- approve
  if w.status='assigned' and w.approved_at is not null then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;
  if w.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only a Work Order awaiting approval may be approved.'); end if;
  if w.in_house_work then
    -- D-07: in-house services, pricing waived; same authority rule at S$0.
    authority:=public.work_order_approval_authority(w.id,0,reason);
    if authority is not null then return authority; end if;
    select version_id into limit_version from public.work_order_approval_limit_policy where singleton;
    update public.work_orders set status='assigned',approved_at=pg_catalog.now(),assigned_at=coalesce(assigned_at,pg_catalog.now()),
        accepted_at=case when assigned_technician_id=requested_by then coalesce(accepted_at,pg_catalog.now()) else accepted_at end,
        approval_limit_version_id=limit_version,updated_at=pg_catalog.now()
      where id=w.id returning * into result;
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_approve','submitted','assigned',actor_name,
      pg_catalog.jsonb_build_object('decision','approved_to_proceed','in_house_work',true,'approved_amount',0,'approval_limit_version_id',limit_version,
        'approver_role',role,'reason',reason,'administrator_override',(actor_id=w.requested_by or actor_id=w.assigned_technician_id) and role='administrator')::text);
    perform public.work_order_notify(w.id,'work_order_approved',false,true,actor_id);
    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'approved_amount',0);
  end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id;
  select * into q from public.contractor_quotations where work_order_id=w.id and vendor_id=w.recommended_vendor_id and status='submitted'
    order by version_no desc limit 1;
  if control.work_order_id is null or control.cost_status<>'recommended' or q.id is null or control.quoted_cost is distinct from q.total_amount then
    return public.work_order_result_error('APPROVAL_NOT_READY','The recommended quotation is not ready for approval.'); end if;
  amount:=q.total_amount;
  authority:=public.work_order_approval_authority(w.id,amount,reason);
  if authority is not null then return authority; end if;
  if amount>1000000 and (nullif(pg_catalog.btrim(coalesce(payload->>'board_approval_reference','')),'') is null
    or nullif(payload->>'board_approval_date','') is null) then
    return public.work_order_result_error('BOARD_APPROVAL_REQUIRED','Board approval reference and date are required above S$1,000,000.'); end if;
  note_text:=coalesce(nullif(pg_catalog.btrim(coalesce(payload->>'note','')),''),reason,'Approved to proceed with the recommended quotation.');
  r:=public.approve_work_order_proposal(w.id,q.id,note_text);
  if not coalesce((r->>'ok')::boolean,false) then return r; end if;
  select version_id into limit_version from public.work_order_approval_limit_policy where singleton;
  update public.work_orders set status='assigned',approved_at=pg_catalog.now(),
      assigned_vendor_id=coalesce(assigned_vendor_id,q.vendor_id),assigned_at=coalesce(assigned_at,pg_catalog.now()),
      accepted_at=case when assigned_technician_id=requested_by then coalesce(accepted_at,pg_catalog.now()) else accepted_at end,
      approval_limit_version_id=limit_version,updated_at=pg_catalog.now()
    where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_approve','submitted','assigned',actor_name,
    pg_catalog.jsonb_build_object('decision','approved_to_proceed','approved_amount',amount,'quotation_id',q.id,'vendor_id',q.vendor_id,
      'approval_limit_version_id',limit_version,'approver_role',role,'reason',reason,
      'board_approval_reference',payload->>'board_approval_reference','board_approval_date',payload->>'board_approval_date',
      'administrator_override',(actor_id=w.requested_by or actor_id=w.assigned_technician_id) and role='administrator')::text);
  perform public.work_order_notify(w.id,'work_order_approved',false,true,actor_id);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'approved_amount',amount);
exception when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow or invalid_datetime_format then
  return public.work_order_result_error('VALIDATION_ERROR','Transition data is invalid.');
end;$function$;

-- approval summary: endorsement
CREATE OR REPLACE FUNCTION public.work_order_approval_summary(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare w public.work_orders%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer;
  amount numeric; level text; authority jsonb; missing jsonb:='[]'::jsonb;
begin
  if not public.release1_work_order_visible(p_work_order_id) then
    return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into control from public.work_order_financial_controls where work_order_id=w.id;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id;
  select pg_catalog.count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  amount:=control.quoted_cost;
  if pg_catalog.length(pg_catalog.btrim(coalesce(w.description,'')))<10 then missing:=missing||'"Reason the work is needed"'::jsonb; end if;
  if w.assigned_technician_id is null then missing:=missing||'"Field-witness Technician"'::jsonb; end if;
  if not w.emergency_work then
    if not public.work_order_location_marked(w.id) then missing:=missing||'"Location marked on the layout plan"'::jsonb; end if;
    if not public.work_order_before_evidence_present(w.id) then missing:=missing||'"Before photo, video or voice note of the site"'::jsonb; end if;
  end if;
  if public.work_order_endorsement_missing(w.id,'submission') then missing:=missing||'"Second Technician endorsement"'::jsonb; end if;
  if not w.emergency_work and not w.in_house_work then
    if collected_count<coalesce(required_count,1) then missing:=missing||pg_catalog.to_jsonb(pg_catalog.format('Quotations: %s of %s submitted',collected_count,coalesce(required_count,1))); end if;
    if control.work_order_id is null or control.cost_status<>'recommended' or amount is null then missing:=missing||'"Recommended contractor quotation"'::jsonb; end if;
  end if;
  select l.role into level from public.work_order_approval_limits l join public.work_order_approval_limit_policy p on p.version_id=l.version_id
    where amount is not null and (l.maximum_amount is null or l.maximum_amount>=amount)
    order by l.maximum_amount nulls last, case l.role when 'approver' then 1 when 'supervisor' then 2 when 'facility_manager' then 3 else 4 end limit 1;
  if w.status='submitted' and (amount is not null or w.in_house_work) then authority:=public.work_order_approval_authority(w.id,coalesce(amount,0),null); end if;
  return pg_catalog.jsonb_build_object('ok',true,'status',w.status,'emergency_work',w.emergency_work,'in_house_work',w.in_house_work,
    'quoted_cost',amount,'approved_budget',control.approved_budget,'cost_status',control.cost_status,
    'required_quotations',coalesce(required_count,1),'collected_quotations',collected_count,
    'missing_requirements',missing,'ready',pg_catalog.jsonb_array_length(missing)=0,
    'lowest_authority',level,'board_approval_required',coalesce(amount,0)>1000000,
    'can_approve',w.status='submitted' and (amount is not null or w.in_house_work) and authority is null,
    'approval_blocker',authority->>'code','approval_blocker_message',authority->>'message');
end;$function$;

-- review: actual times, endorsement, Finance copied at Completed
CREATE OR REPLACE FUNCTION public.verify_completed_work(p_work_order_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  previous public.work_orders%rowtype; result public.work_orders%rowtype;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  completion_activity_id uuid; completion_actor_id uuid; cycle_number integer;
  fc public.work_order_final_cost_submissions%rowtype; control public.work_order_financial_controls%rowtype;
  q public.contractor_quotations%rowtype; amount numeric(14,2); approved numeric(14,2); variance boolean; authority jsonb;
  vendor uuid; payable public.contractor_payment_assessments%rowtype; self_override boolean := false; proposer uuid; closed boolean := false;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := coalesce(actor ->> 'display_name', 'Unknown user'); actor_role := actor ->> 'role';
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if actor_role not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Approval authority is required to review completed work.'); end if;
  if not public.approval_facility_permitted(previous.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Active same-facility approval membership is required.'); end if;
  if previous.status = 'reviewed' then
    return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE', 'work_order', pg_catalog.to_jsonb(previous)); end if;
  if previous.status <> 'completed' then
    return public.work_order_result_error('INVALID_TRANSITION', 'Only work submitted for review can be approved as Completed.'); end if;

  select l.id, l.user_id into completion_activity_id, completion_actor_id from public.activity_logs l
  where l.work_order_id = previous.id and l.action = 'work_order_complete' order by l.created_at desc, l.id desc limit 1;
  if completion_activity_id is null then
    return public.work_order_result_error('COMPLETION_AUDIT_REQUIRED', 'The latest completion submission record could not be found.'); end if;
  if not exists(select 1 from public.evidence_items e where e.work_order_id=previous.id and e.category='after' and e.deleted_at is null) then
    return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED', 'At least one active After evidence item is required.'); end if;
  -- Normal and in-house work were checked at submission; emergency work is marked before the review.
  if previous.emergency_work and not public.work_order_location_marked(previous.id) then
    return public.work_order_result_error('LOCATION_MARKUP_REQUIRED', 'Mark the work location on the layout plan before the review.'); end if;
  if previous.emergency_work and not public.work_order_before_evidence_present(previous.id) then
    return public.work_order_result_error('BEFORE_EVIDENCE_REQUIRED', 'Add the Before photo, video or voice note of the site before the review.'); end if;
  if previous.actual_work_started_at is null or previous.actual_work_ended_at is null then
    return public.work_order_result_error('ACTUAL_TIMES_REQUIRED', 'The Technician has not entered the actual start and end times of the work.'); end if;
  if public.work_order_endorsement_missing(previous.id,'review') then
    return public.work_order_result_error('ENDORSEMENT_REQUIRED', 'A second Technician of this facility must endorse the Work Order as authentic before the review.'); end if;

  select * into fc from public.work_order_final_cost_submissions where work_order_id = previous.id for update;
  if not previous.in_house_work and (fc.id is null or fc.status not in ('confirmed','variance_pending','variance_approved')) then
    return public.work_order_result_error('FINAL_COST_REQUIRED', 'The Technician has not entered the final cost.'); end if;
  amount := case when previous.in_house_work then 0 else fc.confirmed_actual_cost end;
  select * into control from public.work_order_financial_controls where work_order_id = previous.id for update;
  approved := control.approved_budget;
  if previous.emergency_work and not previous.in_house_work and (control.work_order_id is null or control.cost_status not in ('recommended','approved') or control.quoted_cost is null) then
    return public.work_order_result_error('QUOTATION_REQUIRED', 'The after-the-fact emergency quotation has not been submitted.'); end if;
  variance := amount > coalesce(approved, control.quoted_cost, 0);
  if variance and reason is null then
    return public.work_order_result_error('VARIANCE_NOTE_REQUIRED', 'The final cost exceeds the approved amount; record why it is accepted.'); end if;
  if public.work_order_final_quotation_missing(previous.id) then
    return public.work_order_result_error('FINAL_QUOTATION_REQUIRED', 'The final cost differs from the approved quotation; attach the contractor''s final quotation for the work actually performed.'); end if;

  -- Monetary limit applies to the final cost; independence from requester and assigned Technician.
  authority := public.work_order_approval_authority(previous.id, amount, reason);
  if authority is not null then return authority; end if;
  if actor_id = completion_actor_id then
    if actor_role <> 'administrator' then return public.work_order_result_error('SELF_REVIEW_DENIED', 'Completed work must be reviewed by another authorised person.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-review requires an audited reason.'); end if;
  end if;
  self_override := actor_id in (completion_actor_id, previous.requested_by, previous.assigned_technician_id);

  -- Emergency: the review approves the after-the-fact quotation.
  if control.work_order_id is not null and control.cost_status = 'recommended' then
    select * into q from public.contractor_quotations where work_order_id = previous.id and vendor_id = previous.recommended_vendor_id and status = 'submitted' order by version_no desc limit 1;
    if q.id is not null then
      update public.contractor_quotations set status='superseded',updated_at=pg_catalog.now() where work_order_id=previous.id and id<>q.id and status='approved';
      update public.contractor_quotations set status='approved',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=coalesce(reason,'Approved at review'),updated_at=pg_catalog.now() where id=q.id;
      update public.work_order_financial_controls set approved_budget=q.total_amount,cost_status='approved',financial_approved_by=actor_id,financial_approved_at=pg_catalog.now(),
        financial_approval_note=coalesce(reason,'Approved at review'),updated_at=pg_catalog.now() where work_order_id=previous.id;
      vendor := q.vendor_id;
    end if;
  end if;
  if fc.status = 'variance_pending' then
    update public.work_order_final_cost_submissions set status='variance_approved',variance_approved_by=actor_id,variance_approved_at=pg_catalog.now(),
      variance_approval_note=coalesce(reason,'Approved at review'),updated_at=pg_catalog.now() where id=fc.id;
  end if;

  select pg_catalog.count(*) + 1 into cycle_number from public.activity_logs l where l.work_order_id = previous.id and l.action = 'work_order_returned_for_rework';
  update public.work_orders set status='reviewed', reviewed_at=pg_catalog.now(), updated_at=pg_catalog.now() where id=previous.id returning * into result;

  -- D-07: in-house work has no payable; record the audited in-house no-payment disposition.
  if result.in_house_work then
    proposer := case when completion_actor_id is distinct from actor_id then completion_actor_id
                     when result.requested_by is distinct from actor_id then result.requested_by
                     else result.assigned_technician_id end;
    if proposer is not null and proposer is distinct from actor_id then
      insert into public.work_order_financial_dispositions(work_order_id,disposition_type,reason_code,reason,status,proposed_by,approved_by,approved_at,approval_note)
      values(result.id,'no_payment_required','in_house','Services provided in-house; pricing waived (D-07).','approved',proposer,actor_id,pg_catalog.now(),
        coalesce(reason,'In-house work approved as Completed.'))
      on conflict(work_order_id) do update set disposition_type='no_payment_required',reason_code='in_house',reason=excluded.reason,status='approved',
        proposed_by=excluded.proposed_by,approved_by=excluded.approved_by,approved_at=excluded.approved_at,approval_note=excluded.approval_note,updated_at=pg_catalog.now();
    end if;
  end if;

  -- Approved payable for the contractor; the invoice follows (§3.5).
  vendor := coalesce(vendor, result.assigned_vendor_id, result.recommended_vendor_id);
  if vendor is not null and amount > 0 and not result.in_house_work then
    insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,approved_by,approved_at,approval_note)
    values(result.id,vendor,'approved_for_payment',amount,result.reviewed_at,actor_id,pg_catalog.now(),coalesce(reason,'Approved at review to Completed'))
    on conflict(work_order_id) do update set vendor_id=excluded.vendor_id,status='approved_for_payment',assessed_amount=excluded.assessed_amount,
      completed_work_accepted_at=excluded.completed_work_accepted_at,approved_by=excluded.approved_by,approved_at=excluded.approved_at,approval_note=excluded.approval_note,
      recommended_by=null,recommended_at=null,invoice_reference=null,invoice_amount=null,invoice_uploaded_at=null,invoice_uploaded_by=null,
      invoice_received_at=null,invoice_received_by=null,payment_term_started_at=null,payment_due_at=null,
      paid_at=null,paid_amount=null,payment_reference=null,paid_by=null,payment_note=null,updated_at=pg_catalog.now()
    returning * into payable;
  end if;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,result.id,'work_order_review','completed','reviewed',actor_name,
    pg_catalog.jsonb_build_object('cycle',cycle_number,'decision','approved_completed','approved_final_cost',amount,'approved_budget',approved,
      'variance',variance,'reason',reason,'reviewer_role',actor_role,'emergency_work',result.emergency_work,
      'completion_activity_id',completion_activity_id,'payment_assessment_id',payable.id,
      'administrator_override',self_override and actor_role='administrator','verified_at',pg_catalog.now())::text);
  -- D-11: Finance is copied automatically once the Work Order is Completed.
  insert into public.work_order_copied_parties(work_order_id,profile_id,added_by)
    select result.id, p.id, actor_id from public.profiles p where p.role = 'finance' and public.pilot_account_ready(p.id)
    on conflict do nothing;
  perform public.work_order_notify(result.id,'work_order_completed',false,true,actor_id);
  if result.in_house_work then closed := public.work_order_close_if_settled(result.id,actor_id,actor_name); end if;
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle_number,
    'approved_final_cost',amount,'payment',pg_catalog.to_jsonb(payable),'work_order_closed',closed,'notification_status','queued');
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Review data is invalid.');
end;
$function$;

-- verification readiness: actual times and endorsement
CREATE OR REPLACE FUNCTION public.work_order_verification_readiness(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; event_id uuid; event_actor uuid; missing jsonb:='[]'::jsonb; same_actor boolean;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Completed Work verification authority is required.'); end if;
  if not public.approval_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Active same-facility approval membership is required.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  if w.status<>'completed' then missing:=missing||'"completed_awaiting_verification_status"'::jsonb; end if;
  if w.emergency_work and not public.work_order_location_marked(w.id) then missing:=missing||'"Location marked on the layout plan"'::jsonb; end if;
  if w.emergency_work and not public.work_order_before_evidence_present(w.id) then missing:=missing||'"Before photo, video or voice note of the site"'::jsonb; end if;
  if w.actual_work_started_at is null or w.actual_work_ended_at is null then missing:=missing||'"Actual start and end times of the work"'::jsonb; end if;
  if public.work_order_endorsement_missing(w.id,'review') then missing:=missing||'"Second Technician endorsement"'::jsonb; end if;
  if public.work_order_final_quotation_missing(w.id) then missing:=missing||'"Final quotation for the work actually performed (final cost differs from the approved quotation)"'::jsonb; end if;
  select l.id,l.user_id into event_id,event_actor from public.activity_logs l where l.work_order_id=w.id and l.action='work_order_complete' order by l.created_at desc,l.id desc limit 1;
  if event_id is null then missing:=missing||'"authoritative_completion_submission_event"'::jsonb; end if;
  same_actor:=event_actor=(actor->>'id')::uuid;
  if same_actor and actor->>'role'<>'administrator' then missing:=missing||'"independent_authorised_verifier"'::jsonb; end if;
  return pg_catalog.jsonb_build_object('ok',true,'verification_ready',pg_catalog.jsonb_array_length(missing)=0,
    'missing_requirements',missing,'completion_event_found',event_id is not null,'completion_event_id',event_id,
    'legacy_completion_record',w.status='completed' and event_id is null,
    'self_verification_reason_required',same_actor and actor->>'role'='administrator');
end;$function$;

-- copied parties: Finance automatic only
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
    and not exists(select 1 from public.profiles p where p.id=c.profile_id and p.role='finance');
  insert into public.work_order_copied_parties(work_order_id,profile_id,added_by)
    select w.id,x,(actor->>'id')::uuid from pg_catalog.unnest(coalesce(p_profile_ids,'{}'::uuid[])) x
    where not exists(select 1 from public.profiles p where p.id=x and p.role='finance') on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values((actor->>'id')::uuid,w.id,'work_order_copied_parties_changed',w.status,w.status,coalesce(actor->>'display_name','Unknown user'),
    pg_catalog.jsonb_build_object('previous',previous,'copied_party_ids',p_profile_ids)::text);
  return pg_catalog.jsonb_build_object('ok',true,'copied_party_ids',to_jsonb(coalesce(p_profile_ids,'{}'::uuid[])));
end;$function$;

-- notify: no duplicate notice for the same person and event
CREATE OR REPLACE FUNCTION public.work_order_notify(p_work_order_id uuid, p_event text, p_include_approvers boolean, p_include_technician boolean, p_exclude uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare w public.work_orders%rowtype; n integer; stamp text:=pg_catalog.to_char(pg_catalog.clock_timestamp(),'YYYYMMDDHH24MISSUS');
begin
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return 0; end if;
  insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
  select w.id,p_event,'work_order:'||w.id::text||':'||p_event||':'||stamp,p.id,p.id,p.email,'email',
    pg_catalog.jsonb_build_object('work_order_id',w.id,'work_order_number',w.work_order_number,'status',w.status,'event',p_event),'pending'
  from public.profiles p
  where p.is_active and p.deleted_at is null and p.id is distinct from p_exclude and (
    (p_include_approvers and (p.role='administrator' or exists(
      select 1 from public.facility_memberships fm where fm.profile_id=p.id and fm.facility_id=w.facility_id and fm.active
        and fm.membership_role in ('approver','supervisor','facility_manager') and fm.membership_role=p.role
        and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now()))))
    or exists(select 1 from public.work_order_copied_parties c where c.work_order_id=w.id and c.profile_id=p.id)
    or (p_include_technician and p.id=w.assigned_technician_id)
  )
  -- D-11: one notice per person per event (Finance can now also be a copied party).
  and not exists(select 1 from public.notification_outbox o where o.work_order_id=w.id and o.event_type=p_event
    and o.recipient_profile_id=p.id and o.created_at>=pg_catalog.now())
  on conflict do nothing;
  get diagnostics n=row_count;
  return n;
end;$function$;

-- create: Finance is not a selectable copied party
CREATE OR REPLACE FUNCTION public.create_work_order(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid; actor_name text; actor_role text;
  requested_status text := pg_catalog.lower(coalesce(p_payload ->> 'status', 'draft'));
  requested_source text := pg_catalog.lower(coalesce(p_payload ->> 'source', 'manual'));
  technician uuid; party uuid; result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := coalesce(actor ->> 'display_name', actor ->> 'name'); actor_role := actor ->> 'role';
  if actor_role not in ('technician','approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Only a Technician, or a superior when the Technician is unavailable, may create Work Orders.');
  end if;
  if requested_status <> 'draft' then return public.work_order_result_error('VALIDATION_ERROR', 'Create the Work Order as Draft, then submit it for approval.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', ''))) < 3
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', ''))) > 200
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'location', ''))) = 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'Title and location are required.'); end if;
  if pg_catalog.lower(coalesce(p_payload ->> 'priority', 'medium')) not in ('low','medium','high','critical')
    or requested_source not in ('manual','reactive','preventive','inspection','condition_based','predictive')
  then return public.work_order_result_error('VALIDATION_ERROR', 'Priority or source is invalid.'); end if;
  if p_payload ? 'estimated_hours' and (p_payload ->> 'estimated_hours')::numeric < 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'A numeric work-order value is outside its allowed range.'); end if;
  if nullif(p_payload ->> 'department_id', '') is not null and not exists (
    select 1 from public.departments where id = (p_payload ->> 'department_id')::uuid and is_active = true and deleted_at is null
  ) then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected department is unavailable.'); end if;
  technician := case when actor_role = 'technician' then actor_id else nullif(p_payload ->> 'assigned_technician_id', '')::uuid end;

  begin
    insert into public.work_orders (
      user_id, requested_by, title, description, location, site, category_id, priority, status, source, source_reference,
      asset_id, facility_id, facility_area_id, department_id, due_date, estimated_hours, internal_notes, contact_number,
      emergency_work, in_house_work, assigned_technician_id, assigned_at
    ) values (
      actor_id, actor_id,
      pg_catalog.btrim(p_payload ->> 'title'),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'description', '')), ''),
      pg_catalog.btrim(p_payload ->> 'location'),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'site', '')), ''),
      nullif(p_payload ->> 'category_id', '')::uuid,
      pg_catalog.lower(coalesce(p_payload ->> 'priority', 'medium')),
      'draft', requested_source,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'source_reference', '')), ''),
      nullif(p_payload ->> 'asset_id', '')::uuid,
      nullif(p_payload ->> 'facility_id', '')::uuid,
      nullif(p_payload ->> 'facility_area_id', '')::uuid,
      nullif(p_payload ->> 'department_id', '')::uuid,
      nullif(p_payload ->> 'due_date', '')::date,
      nullif(p_payload ->> 'estimated_hours', '')::numeric,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'internal_notes', '')), ''),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'contact_number', '')), ''),
      coalesce(nullif(p_payload ->> 'emergency_work', '')::boolean, false),
      coalesce(nullif(p_payload ->> 'in_house_work', '')::boolean, false),
      technician, case when technician is not null then pg_catalog.now() end
    ) returning * into result;

    -- D-08: the chosen area must belong to the Work Order's facility.
    if result.facility_area_id is not null and exists(select 1 from public.facility_areas a where a.id=result.facility_area_id
        and (not a.active or (a.facility_id is not null and a.facility_id is distinct from result.facility_id))) then
      raise exception using errcode = '23514', message = 'AREA_FACILITY_MISMATCH';
    end if;
    -- Facility scope: Technicians create only at their own facility; superiors only where they hold approval membership.
    if actor_role = 'technician' and not public.technician_facility_read_permitted(result.facility_id) then
      raise exception using errcode = '42501', message = 'TECHNICIAN_FACILITY';
    end if;
    if actor_role <> 'technician' and not public.approval_facility_permitted(result.facility_id) then
      raise exception using errcode = '42501', message = 'APPROVAL_FACILITY';
    end if;
    if technician is not null and actor_role <> 'technician' and not exists (
      select 1 from public.profiles p join public.facility_memberships fm on fm.profile_id = p.id
      where p.id = technician and p.role = 'technician' and p.is_active and p.deleted_at is null and not p.password_change_required
        and fm.facility_id = result.facility_id and fm.membership_role = 'technician' and fm.active
        and fm.effective_from <= pg_catalog.now() and (fm.effective_to is null or fm.effective_to > pg_catalog.now())
    ) then raise exception using errcode = '23514', message = 'TECHNICIAN_UNAVAILABLE'; end if;

    if pg_catalog.jsonb_typeof(p_payload -> 'copied_party_ids') = 'array' then
      for party in select (x #>> '{}')::uuid from pg_catalog.jsonb_array_elements(p_payload -> 'copied_party_ids') x loop
        if not public.pilot_account_ready(party) then raise exception using errcode = '23514', message = 'COPIED_PARTY_UNAVAILABLE'; end if;
        if not exists(select 1 from public.profiles fp where fp.id = party and fp.role = 'finance') then
          insert into public.work_order_copied_parties(work_order_id, profile_id, added_by) values (result.id, party, actor_id) on conflict do nothing;
        end if;
      end loop;
    end if;

    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, result.id, 'work_order_created', null, result.status, actor_name,
      pg_catalog.jsonb_build_object('source', result.source, 'created_by_role', actor_role, 'assigned_technician_id', technician,
        'emergency_work', result.emergency_work, 'in_house_work', result.in_house_work, 'superior_created', actor_role <> 'technician')::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception
    when insufficient_privilege then
      return public.work_order_result_error('ACCESS_DENIED', 'You can create Work Orders only for a facility you belong to.');
    when check_violation then
      if sqlerrm = 'TECHNICIAN_UNAVAILABLE' then return public.work_order_result_error('INACTIVE_REFERENCE', 'Assign an active Technician who belongs to this facility.'); end if;
      if sqlerrm = 'AREA_FACILITY_MISMATCH' then return public.work_order_result_error('VALIDATION_ERROR', 'Choose an active area of this facility.'); end if;
      if sqlerrm = 'COPIED_PARTY_UNAVAILABLE' then return public.work_order_result_error('INACTIVE_REFERENCE', 'A copied party is not an active user.'); end if;
      return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
    when invalid_text_representation or numeric_value_out_of_range or foreign_key_violation then
      return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
    when others then
      return public.work_order_result_error('INTERNAL_ERROR', 'Work-order creation failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order creation failed.');
end;
$function$;

do $post$
begin
  if has_function_privilege('authenticated','public.work_order_endorsement_missing(uuid,text)','EXECUTE') then raise exception 'LC2-M7 helper exposed'; end if;
  if (select prosrc from pg_catalog.pg_proc where oid='public.verify_completed_work(uuid,jsonb)'::regprocedure) not like '%ACTUAL_TIMES_REQUIRED%' then raise exception 'LC2-M7 review not patched'; end if;
end;$post$;

commit;

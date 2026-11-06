begin;
-- D-37 (6 Nov 2026): contractor register, facility shortlists and admission of a new contractor.
--   * A Procurement Manager is designated by an Administrator, for one facility or company-wide (facility_id null).
--   * Technician 1 raises "Contractor needed" on a Work Order when no suitable contractor is listed.
--   * A Facility Manager, Administrator or Procurement Manager recommends a contractor for a service at a facility.
--   * A Procurement Manager pre-qualifies it; the Facility Manager or Procurement Manager records the facility owner's
--     approval, and the contractor becomes eligible at the facility "on trial".
--   * Each completed trial job (approved as Completed) is scored 1-5 on quality, on time, safety, documents and price by
--     the Facility Manager, the Approver, Technician 1 or Technician 2 (per facility setting).
--   * After the required trial jobs (standard 2) with an average at or above the pass mark (standard 3.5) and no score
--     of 1 on safety, a Procurement Manager admits the contractor to the facility's shortlist. Rejection at any step.
-- All writes go through the functions below; the tables are read-only to signed-in users.

alter table public.vendor_facility_eligibility
  add column if not exists admission_status text not null default 'shortlisted';
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'vendor_facility_eligibility_admission_status_check') then
    alter table public.vendor_facility_eligibility add constraint vendor_facility_eligibility_admission_status_check
      check (admission_status in ('trial', 'shortlisted'));
  end if;
end $c$;

alter table public.facility_settings
  add column if not exists contractor_trial_jobs_required integer not null default 2,
  add column if not exists contractor_pass_mark numeric(3,2) not null default 3.5,
  add column if not exists contractor_evaluators text[] not null default array['facility_manager','approver','technician_1','technician_2'];
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'facility_settings_contractor_trial_check') then
    alter table public.facility_settings add constraint facility_settings_contractor_trial_check check (
      contractor_trial_jobs_required between 1 and 10
      and contractor_pass_mark between 1 and 5
      and cardinality(contractor_evaluators) > 0
      and contractor_evaluators <@ array['facility_manager','approver','technician_1','technician_2']);
  end if;
end $c$;

create table if not exists public.procurement_managers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  facility_id uuid references public.sites(id) on delete restrict,
  active boolean not null default true,
  designated_by uuid not null references public.profiles(id) on delete restrict,
  designated_at timestamptz not null default now()
);
create unique index if not exists procurement_managers_one_per_scope
  on public.procurement_managers (profile_id, coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid));

create table if not exists public.contractor_requests (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.sites(id) on delete restrict,
  work_order_id uuid references public.work_orders(id) on delete restrict,
  service text not null check (char_length(btrim(service)) between 2 and 120),
  reason text not null check (char_length(btrim(reason)) between 5 and 2000),
  raised_by uuid not null references public.profiles(id) on delete restrict,
  raised_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open', 'answered', 'closed'))
);

create table if not exists public.contractor_admissions (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.sites(id) on delete restrict,
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  service text not null check (char_length(btrim(service)) between 2 and 120),
  status text not null default 'recommended' check (status in ('recommended', 'prequalified', 'on_trial', 'admitted', 'rejected')),
  request_id uuid references public.contractor_requests(id) on delete restrict,
  recommended_by uuid not null references public.profiles(id) on delete restrict,
  recommended_at timestamptz not null default now(),
  recommendation_reason text not null check (char_length(btrim(recommendation_reason)) between 5 and 2000),
  prequalified_by uuid references public.profiles(id) on delete restrict,
  prequalified_at timestamptz,
  prequalification_note text,
  owner_approval_recorded_by uuid references public.profiles(id) on delete restrict,
  owner_approval_recorded_at timestamptz,
  owner_approval_note text,
  decided_by uuid references public.profiles(id) on delete restrict,
  decided_at timestamptz,
  decision_note text
);
create unique index if not exists contractor_admissions_one_open
  on public.contractor_admissions (facility_id, vendor_id) where status in ('recommended', 'prequalified', 'on_trial');

create table if not exists public.contractor_trial_evaluations (
  id uuid primary key default gen_random_uuid(),
  admission_id uuid not null references public.contractor_admissions(id) on delete restrict,
  work_order_id uuid not null references public.work_orders(id) on delete restrict,
  scored_by uuid not null references public.profiles(id) on delete restrict,
  scorer_capacity text not null check (scorer_capacity in ('facility_manager', 'approver', 'technician_1', 'technician_2')),
  quality smallint not null check (quality between 1 and 5),
  on_time smallint not null check (on_time between 1 and 5),
  safety smallint not null check (safety between 1 and 5),
  documents smallint not null check (documents between 1 and 5),
  price smallint not null check (price between 1 and 5),
  comments text check (comments is null or char_length(comments) <= 2000),
  scored_at timestamptz not null default now(),
  unique (work_order_id, scored_by)
);

alter table public.procurement_managers enable row level security;
alter table public.contractor_requests enable row level security;
alter table public.contractor_admissions enable row level security;
alter table public.contractor_trial_evaluations enable row level security;
drop policy if exists procurement_managers_read on public.procurement_managers;
create policy procurement_managers_read on public.procurement_managers for select to authenticated using (public.pilot_account_ready());
drop policy if exists contractor_requests_read on public.contractor_requests;
create policy contractor_requests_read on public.contractor_requests for select to authenticated using (public.pilot_account_ready());
drop policy if exists contractor_admissions_read on public.contractor_admissions;
create policy contractor_admissions_read on public.contractor_admissions for select to authenticated using (public.pilot_account_ready());
drop policy if exists contractor_trial_evaluations_read on public.contractor_trial_evaluations;
create policy contractor_trial_evaluations_read on public.contractor_trial_evaluations for select to authenticated using (public.pilot_account_ready());
revoke all on public.procurement_managers, public.contractor_requests, public.contractor_admissions, public.contractor_trial_evaluations from anon, authenticated;
grant select on public.procurement_managers, public.contractor_requests, public.contractor_admissions, public.contractor_trial_evaluations to authenticated;

-- Is the signed-in user a Procurement Manager for this facility (or company-wide)?
create or replace function public.procurement_manager_permitted(p_facility_id uuid)
returns boolean language sql stable security definer set search_path to 'pg_catalog' as $function$
  select public.pilot_account_ready(auth.uid()) and exists (
    select 1 from public.procurement_managers pm
    where pm.profile_id = auth.uid() and pm.active and (pm.facility_id is null or pm.facility_id = p_facility_id))
$function$;

create or replace function public.contractor_admission_settings(p_facility_id uuid)
returns jsonb language sql stable security definer set search_path to 'pg_catalog' as $function$
  select pg_catalog.jsonb_build_object(
    'trial_jobs_required', coalesce((select fs.contractor_trial_jobs_required from public.facility_settings fs where fs.facility_id = p_facility_id), 2),
    'pass_mark', coalesce((select fs.contractor_pass_mark from public.facility_settings fs where fs.facility_id = p_facility_id), 3.5),
    'evaluators', pg_catalog.to_jsonb(coalesce((select fs.contractor_evaluators from public.facility_settings fs where fs.facility_id = p_facility_id),
                                               array['facility_manager','approver','technician_1','technician_2'])))
$function$;

-- Trial result: completed trial jobs scored, the average across them, the lowest safety score, and whether it passes.
create or replace function public.contractor_trial_result(p_admission_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog' as $function$
declare a public.contractor_admissions%rowtype; s jsonb; jobs integer; avg_score numeric; min_safety integer; required integer; pass numeric;
begin
  select * into a from public.contractor_admissions where id = p_admission_id;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Contractor admission not found.'); end if;
  s := public.contractor_admission_settings(a.facility_id);
  required := (s ->> 'trial_jobs_required')::integer;
  pass := (s ->> 'pass_mark')::numeric;
  with per_job as (
    select e.work_order_id, avg((e.quality + e.on_time + e.safety + e.documents + e.price)::numeric / 5) as job_avg, min(e.safety) as job_min_safety
    from public.contractor_trial_evaluations e
    join public.work_orders w on w.id = e.work_order_id and w.status in ('reviewed', 'closed')
    where e.admission_id = a.id
    group by e.work_order_id)
  select count(*), round(avg(job_avg), 2), min(job_min_safety) into jobs, avg_score, min_safety from per_job;
  return pg_catalog.jsonb_build_object('ok', true, 'admission_id', a.id, 'status', a.status,
    'jobs_scored', jobs, 'jobs_required', required, 'average', avg_score, 'pass_mark', pass, 'lowest_safety', min_safety,
    'passed', jobs >= required and coalesce(avg_score, 0) >= pass and coalesce(min_safety, 0) > 1);
end;
$function$;

create or replace function public.contractor_admission_log(p_action text, p_admission public.contractor_admissions, p_note jsonb)
returns void language sql security definer set search_path to 'pg_catalog' as $function$
  insert into public.activity_logs(user_id, action, actor, note)
  values (auth.uid(), p_action, coalesce((select display_name from public.profiles where id = auth.uid()), 'Unknown user'),
    (pg_catalog.jsonb_build_object('admission_id', p_admission.id, 'facility_id', p_admission.facility_id,
      'vendor_id', p_admission.vendor_id, 'service', p_admission.service, 'status', p_admission.status) || coalesce(p_note, '{}'::jsonb))::text)
$function$;

-- Administrator designates (or removes) a Procurement Manager for a facility, or company-wide when p_facility_id is null.
create or replace function public.designate_procurement_manager(p_profile_id uuid, p_facility_id uuid, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb := public.work_order_actor(); row public.procurement_managers%rowtype;
begin
  if actor is null or actor ->> 'role' <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Only an Administrator designates Procurement Managers.');
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_profile_id and p.is_active and p.deleted_at is null) then
    return public.work_order_result_error('NOT_FOUND', 'That person is not an active user.');
  end if;
  if p_facility_id is not null and not exists (select 1 from public.sites s where s.id = p_facility_id) then
    return public.work_order_result_error('NOT_FOUND', 'Facility not found.');
  end if;
  insert into public.procurement_managers(profile_id, facility_id, active, designated_by)
  values (p_profile_id, p_facility_id, coalesce(p_active, true), (actor ->> 'id')::uuid)
  on conflict (profile_id, coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set active = excluded.active, designated_by = excluded.designated_by, designated_at = now()
  returning * into row;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor ->> 'id')::uuid, 'procurement_manager_designated', actor ->> 'display_name',
    pg_catalog.jsonb_build_object('profile_id', p_profile_id, 'facility_id', p_facility_id, 'active', row.active)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'procurement_manager', pg_catalog.to_jsonb(row));
end;
$function$;

-- Technician 1 raises "Contractor needed" on their Work Order when no suitable contractor is listed.
create or replace function public.raise_contractor_request(p_work_order_id uuid, p_service text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb := public.work_order_actor(); w public.work_orders%rowtype; r public.contractor_requests%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id = p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work Order not found.'); end if;
  if actor ->> 'role' <> 'technician' or w.assigned_technician_id is distinct from (actor ->> 'id')::uuid
     or not public.technician_facility_read_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the assigned Technician raises Contractor needed on this Work Order.');
  end if;
  if w.status in ('reviewed', 'closed', 'cancelled') then
    return public.work_order_result_error('INVALID_STATE', 'This Work Order is finished.');
  end if;
  if char_length(btrim(coalesce(p_service, ''))) < 2 or char_length(btrim(coalesce(p_reason, ''))) < 5 then
    return public.work_order_result_error('VALIDATION_ERROR', 'Name the service needed and say why no listed contractor is suitable.');
  end if;
  insert into public.contractor_requests(facility_id, work_order_id, service, reason, raised_by)
  values (w.facility_id, w.id, btrim(p_service), btrim(p_reason), (actor ->> 'id')::uuid) returning * into r;
  insert into public.activity_logs(user_id, work_order_id, action, actor, note)
  values ((actor ->> 'id')::uuid, w.id, 'contractor_requested', actor ->> 'display_name',
    pg_catalog.jsonb_build_object('request_id', r.id, 'service', r.service, 'reason', r.reason)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'request', pg_catalog.to_jsonb(r));
end;
$function$;

-- A Facility Manager, Administrator or Procurement Manager recommends a contractor for a service at a facility,
-- either from the company register (vendor_id) or as a new company (new_vendor).
create or replace function public.recommend_contractor(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; facility uuid; vendor uuid; service text; reason text;
  request public.contractor_requests%rowtype; nv jsonb := p_payload -> 'new_vendor'; a public.contractor_admissions%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid;
  begin
    facility := nullif(p_payload ->> 'facility_id', '')::uuid;
    vendor := nullif(p_payload ->> 'vendor_id', '')::uuid;
  exception when others then
    return public.work_order_result_error('VALIDATION_ERROR', 'Invalid facility or contractor.');
  end;
  if nullif(p_payload ->> 'request_id', '') is not null then
    select * into request from public.contractor_requests where id = (p_payload ->> 'request_id')::uuid;
    if not found or request.status <> 'open' then return public.work_order_result_error('NOT_FOUND', 'That Contractor needed request is not open.'); end if;
    facility := coalesce(facility, request.facility_id);
    if facility <> request.facility_id then return public.work_order_result_error('VALIDATION_ERROR', 'The request is for another facility.'); end if;
  end if;
  if facility is null or not exists (select 1 from public.sites where id = facility) then
    return public.work_order_result_error('VALIDATION_ERROR', 'Choose the facility.');
  end if;
  if not (actor ->> 'role' = 'administrator'
          or (actor ->> 'role' = 'facility_manager' and public.facility_manager_facility_permitted(facility))
          or public.procurement_manager_permitted(facility)) then
    return public.work_order_result_error('ACCESS_DENIED', 'A Facility Manager, Administrator or Procurement Manager recommends contractors.');
  end if;
  service := btrim(coalesce(p_payload ->> 'service', request.service, ''));
  reason := btrim(coalesce(p_payload ->> 'reason', ''));
  if char_length(service) < 2 or char_length(reason) < 5 then
    return public.work_order_result_error('VALIDATION_ERROR', 'Give the service and the reason for the recommendation.');
  end if;
  if vendor is null then
    if nv is null or char_length(btrim(coalesce(nv ->> 'name', ''))) < 2 or char_length(btrim(coalesce(nv ->> 'company_registration_no', ''))) < 5 then
      return public.work_order_result_error('VALIDATION_ERROR', 'Choose a contractor from the register, or give the new company''s name and UEN.');
    end if;
    select v.id into vendor from public.vendors v
    where upper(btrim(v.company_registration_no)) = upper(btrim(nv ->> 'company_registration_no')) and v.deleted_at is null limit 1;
    if vendor is null then
      insert into public.vendors(name, trade, company_registration_no, contact_name, contact_email, contact_phone, vendor_type, emergency_available, payment_terms_days, active)
      values (btrim(nv ->> 'name'), service, upper(btrim(nv ->> 'company_registration_no')), nullif(btrim(coalesce(nv ->> 'contact_name', '')), ''),
              nullif(btrim(coalesce(nv ->> 'contact_email', '')), ''), nullif(btrim(coalesce(nv ->> 'contact_phone', '')), ''),
              'specialist_contractor', coalesce((nv ->> 'emergency_available')::boolean, false), 30, true)
      returning id into vendor;
    end if;
  elsif not exists (select 1 from public.vendors v where v.id = vendor and v.active and v.deleted_at is null) then
    return public.work_order_result_error('NOT_FOUND', 'That contractor is not in the register.');
  end if;
  if exists (select 1 from public.vendor_facility_eligibility e where e.vendor_id = vendor and e.facility_id = facility and e.active
             and e.procurement_prequalified and e.facility_confirmed and e.admission_status = 'shortlisted') then
    return public.work_order_result_error('ALREADY_LISTED', 'This contractor is already on the facility''s list.');
  end if;
  if exists (select 1 from public.contractor_admissions x where x.vendor_id = vendor and x.facility_id = facility and x.status in ('recommended','prequalified','on_trial')) then
    return public.work_order_result_error('ALREADY_IN_PROGRESS', 'This contractor is already being admitted at this facility.');
  end if;
  insert into public.contractor_admissions(facility_id, vendor_id, service, request_id, recommended_by, recommendation_reason)
  values (facility, vendor, service, request.id, actor_id, reason) returning * into a;
  if request.id is not null then update public.contractor_requests set status = 'answered' where id = request.id; end if;
  perform public.contractor_admission_log('contractor_recommended', a, pg_catalog.jsonb_build_object('reason', reason));
  return pg_catalog.jsonb_build_object('ok', true, 'admission', pg_catalog.to_jsonb(a));
end;
$function$;

-- A Procurement Manager pre-qualifies the contractor (UEN, insurance, licences checked).
create or replace function public.prequalify_contractor(p_admission_id uuid, p_note text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare a public.contractor_admissions%rowtype;
begin
  select * into a from public.contractor_admissions where id = p_admission_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Contractor admission not found.'); end if;
  if not public.procurement_manager_permitted(a.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only a Procurement Manager pre-qualifies contractors.');
  end if;
  if a.status <> 'recommended' then return public.work_order_result_error('INVALID_STATE', 'This contractor is not waiting for pre-qualification.'); end if;
  if char_length(btrim(coalesce(p_note, ''))) < 5 then
    return public.work_order_result_error('VALIDATION_ERROR', 'Record what was checked (e.g. UEN, insurance, licences).');
  end if;
  update public.contractor_admissions set status = 'prequalified', prequalified_by = auth.uid(), prequalified_at = now(), prequalification_note = btrim(p_note)
  where id = a.id returning * into a;
  perform public.contractor_admission_log('contractor_prequalified', a, pg_catalog.jsonb_build_object('note', a.prequalification_note));
  return pg_catalog.jsonb_build_object('ok', true, 'admission', pg_catalog.to_jsonb(a));
end;
$function$;

-- The Facility Manager or Procurement Manager records the facility owner's approval; the contractor goes on trial.
create or replace function public.record_contractor_owner_approval(p_admission_id uuid, p_note text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb := public.work_order_actor(); a public.contractor_admissions%rowtype;
begin
  select * into a from public.contractor_admissions where id = p_admission_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Contractor admission not found.'); end if;
  if actor is null or not ((actor ->> 'role' = 'facility_manager' and public.facility_manager_facility_permitted(a.facility_id))
                           or public.procurement_manager_permitted(a.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED', 'The Facility Manager or a Procurement Manager records the owner''s approval.');
  end if;
  if a.status <> 'prequalified' then return public.work_order_result_error('INVALID_STATE', 'The contractor must be pre-qualified first.'); end if;
  if char_length(btrim(coalesce(p_note, ''))) < 5 then
    return public.work_order_result_error('VALIDATION_ERROR', 'Record who approved for the owner, when and how (e.g. email of 6 Nov from the owner''s director).');
  end if;
  update public.contractor_admissions set status = 'on_trial', owner_approval_recorded_by = auth.uid(), owner_approval_recorded_at = now(), owner_approval_note = btrim(p_note)
  where id = a.id returning * into a;
  insert into public.vendor_facility_eligibility(vendor_id, facility_id, procurement_prequalified, facility_confirmed, confirmation_basis, confirmed_by, confirmed_at, active, admission_status)
  values (a.vendor_id, a.facility_id, true, true, 'Owner approval recorded (D-37): ' || a.owner_approval_note, auth.uid(), now(), true, 'trial')
  on conflict (vendor_id, facility_id) do update set procurement_prequalified = true, facility_confirmed = true, active = true,
    admission_status = 'trial', confirmation_basis = excluded.confirmation_basis, confirmed_by = excluded.confirmed_by, confirmed_at = excluded.confirmed_at;
  perform public.contractor_admission_log('contractor_owner_approval_recorded', a, pg_catalog.jsonb_build_object('note', a.owner_approval_note));
  return pg_catalog.jsonb_build_object('ok', true, 'admission', pg_catalog.to_jsonb(a));
end;
$function$;

-- Score a completed trial job (approved as Completed) of a contractor on trial at the Work Order's facility.
create or replace function public.score_contractor_trial_job(p_work_order_id uuid, p_scores jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; a public.contractor_admissions%rowtype;
  capacity text; allowed jsonb; q smallint; t smallint; sf smallint; d smallint; pr smallint; e public.contractor_trial_evaluations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid;
  select * into w from public.work_orders where id = p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work Order not found.'); end if;
  if w.status not in ('reviewed', 'closed') then
    return public.work_order_result_error('INVALID_STATE', 'A trial job is scored once it is approved as Completed.');
  end if;
  select * into a from public.contractor_admissions x
  where x.facility_id = w.facility_id and x.vendor_id = w.assigned_vendor_id and x.status = 'on_trial';
  if not found then return public.work_order_result_error('NOT_A_TRIAL_JOB', 'This Work Order was not done by a contractor on trial here.'); end if;
  allowed := public.contractor_admission_settings(w.facility_id) -> 'evaluators';
  capacity := case
    when w.assigned_technician_id = actor_id and allowed ? 'technician_1' then 'technician_1'
    when actor ->> 'role' = 'technician' and allowed ? 'technician_2'
         and exists (select 1 from public.work_order_endorsements en where en.work_order_id = w.id and en.endorsed_by = actor_id) then 'technician_2'
    when actor ->> 'role' = 'facility_manager' and allowed ? 'facility_manager' and public.facility_manager_facility_permitted(w.facility_id) then 'facility_manager'
    when actor ->> 'role' in ('approver', 'supervisor') and allowed ? 'approver' and public.approval_facility_permitted(w.facility_id) then 'approver'
  end;
  if capacity is null then
    return public.work_order_result_error('ACCESS_DENIED', 'You are not one of the people who score trial jobs for this Work Order.');
  end if;
  begin
    q := (p_scores ->> 'quality')::smallint; t := (p_scores ->> 'on_time')::smallint; sf := (p_scores ->> 'safety')::smallint;
    d := (p_scores ->> 'documents')::smallint; pr := (p_scores ->> 'price')::smallint;
  exception when others then
    return public.work_order_result_error('VALIDATION_ERROR', 'Each score must be a whole number from 1 to 5.');
  end;
  if q is null or t is null or sf is null or d is null or pr is null
     or least(q, t, sf, d, pr) < 1 or greatest(q, t, sf, d, pr) > 5 then
    return public.work_order_result_error('VALIDATION_ERROR', 'Score quality, on time, safety, documents and price, each from 1 to 5.');
  end if;
  if exists (select 1 from public.contractor_trial_evaluations x where x.work_order_id = w.id and x.scored_by = actor_id) then
    return public.work_order_result_error('ALREADY_SCORED', 'You have already scored this job.');
  end if;
  insert into public.contractor_trial_evaluations(admission_id, work_order_id, scored_by, scorer_capacity, quality, on_time, safety, documents, price, comments)
  values (a.id, w.id, actor_id, capacity, q, t, sf, d, pr, nullif(btrim(coalesce(p_scores ->> 'comments', '')), '')) returning * into e;
  insert into public.activity_logs(user_id, work_order_id, action, actor, note)
  values (actor_id, w.id, 'contractor_trial_job_scored', actor ->> 'display_name',
    pg_catalog.jsonb_build_object('admission_id', a.id, 'capacity', capacity, 'quality', q, 'on_time', t, 'safety', sf, 'documents', d, 'price', pr)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'evaluation', pg_catalog.to_jsonb(e), 'trial', public.contractor_trial_result(a.id));
end;
$function$;

-- A Procurement Manager admits a contractor that has passed its trial to the facility's shortlist.
create or replace function public.admit_contractor(p_admission_id uuid, p_note text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare a public.contractor_admissions%rowtype; result jsonb;
begin
  select * into a from public.contractor_admissions where id = p_admission_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Contractor admission not found.'); end if;
  if not public.procurement_manager_permitted(a.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only a Procurement Manager admits contractors to the list.');
  end if;
  if a.status <> 'on_trial' then return public.work_order_result_error('INVALID_STATE', 'Only a contractor on trial can be admitted.'); end if;
  result := public.contractor_trial_result(a.id);
  if not coalesce((result ->> 'passed')::boolean, false) then
    return public.work_order_result_error('TRIAL_NOT_PASSED',
      pg_catalog.format('Not yet passed: %s of %s trial jobs scored, average %s (pass mark %s), lowest safety %s.',
        result ->> 'jobs_scored', result ->> 'jobs_required', coalesce(result ->> 'average', '-'), result ->> 'pass_mark', coalesce(result ->> 'lowest_safety', '-')));
  end if;
  update public.contractor_admissions set status = 'admitted', decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), '')
  where id = a.id returning * into a;
  update public.vendor_facility_eligibility set admission_status = 'shortlisted', active = true
  where vendor_id = a.vendor_id and facility_id = a.facility_id;
  perform public.contractor_admission_log('contractor_admitted', a, pg_catalog.jsonb_build_object('trial', result));
  return pg_catalog.jsonb_build_object('ok', true, 'admission', pg_catalog.to_jsonb(a), 'trial', result);
end;
$function$;

-- A Procurement Manager or the Facility Manager rejects a contractor at any step before admission.
create or replace function public.reject_contractor(p_admission_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb := public.work_order_actor(); a public.contractor_admissions%rowtype;
begin
  select * into a from public.contractor_admissions where id = p_admission_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Contractor admission not found.'); end if;
  if actor is null or not ((actor ->> 'role' = 'facility_manager' and public.facility_manager_facility_permitted(a.facility_id))
                           or public.procurement_manager_permitted(a.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED', 'The Facility Manager or a Procurement Manager rejects contractors.');
  end if;
  if a.status in ('admitted', 'rejected') then return public.work_order_result_error('INVALID_STATE', 'This admission is already decided.'); end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 5 then return public.work_order_result_error('VALIDATION_ERROR', 'Give the reason.'); end if;
  update public.contractor_admissions set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = btrim(p_reason)
  where id = a.id returning * into a;
  update public.vendor_facility_eligibility set active = false
  where vendor_id = a.vendor_id and facility_id = a.facility_id and admission_status = 'trial';
  perform public.contractor_admission_log('contractor_rejected', a, pg_catalog.jsonb_build_object('reason', a.decision_note));
  return pg_catalog.jsonb_build_object('ok', true, 'admission', pg_catalog.to_jsonb(a));
end;
$function$;

-- Prepare Proposal's contractor list now says whether a contractor is on trial (the core only; the wrapper is unchanged).
create or replace function public.work_order_eligible_contractors_r1_scope_core(p_work_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog' as $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may review eligible contractors.');
  end if;
  if actor->>'role' not in ('technician','approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Commercial access is required.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'trade',v.trade,'payment_terms_days',v.payment_terms_days,'admission_status',e.admission_status) order by e.admission_status desc, v.name),'[]'::jsonb)
  into result from public.vendor_facility_eligibility e join public.vendors v on v.id=e.vendor_id
  where e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and v.active and v.deleted_at is null;
  return jsonb_build_object('ok',true,'contractors',result);
end;$function$;

revoke all on function public.procurement_manager_permitted(uuid), public.contractor_admission_settings(uuid), public.contractor_trial_result(uuid),
  public.contractor_admission_log(text, public.contractor_admissions, jsonb), public.designate_procurement_manager(uuid, uuid, boolean),
  public.raise_contractor_request(uuid, text, text), public.recommend_contractor(jsonb), public.prequalify_contractor(uuid, text),
  public.record_contractor_owner_approval(uuid, text), public.score_contractor_trial_job(uuid, jsonb), public.admit_contractor(uuid, text),
  public.reject_contractor(uuid, text) from public, anon;
grant execute on function public.procurement_manager_permitted(uuid), public.contractor_admission_settings(uuid), public.contractor_trial_result(uuid),
  public.designate_procurement_manager(uuid, uuid, boolean), public.raise_contractor_request(uuid, text, text), public.recommend_contractor(jsonb),
  public.prequalify_contractor(uuid, text), public.record_contractor_owner_approval(uuid, text), public.score_contractor_trial_job(uuid, jsonb),
  public.admit_contractor(uuid, text), public.reject_contractor(uuid, text) to authenticated;

do $postcheck$
begin
  if to_regprocedure('public.admit_contractor(uuid,text)') is null or to_regclass('public.contractor_trial_evaluations') is null
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.work_order_eligible_contractors_r1_scope_core(uuid)'::regprocedure), 'admission_status') = 0 then
    raise exception 'D-37 contractor admission was not installed';
  end if;
end;$postcheck$;
commit;

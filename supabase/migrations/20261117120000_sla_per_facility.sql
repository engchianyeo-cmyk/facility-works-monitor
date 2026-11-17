-- M32 (owner, 17 Nov 2026): one standard SLA for all facilities, with a facility's own times where it needs them
-- (Facility 2 runs tighter); the Super-Administrator sets the times on one page instead of through document clauses.
-- 1. sla_agreements.facility_id: null = the company standard; set = that facility's own SLA.
-- 2. A new Work Order's clock uses its facility's SLA first, then the standard.
-- 3. admin_set_sla_times(): writes a new approved version (the old one is ended, its clocks keep their times).
-- 4. admin_use_standard_sla(): a facility goes back to the standard.
begin;

alter table public.sla_agreements add column facility_id uuid references public.sites(id) on delete restrict;
create unique index sla_agreements_one_active_per_facility on public.sla_agreements(facility_id) where is_active and facility_id is not null;
comment on column public.sla_agreements.facility_id is 'M32: null = the company standard SLA; set = this facility''s own SLA, used first for its Work Orders.';

-- The rule for a Work Order: its facility's own approved SLA first, then the standard (facility null).
create or replace function public.sla_rule_for(p_facility_id uuid, p_category_id uuid, p_priority text, p_at timestamptz)
returns public.sla_rules language sql stable security definer set search_path = pg_catalog as $function$
  select r.* from public.sla_rules r
  join public.sla_agreement_versions v on v.id = r.version_id
  join public.sla_agreements a on a.id = v.agreement_id
  where r.service_category_id = p_category_id and r.work_order_priority = p_priority and r.is_active and a.is_active
    and v.approval_status = 'approved' and v.effective_from <= p_at::date and (v.effective_to is null or v.effective_to >= p_at::date)
    and (a.facility_id is null or a.facility_id = p_facility_id)
  order by (a.facility_id is not null) desc, v.effective_from desc, v.version_number desc
  limit 1
$function$;
revoke all on function public.sla_rule_for(uuid, uuid, text, timestamptz) from public, anon, authenticated, service_role;

create or replace function public.attach_approved_sla_clock()
returns trigger language plpgsql set search_path = pg_catalog as $fn$
declare selected_rule public.sla_rules; start_time timestamptz := coalesce(new.submitted_at, new.created_at, pg_catalog.now());
begin
  selected_rule := public.sla_rule_for(new.facility_id, new.sla_service_category_id, new.priority, start_time);
  if selected_rule.id is not null then
    insert into public.work_order_sla_clocks(work_order_id, sla_rule_id, started_at, acknowledgement_deadline, response_deadline, attendance_deadline, make_safe_deadline, rectification_deadline)
    values (new.id, selected_rule.id, start_time,
      case when selected_rule.acknowledgement_minutes is not null then start_time + pg_catalog.make_interval(mins => selected_rule.acknowledgement_minutes) end,
      case when selected_rule.response_minutes is not null then start_time + pg_catalog.make_interval(mins => selected_rule.response_minutes) end,
      case when selected_rule.attendance_minutes is not null then start_time + pg_catalog.make_interval(mins => selected_rule.attendance_minutes) end,
      case when selected_rule.make_safe_minutes is not null then start_time + pg_catalog.make_interval(mins => selected_rule.make_safe_minutes) end,
      start_time + pg_catalog.make_interval(mins => selected_rule.rectification_minutes))
    on conflict (work_order_id) do nothing;
  end if;
  return new;
end;$fn$;

-- The Super-Administrator sets all four priorities' times for the standard (p_facility_id null) or one facility.
-- p_rows: [{"priority":"critical","acknowledgement_minutes":15,"attendance_minutes":30,"make_safe_minutes":120,
--           "rectification_minutes":240,"kpi_target_percent":95}, ... high, medium, low]
create or replace function public.admin_set_sla_times(p_facility_id uuid, p_rows jsonb, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  v_category uuid; v_agreement public.sla_agreements%rowtype; v_old public.sla_agreement_versions%rowtype; v_new uuid;
  v_name text; v_code text; v_row jsonb; v_priority text; v_class text; v_count integer := 0; v_seen text[] := '{}';
  v_ack integer; v_att integer; v_safe integer; v_fix integer; v_kpi numeric;
begin
  if actor is null or actor ->> 'role' <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the Super-Administrator sets SLA times.');
  end if;
  actor_id := (actor ->> 'id')::uuid;
  if pg_catalog.length(v_reason) < 5 then return public.work_order_result_error('VALIDATION_ERROR', 'Give a reason of at least 5 characters.'); end if;
  if p_facility_id is not null and not exists(select 1 from public.sites where id = p_facility_id) then
    return public.work_order_result_error('NOT_FOUND', 'Facility not found.');
  end if;
  if pg_catalog.jsonb_typeof(p_rows) <> 'array' or pg_catalog.jsonb_array_length(p_rows) <> 4 then
    return public.work_order_result_error('VALIDATION_ERROR', 'Give times for all four priorities: Critical, High, Medium and Low.');
  end if;
  for v_row in select value from pg_catalog.jsonb_array_elements(p_rows) loop
    v_priority := v_row ->> 'priority';
    if v_priority not in ('critical','high','medium','low') or v_priority = any(v_seen) then
      return public.work_order_result_error('VALIDATION_ERROR', 'Each priority (Critical, High, Medium, Low) must appear once.');
    end if;
    v_seen := v_seen || v_priority;
    begin
      v_ack := nullif(v_row ->> 'acknowledgement_minutes', '')::integer; v_att := nullif(v_row ->> 'attendance_minutes', '')::integer;
      v_safe := nullif(v_row ->> 'make_safe_minutes', '')::integer; v_fix := nullif(v_row ->> 'rectification_minutes', '')::integer;
      v_kpi := nullif(v_row ->> 'kpi_target_percent', '')::numeric;
    exception when others then
      return public.work_order_result_error('VALIDATION_ERROR', 'Times must be whole minutes and the target a percentage.');
    end;
    if v_fix is null or v_fix <= 0 or v_kpi is null or v_kpi < 0 or v_kpi > 100
       or coalesce(v_ack, 1) <= 0 or coalesce(v_att, 1) <= 0 or coalesce(v_safe, 1) <= 0 then
      return public.work_order_result_error('VALIDATION_ERROR', 'Every priority needs a fix time above zero and a target between 0 and 100 %.');
    end if;
    if coalesce(v_ack, 0) > coalesce(v_att, v_fix) or coalesce(v_att, 0) > coalesce(v_safe, v_fix) or coalesce(v_safe, 0) > v_fix then
      return public.work_order_result_error('VALIDATION_ERROR', 'Times must not run backwards: acknowledge, then attend, then make safe, then fix.');
    end if;
  end loop;

  select id into v_category from public.service_categories where code = 'GENERAL';
  if v_category is null then return public.work_order_result_error('INVALID_STATE', 'The GENERAL service category is missing.'); end if;

  select * into v_agreement from public.sla_agreements
   where is_active and ((p_facility_id is null and facility_id is null and agreement_code = 'FMW-STANDARD') or facility_id = p_facility_id)
   order by created_at limit 1;
  if v_agreement.id is null then
    if p_facility_id is null then v_code := 'FMW-STANDARD'; v_name := 'FMWorks standard SLA (all facilities)';
    else
      select 'FMW-FAC-' || code, name || ' SLA' into v_code, v_name from public.sites where id = p_facility_id;
      if exists(select 1 from public.sla_agreements where agreement_code = v_code) then v_code := v_code || '-' || pg_catalog.to_char(pg_catalog.now(), 'YYYYMMDDHH24MISS'); end if;
    end if;
    insert into public.sla_agreements(agreement_code, name, counterparty, facility_id, created_by)
    values (v_code, v_name, 'Facility owner', p_facility_id, actor_id) returning * into v_agreement;
  end if;

  -- The standard replaces any older company-wide agreement, so one set of times shows on Site SLA.
  if p_facility_id is null then
    update public.sla_rules r set is_active = false from public.sla_agreement_versions v, public.sla_agreements a
     where r.version_id = v.id and v.agreement_id = a.id and a.facility_id is null and a.id <> v_agreement.id and r.is_active;
    update public.sla_agreements set is_active = false, updated_at = pg_catalog.now() where facility_id is null and id <> v_agreement.id and is_active;
  end if;

  -- End the current version (it keeps its approval record); its rules stop applying to new Work Orders but stay
  -- for the clocks already running on them.
  for v_old in select * from public.sla_agreement_versions where agreement_id = v_agreement.id and approval_status = 'approved'
      and (effective_to is null or effective_to >= current_date) loop
    update public.sla_agreement_versions set effective_to = greatest(v_old.effective_from, current_date - 1) where id = v_old.id;
    update public.sla_rules set is_active = false where version_id = v_old.id;
  end loop;

  insert into public.sla_agreement_versions(agreement_id, version_number, effective_from, source_reference, approval_status, approved_by, approved_at, approval_note, created_by)
  values (v_agreement.id, coalesce((select max(version_number) from public.sla_agreement_versions where agreement_id = v_agreement.id), 0) + 1,
    current_date, 'Set in FMWorks by the Super-Administrator', 'approved', actor_id, pg_catalog.now(), v_reason, actor_id)
  returning id into v_new;

  for v_row in select value from pg_catalog.jsonb_array_elements(p_rows) loop
    v_priority := v_row ->> 'priority';
    v_class := case v_priority when 'critical' then 'P1' when 'high' then 'P2' when 'medium' then 'P3' else 'P4' end;
    insert into public.sla_rules(version_id, service_category_id, priority_class, work_order_priority, acknowledgement_minutes, response_minutes,
      attendance_minutes, make_safe_minutes, rectification_minutes, kpi_target_percent, source_clause)
    values (v_new, v_category, v_class, v_priority, nullif(v_row ->> 'acknowledgement_minutes', '')::integer, null,
      nullif(v_row ->> 'attendance_minutes', '')::integer, nullif(v_row ->> 'make_safe_minutes', '')::integer,
      (v_row ->> 'rectification_minutes')::integer, (v_row ->> 'kpi_target_percent')::numeric,
      'Set by ' || coalesce(actor ->> 'display_name', actor ->> 'name', 'the Super-Administrator') || ': ' || v_reason);
    v_count := v_count + 1;
  end loop;

  insert into public.activity_logs(user_id, action, actor, note)
  values (actor_id, 'sla_times_set', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'agreement_id', v_agreement.id, 'version_id', v_new, 'reason', v_reason, 'rows', p_rows)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'agreement_id', v_agreement.id, 'version_id', v_new, 'rules', v_count);
end;
$function$;

create or replace function public.admin_use_standard_sla(p_facility_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); v_reason text := pg_catalog.btrim(coalesce(p_reason, '')); v_id uuid;
begin
  if actor is null or actor ->> 'role' <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the Super-Administrator sets SLA times.');
  end if;
  if pg_catalog.length(v_reason) < 5 then return public.work_order_result_error('VALIDATION_ERROR', 'Give a reason of at least 5 characters.'); end if;
  select id into v_id from public.sla_agreements where facility_id = p_facility_id and is_active;
  if v_id is null then return public.work_order_result_error('NOT_FOUND', 'This facility already uses the standard SLA.'); end if;
  update public.sla_rules r set is_active = false from public.sla_agreement_versions v where r.version_id = v.id and v.agreement_id = v_id;
  update public.sla_agreements set is_active = false, updated_at = pg_catalog.now() where id = v_id;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor ->> 'id')::uuid, 'sla_facility_uses_standard', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'agreement_id', v_id, 'reason', v_reason)::text);
  return pg_catalog.jsonb_build_object('ok', true);
end;
$function$;

revoke all on function public.admin_set_sla_times(uuid, jsonb, text), public.admin_use_standard_sla(uuid, text) from public, anon, service_role;
grant execute on function public.admin_set_sla_times(uuid, jsonb, text), public.admin_use_standard_sla(uuid, text) to authenticated;

commit;

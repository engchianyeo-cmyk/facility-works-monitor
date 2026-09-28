-- WP-FMW-009: deterministic SLA, escalation, reporting, and scheduling foundation.
begin;

do $preflight$
begin
  if to_regclass('public.work_orders') is null or to_regclass('public.activity_logs') is null
    or to_regprocedure('public.work_order_actor()') is null then
    raise exception '0025 prerequisite missing: approved Work Order/audit foundation';
  end if;
end;
$preflight$;

create table public.service_categories(
  id uuid primary key default gen_random_uuid(), code text not null, name text not null,
  is_active boolean not null default true, created_at timestamptz not null default now(),
  unique(code), check(length(btrim(code)) between 1 and 40), check(length(btrim(name)) between 1 and 160)
);
insert into public.service_categories(code,name) values('GENERAL','General Facilities Service');
alter table public.work_orders add column sla_service_category_id uuid references public.service_categories(id) on delete restrict;

create table public.sla_agreements(
  id uuid primary key default gen_random_uuid(), agreement_code text not null unique, name text not null,
  counterparty text, is_active boolean not null default true, created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.sla_agreement_versions(
  id uuid primary key default gen_random_uuid(), agreement_id uuid not null references public.sla_agreements(id) on delete restrict,
  version_number integer not null check(version_number>0), effective_from date not null, effective_to date,
  source_reference text, approval_status text not null default 'draft' check(approval_status in ('draft','pending_approval','approved','rejected','superseded')),
  approved_by uuid references public.profiles(id), approved_at timestamptz, approval_note text,
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
  unique(agreement_id,version_number), check(effective_to is null or effective_to>=effective_from),
  check((approval_status='approved')=(approved_by is not null and approved_at is not null))
);

create table public.sla_rules(
  id uuid primary key default gen_random_uuid(), version_id uuid not null references public.sla_agreement_versions(id) on delete cascade,
  service_category_id uuid not null references public.service_categories(id),
  priority_class text not null check(priority_class in ('P1','P2','P3','P4')),
  work_order_priority text not null check(work_order_priority in ('critical','high','medium','low')),
  acknowledgement_minutes integer check(acknowledgement_minutes>0), response_minutes integer check(response_minutes>0),
  attendance_minutes integer check(attendance_minutes>0), make_safe_minutes integer check(make_safe_minutes>0),
  rectification_minutes integer not null check(rectification_minutes>0), kpi_target_percent numeric(5,2) not null check(kpi_target_percent between 0 and 100),
  source_clause text not null, is_active boolean not null default true, created_at timestamptz not null default now(),
  unique(version_id,service_category_id,priority_class)
);

create table public.sla_extraction_proposals(
  id uuid primary key default gen_random_uuid(), agreement_id uuid references public.sla_agreements(id),
  source_page text, source_section text, source_clause text, extracted_obligation text not null,
  proposed_rule jsonb not null, confidence numeric(5,4) check(confidence between 0 and 1),
  ambiguity_warning text, provider_key text not null, human_approval_state text not null default 'pending'
    check(human_approval_state in ('pending','approved_for_draft','rejected')),
  reviewed_by uuid references public.profiles(id), reviewed_at timestamptz,
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
  check(human_approval_state='pending' or reviewed_by is not null)
);

create table public.work_order_sla_clocks(
  work_order_id uuid primary key references public.work_orders(id) on delete cascade,
  sla_rule_id uuid not null references public.sla_rules(id) on delete restrict,
  started_at timestamptz not null, acknowledgement_deadline timestamptz, response_deadline timestamptz,
  attendance_deadline timestamptz, make_safe_deadline timestamptz, rectification_deadline timestamptz not null,
  acknowledged_at timestamptz, responded_at timestamptz, attended_at timestamptz, made_safe_at timestamptz, rectified_at timestamptz,
  risk_state text not null default 'on_track' check(risk_state in ('on_track','at_risk','breached','met')),
  consumed_percent numeric(8,2) not null default 0, last_evaluated_at timestamptz not null default now()
);

create or replace function public.default_work_order_sla_category()
returns trigger language plpgsql set search_path=pg_catalog as $fn$
begin
 if new.sla_service_category_id is null then select id into new.sla_service_category_id from public.service_categories where code='GENERAL'; end if;
 return new;
end;$fn$;
create trigger default_work_order_sla_category before insert on public.work_orders for each row execute function public.default_work_order_sla_category();

create or replace function public.attach_approved_sla_clock()
returns trigger language plpgsql set search_path=pg_catalog as $fn$
declare selected_rule public.sla_rules; start_time timestamptz:=coalesce(new.submitted_at,new.created_at,now());
begin
 select r.* into selected_rule from public.sla_rules r join public.sla_agreement_versions v on v.id=r.version_id
 join public.sla_agreements a on a.id=v.agreement_id
 where r.service_category_id=new.sla_service_category_id and r.work_order_priority=new.priority and r.is_active and a.is_active
   and v.approval_status='approved' and v.effective_from<=start_time::date and (v.effective_to is null or v.effective_to>=start_time::date)
 order by v.effective_from desc,v.version_number desc limit 1;
 if found then
  insert into public.work_order_sla_clocks(work_order_id,sla_rule_id,started_at,acknowledgement_deadline,response_deadline,attendance_deadline,make_safe_deadline,rectification_deadline)
  values(new.id,selected_rule.id,start_time,
   case when selected_rule.acknowledgement_minutes is not null then start_time+make_interval(mins=>selected_rule.acknowledgement_minutes) end,
   case when selected_rule.response_minutes is not null then start_time+make_interval(mins=>selected_rule.response_minutes) end,
   case when selected_rule.attendance_minutes is not null then start_time+make_interval(mins=>selected_rule.attendance_minutes) end,
   case when selected_rule.make_safe_minutes is not null then start_time+make_interval(mins=>selected_rule.make_safe_minutes) end,
   start_time+make_interval(mins=>selected_rule.rectification_minutes)) on conflict(work_order_id) do nothing;
 end if;
 return new;
end;$fn$;
create trigger attach_approved_sla_clock after insert on public.work_orders for each row execute function public.attach_approved_sla_clock();

create table public.escalation_matrix_steps(
  id uuid primary key default gen_random_uuid(), version_id uuid not null references public.sla_agreement_versions(id) on delete cascade,
  threshold_percent numeric(5,2) not null check(threshold_percent between 0 and 100),
  escalation_level text not null check(escalation_level in ('warning','supervisor','facilities_engineer','facility_manager','contract_fm_manager','client_management','breach')),
  recipient_role text, is_immediate_for_critical_safety boolean not null default false,
  created_at timestamptz not null default now(), unique(version_id,threshold_percent,escalation_level)
);

create table public.sla_escalation_events(
  id uuid primary key default gen_random_uuid(), work_order_id uuid not null references public.work_orders(id) on delete cascade,
  matrix_step_id uuid not null references public.escalation_matrix_steps(id), threshold_percent numeric(5,2) not null,
  escalation_level text not null, reason text not null, triggered_at timestamptz not null default now(),
  acknowledged_by uuid references public.profiles(id), acknowledged_at timestamptz, acknowledgement_note text,
  unique(work_order_id,matrix_step_id)
);

create table public.sites(id uuid primary key default gen_random_uuid(),code text not null unique,name text not null,is_active boolean not null default true);
create table public.buildings(id uuid primary key default gen_random_uuid(),site_id uuid not null references public.sites(id),code text not null,name text not null,is_active boolean not null default true,unique(site_id,code));
create table public.location_levels(id uuid primary key default gen_random_uuid(),building_id uuid not null references public.buildings(id),code text not null,name text not null,is_active boolean not null default true,unique(building_id,code));
create table public.location_zones(id uuid primary key default gen_random_uuid(),level_id uuid not null references public.location_levels(id),code text not null,name text not null,zone_type text not null default 'zone' check(zone_type in ('zone','room')),is_active boolean not null default true,unique(level_id,code));
alter table public.assets add column location_zone_id uuid references public.location_zones(id) on delete set null;

create table public.report_schedules(
  id uuid primary key default gen_random_uuid(), name text not null,
  cadence text not null check(cadence in ('daily','weekly','monthly')),
  report_scope jsonb not null default '{}'::jsonb, recipient_roles text[] not null default '{}', recipient_emails text[] not null default '{}',
  is_active boolean not null default true, last_run_at timestamptz, next_run_at timestamptz not null,
  last_delivery_status text not null default 'NOT_CONFIGURED' check(last_delivery_status in ('NOT_CONFIGURED','GENERATED','DELIVERED','FAILED')),
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.report_runs(
  id uuid primary key default gen_random_uuid(), schedule_id uuid references public.report_schedules(id),
  report_type text not null check(report_type in ('daily','weekly','monthly','custom')),
  period_start date not null, period_end date not null, scope jsonb not null default '{}'::jsonb,
  metrics_snapshot jsonb not null, delivery_status text not null default 'NOT_CONFIGURED'
    check(delivery_status in ('NOT_CONFIGURED','GENERATED','DELIVERED','FAILED')),
  generated_by uuid references public.profiles(id), generated_at timestamptz not null default now(),
  check(period_end>=period_start)
);

create or replace function public.approve_sla_version(p_version_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); result public.sla_agreement_versions;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Facility Manager or Administrator approval is required.'); end if;
 if not exists(select 1 from public.sla_rules r where r.version_id=p_version_id and r.is_active) then return public.work_order_result_error('VALIDATION_ERROR','At least one active SLA rule is required.'); end if;
 update public.sla_agreement_versions set approval_status='approved',approved_by=(actor->>'id')::uuid,approved_at=now(),approval_note=nullif(btrim(coalesce(p_note,'')),'') where id=p_version_id and approval_status in ('draft','pending_approval') returning * into result;
 if not found then return public.work_order_result_error('INVALID_STATE','Only a draft or pending version can be approved.'); end if;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_version_approved',actor->>'name',jsonb_build_object('version_id',result.id,'note',p_note)::text);
 return jsonb_build_object('ok',true,'version',to_jsonb(result));
end;$fn$;

create or replace function public.refresh_work_order_sla(p_work_order_id uuid,p_as_of timestamptz default now())
returns public.work_order_sla_clocks language plpgsql security definer set search_path=pg_catalog as $fn$
declare c public.work_order_sla_clocks; elapsed numeric; total numeric;
begin
 select * into c from public.work_order_sla_clocks where work_order_id=p_work_order_id for update;
 if not found then return null; end if;
 total:=greatest(extract(epoch from(c.rectification_deadline-c.started_at)),1);
 elapsed:=greatest(extract(epoch from(coalesce(c.rectified_at,p_as_of)-c.started_at)),0);
 update public.work_order_sla_clocks set consumed_percent=least(999.99,round(elapsed/total*100,2)),
  risk_state=case when rectified_at is not null and rectified_at<=rectification_deadline then 'met' when coalesce(rectified_at,p_as_of)>rectification_deadline then 'breached' when elapsed/total>=.75 then 'at_risk' else 'on_track' end,
  last_evaluated_at=p_as_of where work_order_id=p_work_order_id returning * into c;
 return c;
end;$fn$;

create or replace function public.process_sla_escalations(p_as_of timestamptz default now())
returns integer language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); inserted_count integer;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then raise exception 'ACCESS_DENIED'; end if;
 perform public.refresh_work_order_sla(c.work_order_id,p_as_of) from public.work_order_sla_clocks c;
 insert into public.sla_escalation_events(work_order_id,matrix_step_id,threshold_percent,escalation_level,reason,triggered_at)
 select c.work_order_id,s.id,s.threshold_percent,s.escalation_level,
  case when s.is_immediate_for_critical_safety and w.priority='critical' then 'Critical safety immediate escalation' else 'SLA threshold reached' end,p_as_of
 from public.work_order_sla_clocks c join public.sla_rules r on r.id=c.sla_rule_id
 join public.sla_agreement_versions v on v.id=r.version_id join public.escalation_matrix_steps s on s.version_id=v.id
 join public.work_orders w on w.id=c.work_order_id
 where c.risk_state<>'met' and (c.consumed_percent>=s.threshold_percent or (s.is_immediate_for_critical_safety and w.priority='critical'))
 on conflict(work_order_id,matrix_step_id) do nothing;
 get diagnostics inserted_count=row_count;
 insert into public.activity_logs(user_id,work_order_id,action,actor,note)
 select (actor->>'id')::uuid,e.work_order_id,'sla_escalated',actor->>'name',jsonb_build_object('level',e.escalation_level,'threshold_percent',e.threshold_percent,'reason',e.reason)::text
 from public.sla_escalation_events e where e.triggered_at=p_as_of;
 return inserted_count;
end;$fn$;

create or replace function public.create_report_schedule(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); result public.report_schedules; cadence_value text:=lower(coalesce(p_payload->>'cadence',''));
begin
 if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management reporting authority is required.'); end if;
 if cadence_value not in ('daily','weekly','monthly') or length(btrim(coalesce(p_payload->>'name','')))<3 then return public.work_order_result_error('VALIDATION_ERROR','A valid name and cadence are required.'); end if;
 insert into public.report_schedules(name,cadence,report_scope,recipient_roles,recipient_emails,next_run_at,created_by)
 values(btrim(p_payload->>'name'),cadence_value,coalesce(p_payload->'scope','{}'::jsonb),coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'recipient_roles','[]'::jsonb))),'{}'),coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'recipient_emails','[]'::jsonb))),'{}'),coalesce(nullif(p_payload->>'next_run_at','')::timestamptz,now()),(actor->>'id')::uuid) returning * into result;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'report_schedule_created',actor->>'name',jsonb_build_object('schedule_id',result.id,'cadence',result.cadence,'delivery_status','NOT_CONFIGURED')::text);
 return jsonb_build_object('ok',true,'schedule',to_jsonb(result));
end;$fn$;

create or replace function public.acknowledge_sla_escalation(p_event_id uuid,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); event public.sla_escalation_events;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management acknowledgement authority is required.'); end if;
 update public.sla_escalation_events set acknowledged_by=(actor->>'id')::uuid,acknowledged_at=now(),acknowledgement_note=nullif(btrim(coalesce(p_note,'')),'') where id=p_event_id and acknowledged_at is null returning * into event;
 if not found then return public.work_order_result_error('INVALID_STATE','Escalation is unavailable or already acknowledged.'); end if;
 insert into public.activity_logs(user_id,work_order_id,action,actor,note)values((actor->>'id')::uuid,event.work_order_id,'sla_escalation_acknowledged',actor->>'name',jsonb_build_object('event_id',event.id,'note',p_note)::text);
 return jsonb_build_object('ok',true,'event',to_jsonb(event));
end;$fn$;

alter table public.service_categories enable row level security; alter table public.sla_agreements enable row level security;
alter table public.sla_agreement_versions enable row level security; alter table public.sla_rules enable row level security;
alter table public.sla_extraction_proposals enable row level security; alter table public.work_order_sla_clocks enable row level security;
alter table public.escalation_matrix_steps enable row level security; alter table public.sla_escalation_events enable row level security;
alter table public.sites enable row level security; alter table public.buildings enable row level security; alter table public.location_levels enable row level security; alter table public.location_zones enable row level security;
alter table public.report_schedules enable row level security; alter table public.report_runs enable row level security;

do $policies$ declare t text; begin
 foreach t in array array['service_categories','sla_agreements','sla_agreement_versions','sla_rules','sla_extraction_proposals','work_order_sla_clocks','escalation_matrix_steps','sla_escalation_events','report_schedules','report_runs'] loop
  execute format('create policy %I on public.%I for select to authenticated using (public.current_user_role() in (''approver'',''supervisor'',''administrator''))',t||'_management_read',t);
 end loop;
 foreach t in array array['sites','buildings','location_levels','location_zones'] loop
  execute format('create policy %I on public.%I for select to authenticated using (public.current_user_role() is not null)',t||'_authenticated_read',t);
 end loop;
end;$policies$;

revoke insert,update,delete on public.sla_agreements,public.sla_agreement_versions,public.sla_rules,public.sla_extraction_proposals,public.work_order_sla_clocks,public.escalation_matrix_steps,public.sla_escalation_events,public.report_schedules,public.report_runs from authenticated;
grant select on public.service_categories,public.sla_agreements,public.sla_agreement_versions,public.sla_rules,public.sla_extraction_proposals,public.work_order_sla_clocks,public.escalation_matrix_steps,public.sla_escalation_events,public.report_schedules,public.report_runs to authenticated;
grant select on public.sites,public.buildings,public.location_levels,public.location_zones to authenticated;
revoke all on function public.approve_sla_version(uuid,text),public.refresh_work_order_sla(uuid,timestamptz),public.process_sla_escalations(timestamptz),public.create_report_schedule(jsonb),public.acknowledge_sla_escalation(uuid,text) from public,anon,service_role;
grant execute on function public.approve_sla_version(uuid,text),public.refresh_work_order_sla(uuid,timestamptz),public.process_sla_escalations(timestamptz),public.create_report_schedule(jsonb),public.acknowledge_sla_escalation(uuid,text) to authenticated;

commit;

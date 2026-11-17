-- M34 (owner, 17 Nov 2026): the maintenance plan by frequency.
-- 1. Each planned-maintenance requirement (daily, weekly, monthly, quarterly, 6-monthly, annual) can have a
--    Technician responsible, set by a Supervisor, Facility Manager or the Super-Administrator. The Work Orders it
--    generates are assigned to that Technician automatically.
-- 2. Each asset can carry documents, first of all its O&M manual, for Technicians to cross-reference.
-- 3. Everyone at a facility can read its maintenance plan (until now only approvers and up could).
begin;

-- 1. Technician responsible ------------------------------------------------------------------------------------------
alter table public.maintenance_requirements
  add column assigned_technician_id uuid references public.profiles(id) on delete set null,
  add column assigned_by uuid references public.profiles(id) on delete set null,
  add column assigned_at timestamptz;
comment on column public.maintenance_requirements.assigned_technician_id is 'M34: the Technician responsible; generated Work Orders are assigned to them.';

create or replace function public.facility_of_asset(p_asset_id uuid)
returns uuid language sql stable security definer set search_path = pg_catalog as $function$
  select facility_id from public.assets where id = p_asset_id
$function$;
revoke all on function public.facility_of_asset(uuid) from public, anon, service_role;
grant execute on function public.facility_of_asset(uuid) to authenticated;

-- Who may plan at a facility: the Super-Administrator, or a Supervisor / Facility Manager who is staff there.
create or replace function public.pm_planner_for(p_facility_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and (
    public.current_user_role() = 'administrator'
    or (public.current_user_role() in ('supervisor','facility_manager') and exists(
      select 1 from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = auth.uid() and m.active
        and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now()))))
$function$;
revoke all on function public.pm_planner_for(uuid) from public, anon, service_role;
grant execute on function public.pm_planner_for(uuid) to authenticated;

create or replace function public.assign_pm_technician(p_requirement_id uuid, p_technician_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); req public.maintenance_requirements%rowtype; v_facility uuid; v_name text;
begin
  select * into req from public.maintenance_requirements where id = p_requirement_id for update;
  if req.id is null then return public.pm_result_error('NOT_FOUND', 'Maintenance requirement not found.'); end if;
  v_facility := public.facility_of_asset(req.asset_id);
  if actor is null or not public.pm_planner_for(v_facility) then
    return public.pm_result_error('ACCESS_DENIED', 'A Supervisor or Facility Manager of this facility, or the Super-Administrator, assigns Technicians.');
  end if;
  if p_technician_id is not null then
    if not exists(select 1 from public.profiles p where p.id = p_technician_id and p.role = 'technician' and p.is_active and p.deleted_at is null)
       or not public.active_facility_member(v_facility, 'technician', p_technician_id) then
      return public.pm_result_error('INVALID_REFERENCE', 'Choose an active Technician who is staff of this facility.');
    end if;
    select display_name into v_name from public.profiles where id = p_technician_id;
  end if;
  if req.assigned_technician_id is not distinct from p_technician_id then
    return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE');
  end if;
  update public.maintenance_requirements set assigned_technician_id = p_technician_id, assigned_by = (actor ->> 'id')::uuid,
    assigned_at = pg_catalog.now(), updated_by = (actor ->> 'id')::uuid, updated_at = pg_catalog.now() where id = req.id;
  insert into public.activity_logs(user_id, asset_id, maintenance_requirement_id, action, actor, note)
  values ((actor ->> 'id')::uuid, req.asset_id, req.id, 'pm_technician_assigned', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('technician_id', p_technician_id, 'technician', v_name, 'previous_technician_id', req.assigned_technician_id)::text);
  return pg_catalog.jsonb_build_object('ok', true);
end;
$function$;
revoke all on function public.assign_pm_technician(uuid, uuid) from public, anon, service_role;
grant execute on function public.assign_pm_technician(uuid, uuid) to authenticated;

-- A Work Order generated from a planned-maintenance occurrence goes to the requirement's Technician.
create or replace function public.assign_pm_work_order_technician()
returns trigger language plpgsql security definer set search_path = pg_catalog as $function$
declare v_tech uuid;
begin
  if new.pm_occurrence_id is null or new.assigned_technician_id is not null then return new; end if;
  select r.assigned_technician_id into v_tech from public.pm_occurrences o join public.maintenance_requirements r on r.id = o.requirement_id
   where o.id = new.pm_occurrence_id;
  -- This trigger runs before the one that fills in the facility, so take the facility from the asset.
  if v_tech is not null and public.pilot_account_ready(v_tech)
     and public.active_facility_member(coalesce(new.facility_id, public.facility_of_asset(new.asset_id)), 'technician', v_tech) then
    new.assigned_technician_id := v_tech;
    new.assigned_at := coalesce(new.assigned_at, pg_catalog.now());
  end if;
  return new;
end;
$function$;
revoke all on function public.assign_pm_work_order_technician() from public, anon, authenticated, service_role;
create trigger assign_pm_work_order_technician before insert on public.work_orders
  for each row execute function public.assign_pm_work_order_technician();

-- Everyone at the facility reads its plan (requirements and their revisions follow).
create policy maintenance_requirements_facility_read on public.maintenance_requirements for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (assigned_technician_id = auth.uid() or exists(
    select 1 from public.facility_memberships m where m.facility_id = public.facility_of_asset(asset_id) and m.profile_id = auth.uid() and m.active
      and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now())))
);

-- The Technicians a planner can choose at a facility.
create or replace function public.facility_technicians(p_facility_id uuid)
returns table(id uuid, display_name text, trade_discipline text)
language sql stable security definer set search_path = pg_catalog as $function$
  select p.id, p.display_name, p.trade_discipline from public.profiles p
  where public.pilot_account_ready(auth.uid()) and (public.pm_planner_for(p_facility_id) or public.current_user_role() in ('approver','facility_administrator'))
    and p.role = 'technician' and p.is_active and p.deleted_at is null and public.active_facility_member(p_facility_id, 'technician', p.id)
  order by p.display_name
$function$;
revoke all on function public.facility_technicians(uuid) from public, anon, service_role;
grant execute on function public.facility_technicians(uuid) to authenticated;

-- 2. Asset documents (O&M manuals) ----------------------------------------------------------------------------------
create table public.asset_documents (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete restrict,
  kind text not null default 'om_manual' check (kind in ('om_manual','datasheet','certificate','drawing','other')),
  title text not null check (length(btrim(title)) between 2 and 200),
  original_filename text not null check (length(original_filename) between 1 and 200),
  content_type text not null check (content_type in ('application/pdf','image/png','image/jpeg','image/webp')),
  byte_size integer not null check (byte_size > 0 and byte_size <= 52428800),
  storage_path text not null unique check (storage_path like 'asset-documents/%'),
  active boolean not null default true,
  uploaded_by uuid references public.profiles(id) on delete set null,
  uploaded_at timestamptz not null default now(),
  retired_by uuid references public.profiles(id) on delete set null,
  retired_at timestamptz,
  retired_reason text
);
create index asset_documents_asset_idx on public.asset_documents(asset_id) where active;
comment on table public.asset_documents is 'M34: documents kept with an asset, first of all its O&M manual.';
alter table public.asset_documents enable row level security;
revoke all on public.asset_documents from public, anon, authenticated, service_role;
grant select on public.asset_documents to authenticated;
create policy asset_documents_read on public.asset_documents for select to authenticated using (
  public.pilot_account_ready(auth.uid()) and (public.current_user_role() = 'administrator' or exists(
    select 1 from public.facility_memberships m where m.facility_id = public.facility_of_asset(asset_id) and m.profile_id = auth.uid() and m.active
      and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now())))
);

-- Who may file documents for an asset: its planners and the facility's Facility Administrator.
create or replace function public.asset_document_editor(p_asset_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select public.pm_planner_for(public.facility_of_asset(p_asset_id))
    or (public.current_user_role() = 'facility_administrator' and public.pilot_account_ready(auth.uid())
        and public.active_facility_member(public.facility_of_asset(p_asset_id), 'facility_administrator'))
$function$;
revoke all on function public.asset_document_editor(uuid) from public, anon, service_role;
grant execute on function public.asset_document_editor(uuid) to authenticated;

create or replace function public.register_asset_document(p_asset_id uuid, p_kind text, p_title text, p_filename text, p_content_type text, p_byte_size integer, p_storage_path text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); v_id uuid;
begin
  if actor is null or not exists(select 1 from public.assets where id = p_asset_id) or not public.asset_document_editor(p_asset_id) then
    return public.pm_result_error('ACCESS_DENIED', 'A Supervisor, Facility Manager or Facility Administrator of this facility, or the Super-Administrator, files asset documents.');
  end if;
  insert into public.asset_documents(asset_id, kind, title, original_filename, content_type, byte_size, storage_path, uploaded_by)
  values (p_asset_id, coalesce(nullif(p_kind, ''), 'om_manual'), pg_catalog.btrim(p_title), p_filename, p_content_type, p_byte_size, p_storage_path, (actor ->> 'id')::uuid)
  returning id into v_id;
  insert into public.activity_logs(user_id, asset_id, action, actor, note)
  values ((actor ->> 'id')::uuid, p_asset_id, 'asset_document_added', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('document_id', v_id, 'kind', p_kind, 'title', p_title, 'filename', p_filename)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation or unique_violation then
  return public.pm_result_error('VALIDATION_ERROR', 'The document details are invalid.');
end;
$function$;

create or replace function public.retire_asset_document(p_document_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); doc public.asset_documents%rowtype; v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  select * into doc from public.asset_documents where id = p_document_id and active;
  if doc.id is null then return public.pm_result_error('NOT_FOUND', 'Document not found.'); end if;
  if actor is null or not public.asset_document_editor(doc.asset_id) then return public.pm_result_error('ACCESS_DENIED', 'You cannot retire this document.'); end if;
  if pg_catalog.length(v_reason) < 5 then return public.pm_result_error('VALIDATION_ERROR', 'Give a reason of at least 5 characters.'); end if;
  update public.asset_documents set active = false, retired_by = (actor ->> 'id')::uuid, retired_at = pg_catalog.now(), retired_reason = v_reason where id = doc.id;
  insert into public.activity_logs(user_id, asset_id, action, actor, note)
  values ((actor ->> 'id')::uuid, doc.asset_id, 'asset_document_retired', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('document_id', doc.id, 'title', doc.title, 'reason', v_reason)::text);
  return pg_catalog.jsonb_build_object('ok', true);
end;
$function$;
revoke all on function public.register_asset_document(uuid, text, text, text, text, integer, text), public.retire_asset_document(uuid, text) from public, anon, service_role;
grant execute on function public.register_asset_document(uuid, text, text, text, text, integer, text), public.retire_asset_document(uuid, text) to authenticated;

commit;

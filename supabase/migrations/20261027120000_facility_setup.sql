-- WP-FAC-01 (D-17, owner 27 Oct 2026 17:59): the Administrator adds new facilities, their areas, their
-- layout drawings (upload, view, download) and their staff, without database scripts.
-- All writes go through audited Administrator-only functions; direct table writes stay revoked.
begin;

alter table public.sites add column address text check (address is null or pg_catalog.length(address) <= 500);
alter table public.sites add column updated_at timestamptz not null default pg_catalog.now();
comment on column public.sites.address is 'D-17: facility address shown on the Facilities page.';

-- Area codes repeat across facilities (every facility has an ELR-01 Electrical Room); unique per facility.
alter table public.facility_areas drop constraint facility_areas_area_code_key;
alter table public.facility_areas add constraint facility_areas_facility_code_key unique (facility_id, area_code);

create table public.facility_drawings (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.sites(id) on delete restrict,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9-]{0,23}$'),
  title text not null check (pg_catalog.length(pg_catalog.btrim(title)) between 2 and 200),
  revision text check (revision is null or pg_catalog.length(revision) <= 60),
  original_filename text not null check (pg_catalog.length(original_filename) between 1 and 255),
  content_type text not null check (content_type in ('image/png','image/jpeg','image/webp','application/pdf')),
  byte_size bigint not null check (byte_size > 0 and byte_size <= 52428800),
  width integer check (width is null or width between 1 and 20000),
  height integer check (height is null or height between 1 and 20000),
  storage_path text not null unique,
  active boolean not null default true,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  uploaded_at timestamptz not null default pg_catalog.now(),
  removed_by uuid references public.profiles(id) on delete restrict,
  removed_at timestamptz,
  removal_reason text,
  check (content_type = 'application/pdf' or (width is not null and height is not null))
);
create unique index facility_drawings_active_code_idx on public.facility_drawings(facility_id, code) where active;
alter table public.facility_drawings enable row level security;
create policy facility_drawings_read on public.facility_drawings for select to authenticated using (public.pilot_account_ready(auth.uid()));
revoke all on public.facility_drawings from public, anon, authenticated, service_role;
grant select on public.facility_drawings to authenticated;

create function public.facility_admin_actor() returns jsonb
language sql stable security definer set search_path = pg_catalog as $function$
  select a from (select public.work_order_actor() a) x where a->>'role' = 'administrator'
$function$;

create function public.admin_save_facility(p_facility_id uuid, p_code text, p_name text, p_address text, p_active boolean, p_seed_standard_areas boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor(); v_code text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_code,'')));
  v_name text := pg_catalog.btrim(coalesce(p_name,'')); before public.sites%rowtype; result public.sites%rowtype; seeded integer := 0;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Administrator may set up facilities.'); end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{1,19}$' then return public.work_order_result_error('VALIDATION_ERROR','Facility code: 2 to 20 letters, numbers or dashes.'); end if;
  if pg_catalog.length(v_name) not between 2 and 120 then return public.work_order_result_error('VALIDATION_ERROR','Enter the facility name (2 to 120 characters).'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason for the change.'); end if;
  if exists(select 1 from public.sites s where s.code = v_code and s.id is distinct from p_facility_id) then
    return public.work_order_result_error('VALIDATION_ERROR','Another facility already uses that code.'); end if;
  if p_facility_id is null then
    insert into public.sites(code, name, address, is_active) values (v_code, v_name, nullif(pg_catalog.btrim(coalesce(p_address,'')),''), true) returning * into result;
    if coalesce(p_seed_standard_areas, true) then
      insert into public.facility_areas(facility_id, area_code, name)
      select result.id, a.code, a.name from (values ('REC-01','Reception'),('OFF-01','Office'),('MTR-01','Meeting Room'),('PAN-01','Pantry'),('TLT-01','Toilet'),
        ('WHS-01','Warehouse'),('LDB-01','Loading / Unloading Bay'),('ELR-01','Electrical Room'),('TFR-01','Transformer Room'),('ITR-01','Server / IT Room'),
        ('AHR-01','AHU Room'),('GNR-01','Generator Room'),('PMR-01','Pump Room'),('FPR-01','Fire Pump Room'),('MWS-01','Maintenance Workshop'),('STR-01','Staircase'),
        ('LFT-01','Lift'),('LBY-01','Lift Lobby'),('COR-01','Corridor'),('ROF-01','Roof'),('CPK-01','Car Park'),('GDH-01','Guard House'),
        ('RHA-01','Rubbish Holding Area'),('LSZ-01','Landscape Zone'),('SYD-01','External / Service Yard')) a(code, name);
      get diagnostics seeded = row_count;
    end if;
  else
    select * into before from public.sites where id = p_facility_id for update;
    if before.id is null then return public.work_order_result_error('NOT_FOUND','Facility not found.'); end if;
    if not coalesce(p_active, true) and exists(select 1 from public.work_orders w where w.facility_id = before.id and w.status not in ('closed','cancelled')) then
      return public.work_order_result_error('VALIDATION_ERROR','Close or cancel this facility''s open Work Orders before switching it off.'); end if;
    update public.sites set code = v_code, name = v_name, address = nullif(pg_catalog.btrim(coalesce(p_address,'')),''), is_active = coalesce(p_active, true), updated_at = pg_catalog.now()
     where id = before.id returning * into result;
  end if;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, case when p_facility_id is null then 'facility_created' else 'facility_updated' end, actor->>'display_name',
    pg_catalog.jsonb_build_object('facility_id', result.id, 'previous', case when before.id is null then null else pg_catalog.to_jsonb(before) end,
      'next', pg_catalog.to_jsonb(result), 'standard_areas_added', seeded, 'reason', pg_catalog.btrim(p_reason))::text);
  return pg_catalog.jsonb_build_object('ok', true, 'facility', pg_catalog.to_jsonb(result), 'standard_areas_added', seeded);
end;$function$;

create function public.admin_add_facility_area(p_facility_id uuid, p_area_code text, p_name text, p_level text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor(); v_code text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_area_code,''))); result public.facility_areas%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Administrator may add facility areas.'); end if;
  if not exists(select 1 from public.sites s where s.id = p_facility_id and s.is_active) then return public.work_order_result_error('NOT_FOUND','Active facility not found.'); end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{1,19}$' then return public.work_order_result_error('VALIDATION_ERROR','Area code: 2 to 20 letters, numbers or dashes, e.g. ELR-02.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_name,''))) not between 2 and 120 then return public.work_order_result_error('VALIDATION_ERROR','Enter the area name.'); end if;
  if exists(select 1 from public.facility_areas a where a.facility_id = p_facility_id and a.area_code = v_code) then
    return public.work_order_result_error('VALIDATION_ERROR','This facility already has an area with that code.'); end if;
  insert into public.facility_areas(facility_id, area_code, name, level)
  values (p_facility_id, v_code, pg_catalog.btrim(p_name), nullif(pg_catalog.btrim(coalesce(p_level,'')),'')) returning * into result;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, 'facility_area_added', actor->>'display_name', pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'area', pg_catalog.to_jsonb(result))::text);
  return pg_catalog.jsonb_build_object('ok', true, 'area', pg_catalog.to_jsonb(result));
end;$function$;

create function public.admin_set_facility_membership(p_facility_id uuid, p_profile_id uuid, p_active boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor(); person public.profiles%rowtype; changed integer := 0;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Administrator may change facility staff.'); end if;
  if not exists(select 1 from public.sites s where s.id = p_facility_id) then return public.work_order_result_error('NOT_FOUND','Facility not found.'); end if;
  select * into person from public.profiles where id = p_profile_id;
  if person.id is null or person.deleted_at is not null then return public.work_order_result_error('NOT_FOUND','Person not found.'); end if;
  if person.role not in ('technician','approver','supervisor','facility_manager') then
    return public.work_order_result_error('VALIDATION_ERROR','Only Technicians, Approvers, Supervisors and Facility Managers belong to a facility; Administrators and Finance see all facilities.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason for the change.'); end if;
  if coalesce(p_active, true) then
    if not exists(select 1 from public.sites s where s.id = p_facility_id and s.is_active) then return public.work_order_result_error('VALIDATION_ERROR','The facility is switched off.'); end if;
    if exists(select 1 from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = person.id and m.membership_role = person.role and m.active) then
      return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE'); end if;
    insert into public.facility_memberships(facility_id, profile_id, membership_role, created_by) values (p_facility_id, person.id, person.role, (actor->>'id')::uuid);
    changed := 1;
  else
    update public.facility_memberships set active = false, effective_to = greatest(pg_catalog.now(), effective_from + interval '1 millisecond'), updated_at = pg_catalog.now()
     where facility_id = p_facility_id and profile_id = person.id and active;
    get diagnostics changed = row_count;
    if changed = 0 then return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE'); end if;
  end if;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, case when coalesce(p_active, true) then 'facility_staff_added' else 'facility_staff_removed' end, actor->>'display_name',
    pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'profile_id', person.id, 'display_name', person.display_name, 'role', person.role, 'reason', pg_catalog.btrim(p_reason))::text);
  return pg_catalog.jsonb_build_object('ok', true, 'changed', changed);
end;$function$;

create function public.admin_facility_staff(p_facility_id uuid)
returns table(profile_id uuid, display_name text, email text, role text, member boolean, member_since timestamptz)
language sql stable security definer set search_path = pg_catalog as $function$
  select p.id, p.display_name, p.email, p.role,
    exists(select 1 from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = p.id and m.membership_role = p.role and m.active),
    (select pg_catalog.min(m.effective_from) from public.facility_memberships m where m.facility_id = p_facility_id and m.profile_id = p.id and m.active)
  from public.profiles p
  where public.facility_admin_actor() is not null and p.is_active and p.deleted_at is null
    and p.role in ('technician','approver','supervisor','facility_manager')
  order by case p.role when 'technician' then 1 when 'approver' then 2 when 'supervisor' then 3 else 4 end, p.display_name
$function$;

create function public.admin_register_facility_drawing(p_facility_id uuid, p_code text, p_title text, p_revision text, p_original_filename text,
  p_content_type text, p_byte_size bigint, p_width integer, p_height integer, p_storage_path text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor(); v_code text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_code,''))); result public.facility_drawings%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Administrator may add facility drawings.'); end if;
  if not exists(select 1 from public.sites s where s.id = p_facility_id and s.is_active) then return public.work_order_result_error('NOT_FOUND','Active facility not found.'); end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{0,23}$' then return public.work_order_result_error('VALIDATION_ERROR','Drawing number: letters, numbers and dashes, e.g. ABC-001.'); end if;
  if v_code in ('FW-001','FW-002','FW-003','FW-004','FW-005') then return public.work_order_result_error('VALIDATION_ERROR','FW-001 to FW-005 are the mock-up drawings; choose another drawing number.'); end if;
  if exists(select 1 from public.facility_drawings d where d.facility_id = p_facility_id and d.code = v_code and d.active) then
    return public.work_order_result_error('VALIDATION_ERROR','This facility already has an active drawing with that number; remove it first to replace it.'); end if;
  if p_storage_path is null or p_storage_path not like 'drawings/facility/'||p_facility_id::text||'/%'
     or not exists(select 1 from storage.objects o where o.bucket_id = 'field-evidence' and o.name = p_storage_path) then
    return public.work_order_result_error('INVALID_STORAGE_OBJECT','The uploaded drawing file could not be verified.'); end if;
  insert into public.facility_drawings(facility_id, code, title, revision, original_filename, content_type, byte_size, width, height, storage_path, uploaded_by)
  values (p_facility_id, v_code, pg_catalog.btrim(p_title), nullif(pg_catalog.btrim(coalesce(p_revision,'')),''), p_original_filename, p_content_type, p_byte_size,
    case when p_content_type = 'application/pdf' then null else p_width end, case when p_content_type = 'application/pdf' then null else p_height end,
    p_storage_path, (actor->>'id')::uuid) returning * into result;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, 'facility_drawing_added', actor->>'display_name',
    pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'drawing_id', result.id, 'code', result.code, 'title', result.title, 'revision', result.revision, 'filename', result.original_filename)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'drawing', pg_catalog.to_jsonb(result));
exception when check_violation or unique_violation then
  return public.work_order_result_error('VALIDATION_ERROR','Drawing details are invalid (title 2–200 characters; PNG, JPG, WebP or PDF up to 50 MB).');
end;$function$;

create function public.admin_remove_facility_drawing(p_drawing_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.facility_admin_actor(); result public.facility_drawings%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','Only the Administrator may remove facility drawings.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason for removing the drawing.'); end if;
  update public.facility_drawings set active = false, removed_by = (actor->>'id')::uuid, removed_at = pg_catalog.now(), removal_reason = pg_catalog.btrim(p_reason)
   where id = p_drawing_id and active returning * into result;
  if result.id is null then return public.work_order_result_error('NOT_FOUND','Active drawing not found.'); end if;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, 'facility_drawing_removed', actor->>'display_name',
    pg_catalog.jsonb_build_object('facility_id', result.facility_id, 'drawing_id', result.id, 'code', result.code, 'reason', result.removal_reason)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'drawing', pg_catalog.to_jsonb(result));
end;$function$;

revoke all on function public.facility_admin_actor() from public, anon, authenticated, service_role;
revoke all on function public.admin_save_facility(uuid,text,text,text,boolean,boolean,text), public.admin_add_facility_area(uuid,text,text,text),
  public.admin_set_facility_membership(uuid,uuid,boolean,text), public.admin_facility_staff(uuid),
  public.admin_register_facility_drawing(uuid,text,text,text,text,text,bigint,integer,integer,text), public.admin_remove_facility_drawing(uuid,text)
  from public, anon, service_role;
grant execute on function public.admin_save_facility(uuid,text,text,text,boolean,boolean,text), public.admin_add_facility_area(uuid,text,text,text),
  public.admin_set_facility_membership(uuid,uuid,boolean,text), public.admin_facility_staff(uuid),
  public.admin_register_facility_drawing(uuid,text,text,text,text,text,bigint,integer,integer,text), public.admin_remove_facility_drawing(uuid,text)
  to authenticated;

do $postcheck$
begin
  if has_function_privilege('authenticated','public.facility_admin_actor()','EXECUTE') then raise exception 'FAC-01 helper exposed'; end if;
  if has_table_privilege('authenticated','public.facility_drawings','INSERT') or has_table_privilege('authenticated','public.facility_drawings','UPDATE') then
    raise exception 'FAC-01 direct drawing writes granted'; end if;
  if not exists(select 1 from pg_catalog.pg_constraint where conname = 'facility_areas_facility_code_key') then raise exception 'FAC-01 area code key missing'; end if;
end;$postcheck$;
commit;

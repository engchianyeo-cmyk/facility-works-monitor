begin;
-- D-44 (9 Nov 2026): on the Facility drawings page the PDF is the master copy that staff view and download.
-- When a PDF is uploaded, the Administrator's browser also makes an image of its first page (the "pin image"),
-- stored beside it, so Technicians can pin and mark up Work Orders on PDF drawings too.
-- Uploading a new revision with the same drawing number supersedes the current one, which moves to Earlier revisions.

alter table public.facility_drawings
  add column if not exists pin_image_path text,
  add column if not exists pin_width integer,
  add column if not exists pin_height integer,
  add column if not exists superseded_by uuid references public.facility_drawings(id) on delete restrict,
  add column if not exists superseded_at timestamptz;

do $constraints$
begin
  if not exists (select 1 from pg_constraint where conname = 'facility_drawings_pin_image_check') then
    alter table public.facility_drawings add constraint facility_drawings_pin_image_check check (
      (pin_image_path is null and pin_width is null and pin_height is null)
      or (content_type = 'application/pdf' and pin_image_path is not null
          and pin_width between 1 and 20000 and pin_height between 1 and 20000));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'facility_drawings_pin_image_path_key') then
    alter table public.facility_drawings add constraint facility_drawings_pin_image_path_key unique (pin_image_path);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'facility_drawings_superseded_check') then
    alter table public.facility_drawings add constraint facility_drawings_superseded_check check (
      (superseded_by is null and superseded_at is null) or (superseded_at is not null and not active));
  end if;
end;
$constraints$;

create or replace function public.admin_register_facility_drawing_revision(p_facility_id uuid, p_code text, p_title text, p_revision text,
  p_original_filename text, p_content_type text, p_byte_size bigint, p_width integer, p_height integer, p_storage_path text,
  p_pin_image_path text, p_pin_width integer, p_pin_height integer)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare
  actor jsonb := public.facility_admin_actor();
  v_code text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_code, '')));
  v_revision text := nullif(pg_catalog.btrim(coalesce(p_revision, '')), '');
  v_pdf boolean := p_content_type = 'application/pdf';
  previous public.facility_drawings%rowtype;
  result public.facility_drawings%rowtype;
  prefix text := 'drawings/facility/' || p_facility_id::text || '/';
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'Only the Administrator may add facility drawings.'); end if;
  if not exists (select 1 from public.sites s where s.id = p_facility_id and s.is_active) then
    return public.work_order_result_error('NOT_FOUND', 'Active facility not found.'); end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9-]{0,23}$' then
    return public.work_order_result_error('VALIDATION_ERROR', 'Drawing number: letters, numbers and dashes, e.g. ABC-001.'); end if;
  if v_code in ('FW-001', 'FW-002', 'FW-003', 'FW-004', 'FW-005') then
    return public.work_order_result_error('VALIDATION_ERROR', 'FW-001 to FW-005 are the mock-up drawings; choose another drawing number.'); end if;
  if p_storage_path is null or p_storage_path not like prefix || '%'
     or not exists (select 1 from storage.objects o where o.bucket_id = 'field-evidence' and o.name = p_storage_path) then
    return public.work_order_result_error('INVALID_STORAGE_OBJECT', 'The uploaded drawing file could not be verified.'); end if;
  if p_pin_image_path is not null and (not v_pdf or p_pin_image_path not like prefix || '%'
     or not exists (select 1 from storage.objects o where o.bucket_id = 'field-evidence' and o.name = p_pin_image_path)) then
    return public.work_order_result_error('INVALID_STORAGE_OBJECT', 'The pin image made from the PDF could not be verified.'); end if;

  select * into previous from public.facility_drawings d
   where d.facility_id = p_facility_id and d.code = v_code and d.active for update;
  if previous.id is not null then
    if pg_catalog.lower(coalesce(previous.revision, '')) = pg_catalog.lower(coalesce(v_revision, '')) then
      return public.work_order_result_error('VALIDATION_ERROR', pg_catalog.format(
        '%s %s is already the current revision. Enter the new revision (e.g. Rev B) to replace it.', v_code, coalesce(previous.revision, '(no revision)')));
    end if;
    update public.facility_drawings
       set active = false, removed_by = (actor ->> 'id')::uuid, removed_at = pg_catalog.now(), superseded_at = pg_catalog.now(),
           removal_reason = pg_catalog.format('Superseded by %s', coalesce(v_revision, 'a new upload'))
     where id = previous.id;
  end if;

  insert into public.facility_drawings(facility_id, code, title, revision, original_filename, content_type, byte_size, width, height,
    storage_path, uploaded_by, pin_image_path, pin_width, pin_height)
  values (p_facility_id, v_code, pg_catalog.btrim(p_title), v_revision, p_original_filename, p_content_type, p_byte_size,
    case when v_pdf then null else p_width end, case when v_pdf then null else p_height end, p_storage_path, (actor ->> 'id')::uuid,
    case when v_pdf then p_pin_image_path end, case when v_pdf and p_pin_image_path is not null then p_pin_width end,
    case when v_pdf and p_pin_image_path is not null then p_pin_height end)
  returning * into result;
  if previous.id is not null then update public.facility_drawings set superseded_by = result.id where id = previous.id; end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor ->> 'id')::uuid, case when previous.id is null then 'facility_drawing_added' else 'facility_drawing_revised' end, actor ->> 'display_name',
    pg_catalog.jsonb_build_object('facility_id', p_facility_id, 'drawing_id', result.id, 'code', result.code, 'title', result.title,
      'revision', result.revision, 'filename', result.original_filename, 'pin_image', result.pin_image_path is not null,
      'superseded_drawing_id', previous.id, 'superseded_revision', previous.revision)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'drawing', pg_catalog.to_jsonb(result), 'superseded_revision', previous.revision,
    'superseded', previous.id is not null);
exception when check_violation or unique_violation then
  return public.work_order_result_error('VALIDATION_ERROR', 'Drawing details are invalid (title 2–200 characters; PNG, JPG, WebP or PDF up to 50 MB).');
end;
$function$;

revoke all on function public.admin_register_facility_drawing_revision(uuid,text,text,text,text,text,bigint,integer,integer,text,text,integer,integer)
  from public, anon, service_role;
grant execute on function public.admin_register_facility_drawing_revision(uuid,text,text,text,text,text,bigint,integer,integer,text,text,integer,integer)
  to authenticated;
commit;

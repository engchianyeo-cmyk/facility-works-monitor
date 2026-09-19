begin;

do $uat$
declare
  target_work_order public.work_orders%rowtype;
  loading_bay public.facility_areas%rowtype;
  yang uuid;
  replacement_markup_id constant uuid := '9f120000-0000-4000-8000-000000000012';
  target_x constant numeric(6,3) := 23.077;
  target_y constant numeric(6,3) := 37.390;
begin
  select * into target_work_order
  from public.work_orders
  where work_order_number = 'WO-TEST-012';

  select * into loading_bay
  from public.facility_areas
  where facility_id = target_work_order.facility_id
    and area_code = 'LDB-01';

  select id into yang
  from public.profiles
  where email = 'koi.kpr@gmail.com'
    and role = 'technician'
    and is_active
    and deleted_at is null;

  if target_work_order.id is null or loading_bay.id is null or yang is null then
    raise exception 'WO-TEST-012 RS-01 loading-dock alignment prerequisite missing';
  end if;

  update public.facility_areas
  set drawing_reference = 'FW-001', map_x = target_x, map_y = target_y
  where id = loading_bay.id;

  update public.work_order_markups
  set deleted_at = pg_catalog.now(), deleted_by = yang
  where work_order_id = target_work_order.id
    and source_type = 'drawing'
    and source_reference = 'FW-001'
    and deleted_at is null
    and (
      note ilike 'RS-01%'
      or (x_percent between 24 and 38 and y_percent between 45 and 65)
    );

  insert into public.work_order_markups(
    id, work_order_id, source_type, source_reference, drawing_revision,
    page_number, x_percent, y_percent, annotation_type, geometry, note,
    created_by, created_at
  ) values (
    replacement_markup_id, target_work_order.id, 'drawing', 'FW-001', 'A (25 May 2024)',
    null, target_x, target_y, 'marker',
    pg_catalog.jsonb_build_object(
      'points', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('x', target_x, 'y', target_y)),
      'source_pixel', pg_catalog.jsonb_build_object('x', 246, 'y', 255),
      'source_dimensions', pg_catalog.jsonb_build_object('width', 1066, 'height', 682),
      'landmark', 'Main Building loading dock roller-shutter opening immediately behind truck'
    ),
    'RS-01 Main Building loading dock roller-shutter opening', yang, pg_catalog.now()
  )
  on conflict (id) do update
  set x_percent = excluded.x_percent,
      y_percent = excluded.y_percent,
      geometry = excluded.geometry,
      note = excluded.note,
      deleted_at = null,
      deleted_by = null;

  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values (
    yang,
    target_work_order.id,
    'uat_rs01_main_building_loading_dock_aligned',
    target_work_order.status,
    target_work_order.status,
    'Preview UAT remediation',
    pg_catalog.jsonb_build_object(
      'facility_area_id', loading_bay.id,
      'drawing_reference', 'FW-001',
      'source_pixel', pg_catalog.jsonb_build_object('x', 246, 'y', 255),
      'source_dimensions', pg_catalog.jsonb_build_object('width', 1066, 'height', 682),
      'map_x', target_x,
      'map_y', target_y,
      'landmark', 'Main Building loading dock roller-shutter opening immediately behind truck',
      'excluded_landmark', 'visitor and accessibility parking canopy'
    )::text
  );
end;
$uat$;

commit;

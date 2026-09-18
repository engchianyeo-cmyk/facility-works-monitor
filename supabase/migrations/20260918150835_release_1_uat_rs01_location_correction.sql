begin;

do $uat$
declare
  target_work_order public.work_orders%rowtype;
  loading_bay public.facility_areas%rowtype;
  yang uuid;
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
    raise exception 'WO-TEST-012 RS-01 location correction prerequisite missing';
  end if;

  update public.facility_areas
  set drawing_reference = 'FW-001', map_x = 31, map_y = 48
  where id = loading_bay.id;

  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values (
    yang,
    target_work_order.id,
    'uat_rs01_drawing_location_corrected',
    target_work_order.status,
    target_work_order.status,
    'Preview UAT remediation',
    pg_catalog.jsonb_build_object(
      'facility_area_id', loading_bay.id,
      'drawing_reference', 'FW-001',
      'map_x', 31,
      'map_y', 48,
      'reason', 'Align RS-01 marker to the Loading Bay dock on FW-001'
    )::text
  );
end;
$uat$;

commit;

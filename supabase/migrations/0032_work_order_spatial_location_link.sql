-- Link the controlled damaged-socket UAT Work Order to the governed facility area.
--
-- This migration is intentionally narrow and idempotent. It enriches the existing
-- PAN-01 seed record only when its current values are compatible with the governed
-- Level 2 pantry definition. It does not invent drawing coordinates: map_x/map_y
-- remain unchanged until the plan is explicitly calibrated.

begin;

do $link$
declare
  target_work_order_id constant uuid := '08000000-0000-4000-8000-000000000013';
  target_asset_id constant uuid := '08000000-0000-4000-8000-000000000313';
  target_area_id uuid;
  existing_area_id uuid;
  actor_id uuid;
  current_area_name text;
  current_level text;
  current_drawing_reference text;
begin
  if current_user <> 'postgres' then
    raise exception '0032 must be applied as postgres';
  end if;

  if to_regclass('public.facility_areas') is null then
    raise exception '0032 refused: facility_areas is missing';
  end if;

  select id, name, level, drawing_reference
  into target_area_id, current_area_name, current_level, current_drawing_reference
  from public.facility_areas
  where area_code = 'PAN-01'
    and active = true
  for update;

  if target_area_id is null then
    raise exception '0032 refused: active PAN-01 facility area is missing';
  end if;

  if current_area_name not in ('Pantry', 'Pantry / Break Area') then
    raise exception '0032 refused: PAN-01 has unexpected name %', current_area_name;
  end if;

  if current_level is not null and current_level <> '2' then
    raise exception '0032 refused: PAN-01 has unexpected level %', current_level;
  end if;

  if current_drawing_reference is not null and current_drawing_reference <> 'FW-002' then
    raise exception '0032 refused: PAN-01 has unexpected drawing reference %', current_drawing_reference;
  end if;

  update public.facility_areas
  set name = 'Pantry / Break Area',
      level = '2',
      drawing_reference = 'FW-002'
  where id = target_area_id
    and (
      name is distinct from 'Pantry / Break Area'
      or level is distinct from '2'
      or drawing_reference is distinct from 'FW-002'
    );

  select facility_area_id
  into existing_area_id
  from public.work_orders
  where id = target_work_order_id
    and work_order_number = 'WO-TEST-013'
    and title = 'Damaged Socket SOCKET-L2-P-04'
    and asset_id = target_asset_id
    and location = 'Level 2 Pantry'
  for update;

  if not found then
    raise exception '0032 refused: controlled WO-TEST-013 identity does not match';
  end if;

  if existing_area_id is not null and existing_area_id <> target_area_id then
    raise exception '0032 refused: WO-TEST-013 is already linked to a different facility area';
  end if;

  if existing_area_id is null then
    update public.work_orders
    set facility_area_id = target_area_id,
        updated_at = pg_catalog.now()
    where id = target_work_order_id;

    select id
    into actor_id
    from public.profiles
    where role = 'administrator'
      and is_active = true
      and deleted_at is null
    order by created_at, id
    limit 1;

    insert into public.activity_logs(user_id, work_order_id, action, actor, note)
    values (
      actor_id,
      target_work_order_id,
      'work_order_location_area_linked',
      'Spatial UAT reconciliation',
      pg_catalog.jsonb_build_object(
        'migration', '0032_work_order_spatial_location_link',
        'work_order_number', 'WO-TEST-013',
        'asset_tag', 'SOCKET-L2-P-04',
        'facility_area_code', 'PAN-01',
        'facility_area_name', 'Pantry / Break Area',
        'level', '2',
        'drawing_reference', 'FW-002',
        'coordinates_calibrated', false
      )::text
    );
  end if;
end;
$link$;

commit;
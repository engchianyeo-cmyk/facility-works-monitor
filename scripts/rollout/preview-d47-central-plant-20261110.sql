-- D-47 (owner, 10 Nov 2026): the UAT facility has a Central Plant Block that joins the Main Building and the
-- Utility Block and closes the opening between them, with an AHU Room and a Chiller Plant Room (drawing FW-006). This replaces D-11's
-- "split air-conditioning, not chillers": the facility now has a chilled-water plant as well; the split-AC
-- units already in the data stay as they are.
--
-- What it changes in the Preview UAT data (pvajuywwwpjlikqjnvgv only):
--   * Areas: AHR-01 AHU Room and CPR-01 Chiller Plant Room (added if missing), level "1st Storey",
--     zone "Central Plant Block", pinned on FW-006 at the middle of each room (the Administrator can move them).
--   * Assets: 9 new synthetic assets (CH-01, CH-02, CHWP-01, CHWP-02, CWP-01, CWP-02, CT-01, CT-02, AHU-01);
--     AHU-02 moves from "Level 2 AHU Room" to the new AHU Room.
--   * WO-TEST-002 (Quarterly PM AHU-02): location follows AHU-02 to the AHU Room (only while it is open).
--   * FW-001 Rev B (owner, 14:53 and 14:59: one building, Utility Block to scale and enlarged): 1st storey and site
--     areas are pinned on the new FW-001; 7 new Utility Block areas (WTR-01, SPT-01, FCC-01, SUB-01, ESR-01, PVR-01,
--     BTR-01) are added. An area already pinned on FW-002, FW-003, FW-006 or an uploaded drawing keeps its pin.
--     Any other area still pinned on the old FW-001, FW-004 (elevations, redrawn) or FW-005 loses that pin, for the Administrator to place again,
--     unless someone placed it on or after 10 Nov 2026.
--   * D-48: the car park solar PV canopy becomes area SPV-01, pinned on FW-007 (maintenance access drawing).
--   * TR-01 moves from "Transformer Yard" to "Transformer Room", INV-PV-02 from "Solar Inverter Room" to
--     "Solar PV Rectifier Room" (both now inside the Utility Block); their open Work Orders follow.
-- Every change is written to the activity log.
--
-- Dry run (default — shows the changes, then rolls back):
--   psql -X -c "set role postgres" -f this file
-- Apply:
--   psql -X -v apply=yes -c "set role postgres" -f this file
--
-- Safe to run again: anything already done is skipped. If a row is not what is expected, nothing changes.
\set ON_ERROR_STOP on
begin;
create temp table d47_changes(kind text, item text, field text, before text, after text);
do $d47$
declare
  admin uuid; fac uuid; fac_dept uuid; ahu2 record; r record; a record; area_id uuid; n int;
  areas constant jsonb := '[
    {"code":"AHR-01","name":"AHU Room","x":20.41,"y":35.458,"description":"Central Plant Block: air handling units AHU-01 and AHU-02 (FW-006)."},
    {"code":"CPR-01","name":"Chiller Plant Room","x":20.41,"y":69.987,"description":"Central Plant Block: chillers, chilled and condenser water pumps; cooling towers on the roof above (FW-006)."}
  ]';
  new_assets constant jsonb := '[
    {"tag":"CH-01","name":"Water-Cooled Chiller No. 1","type":"Chiller","criticality":"critical","room":"Chiller Plant Room"},
    {"tag":"CH-02","name":"Water-Cooled Chiller No. 2","type":"Chiller","criticality":"critical","room":"Chiller Plant Room"},
    {"tag":"CHWP-01","name":"Chilled Water Pump No. 1","type":"Pump","criticality":"high","room":"Chiller Plant Room"},
    {"tag":"CHWP-02","name":"Chilled Water Pump No. 2","type":"Pump","criticality":"high","room":"Chiller Plant Room"},
    {"tag":"CWP-01","name":"Condenser Water Pump No. 1","type":"Pump","criticality":"high","room":"Chiller Plant Room"},
    {"tag":"CWP-02","name":"Condenser Water Pump No. 2","type":"Pump","criticality":"high","room":"Chiller Plant Room"},
    {"tag":"CT-01","name":"Cooling Tower No. 1","type":"Cooling tower","criticality":"high","room":"Roof (above Chiller Plant Room)"},
    {"tag":"CT-02","name":"Cooling Tower No. 2","type":"Cooling tower","criticality":"high","room":"Roof (above Chiller Plant Room)"},
    {"tag":"AHU-01","name":"Air Handling Unit No. 1","type":"Air handling unit","criticality":"medium","room":"AHU Room"}
  ]';
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  select id into admin from public.profiles
    where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;
  if admin is null then raise exception 'No active Administrator to record the changes against; nothing changed'; end if;
  select * into ahu2 from public.assets where lower(asset_tag) = 'ahu-02' for update;
  if ahu2.id is null then raise exception 'Asset AHU-02 not found, so the UAT facility cannot be identified; nothing changed'; end if;
  fac := ahu2.facility_id;
  select id into fac_dept from public.departments where code = 'FAC' and is_active and deleted_at is null order by created_at limit 1;

  -- Areas, pinned on FW-006
  for a in select * from pg_catalog.jsonb_to_recordset(areas) as x(code text, name text, x numeric, y numeric, description text) loop
    select * into r from public.facility_areas where facility_id = fac and area_code = a.code for update;
    if r.id is null then
      insert into public.facility_areas(facility_id, area_code, name, level, zone, description, drawing_reference, map_x, map_y, active)
      values (fac, a.code, a.name, '1st Storey', 'Central Plant Block', a.description, 'FW-006', a.x, a.y, true) returning id into area_id;
      insert into d47_changes values ('area', a.code, 'added', '', a.code||' · '||a.name||' · FW-006 ('||a.x||', '||a.y||')');
    else
      area_id := r.id;
      if r.name is distinct from a.name then raise exception 'Area % is now named "%", not "%"; nothing changed', a.code, r.name, a.name; end if;
      if r.drawing_reference is not distinct from 'FW-006' and r.zone is not distinct from 'Central Plant Block' and r.active then continue; end if; -- already done
      update public.facility_areas set level = '1st Storey', zone = 'Central Plant Block', description = coalesce(description, a.description),
          drawing_reference = 'FW-006', map_x = a.x, map_y = a.y, active = true
        where id = r.id;
      insert into d47_changes values ('area', a.code, 'zone / pin',
        coalesce(r.zone, '(no zone)')||' · '||coalesce(r.drawing_reference, 'no pin')||coalesce(' ('||r.map_x||', '||r.map_y||')', '')||case when r.active then '' else ' · inactive' end,
        'Central Plant Block · FW-006 ('||a.x||', '||a.y||')');
    end if;
    insert into public.activity_logs(user_id, action, actor, note)
    values (admin, 'facility_area_drawing_location_updated', 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('facility_id', fac, 'facility_area_id', area_id, 'facility_area', a.code||' · '||a.name,
        'previous', pg_catalog.jsonb_build_object('drawing_reference', r.drawing_reference, 'map_x', r.map_x, 'map_y', r.map_y),
        'next', pg_catalog.jsonb_build_object('drawing_reference', 'FW-006', 'map_x', a.x, 'map_y', a.y),
        'reason', 'D-47: Central Plant Block added (FW-006)', 'actor_id', admin, 'timestamp', pg_catalog.now())::text);
  end loop;

  -- New assets
  for a in select * from pg_catalog.jsonb_to_recordset(new_assets) as x(tag text, name text, type text, criticality text, room text) loop
    select * into r from public.assets where lower(asset_tag) = lower(a.tag);
    if r.id is not null then
      if r.name = a.name then continue; end if; -- already added
      raise exception 'Asset tag % already exists as "%"; nothing changed', a.tag, r.name;
    end if;
    insert into public.assets(asset_tag, name, asset_type, criticality, lifecycle_status, site, location, building, floor_zone, room,
        description, department_id, facility_id, created_by, updated_by)
    values (a.tag, a.name, a.type, a.criticality, 'active', 'Central Plant Block', a.room, 'Central Plant Block', '1st Storey', a.room,
        'Synthetic UAT asset: central chilled-water plant (D-47, drawing FW-006).', fac_dept, fac, admin, admin)
    returning * into r;
    insert into public.activity_logs(user_id, asset_id, action, actor, note)
    values (admin, r.id, 'asset_created', 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('asset_tag', r.asset_tag, 'name', r.name, 'asset_type', r.asset_type, 'site', r.site, 'location', r.location,
        'reason', 'D-47: Central Plant Block added (FW-006)')::text);
    insert into d47_changes values ('asset', a.tag, 'added', '', a.name||' · '||a.room);
  end loop;

  -- AHU-02 moves to the new AHU Room
  if ahu2.location is distinct from 'AHU Room' or ahu2.site is distinct from 'Central Plant Block' then
    update public.assets set site = 'Central Plant Block', location = 'AHU Room', building = 'Central Plant Block', floor_zone = '1st Storey',
        room = 'AHU Room', updated_by = admin, updated_at = pg_catalog.now()
      where id = ahu2.id;
    insert into public.activity_logs(user_id, asset_id, action, actor, note)
    values (admin, ahu2.id, 'asset_location_changed', 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('before', pg_catalog.jsonb_build_object('site', ahu2.site, 'location', ahu2.location),
        'after', pg_catalog.jsonb_build_object('site', 'Central Plant Block', 'location', 'AHU Room'),
        'reason', 'D-47: AHU-02 is in the Central Plant Block AHU Room (FW-006)')::text);
    insert into d47_changes values ('asset', 'AHU-02', 'site / location', ahu2.site||' · '||ahu2.location, 'Central Plant Block · AHU Room');
  end if;

  -- WO-TEST-002 follows AHU-02 while it is open
  select id into area_id from public.facility_areas where facility_id = fac and area_code = 'AHR-01';
  for r in select * from public.work_orders where work_order_number = 'WO-TEST-002' for update loop
    if r.status in ('completed', 'reviewed', 'closed', 'cancelled') then
      insert into d47_changes values ('work order', 'WO-TEST-002', 'kept (status '||r.status||')', r.location, r.location); continue;
    end if;
    if r.location = 'AHU Room' and r.facility_area_id is not distinct from area_id then continue; end if;
    update public.work_orders set location = 'AHU Room', site = 'Central Plant Block', facility_area_id = coalesce(facility_area_id, area_id),
        updated_at = pg_catalog.now()
      where id = r.id;
    insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
    values (admin, r.id, 'work_order_uat_data_corrected', r.status, r.status, 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('reason', 'D-47: AHU-02 is in the Central Plant Block AHU Room (FW-006)',
        'previous_location', r.location, 'location', 'AHU Room', 'previous_site', r.site, 'site', 'Central Plant Block', 'date', '2026-11-10')::text);
    insert into d47_changes values ('work order', 'WO-TEST-002', 'location', coalesce(r.site, '')||' · '||coalesce(r.location, ''), 'Central Plant Block · AHU Room');
  end loop;

  select pg_catalog.count(*) into n from d47_changes;
  raise notice 'D-47 Central Plant Block: % changes prepared', n;
end;
$d47$;
-- FW-001 Rev B: re-pin the 1st storey and site areas, add the new Utility Block rooms, move two assets indoors
do $d47b$
declare
  admin uuid; fac uuid; r record; a record; area_id uuid; n int;
  pins constant jsonb := '[
    {"code":"BTR-01","name":"Battery Room","zone":"Utility Block","level":"1st Storey","x":54.395,"y":90.296},
    {"code":"CPK-01","name":"Car Park","zone":"Site","level":"Site (external)","x":35.645,"y":53.571},
    {"code":"ELR-01","name":"Electrical Room","zone":"Main Building","level":"1st Storey","x":32.715,"y":81.402},
    {"code":"ESR-01","name":"Electrical Switch Room","zone":"Utility Block","level":"1st Storey","x":47.363,"y":90.296},
    {"code":"FCC-01","name":"Fire Control Centre","zone":"Utility Block","level":"1st Storey","x":56.738,"y":82.21},
    {"code":"FPR-01","name":"Fire Pump Room","zone":"Utility Block","level":"1st Storey","x":46.191,"y":79.784},
    {"code":"GDH-01","name":"Guard House","zone":"Site","level":"Site (external)","x":11.475,"y":52.224},
    {"code":"GNR-01","name":"Generator Room","zone":"Utility Block","level":"1st Storey","x":49.707,"y":90.296},
    {"code":"LBY-01","name":"Lift Lobby","zone":"Main Building","level":"1st Storey","x":22.754,"y":92.318},
    {"code":"LDB-01","name":"Loading / Unloading Bay","zone":"Main Building","level":"1st Storey","x":15.723,"y":93.693},
    {"code":"LFT-01","name":"Lift","zone":"Main Building","level":"1st Storey","x":22.754,"y":88.194},
    {"code":"LSZ-01","name":"Landscape Zone","zone":"Site","level":"Site (external)","x":32.715,"y":12.129},
    {"code":"MWS-01","name":"Maintenance Workshop","zone":"Utility Block","level":"1st Storey","x":41.504,"y":79.784},
    {"code":"PVR-01","name":"Solar PV Rectifier Room","zone":"Utility Block","level":"1st Storey","x":52.051,"y":90.296},
    {"code":"REC-01","name":"Reception","zone":"Main Building","level":"1st Storey","x":22.754,"y":93.531},
    {"code":"RHA-01","name":"Rubbish Holding Area","zone":"Site","level":"Site (external)","x":62.5,"y":55.93},
    {"code":"SPT-01","name":"Sprinkler Tank Room","zone":"Utility Block","level":"1st Storey","x":55.566,"y":77.358},
    {"code":"STR-01","name":"Staircase","zone":"Main Building","level":"1st Storey","x":20.41,"y":91.914},
    {"code":"SUB-01","name":"Substation","zone":"Utility Block","level":"1st Storey","x":40.918,"y":90.296},
    {"code":"SYD-01","name":"External / Service Yard","zone":"Site","level":"Site (external)","x":58.105,"y":28.976},
    {"code":"TFR-01","name":"Transformer Room","zone":"Utility Block","level":"1st Storey","x":44.434,"y":90.296},
    {"code":"TLT-01","name":"Toilet","zone":"Main Building","level":"1st Storey","x":32.715,"y":88.275},
    {"code":"WHS-01","name":"Warehouse","zone":"Main Building","level":"1st Storey","x":13.379,"y":81.402},
    {"code":"WTR-01","name":"Water Tank Room","zone":"Utility Block","level":"1st Storey","x":50.879,"y":79.784}
  ]';
  canopy constant jsonb := '{"code":"SPV-01","name":"Solar PV Canopy (Car Park)","x":39.551,"y":25.606}';
  moves constant jsonb := '[
    {"tag":"TR-01","old":"Transformer Yard","new":"Transformer Room"},
    {"tag":"INV-PV-02","old":"Solar Inverter Room","new":"Solar PV Rectifier Room"}
  ]';
begin
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;
  select facility_id into fac from public.assets where lower(asset_tag) = 'ahu-02';
  for a in select * from pg_catalog.jsonb_to_recordset(pins) as x(code text, name text, zone text, level text, x numeric, y numeric) loop
    select * into r from public.facility_areas where facility_id = fac and area_code = a.code for update;
    if r.id is null then
      insert into public.facility_areas(facility_id, area_code, name, level, zone, description, drawing_reference, map_x, map_y, active)
      values (fac, a.code, a.name, a.level, a.zone, 'Added for FW-001 Rev B (D-47, one building).', 'FW-001', a.x, a.y, true) returning id into area_id;
      insert into d47_changes values ('area', a.code, 'added (FW-001 Rev B)', '', a.name||' · '||a.zone||' · FW-001 ('||a.x||', '||a.y||')');
    else
      area_id := r.id;
      if r.drawing_reference is not null and r.drawing_reference not in ('FW-001', 'FW-004', 'FW-005') then
        insert into d47_changes values ('area', a.code, 'pin kept', r.drawing_reference||' ('||r.map_x||', '||r.map_y||')', 'unchanged');
        continue;
      end if;
      if r.drawing_reference = 'FW-001' and r.map_x = a.x and r.map_y = a.y then continue; end if; -- already done
      update public.facility_areas set drawing_reference = 'FW-001', map_x = a.x, map_y = a.y where id = r.id;
      insert into d47_changes values ('area', a.code, 'pin (FW-001 Rev B)',
        coalesce(r.drawing_reference, 'no pin')||coalesce(' ('||r.map_x||', '||r.map_y||')', ''), 'FW-001 ('||a.x||', '||a.y||')');
    end if;
    insert into public.activity_logs(user_id, action, actor, note)
    values (admin, 'facility_area_drawing_location_updated', 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('facility_id', fac, 'facility_area_id', area_id, 'facility_area', a.code||' · '||a.name,
        'previous', pg_catalog.jsonb_build_object('drawing_reference', r.drawing_reference, 'map_x', r.map_x, 'map_y', r.map_y),
        'next', pg_catalog.jsonb_build_object('drawing_reference', 'FW-001', 'map_x', a.x, 'map_y', a.y),
        'reason', 'D-47: FW-001 Rev B, one building drawn to scale', 'actor_id', admin, 'timestamp', pg_catalog.now())::text);
  end loop;

  -- D-48: the car park solar PV canopy as an area, pinned on FW-007 (maintenance access drawing)
  select * into r from public.facility_areas where facility_id = fac and area_code = canopy->>'code' for update;
  if r.id is null then
    insert into public.facility_areas(facility_id, area_code, name, level, zone, description, drawing_reference, map_x, map_y, active)
    values (fac, canopy->>'code', canopy->>'name', 'Canopy deck +3.90 m', 'Site',
      'D-48: walkways, guardrail, access stair, robot docks and water points for cleaning and maintenance (FW-007).',
      'FW-007', (canopy->>'x')::numeric, (canopy->>'y')::numeric, true) returning id into area_id;
    insert into public.activity_logs(user_id, action, actor, note)
    values (admin, 'facility_area_drawing_location_updated', 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('facility_id', fac, 'facility_area_id', area_id, 'facility_area', (canopy->>'code')||' · '||(canopy->>'name'),
        'previous', pg_catalog.jsonb_build_object('drawing_reference', null, 'map_x', null, 'map_y', null),
        'next', pg_catalog.jsonb_build_object('drawing_reference', 'FW-007', 'map_x', canopy->'x', 'map_y', canopy->'y'),
        'reason', 'D-48: car park solar PV canopy maintenance access', 'actor_id', admin, 'timestamp', pg_catalog.now())::text);
    insert into d47_changes values ('area', canopy->>'code', 'added (FW-007)', '', (canopy->>'name')||' · FW-007 ('||(canopy->>'x')||', '||(canopy->>'y')||')');
  end if;

  -- Areas still pinned on the old FW-001 / FW-005 that this script does not place: clear the pin for the Administrator
  for r in select f.* from public.facility_areas f
      where f.facility_id = fac and f.drawing_reference in ('FW-001', 'FW-004', 'FW-005')
        and f.area_code not in (select x.code from pg_catalog.jsonb_to_recordset(pins) as x(code text))
        and not exists (select 1 from public.activity_logs l where l.action = 'facility_area_drawing_location_updated'
                          and l.created_at >= '2026-11-10' and l.note like '%'||f.id::text||'%')
      for update of f loop
    update public.facility_areas set drawing_reference = null, map_x = null, map_y = null where id = r.id;
    insert into public.activity_logs(user_id, action, actor, note)
    values (admin, 'facility_area_drawing_location_updated', 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('facility_id', fac, 'facility_area_id', r.id, 'facility_area', r.area_code||' · '||r.name,
        'previous', pg_catalog.jsonb_build_object('drawing_reference', r.drawing_reference, 'map_x', r.map_x, 'map_y', r.map_y),
        'next', pg_catalog.jsonb_build_object('drawing_reference', null, 'map_x', null, 'map_y', null),
        'reason', 'D-47: FW-001 Rev B replaces the old sheet; the Administrator places this area again', 'actor_id', admin,
        'timestamp', pg_catalog.now())::text);
    insert into d47_changes values ('area', r.area_code, 'pin cleared (place again)', r.drawing_reference||' ('||r.map_x||', '||r.map_y||')', 'no pin');
  end loop;

  -- Assets that are now inside the Utility Block, and their open Work Orders
  for a in select * from pg_catalog.jsonb_to_recordset(moves) as x(tag text, old text, new text) loop
    select * into r from public.assets where lower(asset_tag) = lower(a.tag) for update;
    if r.id is null or r.location is distinct from a.old then continue; end if;
    update public.assets set location = a.new, room = a.new, building = 'Utility Block', updated_by = admin, updated_at = pg_catalog.now() where id = r.id;
    insert into public.activity_logs(user_id, asset_id, action, actor, note)
    values (admin, r.id, 'asset_location_changed', 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('before', pg_catalog.jsonb_build_object('site', r.site, 'location', r.location),
        'after', pg_catalog.jsonb_build_object('site', r.site, 'location', a.new),
        'reason', 'D-47: now a room inside the Utility Block (FW-001 Rev B)')::text);
    insert into d47_changes values ('asset', a.tag, 'location', r.location, a.new);
    for area_id in select w.id from public.work_orders w
        where w.asset_id = r.id and w.location = a.old and w.status not in ('completed', 'reviewed', 'closed', 'cancelled') loop
      update public.work_orders set location = a.new, updated_at = pg_catalog.now() where id = area_id;
      insert into public.activity_logs(user_id, work_order_id, action, actor, note)
      values (admin, area_id, 'work_order_uat_data_corrected', 'UAT data correction (owner-approved)',
        pg_catalog.jsonb_build_object('reason', 'D-47: '||a.tag||' is now inside the Utility Block', 'previous_location', a.old,
          'location', a.new, 'date', '2026-11-10')::text);
      insert into d47_changes select 'work order', w.work_order_number, 'location', a.old, a.new from public.work_orders w where w.id = area_id;
    end loop;
  end loop;
  select pg_catalog.count(*) into n from d47_changes;
  raise notice 'D-47 in total: % changes prepared', n;
end;
$d47b$;
select kind, item, field, before, after from d47_changes order by kind, item;
\if :{?apply}
  \echo 'Applying the changes.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

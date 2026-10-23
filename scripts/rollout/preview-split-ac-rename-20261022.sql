-- D-11.1 (owner, 22 Oct 2026): the facility runs on split air-conditioning, not chillers.
-- Renames the chiller-plant items in the Preview UAT data to split-AC equivalents and turns the
-- unused Chiller Plant Room area into the Generator Room (added to the Utility Block drawing).
-- Preview only (pvajuywwwpjlikqjnvgv). NOT APPLIED until the owner says go.
--
-- Dry run (default — shows the changes, then rolls back):
--   psql -X -c "set role postgres" -f this file
-- Apply:
--   psql -X -v apply=yes -c "set role postgres" -f this file
--
-- Every row is checked against its expected current value first; if anything differs, nothing changes.
-- Closed and cancelled Work Orders keep their recorded titles (their history is not rewritten);
-- their asset is renamed like every other.
\set ON_ERROR_STOP on
begin;
create temp table split_ac_changes(kind text, item text, field text, before text, after text);
do $rename$
declare
  admin uuid; r record; a record; n int;
  asset_map constant jsonb := '[
    {"old_tag":"P-CHW-01","new_tag":"ACCU-01","old_name":"Chilled Water Pump No. 1","name":"Split AC Condensing Unit No. 1","type":"Condensing unit","site":"Utility Block","location":"External / Service Yard"},
    {"old_tag":"P-CHW-03-MTR","new_tag":"ACCU-03-CMP","old_name":"Chilled Water Pump No. 3 Motor","name":"Split AC Condensing Unit No. 3 Compressor","type":"Compressor","site":"Utility Block","location":"External / Service Yard"},
    {"old_tag":"CT-02-FAN","new_tag":"ACCU-02-FAN","old_name":"Cooling Tower No. 2 Fan","name":"Split AC Condensing Unit No. 2 Fan Motor","type":"Condenser fan motor","site":"Utility Block","location":"Roof"},
    {"old_tag":"FCU-L2-08","new_tag":"SAC-L2-08","old_name":"Fan Coil Unit L2-08","name":"Split AC Indoor Unit L2-08","type":"Split AC indoor unit","site":"Main Building","location":"Level 2 Office"}
  ]';
  wo_map constant jsonb := '[
    {"number":"WO-TEST-001","old_title":"Chilled Water Pump P-CHW-01 Tripped","title":"Split AC Condensing Unit ACCU-01 Tripped",
     "old_description":"Pump tripped; standby pump is operating. Inspect relay, MCC, coupling, bearing and operating current.",
     "description":"Condensing unit tripped; the served indoor units are not cooling. Inspect contactor, overload relay, compressor, fan motor and operating current.",
     "old_location":"Chiller Plant Room","location":"External / Service Yard"},
    {"number":"WO-TEST-011","old_title":"Cooling Tower CT-02-FAN Bearing Replacement","title":"Split AC Condensing Unit ACCU-02 Fan Motor Bearing Replacement",
     "old_description":"Replace failed fan drive bearing when part is available.","description":"Replace the failed condenser fan motor bearing when the part is available.",
     "old_location":"Roof","location":"Roof"},
    {"number":"WO-TEST-014","old_title":"FCU-L2-08 Not Cooling Inspection","title":"Split AC Indoor Unit SAC-L2-08 Not Cooling Inspection",
     "old_description":null,"description":null,"old_location":"Level 2 Office","location":"Level 2 Office"},
    {"number":"WO-TEST-015","old_title":"Chilled Water Pump P-CHW-03 Motor Replacement","title":"Split AC Condensing Unit ACCU-03 Compressor Replacement",
     "old_description":"Motor insulation failure; proposed motor replacement and alignment.",
     "description":"Compressor winding insulation failure; proposed compressor replacement with refrigerant recovery, evacuation and recharge.",
     "old_location":"Chiller Plant Room","location":"External / Service Yard"}
  ]';
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;

  -- Assets
  for a in select * from pg_catalog.jsonb_to_recordset(asset_map) as x(old_tag text, new_tag text, old_name text, name text, type text, site text, location text) loop
    select * into r from public.assets where asset_tag = a.old_tag for update;
    if r.id is null then
      if exists(select 1 from public.assets where asset_tag = a.new_tag) then continue; end if; -- already renamed
      raise notice 'Asset % not found; skipped', a.old_tag; continue;
    end if;
    if r.name is distinct from a.old_name then raise exception 'Asset % is now named "%", not "%"; nothing changed', a.old_tag, r.name, a.old_name; end if;
    if exists(select 1 from public.assets where asset_tag = a.new_tag) then raise exception 'Asset tag % already exists; nothing changed', a.new_tag; end if;
    update public.assets set asset_tag = a.new_tag, name = a.name, asset_type = a.type, site = a.site, location = a.location, updated_at = pg_catalog.now() where id = r.id;
    insert into split_ac_changes values ('asset', a.old_tag, 'tag / name / type / location',
      r.asset_tag||' · '||r.name||' · '||coalesce(r.asset_type,'')||' · '||coalesce(r.location,''), a.new_tag||' · '||a.name||' · '||a.type||' · '||a.location);
  end loop;

  -- Work Orders (open ones only; closed and cancelled history is kept as recorded)
  for a in select * from pg_catalog.jsonb_to_recordset(wo_map) as x(number text, old_title text, title text, old_description text, description text, old_location text, location text) loop
    select * into r from public.work_orders where work_order_number = a.number for update;
    if r.id is null then raise notice 'Work Order % not found; skipped', a.number; continue; end if;
    if r.title = a.title then continue; end if; -- already renamed
    if r.status in ('closed','cancelled') then
      insert into split_ac_changes values ('work order', a.number, 'kept (status '||r.status||')', r.title, r.title); continue;
    end if;
    if r.title is distinct from a.old_title then raise exception '% is now titled "%"; nothing changed', a.number, r.title; end if;
    update public.work_orders set title = a.title,
        description = case when a.old_description is not null and description = a.old_description then a.description else description end,
        location = case when location is not distinct from a.old_location then a.location else location end,
        updated_at = pg_catalog.now()
      where id = r.id;
    insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
    values (admin, r.id, 'work_order_uat_data_corrected', r.status, r.status, 'UAT data correction (owner-approved)',
      pg_catalog.jsonb_build_object('reason','D-11.1: the facility runs on split air-conditioning; chiller-plant UAT data renamed',
        'previous_title', r.title, 'title', a.title, 'previous_location', r.location, 'date', '2026-10-22')::text);
    insert into split_ac_changes values ('work order', a.number, 'title', r.title, a.title);
  end loop;

  -- Area: the Chiller Plant Room becomes the Generator Room (the Administrator re-places its pin)
  for r in select * from public.facility_areas where area_code = 'CPR-01' and name = 'Chiller Plant Room' for update loop
    if exists(select 1 from public.facility_areas f where f.facility_id = r.facility_id and (f.area_code = 'GNR-01' or f.name = 'Generator Room')) then
      update public.facility_areas set active = false where id = r.id;
      insert into split_ac_changes values ('area', 'CPR-01', 'deactivated (Generator Room exists)', r.name, 'inactive');
    else
      update public.facility_areas set area_code = 'GNR-01', name = 'Generator Room' where id = r.id;
      insert into split_ac_changes values ('area', 'CPR-01', 'code / name', 'CPR-01 · Chiller Plant Room', 'GNR-01 · Generator Room');
    end if;
  end loop;
  select pg_catalog.count(*) into n from split_ac_changes;
  raise notice 'Split-AC rename: % changes prepared', n;
end;
$rename$;
select kind, item, field, before, after from split_ac_changes order by kind, item;
\if :{?apply}
  \echo 'Applying the changes.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

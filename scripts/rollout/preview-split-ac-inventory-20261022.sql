-- READ-ONLY inventory for D-11.1 (owner, 22 Oct 2026): the facility runs on split air-conditioning,
-- so chiller-plant items in the Preview UAT data are to be renamed to split-AC equivalents.
-- This file changes nothing: it lists every row in the public schema whose text mentions a
-- chiller-plant item, so the rename script can be checked against the real Preview rows.
-- Preview only (pvajuywwwpjlikqjnvgv). Run as: psql -X -c "set role postgres" -f this file.
\set ON_ERROR_STOP on
begin; -- rolled back at the end; only a temporary list is written
create temp table split_ac_inventory(table_name text, column_name text, row_key text, value text);
do $inventory$
declare c record; key_column text;
begin
  for c in
    select col.table_name, col.column_name from information_schema.columns col
    join information_schema.tables t on t.table_schema = col.table_schema and t.table_name = col.table_name and t.table_type = 'BASE TABLE'
    where col.table_schema = 'public' and col.data_type in ('text','character varying')
      and col.table_name not in ('activity_logs','notification_outbox','facility_settings_history')
  loop
    select case when exists(select 1 from information_schema.columns k where k.table_schema='public' and k.table_name=c.table_name and k.column_name='work_order_number') then 'work_order_number'
                when exists(select 1 from information_schema.columns k where k.table_schema='public' and k.table_name=c.table_name and k.column_name='asset_tag') then 'asset_tag'
                when exists(select 1 from information_schema.columns k where k.table_schema='public' and k.table_name=c.table_name and k.column_name='area_code') then 'area_code'
                when exists(select 1 from information_schema.columns k where k.table_schema='public' and k.table_name=c.table_name and k.column_name='id') then 'id'
                else null end into key_column;
    execute pg_catalog.format(
      'insert into split_ac_inventory select %L, %L, %s, left(%I, 160) from public.%I where %I ~* %L',
      c.table_name, c.column_name, case when key_column is null then 'null' else pg_catalog.format('%I::text', key_column) end, c.column_name, c.table_name, c.column_name,
      '(chill|chw|cooling tower|fan coil|\mfcu\M|\mahu\M|air handling)');
  end loop;
end;
$inventory$;
select table_name, column_name, row_key, value from split_ac_inventory order by table_name, row_key, column_name;
select table_name, pg_catalog.count(*) as rows from split_ac_inventory group by table_name order by table_name;
rollback;

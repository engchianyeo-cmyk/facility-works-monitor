\set ON_ERROR_STOP on

-- Represents an unknown hosted UUID written before an Asset Registry/FK existed.
update public.work_orders
set asset_id='70000000-0000-4000-8000-000000000099'
where id='30000000-0000-4000-8000-000000000001';

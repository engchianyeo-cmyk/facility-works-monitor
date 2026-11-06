-- One-off Preview UAT data (owner, 6 Nov 2026): the six fictional contractors used in the UAT test documents,
-- made procurement-prequalified and facility-confirmed at the facility of the given Work Order, so they appear
-- in "Eligible contractor". No agreed rates are added; quotation amounts are entered from the documents.
-- Fictional companies for testing only. Preview only (pvajuywwwpjlikqjnvgv). Dry run by default:
--   psql -X -v wo=WO-TEST-007 -c "set role postgres" -f this file
-- Apply:
--   psql -X -v wo=WO-TEST-007 -v apply=yes -c "set role postgres" -f this file
-- Idempotent: existing contractors and eligibility are kept, not duplicated.
\set ON_ERROR_STOP on
begin;
select pg_catalog.set_config('fmworks.fix_wo', :'wo', true);
create temp table contractor_report(stage text, contractor text, trade text, rate_items int, eligible_here boolean);
do $seed$
declare
  w public.work_orders%rowtype; admin uuid; v record;
  vendors jsonb := '[
    {"id":"13a00000-0000-4000-8000-000000000004","name":"Kelvinbay ACMV Engineering Pte Ltd (UAT)","trade":"Air-conditioning (ACMV)","contact":"Daniel Koh","email":"quotes@kelvinbay.example","phone":"6100 0004"},
    {"id":"13a00000-0000-4000-8000-000000000005","name":"Polarline Aircon Services Pte Ltd (UAT)","trade":"Air-conditioning (ACMV)","contact":"Siti Rahman","email":"quotes@polarline.example","phone":"6100 0005"},
    {"id":"13a00000-0000-4000-8000-000000000006","name":"Coolharbour M&E Pte Ltd (UAT)","trade":"Air-conditioning (ACMV)","contact":"Lim Wei Jie","email":"quotes@coolharbour.example","phone":"6100 0006"},
    {"id":"13a00000-0000-4000-8000-000000000007","name":"Gensteady Power Services Pte Ltd (UAT)","trade":"Standby generators","contact":"Arjun Nair","email":"quotes@gensteady.example","phone":"6100 0007"},
    {"id":"13a00000-0000-4000-8000-000000000008","name":"Aquaroute Plumbing Services Pte Ltd (UAT)","trade":"Plumbing and sanitary","contact":"Tan Boon Kiat","email":"quotes@aquaroute.example","phone":"6100 0008"},
    {"id":"13a00000-0000-4000-8000-000000000009","name":"Sunvane Solar Energy Services Pte Ltd (UAT)","trade":"Solar PV and inverters","contact":"Ong Jun Hao","email":"quotes@sunvane.example","phone":"6100 0009"}]';
  vid uuid;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  select * into w from public.work_orders where work_order_number = pg_catalog.current_setting('fmworks.fix_wo');
  if w.id is null or w.facility_id is null then raise exception 'Work Order % not found or has no facility; nothing changed', pg_catalog.current_setting('fmworks.fix_wo'); end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;

  insert into contractor_report
  select 'before', vd.name, vd.trade, (select count(*) from public.contractor_rate_items ri where ri.vendor_id = vd.id and ri.active)::int, true
  from public.vendor_facility_eligibility e join public.vendors vd on vd.id = e.vendor_id
  where e.facility_id = w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and vd.active and vd.deleted_at is null;

  for v in select * from pg_catalog.jsonb_to_recordset(vendors) as x(id uuid, name text, trade text, contact text, email text, phone text) loop
    vid := v.id;
    insert into public.vendors(id, name, trade, contact_name, contact_email, contact_phone, vendor_type, emergency_available, payment_terms_days, active)
    values (vid, v.name, v.trade, v.contact, v.email, v.phone, 'specialist_contractor', true, 30, true)
    on conflict (id) do nothing;
    insert into public.vendor_facility_eligibility(vendor_id, facility_id, procurement_prequalified, facility_confirmed, confirmation_basis, confirmed_by, active)
    values (vid, w.facility_id, true, true, 'UAT test contractor (owner-approved 6 Nov 2026); fictional company', admin, true)
    on conflict (vendor_id, facility_id) do update set procurement_prequalified = true, facility_confirmed = true, active = true;
  end loop;
  insert into public.activity_logs(user_id, action, actor, note)
  values (admin, 'contractor_uat_data_added', 'UAT data (owner-approved)',
    pg_catalog.jsonb_build_object('facility_id', w.facility_id, 'work_order', w.work_order_number, 'vendors', vendors, 'date', '2026-11-06')::text);

  insert into contractor_report
  select 'after', vd.name, vd.trade, (select count(*) from public.contractor_rate_items ri where ri.vendor_id = vd.id and ri.active)::int, true
  from public.vendor_facility_eligibility e join public.vendors vd on vd.id = e.vendor_id
  where e.facility_id = w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and vd.active and vd.deleted_at is null;
end;
$seed$;
select stage, contractor, trade, rate_items from contractor_report order by stage desc, contractor;
\if :{?apply}
  \echo 'Applying the change.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

-- One-off Preview UAT data (owner, 27 Oct 2026): three fictional HV/LV contractors with their agreed
-- transformer rates (Transformer_Contractor_Rates_UAT.xlsx), made procurement-prequalified and
-- facility-confirmed at the facility of the given Work Order, so they appear in "Eligible contractor".
-- Fictional companies for testing only. Preview only (pvajuywwwpjlikqjnvgv). Dry run by default:
--   psql -X -v wo=WO-TEST-010 -c "set role postgres" -f this file
-- Apply:
--   psql -X -v wo=WO-TEST-010 -v apply=yes -c "set role postgres" -f this file
-- Idempotent: existing contractors, rates and eligibility are kept, not duplicated.
\set ON_ERROR_STOP on
begin;
select pg_catalog.set_config('fmworks.fix_wo', :'wo', true);
create temp table contractor_report(stage text, contractor text, trade text, rate_items int, eligible_here boolean);
do $seed$
declare
  w public.work_orders%rowtype; admin uuid; v record; r record;
  vendors jsonb := '[
    {"id":"13a00000-0000-4000-8000-000000000001","name":"Voltquay Electrical Engineering Pte Ltd (UAT)","contact":"Rajan Pillai","email":"quotes@voltquay.example","phone":"6362 4810","m":1.0},
    {"id":"13a00000-0000-4000-8000-000000000002","name":"Ampwell HV Engineering Pte Ltd (UAT)","contact":"Ampwell Estimating","email":"quotes@ampwell.example","phone":"6100 0002","m":2.0},
    {"id":"13a00000-0000-4000-8000-000000000003","name":"Northline Switchgear Services Pte Ltd (UAT)","contact":"Northline Estimating","email":"quotes@northline.example","phone":"6100 0003","m":3.0}]';
  -- code, type, description, unit, Voltquay normal/emergency, Ampwell normal, Northline normal (emergency scaled)
  rates jsonb := '[
    ["TX-OIL-MIN","material","Mineral insulating oil to IEC 60296, uninhibited, supply","litre",5.80,5.80,6.20,5.60],
    ["TX-BRTH","material","Silica gel breather, supply and fix","no.",185,185,195,210],
    ["TX-GSKT","material","Gasket set: top cover, drain and sampling valves","set",260,260,240,300],
    ["TX-CONS","material","Consumables: absorbent pads, spill kit, clean drums, solvent","lot",220,220,250,200],
    ["TX-VAC","equipment","Vacuum oil filtration and filling plant, with operator","day",1200,1500,1350,1150],
    ["TX-LEW","service","LEW switching, isolation, earthing and permit-to-work (HV)","job",950,1400,1000,980],
    ["TX-DRAIN","service","Drain, flush and refill transformer under vacuum (2 technicians)","job",1600,2200,1750,1700],
    ["TX-OILTEST","service","Oil test: breakdown voltage, moisture, acidity, dissolved gas analysis","no.",380,380,420,400],
    ["TX-COMM","service","Insulation resistance and ratio tests, re-energising, commissioning report","job",650,900,700,720],
    ["TX-DISP","service","Waste oil collection and disposal by NEA-licensed collector","litre",0.45,0.45,0.50,0.55],
    ["LB-ELEC","labour","Electrician","man-hour",65,97.5,68,62],
    ["LB-LEW","labour","Licensed Electrical Worker (LEW)","man-hour",120,180,130,125],
    ["CO-HV","callout","Call-out charge, HV/LV","trip",150,300,160,180]]';
  item jsonb; normal numeric; emerg numeric; vid uuid; idx int;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  select * into w from public.work_orders where work_order_number = pg_catalog.current_setting('fmworks.fix_wo');
  if w.id is null or w.facility_id is null then raise exception 'Work Order % not found or has no facility; nothing changed', pg_catalog.current_setting('fmworks.fix_wo'); end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;

  insert into contractor_report
  select 'before', vd.name, vd.trade, (select count(*) from public.contractor_rate_items ri where ri.vendor_id = vd.id and ri.active)::int, true
  from public.vendor_facility_eligibility e join public.vendors vd on vd.id = e.vendor_id
  where e.facility_id = w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and vd.active and vd.deleted_at is null;

  for v in select * from pg_catalog.jsonb_to_recordset(vendors) as x(id uuid, name text, contact text, email text, phone text, m numeric) loop
    vid := v.id; idx := (v.m)::int;
    insert into public.vendors(id, name, trade, contact_name, contact_email, contact_phone, vendor_type, emergency_available, payment_terms_days, active)
    values (vid, v.name, 'Electrical (HV/LV)', v.contact, v.email, v.phone, 'specialist_contractor', true, 30, true)
    on conflict (id) do nothing;
    for item in select * from pg_catalog.jsonb_array_elements(rates) loop
      normal := case idx when 1 then (item->>4)::numeric when 2 then (item->>6)::numeric else (item->>7)::numeric end;
      emerg := pg_catalog.round(normal * (item->>5)::numeric / (item->>4)::numeric, 2);
      if not exists(select 1 from public.contractor_rate_items ri where ri.vendor_id = vid and ri.item_code = item->>0 and ri.active) then
        insert into public.contractor_rate_items(vendor_id, cost_type, item_code, description, unit, normal_unit_rate, emergency_unit_rate, currency, effective_from, effective_to, active)
        values (vid, item->>1, item->>0, item->>2, item->>3, normal, emerg, 'SGD', date '2026-01-01', date '2026-12-31', true);
      end if;
    end loop;
    insert into public.vendor_facility_eligibility(vendor_id, facility_id, procurement_prequalified, facility_confirmed, confirmation_basis, confirmed_by, active)
    values (vid, w.facility_id, true, true, 'UAT test contractor (owner-approved 27 Oct 2026); fictional company', admin, true)
    on conflict (vendor_id, facility_id) do update set procurement_prequalified = true, facility_confirmed = true, active = true;
  end loop;
  insert into public.activity_logs(user_id, action, actor, note)
  values (admin, 'contractor_uat_data_added', 'UAT data (owner-approved)',
    pg_catalog.jsonb_build_object('facility_id', w.facility_id, 'work_order', w.work_order_number, 'vendors', vendors, 'date', '2026-10-27')::text);

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

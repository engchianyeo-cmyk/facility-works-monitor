begin;

create or replace function pg_temp.assert_true(p_condition boolean,p_message text)
returns void language plpgsql as $assert$
begin
  if not coalesce(p_condition,false) then raise exception 'Three-quotation regression failed: %',p_message; end if;
end;$assert$;

create or replace function pg_temp.quote_id(p_vendor uuid)
returns uuid language sql stable security definer set search_path=pg_catalog
as $quote$ select id from public.contractor_quotations where vendor_id=p_vendor and work_order_id='08000000-0000-4000-8000-000000000012' order by created_at desc limit 1 $quote$;

delete from public.work_order_commercial_documents where work_order_id='08000000-0000-4000-8000-000000000012' and document_type='quotation';
delete from public.contractor_quotations where work_order_id='08000000-0000-4000-8000-000000000012';
delete from public.work_order_financial_controls where work_order_id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('fmworks.admin_correction','on',true);
update public.work_orders set status='in_progress',recommended_vendor_id=null,assigned_vendor_id=null,completed_at=null,reviewed_at=null,closed_at=null where id='08000000-0000-4000-8000-000000000012';
select pg_catalog.set_config('fmworks.admin_correction','off',true);

insert into public.vendors(id,name,trade,active) values
('44237000-0000-4000-8000-000000000001','WP2A Threshold Vendor A','Roller shutters',true),
('44237000-0000-4000-8000-000000000002','WP2A Threshold Vendor B','Roller shutters',true),
('44237000-0000-4000-8000-000000000003','WP2A Threshold Vendor C','Roller shutters',true);
insert into public.vendor_facility_eligibility(vendor_id,facility_id,procurement_prequalified,facility_confirmed,confirmation_basis,active)
select v.id,w.facility_id,true,true,'Rollback-only three-quotation test',true from public.vendors v cross join public.work_orders w
where v.id in ('44237000-0000-4000-8000-000000000001','44237000-0000-4000-8000-000000000002','44237000-0000-4000-8000-000000000003') and w.id='08000000-0000-4000-8000-000000000012';

select pg_catalog.set_config('request.jwt.claims','{"sub":"f2007b69-cc4c-40b5-9be1-7678450eb83a","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.assert_true((public.prepare_work_order_proposal('08000000-0000-4000-8000-000000000012','{"vendor_id":"44237000-0000-4000-8000-000000000001","proposed_amount":1000,"scope_summary":"Governed threshold repair"}'::jsonb)->>'ok')::boolean,'first quotation prepared');
select pg_temp.assert_true((public.save_work_order_proposal('08000000-0000-4000-8000-000000000012','{"proposed_amount":900,"scope_summary":"Governed threshold repair","quotation_ref":"WP2A-A","quotation_date":"2026-09-24","contractor_legal_name":"WP2A Threshold Vendor A","gst_treatment":"Inclusive","itemization_note":"Rollback-only authentic quotation"}'::jsonb)->>'governed_estimate')::numeric=1000,'editing a draft below the threshold preserves the governed estimate');
select pg_temp.assert_true((select estimated_cost=1000 from public.work_order_financial_controls where work_order_id='08000000-0000-4000-8000-000000000012'),'draft save cannot downgrade the governed S$1,000 estimate');
reset role;
insert into public.work_order_commercial_documents(work_order_id,document_type,quotation_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
select work_order_id,'quotation',id,'f2007b69-cc4c-40b5-9be1-7678450eb83a','vendor-a.pdf','application/pdf',100,'commercial/work-order/08000000-0000-4000-8000-000000000012/wp2a-a.pdf' from public.contractor_quotations where vendor_id='44237000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_true((public.submit_work_order_proposal('08000000-0000-4000-8000-000000000012',pg_temp.quote_id('44237000-0000-4000-8000-000000000001'),'First authentic quotation')->>'collected_quotations')::integer=1,'first of three collected');
select pg_temp.assert_true(public.recommend_work_order_quotation('08000000-0000-4000-8000-000000000012',pg_temp.quote_id('44237000-0000-4000-8000-000000000001'),'Premature selection')->>'code'='INSUFFICIENT_QUOTATIONS','one quotation cannot bypass three-quotation rule');

select pg_temp.assert_true((public.prepare_work_order_proposal('08000000-0000-4000-8000-000000000012','{"vendor_id":"44237000-0000-4000-8000-000000000002","proposed_amount":900,"scope_summary":"Governed threshold repair"}'::jsonb)->>'ok')::boolean,'second quotation prepared');
reset role;
insert into public.work_order_commercial_documents(work_order_id,document_type,quotation_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
select work_order_id,'quotation',id,'f2007b69-cc4c-40b5-9be1-7678450eb83a','vendor-b.pdf','application/pdf',100,'commercial/work-order/08000000-0000-4000-8000-000000000012/wp2a-b.pdf' from public.contractor_quotations where vendor_id='44237000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.assert_true((public.submit_work_order_proposal('08000000-0000-4000-8000-000000000012',pg_temp.quote_id('44237000-0000-4000-8000-000000000002'),'Second authentic quotation')->>'collected_quotations')::integer=2,'second of three collected');
select pg_temp.assert_true((select estimated_cost=1000 from public.work_order_financial_controls where work_order_id='08000000-0000-4000-8000-000000000012'),'lower quote cannot downgrade governed S$1,000 estimate');

select pg_temp.assert_true((public.prepare_work_order_proposal('08000000-0000-4000-8000-000000000012','{"vendor_id":"44237000-0000-4000-8000-000000000003","proposed_amount":1100,"scope_summary":"Governed threshold repair"}'::jsonb)->>'ok')::boolean,'third quotation prepared');
reset role;
insert into public.work_order_commercial_documents(work_order_id,document_type,quotation_id,uploaded_by,original_filename,content_type,byte_size,storage_path)
select work_order_id,'quotation',id,'f2007b69-cc4c-40b5-9be1-7678450eb83a','vendor-c.pdf','application/pdf',100,'commercial/work-order/08000000-0000-4000-8000-000000000012/wp2a-c.pdf' from public.contractor_quotations where vendor_id='44237000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true((public.submit_work_order_proposal('08000000-0000-4000-8000-000000000012',pg_temp.quote_id('44237000-0000-4000-8000-000000000003'),'Third authentic quotation')->>'ready_for_selection')::boolean,'three distinct quotations make selection ready');
select pg_temp.assert_true((public.recommend_work_order_quotation('08000000-0000-4000-8000-000000000012',pg_temp.quote_id('44237000-0000-4000-8000-000000000002'),'Vendor B offers the compliant lowest evaluated cost.')->>'ok')::boolean,'Technician records explicit recommendation rationale');

select pg_catalog.set_config('request.jwt.claims','{"sub":"826e5c86-8734-4ae6-9e25-e72d8c7f23d5","role":"authenticated"}',true);
select pg_temp.assert_true((public.approve_work_order_proposal('08000000-0000-4000-8000-000000000012',pg_temp.quote_id('44237000-0000-4000-8000-000000000002'),'Independent approval after three-quotation comparison.')->>'ok')::boolean,'independent Approver accepts selected quotation after threshold control');
select pg_temp.assert_true((select approved_budget=900 from public.work_order_financial_controls where work_order_id='08000000-0000-4000-8000-000000000012'),'selected S$900 quote is approved without changing governed threshold history');
reset role;

rollback;

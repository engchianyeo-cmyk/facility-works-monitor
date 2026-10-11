\set ON_ERROR_STOP on
begin;
insert into public.work_order_financial_controls(work_order_id,estimated_cost,rule_id)
select '08000000-0000-4000-8000-000000000015',750,id from public.commercial_approval_rules where minimum_amount=0;
insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path)
select 'work_order','08000000-0000-4000-8000-000000000003',id,'historical.jpg','image/jpeg',100,'before','Historical synthetic evidence','evidence/work-order/08000000-0000-4000-8000-000000000003/91000000-0000-4000-8000-000000000099/before.jpg'
from public.profiles where email='pilot.technician@example.test';
commit;

-- Synthetic Lifecycle v2 acceptance data: one prequalified, facility-confirmed contractor at every
-- active facility (30-day payment terms). No real company, contract or credential. Idempotent.
begin;
insert into public.vendors(id,name,trade,active,payment_terms_days)
values ('12a00000-0000-4000-8000-000000000001','Pilot Synthetic Contractor Pte Ltd','General M&E',true,30)
on conflict (id) do nothing;
insert into public.vendor_facility_eligibility(vendor_id,facility_id,procurement_prequalified,facility_confirmed,confirmation_basis,active)
select '12a00000-0000-4000-8000-000000000001',s.id,true,true,'Synthetic Lifecycle v2 acceptance contractor',true
from public.sites s where s.is_active
and not exists(select 1 from public.vendor_facility_eligibility e where e.vendor_id='12a00000-0000-4000-8000-000000000001' and e.facility_id=s.id and e.active);
commit;

\set ON_ERROR_STOP on
-- D-38 / D-39 (7 Nov 2026): each person reads and marks only their own notices; Finance's completed work register.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Notices / Finance register regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d380000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;

insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'d38.'||n||'@example.test',jsonb_build_object('display_name','D38 '||role||' '||n)
from (values ('technician',1),('technician',2),('approver',3),('finance',6)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Mechanical' end
from (values ('technician',1),('technician',2),('approver',3),('finance',6)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);
create temp table f as select s.id facility_id from public.sites s where s.is_active order by s.id limit 1;
insert into public.facility_memberships(facility_id,profile_id,membership_role,created_by)
select (select facility_id from f),p.id,p.role,pg_temp.u(3) from public.profiles p where p.id in (pg_temp.u(1),pg_temp.u(2),pg_temp.u(3));
create temp table ids(name text primary key, id uuid);
grant select on f to authenticated; grant select, insert on ids to authenticated;

do $t$ declare r jsonb; n text; begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  foreach n in array array['inhouse','contract','overdue','live'] loop
    r:=public.create_work_order(jsonb_build_object('title','D38 '||n,'location','Plant room','facility_id',(select facility_id from f)));
    insert into ids values (n,(r->'work_order'->>'id')::uuid);
  end loop;
end;$t$;
reset role;
insert into public.vendors(id,name,trade,vendor_type,payment_terms_days,active) values ('1d380000-0000-4000-8000-0000000000aa','D38 Contractor','Plumbing','specialist_contractor',30,true);
insert into ids values ('vendor','1d380000-0000-4000-8000-0000000000aa');
update public.work_orders set status='reviewed', reviewed_at=now(), in_house_work=true, completion_notes='Replaced tap cartridge.', actual_labour_hours=1
  where id=(select id from ids where name='inhouse');
update public.work_orders set status='reviewed', reviewed_at=now(), assigned_vendor_id=(select id from ids where name='vendor')
  where id in (select id from ids where name in ('contract','overdue'));
insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,invoice_reference,invoice_amount,invoice_uploaded_at,invoice_received_at,payment_due_at)
values ((select id from ids where name='contract'),(select id from ids where name='vendor'),'approved_for_payment',565,'INV-1',565,now(),now(),now()+interval '30 days'),
       ((select id from ids where name='overdue'),(select id from ids where name='vendor'),'approved_for_payment',100,'INV-2',100,now()-interval '40 days',now()-interval '40 days',now()-interval '10 days');
insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_profile_id,recipient_user_id,recipient_email,channel,payload)
values ((select id from ids where name='contract'),'work_order_invoice_uploaded','d38:1',pg_temp.u(6),pg_temp.u(6),'d38.6@example.test','email','{}'),
       ((select id from ids where name='contract'),'work_order_completed','d38:2',pg_temp.u(6),pg_temp.u(6),'d38.6@example.test','email','{}'),
       ((select id from ids where name='live'),'work_order_approved','d38:3',pg_temp.u(2),pg_temp.u(2),'d38.2@example.test','email','{}');

do $t$ declare r jsonb; begin
  perform pg_temp.act(pg_temp.u(6)); set local role authenticated;
  perform pg_temp.assert_true((select count(*) from public.notification_outbox where event_key like 'd38:%')=2,'Finance sees only its own two notices');
  r:=public.mark_my_notices_read(array[(select id from public.notification_outbox where event_key='d38:1')]);
  perform pg_temp.assert_true((r->>'marked_read')::int=1,'one notice marked read');
  perform pg_temp.assert_true((select count(*) from public.notification_outbox where event_key like 'd38:%' and read_at is null)=1,'the other stays unread');
  perform pg_temp.act(pg_temp.u(2));
  perform pg_temp.assert_true((select count(*) from public.notification_outbox where event_key like 'd38:%')=1,'a Technician sees only their own notice');
  r:=public.mark_my_notices_read(array[(select id from public.notification_outbox where event_key='d38:2')]);
  perform pg_temp.assert_true((r->>'marked_read')::int=0,'nobody can mark someone else''s notice read');
  r:=public.mark_my_notices_read();
  perform pg_temp.assert_true((r->>'marked_read')::int=1,'mark all read covers only your own');
end;$t$;

do $t$ begin
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  perform pg_temp.assert_true(not exists(select 1 from public.finance_completed_work_register()),'a Technician cannot read the Finance register');
  perform pg_temp.act(pg_temp.u(6));
  perform pg_temp.assert_true((select register_status from public.finance_completed_work_register((select id from ids where name='inhouse')))='in_house','in-house work shows as in-house, no payment');
  perform pg_temp.assert_true((select work_performed from public.finance_completed_work_register((select id from ids where name='inhouse')))='Replaced tap cartridge.','the work performed is shown');
  perform pg_temp.assert_true((select register_status='invoice_received' and contractor_name='D38 Contractor' and payment_terms_days=30 and invoice_reference='INV-1'
    from public.finance_completed_work_register((select id from ids where name='contract'))),'contractor work shows the invoice, terms and status');
  perform pg_temp.assert_true((select register_status from public.finance_completed_work_register((select id from ids where name='overdue')))='overdue','a payment past its due date is overdue');
  perform pg_temp.assert_true(not exists(select 1 from public.finance_completed_work_register((select id from ids where name='live'))),'work not yet completed is not in the register');
end;$t$;

-- D-41: duplicate payment references and invoice numbers are refused; test data leaves Finance's lists.
do $t$ declare r jsonb; path text; begin
  perform pg_temp.act(pg_temp.u(6)); set local role authenticated;
  r:=public.record_work_order_finance_payment((select id from ids where name='overdue'),jsonb_build_object('paid_amount',100,'payment_reference','FS-D38-0001','payment_note','Paid'));
  perform pg_temp.assert_true((r->>'ok')::boolean,'Finance records the first payment: '||coalesce(r->>'message',''));
  r:=public.record_work_order_finance_payment((select id from ids where name='contract'),jsonb_build_object('paid_amount',565,'payment_reference','fs-d38-0001 ','payment_note','Paid'));
  perform pg_temp.assert_true(r->>'code'='DUPLICATE_PAYMENT_REFERENCE' and r->>'message' like '%already recorded on%','a payment reference used on another payment is refused: '||coalesce(r->>'message',''));
  reset role;
  insert into ids select 'dup', (public.create_work_order(jsonb_build_object('title','D38 dup','location','Plant room','facility_id',(select facility_id from f)))->'work_order'->>'id')::uuid
    from (select pg_temp.act(pg_temp.u(1))) x;
  update public.work_orders set status='reviewed', reviewed_at=now(), assigned_technician_id=pg_temp.u(1), assigned_vendor_id=(select id from ids where name='vendor') where id=(select id from ids where name='dup');
  insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount) values ((select id from ids where name='dup'),(select id from ids where name='vendor'),'approved_for_payment',80);
  path:='commercial/work-order/'||(select id from ids where name='dup')::text||'/inv.pdf';
  insert into storage.objects(bucket_id,name) values('field-evidence',path);
  perform pg_temp.act(pg_temp.u(1)); set local role authenticated;
  r:=public.register_work_order_invoice((select id from ids where name='dup'),path,'inv.pdf','application/pdf',100,'inv-1',80);
  perform pg_temp.assert_true(r->>'code'='DUPLICATE_INVOICE_NUMBER' and r->>'message' like '%D38 Contractor%','an invoice number already recorded is refused: '||coalesce(r->>'message',''));
  r:=public.register_work_order_invoice((select id from ids where name='dup'),path,'inv.pdf','application/pdf',100,'INV-3',80);
  perform pg_temp.assert_true((r->>'ok')::boolean,'a new invoice number is accepted');
  reset role;
  insert into public.work_order_test_data(work_order_id,reason) values ((select id from ids where name='overdue'),'D38 test record');
  perform pg_temp.act(pg_temp.u(6)); set local role authenticated;
  perform pg_temp.assert_true(not exists(select 1 from public.finance_completed_work_register() where work_order_id=(select id from ids where name='overdue')),'test data leaves the register');
  perform pg_temp.assert_true(not exists(select 1 from public.work_order_finance_tracker() where work_order_id=(select id from ids where name='overdue')),'test data leaves the Finance tracker');
  perform pg_temp.assert_true(exists(select 1 from public.finance_completed_work_register((select id from ids where name='overdue'))),'a test Work Order still shows its own Finance box');
end;$t$;
rollback;

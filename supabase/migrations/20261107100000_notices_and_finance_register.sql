begin;
-- D-38 (7 Nov 2026): each person sees the notices sent to them ("My notices", bell with unread count) and marks them
-- read. Administrators already read every notice (delivery status view). Email delivery itself remains R1-012.
-- D-39 (7 Nov 2026): Finance's completed work register - every Work Order approved as Completed, in-house or by a
-- contractor, with who approved and completed it, the work performed, amounts, invoice, payment due date and status.

alter table public.notification_outbox add column if not exists read_at timestamptz;

drop policy if exists notification_outbox_read_own on public.notification_outbox;
create policy notification_outbox_read_own on public.notification_outbox for select to authenticated
  using (recipient_profile_id = auth.uid() and public.pilot_account_ready());

create or replace function public.mark_my_notices_read(p_notice_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare n integer;
begin
  if auth.uid() is null or not public.pilot_account_ready(auth.uid()) then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  update public.notification_outbox set read_at = now()
  where recipient_profile_id = auth.uid() and read_at is null and (p_notice_ids is null or id = any(p_notice_ids));
  get diagnostics n = row_count;
  return pg_catalog.jsonb_build_object('ok', true, 'marked_read', n);
end;
$function$;

create or replace function public.finance_completed_work_register(p_work_order_id uuid default null)
returns table(
  work_order_id uuid, work_order_number text, title text, facility_name text, status text, in_house_work boolean, emergency_work boolean,
  contractor_name text, technician_name text, approved_by_name text, approved_at timestamptz, completed_by_name text, completed_at timestamptz,
  closed_at timestamptz, work_performed text, actual_labour_hours numeric, actual_work_started_at timestamptz, actual_work_ended_at timestamptz,
  approved_amount numeric, final_amount numeric, invoice_reference text, invoice_amount numeric, invoice_uploaded_at timestamptz,
  invoice_received_at timestamptz, payment_due_at timestamptz, payment_terms_days integer, paid_at timestamptz, paid_amount numeric,
  payment_reference text, register_status text)
language sql stable security definer set search_path to 'pg_catalog' as $function$
  select w.id, w.work_order_number, w.title, s.name, w.status, coalesce(w.in_house_work, false), coalesce(w.emergency_work, false),
    v.name, t.display_name, ap.actor, ap.created_at, cp.actor, coalesce(cp.created_at, w.reviewed_at), w.closed_at,
    w.completion_notes, w.actual_labour_hours, w.actual_work_started_at, w.actual_work_ended_at,
    fc.approved_budget,
    case when coalesce(w.in_house_work, false)
         then (select coalesce(sum(c.amount), 0) from public.work_order_cost_lines c where c.work_order_id = w.id and c.cost_phase = 'actual')
         else p.assessed_amount end,
    p.invoice_reference, p.invoice_amount, p.invoice_uploaded_at, p.invoice_received_at, p.payment_due_at, v.payment_terms_days,
    p.paid_at, p.paid_amount, p.payment_reference,
    case when coalesce(w.in_house_work, false) then 'in_house'
         when p.status = 'paid' or p.paid_at is not null then 'paid'
         when p.invoice_received_at is not null and p.payment_due_at < now() then 'overdue'
         when p.invoice_received_at is not null then 'invoice_received'
         when p.invoice_uploaded_at is not null then 'invoice_uploaded'
         when w.status = 'closed' then 'closed_no_payment'
         else 'awaiting_invoice' end
  from public.work_orders w
  left join public.sites s on s.id = w.facility_id
  left join public.contractor_payment_assessments p on p.work_order_id = w.id
  left join public.vendors v on v.id = coalesce(p.vendor_id, w.assigned_vendor_id)
  left join public.profiles t on t.id = w.assigned_technician_id
  left join public.work_order_financial_controls fc on fc.work_order_id = w.id
  left join lateral (select a.actor, a.created_at from public.activity_logs a
    where a.work_order_id = w.id and a.from_status = 'submitted' and a.to_status in ('approved', 'assigned', 'in_progress')
    order by a.created_at desc limit 1) ap on true
  left join lateral (select a.actor, a.created_at from public.activity_logs a
    where a.work_order_id = w.id and a.action = 'work_order_review' and a.to_status = 'reviewed'
    order by a.created_at desc limit 1) cp on true
  where public.current_user_role() in ('finance', 'administrator') and public.pilot_account_ready(auth.uid())
    and w.status in ('reviewed', 'closed') and (p_work_order_id is null or w.id = p_work_order_id)
  order by coalesce(cp.created_at, w.reviewed_at) desc nulls last
$function$;

revoke all on function public.mark_my_notices_read(uuid[]), public.finance_completed_work_register(uuid) from public, anon, service_role;
grant execute on function public.mark_my_notices_read(uuid[]), public.finance_completed_work_register(uuid) to authenticated;

do $postcheck$
begin
  if to_regprocedure('public.finance_completed_work_register(uuid)') is null or to_regprocedure('public.mark_my_notices_read(uuid[])') is null
     or not exists (select 1 from pg_policy where polname = 'notification_outbox_read_own') then
    raise exception 'D-38/D-39 notices and Finance register were not installed';
  end if;
end;$postcheck$;
commit;

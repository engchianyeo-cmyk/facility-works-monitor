begin;
-- D-45 (9 Nov 2026): every member of staff can read the site's approved SLA targets (the Site SLA card) and the SLA
-- countdown of the Work Orders they can already see. Until now only Approvers, Supervisors and Administrators could.
-- Read-only: who may write SLA records is unchanged.

drop policy if exists sla_agreements_staff_read on public.sla_agreements;
create policy sla_agreements_staff_read on public.sla_agreements for select to authenticated
  using (public.pilot_account_ready() and is_active);

drop policy if exists sla_agreement_versions_staff_read on public.sla_agreement_versions;
create policy sla_agreement_versions_staff_read on public.sla_agreement_versions for select to authenticated
  using (public.pilot_account_ready() and approval_status = 'approved');

drop policy if exists sla_rules_staff_read on public.sla_rules;
create policy sla_rules_staff_read on public.sla_rules for select to authenticated
  using (public.pilot_account_ready() and is_active
    and exists (select 1 from public.sla_agreement_versions v where v.id = version_id and v.approval_status = 'approved'));

drop policy if exists service_categories_staff_read on public.service_categories;
create policy service_categories_staff_read on public.service_categories for select to authenticated
  using (public.pilot_account_ready() and is_active);

-- A clock is visible to whoever can see its Work Order (the Work Order's own rules decide).
drop policy if exists work_order_sla_clocks_staff_read on public.work_order_sla_clocks;
create policy work_order_sla_clocks_staff_read on public.work_order_sla_clocks for select to authenticated
  using (public.pilot_account_ready() and exists (select 1 from public.work_orders w where w.id = work_order_id));

do $postcheck$
begin
  if (select count(*) from pg_policies where schemaname = 'public' and policyname in ('sla_agreements_staff_read', 'sla_agreement_versions_staff_read',
      'sla_rules_staff_read', 'service_categories_staff_read', 'work_order_sla_clocks_staff_read')) <> 5 then
    raise exception 'D-45 SLA read policies missing';
  end if;
end;
$postcheck$;
commit;

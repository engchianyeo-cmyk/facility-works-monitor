-- READ-ONLY Preview report (owner, 22 Nov 2026): who is on the staff of which facility now, who was before, and who
-- has done work at each facility — to decide who belongs in Facility One and who is still needed at Facility 2.
-- Changes nothing (the whole run is rolled back). Shows display names, emails and roles only; no passwords exist here.
-- Preview only (pvajuywwwpjlikqjnvgv). Check the host in the connection string before running.
--   psql -X -c "set role postgres" -c "set fmworks.rollout_project_ref='pvajuywwwpjlikqjnvgv'" -f this file
\set ON_ERROR_STOP on
begin read only;
select current_setting('fmworks.rollout_project_ref', true) is not distinct from 'pvajuywwwpjlikqjnvgv' as ok_ref \gset
\if :ok_ref
\else
  \echo 'Set fmworks.rollout_project_ref to pvajuywwwpjlikqjnvgv (Preview) first.'
  rollback;
  \quit
\endif
\pset pager off
\echo ''
\echo '=== 1. Every active account: role, current facilities, past facilities, Work Orders done per facility ==='
with now_m as (
  select m.profile_id, string_agg(s.code || ' ' || m.membership_role, ', ' order by s.code) as now_in
  from public.facility_memberships m join public.sites s on s.id = m.facility_id
  where m.active and m.effective_from <= now() and (m.effective_to is null or m.effective_to > now()) group by m.profile_id),
past_m as (
  select m.profile_id, string_agg(s.code || ' ' || m.membership_role || ' until ' || to_char(coalesce(m.effective_to, m.updated_at) at time zone 'Asia/Singapore', 'DD Mon'), ', ' order by s.code) as was_in
  from public.facility_memberships m join public.sites s on s.id = m.facility_id
  where not (m.active and m.effective_from <= now() and (m.effective_to is null or m.effective_to > now())) group by m.profile_id),
work as (
  select w.assigned_technician_id as profile_id, string_agg(distinct s.code || ' x' || c.n, ', ') as work_at
  from (select assigned_technician_id, facility_id, count(*) n from public.work_orders where assigned_technician_id is not null group by 1, 2) c
  join public.work_orders w on w.assigned_technician_id = c.assigned_technician_id and w.facility_id = c.facility_id
  join public.sites s on s.id = c.facility_id group by 1)
select p.display_name as name, p.email, p.role, coalesce(n.now_in, '—') as facility_now, coalesce(pm.was_in, '—') as facility_before,
       coalesce(wk.work_at, '—') as work_orders_as_technician, to_char(p.created_at at time zone 'Asia/Singapore', 'DD Mon') as created
from public.profiles p left join now_m n on n.profile_id = p.id left join past_m pm on pm.profile_id = p.id left join work wk on wk.profile_id = p.id
where p.is_active and p.deleted_at is null
order by case when n.now_in is null then 1 else 0 end, n.now_in, p.role, p.display_name;
\echo ''
\echo '=== 2. Head-count per facility (current staff) ==='
select s.code, s.name, m.membership_role as role, count(*) as people
from public.facility_memberships m join public.sites s on s.id = m.facility_id
where m.active and m.effective_from <= now() and (m.effective_to is null or m.effective_to > now()) and s.is_active
group by 1, 2, 3 order by 1, 3;
\echo ''
\echo '=== 3. Staff whose facility role differs from their account role (they drop off the Facilities staff list) ==='
select p.display_name as name, p.email, p.role as account_role, m.membership_role as facility_role, s.code
from public.facility_memberships m join public.profiles p on p.id = m.profile_id join public.sites s on s.id = m.facility_id
where m.active and (m.effective_to is null or m.effective_to > now()) and m.membership_role <> p.role order by s.code, p.display_name;
rollback;
\echo 'Read-only report: nothing was changed.'

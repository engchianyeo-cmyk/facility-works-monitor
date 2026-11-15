-- One-off Preview UAT data change with M29 (owner decision D-54, 12-15 Nov 2026): Finance now belongs to facilities.
-- Every active Finance account becomes staff of the trial facility (code UAT-FAC-001, "Facility One"), so Finance keeps
-- seeing exactly what it sees today. Facility 2 Finance is added later in the app (Facilities › Add a staff member).
-- Preview only (pvajuywwwpjlikqjnvgv). Check the host in the connection string before running. Run AFTER M29.
-- Dry run by default:   psql -X -c "set role postgres" -f this file
-- Apply:                psql -X -v apply=yes -c "set role postgres" -f this file
-- Safe to run again.
\set ON_ERROR_STOP on
begin;
do $m$
declare fac uuid; admin uuid; n integer;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if not exists(select 1 from pg_catalog.pg_proc where proname = 'facility_finance_permitted') then raise exception 'M29 is not applied; nothing changed'; end if;
  select id into fac from public.sites where code = 'UAT-FAC-001';
  if fac is null then raise exception 'Facility UAT-FAC-001 not found; nothing changed'; end if;
  select id into admin from public.profiles where role = 'administrator' and is_active and deleted_at is null order by created_at limit 1;
  insert into public.facility_memberships(facility_id, profile_id, membership_role, created_by)
  select fac, p.id, 'finance', admin from public.profiles p
   where p.role = 'finance' and p.is_active and p.deleted_at is null
     and not exists(select 1 from public.facility_memberships m where m.facility_id = fac and m.profile_id = p.id and m.membership_role = 'finance' and m.active);
  get diagnostics n = row_count;
  insert into public.activity_logs(user_id, action, actor, note)
  select admin, 'facility_staff_added', 'UAT data change (owner decision D-54)',
    pg_catalog.jsonb_build_object('facility_id', fac, 'profile_id', p.id, 'role', 'finance', 'reason', 'Finance belongs to facilities (M29)')::text
  from public.profiles p where p.role = 'finance' and p.is_active and p.deleted_at is null and n > 0;
  raise notice '% Finance account(s) added to Facility One (UAT-FAC-001).', n;
end;
$m$;
select s.code, s.name, p.display_name, p.email, m.membership_role, m.active
from public.facility_memberships m join public.sites s on s.id = m.facility_id join public.profiles p on p.id = m.profile_id
where m.membership_role = 'finance' order by 1, 3;
\if :{?apply}
  \echo 'Applying the change.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

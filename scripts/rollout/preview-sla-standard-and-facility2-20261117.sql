-- One-off Preview UAT data (owner, 17 Nov 2026): load the draft SLA ("Facility Services SLA — Facility One and
-- Facility 2 (draft)") into FMWorks after M32, through the same admin_set_sla_times() the SLA times page uses,
-- acting as the Super-Administrator (engchian.yeo@gmail.com). Working days are counted as whole days (24 h).
--   Standard (all facilities) = the draft's Facility One table; Facility 2 = its own tighter table.
-- Preview only (pvajuywwwpjlikqjnvgv). Check the host in the connection string before running.
-- Dry run by default:   psql -X -c "set role postgres" -c "set fmworks.rollout_project_ref='pvajuywwwpjlikqjnvgv'" -f this file
-- Apply:                add -v apply=yes after -X
\set ON_ERROR_STOP on
begin;
select current_setting('fmworks.rollout_project_ref', true) is not distinct from 'pvajuywwwpjlikqjnvgv' as ok_ref \gset
\if :ok_ref
\else
  \echo 'Set fmworks.rollout_project_ref to pvajuywwwpjlikqjnvgv (Preview) first; nothing changed.'
  rollback;
  \quit
\endif
\o /dev/null
select coalesce((select p.id::text from public.profiles p where lower(p.email) = 'engchian.yeo@gmail.com' and p.role = 'administrator'), '') as admin,
       coalesce((select s.id::text from public.sites s where s.name ilike 'Facility 2%' and s.is_active order by s.code limit 1), '') as fac2 \gset
select set_config('fmw.admin', :'admin', true), set_config('fmw.fac2', :'fac2', true);
do $m$
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if to_regprocedure('public.admin_set_sla_times(uuid,jsonb,text)') is null then raise exception 'M32 is not applied; nothing changed'; end if;
  if nullif(current_setting('fmw.admin'), '') is null or not public.pilot_account_ready(current_setting('fmw.admin')::uuid) then
    raise exception 'Super-Administrator engchian.yeo@gmail.com not found or not ready; nothing changed'; end if;
  if nullif(current_setting('fmw.fac2'), '') is null then raise exception 'No active facility named "Facility 2..."; nothing changed'; end if;
end;
$m$;

select set_config('request.jwt.claims', json_build_object('sub', :'admin', 'role', 'authenticated')::text, true),
       set_config('request.jwt.claim.sub', :'admin', true), set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.admin_set_sla_times(null, '[
  {"priority":"critical","acknowledgement_minutes":15,"attendance_minutes":30,"make_safe_minutes":120,"rectification_minutes":240,"kpi_target_percent":95},
  {"priority":"high","acknowledgement_minutes":30,"attendance_minutes":120,"make_safe_minutes":240,"rectification_minutes":1440,"kpi_target_percent":95},
  {"priority":"medium","acknowledgement_minutes":120,"attendance_minutes":1440,"rectification_minutes":4320,"kpi_target_percent":90},
  {"priority":"low","acknowledgement_minutes":1440,"attendance_minutes":4320,"rectification_minutes":14400,"kpi_target_percent":90}]'::jsonb,
  'Draft SLA of 17 Nov 2026: standard for all facilities (pilot P1 times; others proposed)') as r1 \gset
select public.admin_set_sla_times(:'fac2'::uuid, '[
  {"priority":"critical","acknowledgement_minutes":10,"attendance_minutes":20,"make_safe_minutes":60,"rectification_minutes":240,"kpi_target_percent":98},
  {"priority":"high","acknowledgement_minutes":15,"attendance_minutes":60,"make_safe_minutes":120,"rectification_minutes":480,"kpi_target_percent":98},
  {"priority":"medium","acknowledgement_minutes":60,"attendance_minutes":1440,"rectification_minutes":2880,"kpi_target_percent":90},
  {"priority":"low","acknowledgement_minutes":1440,"attendance_minutes":4320,"rectification_minutes":14400,"kpi_target_percent":90}]'::jsonb,
  'Draft SLA of 17 Nov 2026: Facility 2 runs tighter for cold chain and GMP (proposed)') as r2 \gset
set local role postgres;
select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
select set_config('fmw.r1', :'r1', true), set_config('fmw.r2', :'r2', true);
do $m$
declare n text; begin
  foreach n in array array['r1','r2'] loop
    if coalesce((current_setting('fmw.'||n)::jsonb ->> 'ok')::boolean, false) is not true then
      raise exception 'SLA % not set, nothing changed: %', n, current_setting('fmw.'||n); end if;
  end loop;
end;
$m$;
\o
select coalesce(s.name, 'Standard (all facilities)') as sla, r.priority_class, r.acknowledgement_minutes as ack, r.attendance_minutes as attend,
       r.make_safe_minutes as make_safe, r.rectification_minutes as fix, r.kpi_target_percent as target
from public.sla_rules r join public.sla_agreement_versions v on v.id = r.version_id join public.sla_agreements a on a.id = v.agreement_id
left join public.sites s on s.id = a.facility_id
where r.is_active and a.is_active order by a.facility_id nulls first, r.priority_class;
\if :{?apply}
  \echo 'Applying the change.'
  commit;
\else
  \echo 'Dry run only: rolling back. Re-run with -v apply=yes to apply.'
  rollback;
\endif

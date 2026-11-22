-- One-off Preview UAT data (owner D-81, 22 Nov 2026), after M39:
--   Every operational facility gets an on-call list. Facility 2: Technician 1 first (order 10), Technician 2 next
--   (order 20), all incident types, SMS and WhatsApp. Facility One keeps its existing entry (Yang Ying Zhang, moved to
--   Facility One by M39). Interim until the shift roster (M41) supplies the Technicians on shift.
-- Through the app's own function, as the Super-Administrator (engchian.yeo@gmail.com); audited. Adds nothing that is
-- already there, so running it twice changes nothing.
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
       coalesce((select s.id::text from public.sites s where s.name ilike 'Facility 2%' and s.is_active order by s.code limit 1), '') as fac2,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+1@gmail.com'), '') as tech1,
       coalesce((select p.id::text from public.profiles p where lower(p.email) = 'koi.kpr+2@gmail.com'), '') as tech2 \gset
select set_config('fmw.admin', :'admin', true), set_config('fmw.fac2', :'fac2', true), set_config('fmw.tech1', :'tech1', true), set_config('fmw.tech2', :'tech2', true);
do $m$
declare admin uuid; fac uuid; t record; r jsonb; added int := 0; kept int := 0;
begin
  if current_user <> 'postgres' then raise exception 'Run as postgres (set role postgres)'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='emergency_response_roster' and column_name='facility_id') then raise exception 'M39 is not applied; nothing changed'; end if;
  admin := nullif(current_setting('fmw.admin'), '')::uuid; fac := nullif(current_setting('fmw.fac2'), '')::uuid;
  if admin is null or not public.pilot_account_ready(admin) then raise exception 'Super-Administrator not found or not ready; nothing changed'; end if;
  if fac is null then raise exception 'No active facility named "Facility 2..."; nothing changed'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated')::text, true),
          set_config('request.jwt.claim.sub', admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  for t in select * from (values (nullif(current_setting('fmw.tech1'), '')::uuid, 10, 'Technician 1'), (nullif(current_setting('fmw.tech2'), '')::uuid, 20, 'Technician 2')) v(id, ord, label) loop
    if t.id is null or not public.active_facility_member(fac, 'technician', t.id) then raise exception '% is not a Technician of Facility 2; nothing changed', t.label; end if;
    if exists(select 1 from public.emergency_response_roster where facility_id = fac and profile_id = t.id and active) then kept := kept + 1; continue; end if;
    r := public.upsert_emergency_roster(null, jsonb_build_object('facility_id', fac, 'profile_id', t.id, 'escalation_order', t.ord, 'sms_enabled', true, 'whatsapp_enabled', true, 'active', true));
    if coalesce((r ->> 'ok')::boolean, false) is not true then raise exception '% not added, nothing changed: %', t.label, r; end if;
    added := added + 1;
  end loop;
  perform set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
  perform set_config('fmw.summary', format('Facility 2: %s on-call entries added, %s already there', added, kept), true);
end;
$m$;
\o
select current_setting('fmw.summary') as done;
select coalesce(s.name, 'No facility recorded') as facility, p.display_name as on_call, r.escalation_order as call_order, r.active
from public.emergency_response_roster r left join public.sites s on s.id = r.facility_id left join public.profiles p on p.id = r.profile_id
order by s.name nulls last, r.escalation_order;
\if :{?apply}
  \echo 'apply=yes: committing.'
  commit;
\else
  \echo 'Dry run only: rolled back. Run again with -v apply=yes to keep it.'
  rollback;
\endif

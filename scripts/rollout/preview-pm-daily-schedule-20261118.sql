-- One-off Preview set-up (owner D-67, 18 Nov 2026), after M35: run planned maintenance once a day by the database's
-- own scheduler (pg_cron, free on Supabase), at 22:00 UTC = 06:00 Singapore. Vercel's daily schedule only runs on
-- Production, so Preview uses this. Safe to run again (the job is replaced, not doubled).
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
do $m$ begin
  if to_regprocedure('public.pm_daily_run(date)') is null then raise exception 'M35 is not applied; nothing changed'; end if;
end $m$;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('fmworks-pm-daily', '0 22 * * *', $job$select public.pm_daily_run()$job$) as job_id;
select jobname, schedule, command, active from cron.job where jobname = 'fmworks-pm-daily';
\if :{?apply}
  \echo 'apply=yes: committing.'
  commit;
\else
  \echo 'Dry run only: rolled back. Run again with -v apply=yes to keep it.'
  rollback;
\endif

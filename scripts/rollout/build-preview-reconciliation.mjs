import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const baseline = JSON.parse(readFileSync(new URL('./preview-baseline.json', import.meta.url), 'utf8'));
const manifest = readFileSync(path.join(root, 'supabase/bootstrap/fresh-install-manifest.txt'), 'utf8')
  .split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
const start = manifest.indexOf('supabase/migrations/20260928000000_release1_governance_reconciliation.sql');
if (start < 0 || !manifest.at(-1).endsWith('20261010142142_incident_responder_membership_denial.sql')) {
  throw new Error('Candidate manifest changed; independently review the rollout baseline.');
}
const selected = manifest.slice(start);
// Existing immutable migrations remain the source of each change. One outer
// transaction makes all prerequisite, schema, data and ledger changes atomic.
const bodies = selected.map(file => {
  const source = readFileSync(path.join(root, file), 'utf8');
  if ((source.match(/^begin;\s*$/gmi) || []).length !== 1 || (source.match(/^commit;\s*$/gmi) || []).length !== 1) {
    throw new Error(`Unexpected transaction structure: ${file}`);
  }
  return `-- SOURCE: ${file}\n${source.replace(/^begin;\s*$/gmi, '').replace(/^commit;\s*$/gmi, '')}`;
});
const expected = baseline.versions.map(version => `'${version}'`).join(',');
// Preview's dated 0040 history left the later renamed private core with the
// earlier Technician-only implementation. Restore only this implementation,
// using the exact reviewed canonical four-role body; keep the wrapper/ACLs.
const multirole = readFileSync(path.join(root, 'supabase/migrations/0040_multirole_field_execution_authority.sql'), 'utf8');
const completionStart = multirole.indexOf('create or replace function public.submit_physical_completion(');
const completionEnd = multirole.indexOf('create or replace function public.register_evidence_item(', completionStart);
if (completionStart < 0 || completionEnd < 0) throw new Error('Canonical completion source changed');
const completionRepair = multirole.slice(completionStart, completionEnd)
  .replace('public.submit_physical_completion(', 'public.submit_physical_completion_20260921_core(');
const sql = `-- Preview-only incremental adapter; candidate ${baseline.candidate_sha}.
-- Generated from immutable sources. NEVER bootstrap or run against Production.
-- Caller must independently verify the connection host/project before setting
-- fmworks.rollout_project_ref. This setting is an assertion, not server identity.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_catalog.pg_advisory_xact_lock(610110841);
do $preflight$
declare versions text[];
begin
 if current_setting('fmworks.rollout_project_ref',true) is distinct from '${baseline.project_ref}' then
  raise exception 'Explicit Preview target assertion required';
 end if;
 select array_agg(version::text order by version) into versions from supabase_migrations.schema_migrations;
 if versions is distinct from array[${expected}]::text[] then
  raise exception 'Preview ledger differs from reviewed baseline; stop and re-inspect';
 end if;
 if to_regclass('public.procurement_policy_versions') is not null
   or to_regprocedure('public.void_incident_evidence(uuid,text)') is not null
   or to_regprocedure('public.release1_work_order_visible(uuid)') is not null then
  raise exception 'Candidate objects already exist; partial/repeated rollout refused';
 end if;
 if md5(pg_get_functiondef('public.submit_physical_completion_20260921_core(uuid,jsonb)'::regprocedure))
   is distinct from 'cd2acebf0a8431824eae03b90e71a410' then
  raise exception 'Private completion implementation differs from reviewed Preview baseline';
 end if;
 if (select md5(string_agg(p.proname||'('||pg_get_function_identity_arguments(p.oid)||'):'||md5(replace(p.prosrc,E'\\r','')),E'\\n' order by p.proname,pg_get_function_identity_arguments(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f')
   is distinct from '8e6b6ae7821c6da5e3d48ceb903b5571' then
  raise exception 'Preview function catalog differs from reviewed baseline';
 end if;
 if (select md5(string_agg(c.relname||':'||a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text||':'||a.attgenerated::text||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),''),E'\\n' order by c.relname,a.attnum)) from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where n.nspname='public' and c.relkind='r')
   is distinct from '885783cc1f08ec588ec4f2ead6fa901d' then
  raise exception 'Preview column catalog differs from reviewed baseline';
 end if;
end;$preflight$;
create temp table release1_rollout_snapshot(relation text primary key,row_count bigint,digest text) on commit drop;
do $snapshot$
declare item record; ignored text[]; count_rows bigint; digest_rows text;
begin
 for item in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where (n.nspname='public' and c.relkind='r') or (n.nspname='auth' and c.relname='users') order by n.nspname,c.relname loop
  execute format('lock table %I.%I in share row exclusive mode',item.nspname,item.relname);
  ignored:=case when item.relname='work_order_financial_controls' then array['policy_version_id','updated_at']
    when item.relname='commercial_approval_rules' then array['policy_version_id'] else array[]::text[] end;
  execute format('select count(*),md5(coalesce(string_agg((to_jsonb(t)-$1)::text,E''\\n'' order by (to_jsonb(t)-$1)::text),'''')) from %I.%I t',item.nspname,item.relname)
    into count_rows,digest_rows using ignored;
  insert into release1_rollout_snapshot values(format('%I.%I',item.nspname,item.relname),count_rows,digest_rows);
 end loop;
end;$snapshot$;
-- Reconcile the dated Preview private implementation to canonical 0040.
${completionRepair}
revoke all on function public.submit_physical_completion_20260921_core(uuid,jsonb) from public,anon,authenticated,service_role;
-- Managed event-trigger helper is not an application RPC. Preserve it for the
-- database owner while removing inherited PUBLIC/application execution.
revoke all on function public.rls_auto_enable() from public,anon,authenticated,service_role;
${bodies.join('\n')}
do $preservation$
declare item record; ignored text[]; count_rows bigint; digest_rows text;
begin
 for item in select * from release1_rollout_snapshot loop
  ignored:=case when item.relation='public.work_order_financial_controls' then array['policy_version_id','updated_at']
    when item.relation='public.commercial_approval_rules' then array['policy_version_id'] else array[]::text[] end;
  execute format('select count(*),md5(coalesce(string_agg((to_jsonb(t)-$1)::text,E''\\n'' order by (to_jsonb(t)-$1)::text),'''')) from %s t',item.relation)
    into count_rows,digest_rows using ignored;
  if count_rows is distinct from item.row_count or digest_rows is distinct from item.digest then
    raise exception 'Historical row preservation failed: %',item.relation;
  end if;
 end loop;
end;$preservation$;
${selected.map((file, index) => {
  const name = path.basename(file, '.sql');
  const version = name.split('_')[0];
  const executedSource = (index === 0 ? `${completionRepair}\nrevoke all on function public.submit_physical_completion_20260921_core(uuid,jsonb) from public,anon,authenticated,service_role;\nrevoke all on function public.rls_auto_enable() from public,anon,authenticated,service_role;\n` : '') + bodies[index];
  return `insert into supabase_migrations.schema_migrations(version,name,statements) values('${version}','${name.slice(version.length + 1)}',array['${executedSource.replaceAll("'", "''")}']);`;
}).join('\n')}
commit;
`;
const output = process.argv[2];
if (!output) throw new Error('Pass an explicit output SQL path; this builder never connects to a database.');
writeFileSync(output, sql);
console.log(`Built ${selected.length} targeted changes: ${output}`);

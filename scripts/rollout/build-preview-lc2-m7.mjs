import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Preview-only incremental adapter for WP-LC2-M7 (D-11), applied on top of the 21 Oct 2026
// Lifecycle v2 upgrade (ledger ends at 20261020110000). Builds SQL only; never connects.
const root = fileURLToPath(new URL('../../', import.meta.url));
const baseline = JSON.parse(readFileSync(new URL('./preview-baseline.json', import.meta.url), 'utf8'));
const file = 'supabase/migrations/20261022120000_lifecycle_v2_facility_settings.sql';
const manifest = readFileSync(path.join(root, 'supabase/bootstrap/fresh-install-manifest.txt'), 'utf8')
  .split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
if (manifest.at(-1) !== file || manifest.at(-2) !== 'supabase/migrations/20261020110000_lifecycle_v2_site_location.sql') {
  throw new Error('Candidate manifest changed; independently review this adapter.');
}
const source = readFileSync(path.join(root, file), 'utf8');
if ((source.match(/^begin;\s*$/gmi) || []).length !== 1 || (source.match(/^commit;\s*$/gmi) || []).length !== 1) {
  throw new Error(`Unexpected transaction structure: ${file}`);
}
const body = source.replace(/^begin;\s*$/gmi, '').replace(/^commit;\s*$/gmi, '');
const name = path.basename(file, '.sql');
const version = name.split('_')[0];
const sql = `-- Preview-only incremental adapter: ${path.basename(file)} (source sha256 ${createHash('sha256').update(source).digest('hex')}).
-- NEVER run against Production. Caller must independently verify the connection host/project
-- before setting fmworks.rollout_project_ref. This setting is an assertion, not server identity.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_catalog.pg_advisory_xact_lock(610110841);
do $preflight$
declare latest text; total integer;
begin
 if current_setting('fmworks.rollout_project_ref',true) is distinct from '${baseline.project_ref}' then
  raise exception 'Explicit Preview target assertion required';
 end if;
 select max(version::text), count(*) into latest, total from supabase_migrations.schema_migrations;
 if latest is distinct from '20261020110000' then
  raise exception 'Preview ledger ends at %, expected 20261020110000; stop and re-inspect', latest;
 end if;
 if to_regclass('public.facility_settings') is not null or to_regprocedure('public.endorse_work_order(uuid,text)') is not null then
  raise exception 'M7 objects already exist; partial/repeated rollout refused';
 end if;
 raise notice 'Preflight passed: % ledger entries, latest %', total, latest;
end;$preflight$;
-- SOURCE: ${file}
${body}
insert into supabase_migrations.schema_migrations(version,name,statements) values('${version}','${name.slice(version.length + 1)}',array['${body.replaceAll("'", "''")}']);
commit;
`;
const output = process.argv[2];
if (!output) throw new Error('Pass an explicit output SQL path; this builder never connects to a database.');
writeFileSync(output, sql);
console.log(`Built M7 adapter (${version}): ${output} sha256 ${createHash('sha256').update(sql).digest('hex')}`);

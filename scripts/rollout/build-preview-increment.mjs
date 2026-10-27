import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Preview-only incremental adapter: applies, in one transaction, every manifest migration after the
// version Preview's ledger currently ends at (default 20261022120000, the WP-LC2-M7 upgrade of 24 Oct 2026).
// Usage: node scripts/rollout/build-preview-increment.mjs <output.sql> [expected-latest-version]
// Builds SQL only; never connects.
const root = fileURLToPath(new URL('../../', import.meta.url));
const baseline = JSON.parse(readFileSync(new URL('./preview-baseline.json', import.meta.url), 'utf8'));
const output = process.argv[2];
const expectedLatest = process.argv[3] ?? '20261022120000';
if (!output) throw new Error('Pass an explicit output SQL path; this builder never connects to a database.');
if (!/^\d{14}$/.test(expectedLatest)) throw new Error('Expected latest version must be 14 digits.');
const manifest = readFileSync(path.join(root, 'supabase/bootstrap/fresh-install-manifest.txt'), 'utf8')
  .split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
const start = manifest.findIndex(file => path.basename(file).startsWith(`${expectedLatest}_`));
if (start < 0) throw new Error(`Manifest has no migration ${expectedLatest}.`);
const files = manifest.slice(start + 1);
if (files.length === 0) throw new Error('Nothing to apply after ' + expectedLatest + '.');
const parts = files.map(file => {
  const source = readFileSync(path.join(root, file), 'utf8');
  if ((source.match(/^begin;\s*$/gmi) || []).length !== 1 || (source.match(/^commit;\s*$/gmi) || []).length !== 1) {
    throw new Error(`Unexpected transaction structure: ${file}`);
  }
  const body = source.replace(/^begin;\s*$/gmi, '').replace(/^commit;\s*$/gmi, '');
  const name = path.basename(file, '.sql');
  const version = name.split('_')[0];
  return { file, source, body, name, version };
});
const versions = parts.map(part => `'${part.version}'`).join(',');
const sql = `-- Preview-only incremental adapter after ${expectedLatest}: ${parts.map(part => part.name).join(', ')}.
${parts.map(part => `-- ${part.name}: source sha256 ${createHash('sha256').update(part.source).digest('hex')}`).join('\n')}
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
 if latest is distinct from '${expectedLatest}' then
  raise exception 'Preview ledger ends at %, expected ${expectedLatest}; stop and re-inspect', latest;
 end if;
 if exists(select 1 from supabase_migrations.schema_migrations where version in (${versions})) then
  raise exception 'Some of these migrations are already recorded; partial/repeated rollout refused';
 end if;
 raise notice 'Preflight passed: % ledger entries, latest %; applying ${parts.length} migration(s)', total, latest;
end;$preflight$;
${parts.map(part => `-- SOURCE: ${part.file}\n${part.body}\ninsert into supabase_migrations.schema_migrations(version,name,statements) values('${part.version}','${part.name.slice(part.version.length + 1)}',array['${part.body.replaceAll("'", "''")}']);`).join('\n')}
commit;
`;
writeFileSync(output, sql);
console.log(`Built incremental adapter (${parts.map(part => part.version).join(', ')}): ${output} sha256 ${createHash('sha256').update(sql).digest('hex')}`);

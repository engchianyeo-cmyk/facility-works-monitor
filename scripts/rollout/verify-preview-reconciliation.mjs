// Supplementary WASM PostgreSQL verification. Native runner remains a separate gate.
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
const root = fileURLToPath(new URL('../../', import.meta.url));
const packageRoot = process.env.PGLITE_PACKAGE_ROOT;
if (!packageRoot) throw new Error('Set PGLITE_PACKAGE_ROOT to a separate @electric-sql/pglite 0.5.8 installation.');
const metadata = JSON.parse(readFileSync(path.join(packageRoot, 'package.json'), 'utf8'));
if (metadata.version !== '0.5.8') throw new Error('Review a changed supplementary runtime version before use.');
const { PGlite } = await import(pathToFileURL(path.join(packageRoot, 'dist/index.js')));
const { pgcrypto } = await import(pathToFileURL(path.join(packageRoot, 'dist/contrib/pgcrypto.js')));
const db = new PGlite({ extensions: { pgcrypto } });
const temporary = mkdtempSync(path.join(tmpdir(), 'fmworks-preview-reconciliation-'));
const keepAlive = setInterval(() => {}, 1000);
const clean = source => source.replace(/^\\gset.*$/gm, ';').replace(/^\\.*$/gm, '');
async function apply(file) {
  try { await db.exec(clean(readFileSync(path.join(root, file), 'utf8'))); }
  catch (error) { throw new Error(`${file}: ${error.message}`); }
  console.log(`PASS ${file}`);
}
async function rejected(sql, message) {
  let failure;
  try { await db.exec(sql); } catch (error) { failure = error; }
  await db.exec('rollback;');
  if (!failure || !failure.message.includes(message)) throw new Error(`Expected rejection: ${message}; received ${failure?.message}`);
  console.log(`PASS rejection: ${message}`);
}
async function baselineIntact() {
  const result = await db.query("select to_regclass('public.procurement_policy_versions') is null and (select count(*) from supabase_migrations.schema_migrations)=38 and md5(pg_get_functiondef('public.submit_physical_completion_20260921_core(uuid,jsonb)'::regprocedure))='cd2acebf0a8431824eae03b90e71a410' as intact");
  if (!result.rows[0].intact) throw new Error('Failed rollout changed schema, private implementation or ledger');
}
try {
  await apply('tests/sql/0021_supabase_managed_prerequisite.sql');
  await apply('tests/sql/fixtures/preview_20261011_schema.sql');
  await apply('tests/sql/fixtures/preview_20261011_acl.sql');
  await apply('supabase/migrations/0024_department_master_data_baseline.sql');
  await apply('tests/sql/preview_reconciliation_seed.sql');
  await apply('supabase/uat/008_work_order_uat_dataset.sql');
  await apply('tests/sql/preview_reconciliation_populated_controls.sql');
  const baseline = JSON.parse(readFileSync(path.join(root, 'scripts/rollout/preview-baseline.json'), 'utf8'));
  for (const version of baseline.versions) await db.query('insert into supabase_migrations.schema_migrations(version) values($1)', [version]);
  const output = path.join(temporary, 'adapter.sql');
  execFileSync(process.execPath, [path.join(root, 'scripts/rollout/build-preview-reconciliation.mjs'), output]);
  const adapter = readFileSync(output, 'utf8');
  await db.exec("select set_config('fmworks.rollout_project_ref','WRONG_PROJECT',false)");
  await rejected(adapter, 'Explicit Preview target assertion required');
  await baselineIntact();
  await db.exec("select set_config('fmworks.rollout_project_ref','pvajuywwwpjlikqjnvgv',false); insert into supabase_migrations.schema_migrations(version) values('UNREVIEWED');");
  await rejected(adapter, 'ledger differs from reviewed baseline');
  await db.exec("delete from supabase_migrations.schema_migrations where version='UNREVIEWED'; create function public.unreviewed_change() returns integer language sql as 'select 1';");
  await rejected(adapter, 'function catalog differs from reviewed baseline');
  await db.exec('drop function public.unreviewed_change();');
  await rejected(adapter.replace('do $preservation$', 'select 1/0;\ndo $preservation$'), 'division by zero');
  await baselineIntact();
  await rejected(adapter.replace('do $preservation$', "update public.work_orders set title='Unexpected rollout mutation' where id='08000000-0000-4000-8000-000000000003';\ndo $preservation$"), 'Historical row preservation failed');
  await baselineIntact();
  await db.exec(adapter);
  console.log('PASS atomic reconciliation with populated identity, Work Order, evidence, commercial and audit preservation');
  await rejected(adapter, 'ledger differs from reviewed baseline');
  for (const suite of ['release_1_field_owner_isolation', 'configurable_procurement_policy', 'audited_contractor_administration', 'release_1_security_catalog', 'release_1_three_quotation_current_schema', 'release_1_financial_current_schema', 'release_1_commercial_scope', 'release_1_incident_evidence_lifecycle', 'release_1_incident_terminal_authority']) {
    await apply(`tests/sql/${suite}.test.sql`);
  }
  console.log('PASS supplementary Preview reconciliation gate; NOT native Docker, hosted rollout or browser UAT');
} finally {
  await db.close();
  clearInterval(keepAlive);
  rmSync(temporary, { recursive: true, force: true });
}

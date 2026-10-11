# FMWorks Release-1 Preview reconciliation preparation

Timestamp: 11 October 2026, 08:57 SGT (Asia/Singapore).
Published source: `c72227414bc3b801f5a64aeb3abc50a342f450da`, draft PR #6.
Local repair branch: `codex/preview-schema-reconciliation`. This increment is unpublished.

## Result

Prepared a targeted, atomic Preview adapter and passed supplementary isolated
PostgreSQL/WASM verification against a schema-only copy of the live Preview
public catalog. Native PostgreSQL execution and hosted UAT remain outstanding.
No hosted database was mutated, no push/merge/PR closure occurred, and Production
was not queried or changed.

## Grounded baseline

Live read-only inspection confirmed Preview `pvajuywwwpjlikqjnvgv` has 38 ledger
entries ending at `20260924045239`, 18 Work Orders and 0 Incidents. Dated
historical migrations overlap the canonical numbered history. The adapter skips
that history and reuses the 11 immutable reconciliation/post-baseline migrations
from the candidate manifest. It does not bootstrap or blindly replay the manifest.

The existing `pilot_account_ready(uuid DEFAULT auth.uid())` supports zero-argument
calls. Absence of a separate zero-argument function is not a readiness defect;
the adapter preserves the existing readiness function.

## Defects found by testing the actual Preview schema

1. The private `submit_physical_completion_20260921_core` still required the
   Technician role. The four-role wrapper alone could not enable physical
   completion for assigned Supervisor/Facility Manager/Administrator actors.
   The adapter restores only that private implementation from canonical 0040,
   while retaining wrapper costing checks and denying direct application EXECUTE.
   The four-role positive/negative regression then passed.
2. The managed `rls_auto_enable()` event-trigger helper inherited application
   EXECUTE through PUBLIC. The adapter preserves the function but removes
   PUBLIC/anon/authenticated/service_role EXECUTE, resolving the security catalog
   gate. This is an ACL discrepancy; exploitability was not asserted.

## Adapter controls

- Explicit Preview project assertion; the caller must independently verify the
  actual connection host. A custom setting is not cryptographic server identity.
- Exact reviewed ledger, normalized function-source fingerprint, column catalog
  fingerprint and private completion definition guard. Changed/partial/repeated
  targets fail closed.
- One transaction, an advisory lock, deterministic locks on existing public
  tables and auth.users, bounded lock/statement timeouts.
- Row-count and row-content digests across every existing public table and
  auth.users. Only the intended new procurement policy column and financial
  control updated_at side effect are excluded. Work Orders, identities, evidence,
  audit and existing financial decisions must remain intact.
- Ledger additions occur after preservation checks in the same transaction.

## Executed checks

Supplementary runtime: separately installed `@electric-sql/pglite` 0.5.8 with
pgcrypto. The schema fixture reproduces live public tables, generated columns,
constraints, indexes, views (including security_invoker), functions, policies,
triggers and application ACLs. Owner identities, managed Auth/Storage service
internals, event-trigger installation, physical Storage objects and real hosted
rows are not cloned; their contracts use the existing minimal test prerequisite.
Synthetic identities, 15 Work Orders (including terminal history), assets, audit,
historical evidence, financial controls and quotation bands exercise preservation.

PASS: explicit wrong-target rejection; changed ledger rejection; changed function
catalog rejection; injected late SQL failure with schema/function/ledger rollback;
unexpected historical-row mutation detection with rollback; successful atomic
adapter; repeat-run rejection.

All nine current-schema SQL suites PASS:

- field-owner isolation and assigned four-role physical completion;
- configurable procurement policy;
- audited contractor administration;
- security catalog;
- three-quotation controls;
- financial controls;
- commercial scope isolation;
- Incident evidence lifecycle;
- Incident terminal authority, including inactive/unassigned negatives.

JavaScript syntax checks, focused ESLint and shell syntax checks PASS.
No UI/API application source was changed; the published candidate's Run #24
remains its independent native 796-unit/API-test and 29-browser-test evidence.
Those results do not certify this unpublished adapter.

## Reproduction

Generate SQL without connecting to a database:

```sh
node scripts/rollout/build-preview-reconciliation.mjs /tmp/fmworks-preview-adapter.sql
```

Supplementary verification, using a separate PGlite 0.5.8 installation:

```sh
PGLITE_PACKAGE_ROOT=/absolute/path/to/node_modules/@electric-sql/pglite node scripts/rollout/verify-preview-reconciliation.mjs
```

Native verification requires an empty disposable database and an explicit local
socket/host; the runner refuses other database names and hosted hostnames:

```sh
PGHOST=/absolute/local/socket TEST_DATABASE=fmworks_preview_reconcile_test TEST_WORKSPACE="$PWD" sh tests/sql/run_release1_preview_reconciliation.sh
```

The current runtime lacks Docker/psql. PostgreSQL package installation failed
because the system package cache is not writable. The native runner is prepared
and shell-checked, but has NOT executed. This is the next verification blocker;
no native pass or hosted rollout readiness is claimed.

After native success: review the complete generated SQL and incremental rollback
plan, confirm the real Preview host and backup, and then apply the adapter to
Preview under the authorized rollout scope. Obtain protected Vercel access and
perform hosted role/browser UAT before sign-off. Emergency exception policy and
operational email scope remain owner decisions.

Final live read-only check at 08:57 SGT still showed ledger `20260924045239`,
18 Work Orders, 0 Incidents and absent candidate policy/evidence-removal objects.

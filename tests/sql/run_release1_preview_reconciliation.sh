#!/bin/sh
set -eu
ROOT=${TEST_WORKSPACE:-/workspace}
case ${TEST_DATABASE:-} in fmworks_preview_reconcile_*) ;; *) echo 'Use an explicitly named disposable fmworks_preview_reconcile_* database'; exit 1 ;; esac
case ${PGHOST:-} in /*|localhost|127.0.0.1) ;; *) echo 'Use an explicit local PostgreSQL socket/host; hosted databases are forbidden'; exit 1 ;; esac
PSQL="psql -X -v ON_ERROR_STOP=1 -U postgres -d $TEST_DATABASE"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
$PSQL -f "$ROOT/tests/sql/0021_supabase_managed_prerequisite.sql"
$PSQL -f "$ROOT/tests/sql/fixtures/preview_20261011_schema.sql"
$PSQL -f "$ROOT/tests/sql/fixtures/preview_20261011_acl.sql"
$PSQL -f "$ROOT/supabase/migrations/0024_department_master_data_baseline.sql"
$PSQL -f "$ROOT/tests/sql/preview_reconciliation_seed.sql"
$PSQL -f "$ROOT/supabase/uat/008_work_order_uat_dataset.sql"
$PSQL -f "$ROOT/tests/sql/preview_reconciliation_populated_controls.sql"
node "$ROOT/scripts/rollout/build-preview-reconciliation.mjs" "$TEMP_DIR/adapter.sql"
node -e 'const fs=require("fs");const b=JSON.parse(fs.readFileSync(process.argv[1]));console.log(b.versions.map(v=>`insert into supabase_migrations.schema_migrations(version) values (${String.fromCharCode(39)}${v}${String.fromCharCode(39)});`).join("\n"));' "$ROOT/scripts/rollout/preview-baseline.json" > "$TEMP_DIR/ledger.sql"
$PSQL -f "$TEMP_DIR/ledger.sql"
if $PSQL -c "select set_config('fmworks.rollout_project_ref','WRONG_PROJECT',false)" -f "$TEMP_DIR/adapter.sql" > "$TEMP_DIR/wrong-target.log" 2>&1; then
 echo 'FAIL: wrong project assertion accepted'; exit 1
fi
rg -q 'Explicit Preview target assertion required' "$TEMP_DIR/wrong-target.log"
echo 'PASS: wrong target rejected'
awk '/^do \$preservation\$/{print "select 1/0;"} {print}' "$TEMP_DIR/adapter.sql" > "$TEMP_DIR/late-failure.sql"
if $PSQL -c "select set_config('fmworks.rollout_project_ref','pvajuywwwpjlikqjnvgv',false)" -f "$TEMP_DIR/late-failure.sql" > "$TEMP_DIR/late-failure.log" 2>&1; then
 echo 'FAIL: injected late failure accepted'; exit 1
fi
rg -q 'division by zero' "$TEMP_DIR/late-failure.log"
$PSQL -c "do \$check\$ begin if to_regclass('public.procurement_policy_versions') is not null or (select count(*) from supabase_migrations.schema_migrations)<>38 or md5(pg_get_functiondef('public.submit_physical_completion_20260921_core(uuid,jsonb)'::regprocedure))<>'cd2acebf0a8431824eae03b90e71a410' then raise exception 'Rollback failed'; end if; end; \$check\$;"
echo 'PASS: late failure rolls back schema, function repair and ledger'
$PSQL -c "select set_config('fmworks.rollout_project_ref','pvajuywwwpjlikqjnvgv',false)" -f "$TEMP_DIR/adapter.sql"
echo 'PASS: atomic adapter and populated row preservation'
if $PSQL -c "select set_config('fmworks.rollout_project_ref','pvajuywwwpjlikqjnvgv',false)" -f "$TEMP_DIR/adapter.sql" > "$TEMP_DIR/repeat.log" 2>&1; then
 echo 'FAIL: repeated rollout accepted'; exit 1
fi
rg -q 'ledger differs from reviewed baseline' "$TEMP_DIR/repeat.log"
echo 'PASS: repeated rollout rejected'
for file in release_1_field_owner_isolation configurable_procurement_policy audited_contractor_administration release_1_security_catalog release_1_three_quotation_current_schema release_1_financial_current_schema release_1_commercial_scope release_1_incident_evidence_lifecycle release_1_incident_terminal_authority; do
 $PSQL -f "$ROOT/tests/sql/$file.test.sql"
 echo "PASS: $file"
done

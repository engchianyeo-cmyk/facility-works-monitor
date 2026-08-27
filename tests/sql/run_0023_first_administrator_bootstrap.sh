#!/bin/sh
set -eu

TEST_DATABASE="${TEST_DATABASE:-postgres}"
PSQL="psql -X -v ON_ERROR_STOP=1 -U postgres -d $TEST_DATABASE"

$PSQL -f /workspace/tests/sql/0021_supabase_managed_prerequisite.sql
$PSQL -f /workspace/supabase/bootstrap/fmworks_pre_0012_bootstrap.sql
$PSQL -f /workspace/supabase/migrations/0012_department_management_foundation.sql
$PSQL -f /workspace/supabase/migrations/0013_core_work_order_engine.sql
$PSQL -f /workspace/supabase/migrations/0014_emergency_incident_management.sql
$PSQL -f /workspace/supabase/migrations/0015_incident_safe_projection_and_roster_api.sql
$PSQL -f /workspace/supabase/migrations/0016_secure_field_evidence.sql
$PSQL -f /workspace/supabase/migrations/0017_work_order_completion_rework.sql
$PSQL -f /workspace/supabase/migrations/0018_asset_registry_foundation.sql
$PSQL -f /workspace/supabase/migrations/0019_preventive_maintenance_foundation.sql
$PSQL -f /workspace/supabase/migrations/0020_pilot_identity_trust_hardening.sql
$PSQL -f /workspace/supabase/migrations/0021_fresh_install_trust_contract_repair.sql
$PSQL -f /workspace/supabase/migrations/0022_uat_material_defect_remediation.sql
$PSQL -f /workspace/supabase/migrations/0023_first_administrator_bootstrap.sql
$PSQL -f /workspace/tests/sql/0023_first_administrator_bootstrap.test.sql

#!/bin/sh
set -eu

PSQL="psql -v ON_ERROR_STOP=1 -U postgres -d postgres"

$PSQL -f /workspace/tests/sql/0014_prerequisite_schema.sql
$PSQL -f /workspace/tests/sql/0020_pilot_identity_prerequisite.sql
$PSQL -f /workspace/supabase/migrations/0012_department_management_foundation.sql
$PSQL -f /workspace/supabase/migrations/0013_core_work_order_engine.sql
$PSQL -f /workspace/supabase/migrations/0014_emergency_incident_management.sql
$PSQL -f /workspace/supabase/migrations/0015_incident_safe_projection_and_roster_api.sql
$PSQL -f /workspace/tests/sql/0016_storage_prerequisite.sql
$PSQL -f /workspace/supabase/migrations/0016_secure_field_evidence.sql
$PSQL -f /workspace/supabase/migrations/0017_work_order_completion_rework.sql

# Preserve the 0018 legacy-orphan regression in a post-0017 clone, then bring
# that clone through 0018-0020 before its assertions.
createdb -U postgres -T postgres regression_0018
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0018 -f /workspace/tests/sql/0018_orphan_asset_prerequisite.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0018 -f /workspace/supabase/migrations/0018_asset_registry_foundation.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0018 -f /workspace/supabase/migrations/0019_preventive_maintenance_foundation.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0018 -f /workspace/supabase/migrations/0020_pilot_identity_trust_hardening.sql

$PSQL -f /workspace/supabase/migrations/0018_asset_registry_foundation.sql
$PSQL -f /workspace/supabase/migrations/0019_preventive_maintenance_foundation.sql
$PSQL -f /workspace/supabase/migrations/0020_pilot_identity_trust_hardening.sql

for TEST_NAME in 0013 0014 0016 0017 0019 0020; do
  createdb -U postgres -T postgres "regression_${TEST_NAME}"
done

psql -v ON_ERROR_STOP=1 -U postgres -d regression_0013 -f /workspace/tests/sql/0013_core_work_order_engine.test.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0014 -f /workspace/tests/sql/0014_emergency_incident_management.test.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0016 -f /workspace/tests/sql/0016_secure_field_evidence.test.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0017 -f /workspace/tests/sql/0017_work_order_completion_rework.test.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0018 -f /workspace/tests/sql/0018_asset_registry_foundation.test.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0019 -f /workspace/tests/sql/0019_preventive_maintenance_foundation.test.sql
psql -v ON_ERROR_STOP=1 -U postgres -d regression_0020 -f /workspace/tests/sql/0020_pilot_identity_trust_hardening.test.sql

#!/bin/sh
set -eu
PSQL="psql -X -v ON_ERROR_STOP=1 -U postgres -d ${TEST_DATABASE:-postgres}"
$PSQL -f /workspace/tests/sql/0021_supabase_managed_prerequisite.sql
$PSQL -f /workspace/supabase/bootstrap/fmworks_pre_0012_bootstrap.sql
for number in 0012 0013 0014 0015 0016 0017 0018 0019 0020 0021 0022 0023 0024 0025 0026 0027;do migration=$(find /workspace/supabase/migrations -maxdepth 1 -name "${number}_*.sql"|head -n 1);$PSQL -f "$migration";done
$PSQL -f /workspace/tests/sql/0027_enterprise_ai_document_gateway.test.sql

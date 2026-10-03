#!/bin/sh
set -eu
ROOT=${TEST_WORKSPACE:-/workspace}
PSQL="psql -X -v ON_ERROR_STOP=1 -U postgres -d ${TEST_DATABASE:-postgres}"
$PSQL -f "$ROOT/tests/sql/0021_supabase_managed_prerequisite.sql"
# Build only the pre-Release-1 schema, then populate it before upgrading.
manifest="$ROOT/supabase/bootstrap/fresh-install-manifest.txt"
sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$manifest" |
while IFS= read -r path; do
 case "$path" in supabase/migrations/0028_*) break ;; esac
 $PSQL -f "$ROOT/$path"
done
$PSQL -f "$ROOT/tests/sql/release_1_populated_preview_seed.sql"
sed -n '/^supabase\/migrations\/0028_/,$p' "$manifest" |
sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' |
while IFS= read -r path; do
 $PSQL -f "$ROOT/$path"
done
$PSQL -f "$ROOT/tests/sql/release_1_populated_preview_upgrade.test.sql"

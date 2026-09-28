#!/bin/sh
set -eu

PSQL="psql -X -q -v ON_ERROR_STOP=1 -U postgres"
ROOT=/workspace

new_database() {
  database=$1
  createdb -U postgres "$database"
  $PSQL -d "$database" -f "$ROOT/tests/sql/0021_supabase_managed_prerequisite.sql"
}

expect_failure() {
  label=$1
  sql_file=$2
  database=$3
  if $PSQL -d "$database" -f "$sql_file" >/dev/null 2>&1; then
    echo "$label unexpectedly succeeded" >&2
    exit 1
  fi
  echo "$label: PASS"
}

# A. Empty Auth retains the normal bootstrap behavior.
new_database empty_auth
$PSQL -d empty_auth -f "$ROOT/supabase/bootstrap/fmworks_pre_0012_bootstrap.sql"
$PSQL -d empty_auth -f "$ROOT/tests/sql/fmworks_pre_0012_bootstrap.test.sql"
echo "empty Auth normal bootstrap: PASS"

# B. Non-empty Auth without explicit preservation still fails.
new_database default_refusal
$PSQL -d default_refusal -c "insert into auth.users(id,email,raw_user_meta_data) values ('b1000000-0000-4000-8000-000000000001','synthetic-a@example.test','{}'::jsonb)"
expect_failure "non-empty Auth default refusal" "$ROOT/supabase/bootstrap/fmworks_pre_0012_bootstrap.sql" default_refusal

make_case_sql() {
  output=$1
  mode=$2
  cat > "$output" <<SQL
\\set ON_ERROR_STOP on
create temporary table pg_temp.fmworks_preserved_auth_ids(id uuid primary key);
$mode
select pg_catalog.set_config('fmworks.auth_preservation_mode','on',false);
\\ir $ROOT/supabase/bootstrap/fmworks_pre_0012_bootstrap.sql
SQL
}

# D/E. Exact-set mismatches fail before application objects are created.
new_database missing_user
$PSQL -d missing_user -c "insert into auth.users(id,email,raw_user_meta_data) values ('b1000000-0000-4000-8000-000000000001','synthetic-a@example.test','{}'),('b1000000-0000-4000-8000-000000000002','synthetic-b@example.test','{}')"
make_case_sql /tmp/missing-user.sql "insert into pg_temp.fmworks_preserved_auth_ids values ('b1000000-0000-4000-8000-000000000001');"
expect_failure "missing allowlisted user" /tmp/missing-user.sql missing_user

new_database unexpected_user
$PSQL -d unexpected_user -c "insert into auth.users(id,email,raw_user_meta_data) values ('b1000000-0000-4000-8000-000000000001','synthetic-a@example.test','{}')"
make_case_sql /tmp/unexpected-user.sql "insert into pg_temp.fmworks_preserved_auth_ids values ('b1000000-0000-4000-8000-000000000001'),('b1000000-0000-4000-8000-000000000002');"
expect_failure "unexpected allowlisted user" /tmp/unexpected-user.sql unexpected_user

# C/G-K. Complete preserved-user chain in one session with two synthetic users.
new_database preserved_auth
$PSQL -d preserved_auth -c "insert into auth.users(id,email,raw_user_meta_data) values ('b1000000-0000-4000-8000-000000000001','synthetic-a@example.test','{}'),('b1000000-0000-4000-8000-000000000002','synthetic-b@example.test','{}')"
cat > /tmp/preserved-chain.sql <<SQL
\\set ON_ERROR_STOP on
create temporary table pg_temp.fmworks_preserved_auth_ids(id uuid primary key);
insert into pg_temp.fmworks_preserved_auth_ids values
  ('b1000000-0000-4000-8000-000000000001'),
  ('b1000000-0000-4000-8000-000000000002');
select pg_catalog.set_config('fmworks.auth_preservation_mode','on',false);
SQL
while IFS= read -r path; do
  case "$path" in ''|'#'*) continue ;; esac
  printf '\\ir %s/%s\n' "$ROOT" "$path" >> /tmp/preserved-chain.sql
done < "$ROOT/supabase/bootstrap/auth-preserving-fresh-install-manifest.txt"
printf '\\ir %s/tests/sql/auth_preserving_fresh_install.test.sql\n' "$ROOT" >> /tmp/preserved-chain.sql
$PSQL -d preserved_auth -f /tmp/preserved-chain.sql
echo "two-user auth-preserving complete chain: PASS"

# F/L. The public runner validates syntax/duplicates before psql and 0011 is absent.
printf '%s\n' 'not-a-uuid' > /tmp/malformed-allowlist
if "$ROOT/supabase/bootstrap/run_auth_preserving_fresh_install.sh" /tmp/malformed-allowlist >/dev/null 2>&1; then
  echo "malformed allowlist unexpectedly succeeded" >&2; exit 1
fi
printf '%s\n%s\n' 'b1000000-0000-4000-8000-000000000001' 'b1000000-0000-4000-8000-000000000001' > /tmp/duplicate-allowlist
if "$ROOT/supabase/bootstrap/run_auth_preserving_fresh_install.sh" /tmp/duplicate-allowlist >/dev/null 2>&1; then
  echo "duplicate allowlist unexpectedly succeeded" >&2; exit 1
fi
if grep -Eq '(^|/)0011_' "$ROOT/supabase/bootstrap/auth-preserving-fresh-install-manifest.txt"; then
  echo "historical migration 0011 is present" >&2; exit 1
fi
echo "malformed and duplicate allowlists refused: PASS"
echo "historical migration 0011 excluded: PASS"

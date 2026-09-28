#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <uncommitted-uuid-allowlist-file>" >&2
  exit 64
fi

ALLOWLIST_FILE=$1
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
if [ ! -f "$ALLOWLIST_FILE" ] || [ ! -s "$ALLOWLIST_FILE" ]; then
  echo "auth-preserving allowlist must be a non-empty file" >&2
  exit 65
fi

NORMALIZED_FILE=$(mktemp)
SQL_FILE=$(mktemp)
trap 'rm -f "$NORMALIZED_FILE" "$SQL_FILE"' EXIT HUP INT TERM

awk '
  !/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/ { exit 1 }
  { print tolower($0) }
' "$ALLOWLIST_FILE" > "$NORMALIZED_FILE" || {
  echo "auth-preserving allowlist contains a malformed UUID" >&2
  exit 65
}

if [ "$(sort "$NORMALIZED_FILE" | uniq -d | wc -l | tr -d ' ')" -ne 0 ]; then
  echo "auth-preserving allowlist contains a duplicate UUID" >&2
  exit 65
fi

{
  printf '%s\n' '\set ON_ERROR_STOP on'
  printf '%s\n' 'create temporary table pg_temp.fmworks_preserved_auth_ids (id uuid primary key);'
  awk '{ printf "insert into pg_temp.fmworks_preserved_auth_ids(id) values (%c%s%c::uuid);\n", 39, $0, 39 }' "$NORMALIZED_FILE"
  printf '%s\n' "select pg_catalog.set_config('fmworks.auth_preservation_mode', 'on', false);"
  while IFS= read -r path; do
    case "$path" in ''|'#'*) continue ;; esac
    printf '\\ir %s/%s\n' "$REPOSITORY_ROOT" "$path"
  done < "$(dirname "$0")/auth-preserving-fresh-install-manifest.txt"
} > "$SQL_FILE"

# Credentials and identity values are never echoed. psql receives a generated,
# permission-local control script and fails immediately on the first SQL error.
psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres -f "$SQL_FILE"

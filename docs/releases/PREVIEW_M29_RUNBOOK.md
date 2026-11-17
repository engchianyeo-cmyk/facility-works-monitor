# Preview rollout runbook — M29 (Facility Administrators, Finance per facility, Remove personal details)

Prepared 16 November 2026 00:30 SGT for the owner to run with Claude's guidance. **Preview only
(`pvajuywwwpjlikqjnvgv`, "FMWorks Preview UAT"). Never Production (`pyapukytcrsuowmgzqzh`).**
Code: commit `2ae6ca3` on `uat/claude-review` (`release:verify` PASS 15 Nov 23:54).

## Already done (by Claude, nothing connected)

- `out/preview-increment-m29.sql` built with
  `node scripts/rollout/build-preview-increment.mjs out/preview-increment-m29.sql 20261110100000`
  (sha256 `36959c53e19fe3a181efa182eff45f4b760b6275c4738d8ce0777bee0bdb0433`).
- Rehearsed on a local PostgreSQL 16 copy built from the same migrations up to M28 (with a stand-in ledger ending at
  `20261110100000`): the increment applied and committed; a second run was refused ("ledger ends at
  20261115120000"); a run without the Preview assertion was refused; the Finance script's dry run worked; the
  `facility_administrators.test.sql` checks then passed.

## Steps (one at a time; stop at any surprise)

1. **Check the file is unchanged** (PowerShell, in `C:\Users\engch\fwm-uat`):
   `Get-FileHash out\preview-increment-m29.sql -Algorithm SHA256` must end `…bdb0433` (as above).
2. **Connect** with the Supabase CLI's temporary login, as for M28 on 10 Nov. **Check the host and user both name
   `pvajuywwwpjlikqjnvgv`** (`cli_login_postgres.pvajuywwwpjlikqjnvgv` at `aws-0-ap-southeast-1.pooler.supabase.com`)
   before running anything. Claude gives the exact commands at the time; no password is ever pasted in chat.
3. **Backup**: `pg_dump --role=postgres -n public -n supabase_migrations` to
   `.git\preview-backup-20261116-pre-m29.sql`; check the file is about 2.9 MB or more.
4. **Apply**: `psql -X -v ON_ERROR_STOP=1 -c "set role postgres" -c "set fmworks.rollout_project_ref='pvajuywwwpjlikqjnvgv'" -f out/preview-increment-m29.sql`.
   Expect "Preflight passed: 78 ledger entries, latest 20261110100000" and `COMMIT`.
5. **Finance → Facility One**: dry run
   `psql -X -c "set role postgres" -f scripts/rollout/preview-m29-finance-to-facility-one-20261115.sql`, read the list,
   then apply with `-v apply=yes`.
6. **Check in the app** (Vercel Preview Ready on `2ae6ca3`): Users shows the role "Super-Administrator" and the
   Create form offers "Facility Administrator" and a Facility box; Finance still sees Facility One's register.
7. **Record** each step in the ledger's Preview rollout record (16 November 2026).

## If something goes wrong

- Steps 1-3 change nothing. Step 4 is one transaction: an error before `COMMIT` leaves Preview unchanged.
- After `COMMIT`, the backup from step 3 is the way back; ask Claude before restoring anything.

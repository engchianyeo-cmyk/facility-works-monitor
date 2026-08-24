# FMWorks fresh database bootstrap

For a new, empty deployment only:

```text
Fresh Supabase
→ fmworks_pre_0012_bootstrap.sql
→ migrations 0012 through 0022 in exact order
→ schema, RLS, Storage and application regression
```

Use `fresh-install-manifest.txt` as an explicit allowlist. Do not point normal
migration discovery at the historical migration directory: migrations
`0001–0011` document prior schema evolution, `0010` deliberately refuses
execution, and `0011` is intentionally excluded.

The bootstrap refuses non-empty Auth state and representative existing FMWorks
objects. It contains no users, customer identities, demo work orders, activity
history, incidents, evidence or PM data. Reference categories are also omitted;
they are operational configuration, not a schema prerequisite.

An exceptional auth-preserving fresh install is available only through
`run_auth_preserving_fresh_install.sh`. It requires an external, uncommitted
file containing exactly one Auth UUID per line. The supplied UUID set must
exactly equal `auth.users`; missing, unexpected, malformed and duplicate values
fail closed. Normal bootstrap execution still refuses every non-empty Auth
database.

Preserved identities receive only an inactive `reviewer` quarantine profile
with `password_change_required = true`. Email, metadata, department, trade,
activation and elevated roles are not inferred. Establishing the first
Administrator requires a separate explicitly authorized and audited procedure.
Migration 0011 remains excluded from both manifests.

The runner uses one fail-fast PostgreSQL session and revalidates the exact Auth
set before bootstrap and reconciliation. Historical migrations 0012-0022 own
their committed transaction boundaries, so the complete chain cannot be one
atomic transaction without rewriting those immutable files. A failure rolls
back its current script and stops the chain; operators must treat any partial
installation as failed and reconcile from a verified disposable/empty target.
It never deletes `auth.users`.

Hosted migration-history reconciliation remains a separate release operation.
Supabase CLI repair and explicit ledger registration are both plausible, but
the method must be selected only after comparing the hosted ledger with the
executed bootstrap manifest. This runner does not write hosted migration
history.

Execute the manifest as the local `postgres` migration role. The bootstrap
normalizes that role's default privileges for future `public` objects so the
Supabase platform defaults cannot silently grant anonymous operational access;
later migrations grant each approved authenticated surface explicitly.

Migration `0021_fresh_install_trust_contract_repair.sql` is mandatory for a
fresh install. It restores the presence schema and final profile, deletion and
invitation trust boundaries expected by the application.

Migration `0022_uat_material_defect_remediation.sql` completes the current
fresh-install contract by repairing password-change reconciliation idempotency
and the authenticated PM compliance projection dependency.

Existing FMWorks databases must never use this bootstrap. They continue from
their recorded schema state using only separately approved incremental
migrations. Historical migrations remain repository provenance and must not be
deleted or rewritten.

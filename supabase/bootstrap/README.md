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

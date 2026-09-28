# Release 1.2 Source-Control Reconciliation

## Purpose

This is a proposed Release Candidate boundary, not staging or commit authorization. The worktree is materially dirty and all existing work must be reviewed before an immutable RC is created.

## Classification

| Classification | Current paths | RC decision |
|---|---|---|
| Release 1.2 product code | `app/page.tsx`, `app/operations/`, `app/incidents/`, `app/api/incidents/`, `app/administration/emergency-roster/`, `components/mission-control/`, `components/operations/`, `components/incidents/`, `components/ui/`, `components/site-header.tsx`, `lib/incidents/`, `lib/notifications/incident-centre.ts`, notification provider changes | Include only after scope/security review and exact diff approval |
| Release 1.2 database | tracked 0012/0013; untracked 0014/0015 | 0012/0013 are baseline; add reviewed 0014/0015; do not include 0010 in this release path |
| Release 1.2 tests | incident API/workflow/roster/projection/notification tests, Mission Control and Operations tests, `tests/sql/0014_*`, pre/post 0014 validation, schema fingerprint | Include with matching product/migration scope |
| Release 1.2 documentation | emergency/user/admin/role docs, core architecture/API/security/workflow updates, `docs/releases/` | Review for deployed-versus-local accuracy; include required release evidence |
| Product/commercial research | `docs/product/` | Documentation-only; may be included separately but is not runtime Release 1.2 proof |
| Legacy / conditional | `supabase/migrations/0011_secure_legacy_public_tables.sql` | Exclude from fresh Preview chain; retain for separate legacy-target review |
| Temporary / backup | `components/user-management.tsx.before-enterprise-user-management` | Exclude from RC; preserve until owner approves cleanup |
| Temporary / potentially destructive helper | `remove-old-invitation-ui.ps1` | Do not run or include without line-by-line review and explicit cleanup authority |
| Requires review | modified auth/identity design and security documents, `README.md`, root `README`, deleted `docs/FM Work Order Requirements.docx`, notification changes | Establish ownership and ensure no accidental loss or release-scope expansion |
| Unrelated | Stripe routes and untouched application areas | Exclude unless a diff proves a Release 1.2 dependency |

## Migration-source observations

- 0011, 0014 and 0015 are untracked and therefore absent from any reproducible commit.
- 0015 has no Git history; filesystem metadata dates it to 10 August 2026.
- The SQL prerequisite and 0014 test files are also untracked.
- A release cannot be identified by the current worktree; an RC requires an intentional, reviewed file manifest and commit.

## RC preparation gate

1. Assign an owner to every modified/untracked/deleted path.
2. Review diffs for auth, invitations and notification behavior separately from incident scope.
3. Resolve whether the deleted Word requirement is intentional; do not discard it automatically.
4. Exclude backup/helper artifacts unless explicitly approved.
5. Approve the migration manifest and hashes.
6. Re-run SQL/application validation from the exact candidate.
7. Record build identity, Preview project reference and schema fingerprint.
8. Only then stage an explicit manifest and create an RC commit under separate authorization.

No file was staged, committed, deleted or restored by WP-REL-002.

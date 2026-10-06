# FMWorks Release-1 reconciliation assurance update

**Date:** 28 September 2026 (Singapore) · **Exact source:** `codex/recreate-and-persist-fmworks-release-1-reconciliation` at `35b615f337199ab35c168bf3a25cd67c72d7f0d0` · **PR:** https://github.com/engchianyeo-cmyk/facility-works-monitor/pull/2 · **Decision:** NO GO for Production; PR review can proceed but merge readiness is not established.

This is a new recreated reconciliation commit. The earlier reported `fb6fce2...` commit was not available on GitHub. The PR targets `feature/playwright-authenticated-workflows` at `7cef8c4`; commit `35b615f` is a single-parent commit on `main` (`7851240`), not a merge descendant of `3e4672a`. Its large 472-file diff means the four-role field changes must be verified by behavior, not ancestry alone. GitHub PR API reported `mergeable:false` and `draft:false` at inspection; do not interpret these fields as approval.

| Gate | Independent result on exact commit | Evidence / limitation |
|---|---|---|
| Migration chain | **Partial** | Manifest lists bootstrap and every tracked SQL migration from `0012` through `20260928000000`; `release-verify.mjs` consumes it, and manifest regression passed. No isolated SQL replay occurred because Docker is absent. The final reconciliation migration asserts presence of relations/functions, checks role names appear in function definition and denies `anon` EXECUTE on two functions; it does not itself exercise role behavior. Legacy `0011` provenance is unresolved. |
| Four-role field execution and evidence | **Partial** | `0040_multirole_field_execution_authority.sql` defines Technician, Supervisor, Facility Manager and Administrator checks; source tests cover some permission cases. No post-0040 behavioral SQL test exists in `tests/sql`, and no real database negative matrix ran. Existing `0034` SQL tests predate the override and cannot prove final authority. |
| Incident recovery 409/audit regression | **Open** | `0014_emergency_incident_management.test.sql` covers a successful transition into `recovery`. `tests/api/incident-actions.test.ts` covers a mocked invalid transition returning 409. Neither reproduces the historical recovery 409 plus missing reconciliation audit against the final database. |
| WO/Incident/PM CSV 503 regression | **Open** | `tests/api/exports-route.test.ts` mocks successful database responses for all three and validates output shape. No hosted/real RLS query regression reproduces historical 503, and E2E does not download those three exports. |
| Non-Production migration validation | **Blocked by environment** | Docker executable unavailable here; no verified isolated Supabase project connection or migration ledger was used. No database was changed. |
| Authenticated Playwright | **Blocked by environment** | Synthetic role credentials/local Supabase not provisioned here; deployment protection may require authorized Preview access. No browser acceptance was claimed. |
| Local quality gates | **PASS** | `npm ci --ignore-scripts`, `npm run typecheck` exit 0, `npm run lint` exit 0, `npm run test`: 73 files / 696 tests pass, `npm run build` exit 0 (53 pages). Build skips built-in type/lint, which passed separately. |
| Diff hygiene | **Open, low severity** | `git diff --check HEAD^ HEAD` reports whitespace in several files. This is fixable before merge and does not outweigh database/UAT blockers. |
| Hosted status | **Limited** | GitHub combined commit status reports Vercel success; this is deployment/build status, not authenticated UAT or database migration proof. |

## Remaining blockers and next action

1. Run the exact manifest through `20260928000000` on disposable local Supabase or a clearly identified authorized **non-Production** project; capture ledger, schema, failure/rollback evidence and post-migration RLS/function privileges.
2. Add or run behavioral role × facility × assignment × status cases for all four roles, wrong-facility and inactive membership, evidence create/read/remove and independent verification.
3. Reproduce the prior incident recovery 409/audit path and WO/Incident/PM export 503 paths against the final schema; record positive and negative outcomes.
4. Run authenticated Playwright against an isolated environment with synthetic identities, including ordinary distinct-user flow, financial closure and exports; record immutable candidate SHA and test evidence.
5. Resolve emergency commercial exception, legacy `0011`, contractor audit and operational email scope from the earlier independent matrix. Review large PR diff and any merge conflict before declaring PR ready.

**Exact next action:** Have Codex or the non-Production test operator run the repository's `npm run release:verify` in an isolated Docker/Supabase environment on `35b615f` and supply its complete result. Do not run it against Production. An authenticated Preview UAT run is still needed afterward. No main merge or Production deployment is authorized by this report.

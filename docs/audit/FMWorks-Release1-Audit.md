# FMWorks Release-1 Technical Audit — Phase 1

**Audit date:** 24 September 2026

**Repository:** `engchianyeo-cmyk/facility-works-monitor`

**Branch:** `feature/playwright-authenticated-workflows`

**Baseline:** `a08fed8be0b1a4d7c6f508c1bb8186b3f71349ce`
**Audit posture:** Static and local execution only. No migration was applied, no remote database was queried or changed, and no Vercel deployment or environment was changed.

## Executive conclusion

Release 1 is **not ready for production release**. The repository contains substantial, coherent foundations for authenticated Work Orders, facility-scoped Technician authority, assets, drawing markups, protected evidence, contractor selection, independent approval, final costing, document correction, and payment recording. TypeScript, ESLint, unit/API tests, and the Next.js production build pass.

The principal release blocker is a lifecycle contradiction. Physical completion is currently blocked until final cost approval and a final invoice exist in both the UI and PostgreSQL. This merges three distinct events—physical completion, financial-document receipt, and payment governance—and prevents genuine completion when an invoice arrives later, an emergency is regularised later, or no payment is required. Conversely, the legacy close transition allows a reviewed Work Order to close without proving a paid or approved no-payment disposition.

The commercial path is also incomplete: submission is hard-limited to a single quotation below S$1,000, while no governed path exists at or above S$1,000, for emergency exceptions, or for no-payment work. The current automated release gate does not execute the latest lifecycle/commercial migration chain, so passing tests do not establish database correctness for Release 1.

## Scope and method

The audit traced documented requirements through:

- product and workflow documents in `docs/`;
- Work Order pages, React controls, route handlers, permission helpers, and evidence/storage code;
- all numbered and dated Supabase migrations, with emphasis on `0036`–`0038` and the September 2026 Release-1 migrations;
- Vitest/API/source-contract tests, Playwright configuration, SQL harnesses, and `scripts/release-verify.mjs`;
- local build and static checks;
- the existing dirty worktree, without modifying its preserved artifacts.

The deleted requirements DOCX, untracked security migration, recovery scripts/results, environment-check file, backup component, removal script, and `1. foundation/` were not restored, deleted, executed, or committed. They must remain quarantined until their ownership and intended disposition are decided.

## Test and build results

| Check | Result | Evidence / limitation |
|---|---|---|
| `npm run typecheck` | PASS | `tsc --noEmit`, exit 0 |
| `npm run lint` | PASS | `eslint .`, exit 0 |
| `npm run test` | PASS | 67 files, 668 tests, exit 0 |
| `npm run build` | PASS | Next.js 15.5.20, 53 static pages, exit 0 |
| `npm run test:e2e` | BLOCKED | Collection requires isolated synthetic `E2E_ADMIN_EMAIL` and related identities. Direct execution reported the missing gate-provisioned identity and was terminated after the wrapper remained alive. No remote environment was used. |
| Latest Release-1 SQL runtime regression | NOT ESTABLISHED | The tracked release script applies only the `0012`–`0027` chain. It does not apply `0028`–`0038` or the dated Release-1 commercial migrations. |

The Next build explicitly skips type and lint validation; its success must not be interpreted as covering those checks. They were run separately and passed.

## Lifecycle assessment

### 1. Creation, submission, assignment, and Technician permissions

The core lifecycle and facility membership model are well developed. Critical transitions are implemented as `SECURITY DEFINER` RPCs with pinned `search_path`, explicit grants, structured errors, and activity logging. Technician acceptance, start, evidence, actual-cost entry, and completion require assignment and effective same-facility membership. Self-approval protection exists for Work Order and commercial approval.

Material gaps remain:

- UI copy says an Administrator formally completes recorded work, while the governed completion RPC requires the assigned Technician. This creates an operational dead end or misleading instruction depending on the active UI path.
- The newer lifecycle migrations are not exercised by the tracked full release harness.

### 2. Assets, drawings, and location markups

Assets, facility hierarchy, asset linkage, and effective facility membership are represented. Release-1 markup records preserve source reference, revision, annotation type, geometry, coordinates, author, timestamp, and soft deletion. The drawing editor provides an operational markup path rather than a display-only mock.

Residual risk: source references are metadata rather than a governed drawing-document/version repository. Release acceptance should explicitly state whether drawing ingestion/version custody is in scope; otherwise the current capability should be described as markup against a referenced source, not full drawing document control.

### 3. Before/After evidence, replacement, and audit history

Before/After evidence is private-storage backed, file-signature validated, registered through an RPC, and associated with activity history. The assigned same-facility Technician can mutate evidence during active work; post-completion changes require an authorized document-correction window. Soft removal/replacement preserves metadata and reasons.

The correction model generally preserves the original physical-completion event and allows document-only correction. However, the final-invoice gate means document completeness incorrectly determines whether physical completion may occur at all.

### 4. Procurement-qualified contractors, quotations, and approvals

The schema includes facility-specific vendor eligibility, prequalification/confirmation flags, effective rates, immutable quotation revisions, supporting documents, selected vendor, procurement commitments, and independent approval. The eligible-contractor RPC is the correct architectural direction.

The implemented proposal submission path is restricted to exactly one quotation under S$1,000. It cannot complete the Release-1 lifecycle for higher-value work. Contractor administration uses the service-role client for direct writes and does not create an application activity/audit entry for contractor/rate changes.

### 5. S$1,000 quotation rule and governed exceptions

The below-S$1,000 rule is explicit: `SGD_BELOW_1000_ONE_QUOTE` has a maximum of 1000 and one required quotation; proposal submission rejects `q.total_amount >= 1000`.

There is no complementary rule or working submission path for S$1,000 and above. There is also no persisted, approved exception object containing exception type, reason, authority, evidence, expiry/scope, and audit linkage. As a result, emergency work and other legitimate exceptions cannot be regularised through a governed workflow.

### 6. Emergency and no-payment-required work

Emergency incidents are appropriately separate from Work Orders and can link corrective work. Emergency contractor capability and emergency rates exist. The agreed “fix first, costing later” behavior is documented but not implemented in the commercial approval flow: the same pre-completion final-cost/invoice gates and below-S$1,000 quotation limit still apply.

No `payment_required` determination or approved `no_payment_required` disposition exists. Genuine in-house, warranty, goodwill, zero-cost, or non-billable work therefore lacks a first-class close path and auditable basis.

### 7. Final labour, contractor cost, actual expenditure, and variance

Technicians can enter structured actual cost lines and explicitly confirm a zero-cost outcome. A separate final-cost submission stores labour, contractor amount, confirmed actual cost, comments, and independent approval of positive variance.

This is directionally sound, but the data model has overlapping authoritative values: Work Orders, cost lines, payment assessments, and final-cost submissions can each carry labour/cost values. The latest final-cost save function does not establish a single reconciled ledger snapshot as the source of truth. The UI also calls the final-cost submission a prerequisite for physical completion, which is the central lifecycle defect.

### 8. Physical completion, verification, and document-only correction

Physical completion correctly requires an assigned Technician, work-performed statement, non-negative labour, and active After evidence. Verification is independent and supports reject/reopen. Document correction can be opened after completion without falsifying the original completion timestamp.

Required correction:

1. **Database layer:** replace the latest `submit_physical_completion` wrapper so its physical readiness checks are limited to work performed, labour/effort required for the operational record, active After evidence, assignment, facility membership, and valid status. Remove final-cost status, variance approval, and final-invoice existence from this transition. Do not rewrite the applied migration; add a new migration that preserves the old function for audit/rollback as appropriate and installs a corrected, privilege-tested wrapper.
2. **UI/server layer:** remove final-cost and final-invoice items from `completionMissing` in `app/work-orders/[id]/page.tsx`. Present financial documentation as a separate post-completion readiness track. Keep final account/invoice controls available after completion and verified completion under explicit permissions.
3. **State/readiness model:** expose separate `physical_completion_readiness`, `financial_documentation_readiness`, and `closure_readiness` results. The latter must resolve to either paid/reconciled or independently approved `no_payment_required`.
4. **Tests:** add PostgreSQL behavioral tests proving completion succeeds without an invoice, invoice arrival/replacement does not alter `completed_at`, emergency completion can precede commercial regularisation, and closure remains blocked until financial disposition is resolved.

### 9. Payment proposal, independent approval, recording, and closure

The payment assessment supports draft, awaiting approval, approved for payment, paid, and returned states. It preserves preparer/recommender, independent approver, Finance recorder, amounts, references, timestamps, notes, and due dates.

Closure is not integrated with that state machine. The inherited transition permits `reviewed → closed` based on operational status and role without requiring `paid` or a governed no-payment decision. This permits premature closure while commercial obligations remain unresolved.

### 10. Authentication, database security, email, and audit logs

Authentication uses server-side identity resolution and active-profile/password gates. Administrative Auth operations are server-only, reconciliation-aware, and use invitation flows. Newer RPCs generally pin `search_path`, revoke broad execution, grant only to `authenticated`, enforce facility membership, and write activity logs transactionally.

Outstanding issues:

- The untracked `0011_secure_legacy_public_tables.sql` indicates legacy tables/counters still need an owned, reviewed, tracked security migration. Its unapplied status cannot be assumed safe.
- Contractor/rate administration bypasses RLS through the service-role client and lacks transactional domain audit entries.
- No operational email provider abstraction/delivery tracking exists for Release-1 workflow notifications. Supabase Auth may deliver invitations according to external project configuration, but application assignment/payment email delivery is `NOT_CONFIGURED`/absent and is not verified by repository tests.
- Static source-contract tests are overrepresented; many assert strings inside migrations rather than executing authorization and transition behavior.

## Security observations

Positive controls include private buckets, server-only service-role imports, signature/size validation, RLS on newer tables, explicit RPC ACLs, pinned search paths, facility membership checks, immutable terminal behavior, structured safe errors, and audit insertion in critical functions.

Release acceptance still requires a disposable PostgreSQL run of the complete migration history and privilege matrix. In particular, all public tables must be enumerated for RLS, all `SECURITY DEFINER` functions checked for pinned search paths and explicit EXECUTE grants, and anon/authenticated/service-role privileges compared with the intended call graph. This was not run against a remote database by design.

## Recommended repair order

1. Separate physical completion from final invoice, final cost approval, and payment; add the three readiness models and regression tests.
2. Govern closure with a mandatory financial disposition: `paid` or independently approved `no_payment_required`.
3. Implement the complete S$1,000 rule matrix, including the at/above-threshold multi-quotation path.
4. Add governed emergency and other quotation-exception records with independent approval and retrospective regularisation.
5. Reconcile Technician/Administrator completion authority and UI language.
6. Make one authoritative actual-cost/final-account reconciliation model and prevent divergent totals.
7. Extend the isolated release gate through every current migration and add behavioral SQL tests for Release 1.
8. Resolve, review, and track the legacy-table security migration; audit contractor/rate mutations transactionally.
9. Configure and verify approved email delivery or explicitly accept `NOT_CONFIGURED` as a release limitation with operational runbooks.
10. Re-run disposable SQL, Vitest, TypeScript, ESLint, build, and synthetic Playwright/UAT across all roles before Production consideration.

## WP-2A remediation verification — 24 September 2026

The controlled remediation in commit `0351ffe6292f95fd11316b621fd43f7d84728fc0`, plus its follow-up ACL correction, was applied only to authorized Preview Supabase project `pvajuywwwpjlikqjnvgv`. The first migration attempt failed its own postcondition because the renamed internal transition core retained an `authenticated` EXECUTE grant; the transaction rolled back. The migration was corrected to revoke that inherited grant, reapplied successfully, and recorded as migration `20260924040748`.

Rollback-only behavioral SQL regression `tests/sql/20260924040748_release_1_lifecycle_financial_reconciliation.test.sql` passed on PostgreSQL 17.6 and confirmed:

- Assigned Technician physical completion succeeds without final cost or invoice when notes, labour, After evidence, and execution-cost confirmation are satisfied.
- Invoice absence remains blocked at later payment-proposal submission.
- Reviewed work with unresolved payment cannot close.
- Independently approved no-payment disposition permits closure without fabricated payment.
- Technician financial self-approval is denied.
- WO-TEST-012 keeps S$650 quotation separate from S$620 actual, proposal, and recorded-payment basis.
- The internal `transition_work_order_20260924_core` function is not executable by `authenticated`.

The regression ended with `ROLLBACK`; a post-test query confirmed WO-TEST-012 remained `reviewed`, payment remained `approved_for_payment` for S$620 with no paid amount, and no financial-disposition row persisted. The repository-wide clean-install SQL gate remains incomplete because it still stops at migration `0027` and the Preview migration ledger contains historical alternate versions.

## Release recommendation

**NO GO for Release 1 Production.** The application should remain in audit/remediation status until all Critical/High defects in `FMWorks-Defect-Register.md` are fixed and the complete isolated database/browser gate passes. No finding in this report authorizes modifying Production or the Development environment that shares Production’s Supabase configuration.

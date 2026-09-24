# FMWorks Release-1 UAT Acceptance Report

**Assessment date:** 24 September 2026  
**Repository:** `engchianyeo-cmyk/facility-works-monitor`  
**Branch:** `feature/playwright-authenticated-workflows`  
**Candidate commit:** `26ff450bf736a32402fbe8c7134abdaa3eb18fbb`  
**Authorized Preview Supabase project:** `pvajuywwwpjlikqjnvgv`  
**Vercel Preview:** `https://facility-works-monitor-1xjpx61ud-aoai2.vercel.app`

## Acceptance decision

**NOT READY FOR FINAL RELEASE-1 ACCEPTANCE.** The repaired physical-completion, financial-reconciliation, governed-closure and S$1,000 quotation controls are implemented and verified, and the candidate Preview deployment is healthy. Final acceptance remains blocked by the open defects and owner decisions listed below. Production and the Development environment that shares Production's Supabase configuration were not modified.

## Verified remediation

- R1-001: physical completion no longer requires final cost or a final invoice; work statement, labour, confirmed actual-costing state and After evidence remain mandatory.
- R1-002: work at or above S$1,000 requires three authentic quotations from distinct eligible contractors, explicit Technician recommendation rationale and independent approval. Draft edits cannot lower the governed threshold.
- R1-004: independently approved, audited no-payment-required disposition supports genuine non-payable closure without fabricating payment.
- R1-005: reviewed Work Orders cannot close with unresolved payment or disposition.
- R1-006: assigned Technician completion and independent verification/financial authority are separated.
- R1-007: actual expenditure derives from the execution cost ledger; approved quotation, final contractor charge, payment proposal and recorded payment remain distinct. WO-TEST-012 reconciles S$650 / S$620 / S$620 / S$620 without double counting.
- R1-013: controlling product documents describe the implemented Release-1 commercial lifecycle.
- R1-014: CI runs TypeScript, ESLint, Vitest and build as separate gates.

## Verification evidence

| Gate | Result |
|---|---|
| TypeScript (`npm run typecheck`) | PASS |
| ESLint (`npm run lint`) | PASS |
| Vitest (`npm run test`) | PASS — 70 files, 685 tests |
| Next.js production build (`npm run build`) | PASS; build continues to report type/lint as separately skipped |
| WP-2A rollback-only Preview SQL regression | PASS |
| Three-quotation rollback-only Preview SQL regression | PASS on PostgreSQL 17.6, including governed-estimate edit protection |
| Preview deployment status | READY |
| Preview health | PASS — reported commit `26ff450bf736a32402fbe8c7134abdaa3eb18fbb`, environment `preview` |
| Preview rendered application response | PASS — Vercel-authenticated fetch rendered the FMWorks sign-in page |
| Authenticated browser lifecycle UAT | NOT COMPLETE — ordinary automation reached the Vercel deployment-protection login wall |
| Complete clean-install SQL release gate | NOT COMPLETE — current runner stops at migration `0027` |

## Applied Preview migrations

- `20260924040748_release_1_lifecycle_financial_reconciliation.sql`
- `20260924044237_release_1_three_quotation_control.sql`
- `20260924044902_correct_three_quotation_greatest.sql`
- `20260924045239_preserve_three_quotation_estimate.sql`

All were applied only to the authorized Preview project. The untracked `0011_secure_legacy_public_tables.sql` artifact was not executed.

## Open defects and blockers

- **R1-003 — Emergency commercial exception:** owner must define the retrospective regularisation deadline and accountable approval roles. This is an agreed-business-rule decision, not an implementation detail.
- **R1-008 — Complete SQL release gate:** the isolated gate does not yet replay migrations after `0027`. Several later migrations contain environment-specific UAT identity/data assumptions, so they cannot honestly be declared a clean canonical install without separating schema changes from controlled data corrections.
- **R1-009 — Browser acceptance:** a deterministic isolated command and an authenticated Preview browser run remain incomplete. Preview deployment protection currently prevents an unauthenticated automation session from reaching FMWorks login.
- **R1-010 — Legacy migration provenance:** the untracked `0011_secure_legacy_public_tables.sql` must be accepted, replaced or rejected by the owner after provenance review.
- **R1-011 — Contractor administration audit:** contractor/rate writes still require transactional audited RPC remediation and behavioral tests.
- **R1-012 — Operational email:** owner must choose an approved delivery provider/scope or explicitly accept `NOT_CONFIGURED` for Release 1.

## Owner decisions required before final acceptance

1. Specify emergency-exception regularisation deadline and authorizer/approver roles.
2. Choose the Release-1 operational email position: approved provider and delivery scope, or explicit acceptance of `NOT_CONFIGURED`.
3. Decide the provenance/disposition of the untracked legacy-table migration.
4. Provide or authorize a deploy-protection bypass/authenticated browser route for final Preview UI UAT, or perform the protected login handoff when requested.

## Release recommendation

Keep this candidate in Preview. Do not promote or deploy to Production. Resume final acceptance after the remaining code-owned defects are closed and the four owner-controlled items above are resolved.

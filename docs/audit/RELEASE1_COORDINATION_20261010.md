# FMWorks Release-1 engineering and UAT coordination

Report opened: 10 October 2026, 22:15 SGT (Asia/Singapore).
Updated: 10 October 2026, 22:24 SGT.
Repository: engchianyeo-cmyk/facility-works-monitor.

## Authoritative published state

- PR #5: reconciliation/release1-incremental-repair at 28fb307828036be979bfe3cffcf6f7818da70b2c; open, unmerged.
- PR #6: codex/continue-release-1-defect-family-review; resumed from 8c9f3ae9f50b7c942c0cee2afe4c3645ad4c3604.
- Increment 1: 5d8f2507f0eb970bd8ef70e0eb270fcea3b50e0e. Incident terminal authority, evidence registration serialization, qualified evidence-test predicates, commercial no-payment UI authority, full verification workflow on PR #6 branch.
- Increment 2: e7869525e4450b703e8107f54663db5d403eeb03. Commercial upload authorization before privileged storage writes, size/type preflight, cleanup recovery handling, PNG signature validation, Administrator-only Preview diagnostics.
- No main/Production change, merge, history deletion or force-push.

## Verification evidence and interpretation

Local npm run check at Increment 2: TypeScript PASS; ESLint PASS; Vitest 79 files / 796 tests PASS; Next.js build PASS. SQL fixture follow-up changes only a synthetic terminal evidence path to a schema-valid UUID path.
Local release:verify reached Docker and failed because docker is absent. This is a runtime limitation, not a SQL pass.
Native Release-1 Run #21: https://github.com/engchianyeo-cmyk/facility-works-monitor/actions/runs/38058535514 (Increment 1).
Native Release-1 Run #22: https://github.com/engchianyeo-cmyk/facility-works-monitor/actions/runs/38058684408 (Increment 2).
Runs #21 and #22 failed at the same pre-existing terminal evidence fixture path. Both passed the full replay and prior current-schema security/commercial suites. The fixture correction was published at d48f59a1e43aad3873a2578156421447325dff82; Run #23 (38058981932) tests that candidate.
Execution of the added inactive-team negative exposed a second authorization defect: NULL individual assignment made the OR authorization expression NULL; IF NOT authorized failed to reject it. New migration 20261010142142_incident_responder_membership_denial.sql uses IS NOT TRUE, with inactive/unassigned state+audit negatives and both management roles/actions positive coverage. Native confirmation of this follow-up is required.
Compatible dependency updates now lock Next.js/ESLint 15.5.27, paired Vitest/coverage 4.1.11 and scoped Next PostCSS 8.5.25. Existing Supabase resolutions are pinned, without API upgrades. Dependency review is in RELEASE1_DEPENDENCY_REVIEW_20261010.md. Local full check passes 796 tests/typecheck/lint/build. No zero-vulnerability claim is made.
Results must be updated from completed exact-SHA runs; earlier PR #5 pass is baseline evidence only.
Supplementary PGlite replay PASS for the complete canonical migration manifest through 20261010142142 and all nine current-schema SQL suites. It uses the committed minimal managed-schema prerequisite; it is not hosted Supabase, Docker acceptance or browser UAT.

## Hosted Preview findings (read-only)

Vercel reports Increment 1 deployed successfully. URL: https://facility-works-monitor-58aa6y1ad-aoai2.vercel.app/login . Requests to login and health redirect to Vercel sign-in; the final HTTP 200 is a Vercel login page, not FMWorks health.
Vercel project dashboard: https://vercel.com/aoai2/facility-works-monitor . Authenticated project access/deployment-protection bypass remains required.
Supabase Preview UAT pvajuywwwpjlikqjnvgv is active. Read-only ledger inspection ends at 20260924045239. It contains 18 Work Orders, 0 Incidents, and no void_incident_evidence or work_order_commercial_visible function. The database is not at candidate schema. Targeted read-only catalog confirms four-role field facility authority and both contractor import tables/RPCs already exist; authenticated EXECUTE on submit_physical_completion_20260921_core still exists and requires the pending canonical hardening repair. Existing dated migrations overlap numbered history: apply only a reviewed incremental adapter, never bootstrap/blind replay. Production project pyapukytcrsuowmgzqzh was not queried or changed.

## Current defect and blocker register

| ID | Priority | Status / evidence | Next gate |
| --- | --- | --- | --- |
| R1-015 Incident terminal authority | High | Repaired in Increment 1; responder individual/team terminal denials + preserved state/audit SQL and UI regressions added | Completed native exact-SHA verification |
| R1-016 Incident evidence regression | High | Ambiguous predicates repaired; synthetic terminal storage path corrected; parent locking serializes upload with closure | Native SQL suite including terminal immutability |
| R1-017 Commercial proposer inconsistency | Medium | Approver proposal hidden; assigned Technician and existing management proposers retained; independent approval retained | Rendered role tests pass; hosted role UAT |
| R1-018 Commercial privileged upload preflight | High | User-scoped visibility/authority/state enforced before storage; cleanup failures explicit | Route negatives pass; native/hosted regression |
| R1-019 Truncated PNG acceptance | Medium | Minimum complete PNG signature required | Unit regression passes |
| R1-020 Anonymous Preview probes | Medium | Administrator-only diagnostic | API role negatives pass |
| R1-022 Nullable Incident responder authority | High | New IS NOT TRUE migration repairs NULL authorization bypass; inactive/unassigned denials preserve state and audit | Exact-SHA native verification |
| R1-023 Dependency security | High | Critical Next.js and compatible dependency repairs completed; remaining no-patch advisories tracked separately | Exact-SHA full gate and dependency review |
| R1-021 Hosted schema drift | High | Preview ledger lacks candidate reconciliation and later security/functions | Tested incremental rollout adapter + protected Preview access |
| R1-009 Hosted authenticated browser UAT | High | Vercel deployment protection blocks FMWorks login | Vercel connection/access and dedicated UAT identities |
| R1-003 Emergency commercial exception | High | Business decision remains open; no waiver invented | Owner specifies authorizers and regularisation deadline |
| R1-012 Operational email | Medium | NOT_CONFIGURED/provider boundary retained | Owner confirms scope/provider or accepts limitation |

Older R1-001/002/004/005/006/007/008/010/011/013/014 remain covered by the existing audit and native release gate; they are not re-opened without new failure evidence.

## UAT execution checklist

Record candidate full SHA, health/footers, database migration ledger, actor role, record ID, expected/actual outcome, screenshot or trace, audit row and timestamp for every case. Use isolated synthetic accounts/data; no Production credentials or fixtures.

| Case | Scenario and expected result | Automated evidence | Hosted result |
| --- | --- | --- | --- |
| UAT-01 | Confirm candidate SHA/environment and candidate schema before testing | health/build identity tests | BLOCKED |
| UAT-02 | Reviewer/Initiator/Approver/Technician/Supervisor/Facility Manager/Admin login; inactive/password-pending fail closed | identity + Playwright gate | PENDING |
| UAT-03 | Temporary password forces private change; recovery known/unknown replies indistinguishable; real recovery callback works | auth/API/browser tests; delivery requires hosted check | PENDING |
| UAT-04 | Create Work Order, submit, independent approve, assign, accept, start; refresh retains records/timestamps/audit | field-owner SQL + lifecycle browser | PENDING |
| UAT-05 | Four assigned field roles execute costing/evidence/completion; wrong owner/facility/inactive membership denied atomically | field-owner SQL | PENDING |
| UAT-06 | Physical completion requires work/labour/confirmed execution ledger/After evidence; does not require invoice/final cost | financial SQL + lifecycle browser | PENDING |
| UAT-07 | Independent verification/rework; no self-approval; unresolved financial disposition blocks closure | financial SQL + lifecycle browser | PENDING |
| UAT-08 | Below/at/above threshold; insufficient/distinct quotations; preserve policy version; independent selection approval | three-quotation + policy SQL/browser | PENDING |
| UAT-09 | Actual ledger/final account/payment reconcile; overpayment/NaN denied; invoice required for payable submission | financial SQL/API | PENDING |
| UAT-10 | Assigned Technician/management no-payment proposal; Approver independent approval; self-approval denied | SQL + rendered role matrix | PENDING |
| UAT-11 | Report/assign Incident; individual and active-team responders perform six transitions through Recovery | terminal-authority SQL + Incident API | PENDING |
| UAT-12 | Assigned individual/team responders cannot close/cancel; state/audit unchanged; Supervisor/Admin succeed | terminal-authority SQL/UI | PENDING |
| UAT-13 | Invalid Recovery transition yields 409; valid Recovery advances and audits | Incident API/SQL | PENDING |
| UAT-14 | Active Incident evidence creation/soft removal attributable; unrelated denied; closed/cancelled immutable | Incident evidence SQL/API | PENDING |
| UAT-15 | Cross-record evidence read/upload/delete denied; malformed/oversized files denied; cleanup failure visible | evidence + commercial upload API | PENDING |
| UAT-16 | WO/Asset/Incident/PM CSV scope, text formula protection; database failure yields 503 without sensitive output | exports API/browser | PENDING |
| UAT-17 | Admin user provision/disable, department/team/contractor/rate creation; unauthorized negatives and transactional audit | admin/API/SQL/browser | PENDING |
| UAT-18 | Procurement policy only Facility Manager/Admin; concurrency/history preserved; Supervisor denied | policy SQL/browser | PENDING |
| UAT-19 | Asset/PM creation and processing; document/AI/staffing/SLA controls persist and remain scoped | native browser suite | PENDING |
| UAT-20 | Mobile 390px and desktop: login, work/Incident detail, upload, approval and admin controls usable | manual screenshots/keyboard checks | PENDING |
| UAT-21 | Emergency commercial exception and email delivery scope | requires approved business rules | BLOCKED |

## Readiness recommendation

NOT READY for Release-1 sign-off or Production. Continue technical repairs on PR #6 and native verification. Hosted acceptance requires aligned Preview schema, authenticated Vercel access, role-based UAT evidence and resolution of the two business decisions. A successful Vercel deployment alone is not acceptance.

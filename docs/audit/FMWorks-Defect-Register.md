# FMWorks Release-1 Defect Register

Severity scale: **Critical** permits material unauthorized access/loss or invalid financial closure; **High** blocks a required lifecycle or permits a materially incorrect controlled outcome; **Medium** weakens governance, operability, evidence, or verification; **Low** is localized clarity/maintainability risk.

## R1-001 — Physical completion requires final cost approval and final invoice

- **Severity:** High
- **Implementation status (2026-09-24):** **Verified for WP-2A.** Migration `20260924040748_release_1_lifecycle_financial_reconciliation.sql` replaces the physical-completion wrapper without final-cost or invoice gates. The UI requires the physical work statement, cumulative labour, confirmed execution-cost ledger, and After evidence only. The rollback-only Preview SQL regression proved that the assigned Technician can submit physical completion with no final-cost record or invoice. TypeScript, ESLint, Vitest, build, and the targeted Preview database test pass.
- **Affected:** `app/work-orders/[id]/page.tsx:184`; `components/work-orders/release-one-workspace.tsx:60`; `supabase/migrations/20260921122902_evidence_final_cost_completion_controls.sql:125`; `public.submit_physical_completion(uuid,jsonb)`
- **Expected:** Assigned Technician may submit physical completion when work statement, labour/effort, After evidence, assignment, facility membership, and operational status are valid. Financial documents and payment proceed independently afterward.
- **Actual:** UI removes completion actions until final cost is confirmed/variance-approved and a final invoice exists. PostgreSQL returns `FINAL_COST_REQUIRED` or `FINAL_INVOICE_REQUIRED` before invoking the physical completion core.
- **Evidence:** Page lines 188–191 add both financial checks to `completionMissing`; migration lines 130–132 enforce both checks. `tests/release-one-integrated-lifecycle.test.ts` asserts `FINAL_INVOICE_REQUIRED`, encoding the defect.
- **Proposed fix:** Add a new migration replacing the wrapper with physical-only readiness. Remove financial conditions from UI action filtering. Add separate financial-document and closure readiness RPCs/presentation.
- **Verification:** SQL and browser tests complete an eligible Work Order without final cost/invoice; verify `completed_at` is immutable when invoice arrives later; prove incomplete work/evidence still blocks completion.

## R1-002 — No commercial path for work at or above S$1,000

- **Severity:** High
- **Implementation status (2026-09-24):** **Verified.** Migrations `20260924044237_release_1_three_quotation_control.sql`, `20260924044902_correct_three_quotation_greatest.sql`, and `20260924045239_preserve_three_quotation_estimate.sql` implement collection of authentic quotations from distinct Procurement-qualified, Facility-confirmed contractors, preserve the governed estimate against threshold downgrade during both preparation and later draft edits, require an explicit Technician selection rationale, and block independent approval until the configured count is met. The UI supports adding competing quotations, comparison/recommendation, and independent approval of the explicitly recommended quotation rather than the latest-created row. The rollback-only PostgreSQL 17.6 Preview regression proves one and two quotations cannot bypass the rule, draft editing cannot lower the governed S$1,000 threshold, three distinct quotations make selection ready, and independent approval succeeds for the selected quotation while retaining threshold history. TypeScript, ESLint, all 685 Vitest tests, and the production build pass.
- **Affected:** `supabase/migrations/20260918083838_release_1_uat_markup_financial_controls.sql:23`; `supabase/migrations/20260919064024_release_1_proposal_payment_workflow.sql:129`; `public.submit_work_order_proposal`; Release-1 workspace quotation UI
- **Expected:** Below S$1,000 follows the agreed single-quotation rule; work at/above S$1,000 follows the configured higher-control quotation/approval rule.
- **Actual:** Only `SGD_BELOW_1000_ONE_QUOTE` is seeded. Proposal submission rejects every amount `>= 1000` and every rule whose minimum quotation count is not one.
- **Evidence:** Migration line 142 returns `APPROVAL_NOT_READY` for `q.total_amount>=1000`; no complementary working rule/flow was found.
- **Proposed fix:** Define non-overlapping effective approval bands, required quotation count, authority, and supporting-document requirements; implement multiple independent quotation capture/selection and approval.
- **Verification:** Boundary tests for S$999.99, S$1,000.00, and higher bands; prove insufficient quotations fail and compliant multi-quote selection succeeds with immutable history.

## R1-003 — Emergency “fix first, costing later” has no governed exception

- **Severity:** High
- **Affected:** Release-1 commercial migrations; `work_orders.emergency_work`; proposal/final-cost/completion RPCs; Release-1 workspace
- **Expected:** Authorized emergency work can proceed and physically complete before normal quotation/invoice timing, with a recorded exception, reason, approver, evidence, and retrospective regularisation deadline.
- **Actual:** Emergency status changes rate selection only. The standard quotation threshold and pre-completion final-cost/invoice gates still apply; no persisted exception approval exists.
- **Evidence:** `emergency_work` is used to choose emergency unit rates, while searches found no quotation-waiver/emergency-exception workflow. The documented chain in `docs/WP-WO-009-COMPLETED-WORK-CONTRACTOR-CONTROLS.md` says costing follows physical work.
- **Proposed fix:** Add a governed commercial exception entity/RPC with type, scope, reason, authorizer, timestamp, required follow-up, and closure blocking until regularised.
- **Verification:** Emergency scenario proceeds without pre-work quotation/invoice, completes physically, remains financially outstanding, then regularises with full audit and separation of duties.

## R1-004 — No first-class no-payment-required disposition

- **Severity:** High
- **Implementation status (2026-09-24):** **Verified for WP-2A.** The migration adds an audited `work_order_financial_dispositions` record, bounded reason taxonomy, proposal/independent-approval RPCs, self-approval denial, mutual exclusion with an active payment process, API operations, and UI controls. The rollback-only Preview SQL regression proved that a Technician may propose but not approve the disposition, an independent Approver may approve it, and closure then succeeds without a fabricated payment.
- **Affected:** `contractor_payment_assessments`; Release-1 payment RPCs/UI; closure transition
- **Expected:** In-house, warranty, goodwill, zero-cost, or otherwise non-payable work can be independently classified `no_payment_required` with reason and evidence, then close without a fictitious payment.
- **Actual:** Payment states are draft, awaiting approval, approved for payment, paid, and returned. No no-payment state, decision record, or UI exists.
- **Evidence:** Repository search found no Release-1 no-payment branch; payment status constraint in the proposal/payment migration omits it.
- **Proposed fix:** Add an independently approved financial-disposition record/state, bounded reason taxonomy, note/evidence, approver, and audit event. Do not overload `paid_amount=0`.
- **Verification:** Zero-cost and warranty cases close only after independent no-payment approval; self-approval and missing-reason attempts fail.

## R1-005 — Work Order can close while payment remains unresolved

- **Severity:** High
- **Implementation status (2026-09-24):** **Verified for WP-2A.** `work_order_closure_readiness` and the outer `transition_work_order` wrapper require either a fully reconciled recorded payment or independently approved no-payment disposition before `reviewed → closed`. The detail UI removes Close when readiness is false, and the API maps the database denial to HTTP 409. Preview SQL tests proved unresolved payment is blocked and both reconciled-payment and independently approved no-payment paths become closure-ready.
- **Affected:** `supabase/migrations/0013_core_work_order_engine.sql:592`; later `transition_work_order` wrappers; `lib/work-orders/workflow.ts:15`; close UI action
- **Expected:** Closure requires verified physical completion plus a resolved financial disposition: payment recorded/reconciled or independently approved no-payment-required.
- **Actual:** The canonical transition permits `reviewed → closed` without querying payment assessment or financial disposition.
- **Evidence:** Migration lines 597–605 gate close only on `previous.status='reviewed'`; the client workflow mirrors that rule.
- **Proposed fix:** Add database-owned closure readiness and make close call it atomically. Surface missing payment/no-payment requirements in UI.
- **Verification:** Reviewed/unpaid Work Order cannot close; paid and approved no-payment cases close; audit records the disposition used.

## R1-006 — Completion authority and user guidance conflict

- **Severity:** High
- **Implementation status (2026-09-24):** **Verified for the corrected WP-2A authority paths.** UI guidance states that the assigned Technician submits physical completion and an independently authorized verifier performs verification. The Preview SQL regression exercised Technician physical completion, Technician financial-approval denial, independent Approver authorization, and distinct Administrator Finance recording. Existing role-matrix tests and all application gates also pass.
- **Affected:** `components/work-orders/work-order-actions.tsx:404`; `app/work-orders/[id]/page.tsx:273`; `supabase/migrations/0037_governed_work_order_lifecycle.sql:356`; `0038_governed_technician_actual_costs.sql:125`
- **Expected:** UI wording, visible controls, permission helpers, and RPC authority identify the same accountable actor.
- **Actual:** UI tells the Technician that an Administrator must mark the Work Order Completed and treats Administrator as formal completion authority, while the governed RPC rejects every non-Technician and requires the assigned Technician.
- **Evidence:** UI copy at line 404 and RPC role check at migration line 363/132.
- **Proposed fix:** Confirm the agreed role model, then align UI and RPCs. Recommended: Technician submits physical completion; independent approver/facility manager verifies; Administrator is override-only with reason.
- **Verification:** Role matrix browser/SQL tests prove only the chosen actor can submit, verifier cannot self-verify, and override use is explicit and audited.

## R1-007 — Actual-cost sources can diverge

- **Severity:** High
- **Implementation status (2026-09-24):** **Verified for WP-2A.** Actual expenditure is derived server-side from `work_order_cost_lines` entries in the `actual` phase and snapshotted in `work_order_final_cost_submissions`; labour is copied from physical completion; final contractor charge and approved quotation remain distinct. The rollback-only Preview SQL regression proved WO-TEST-012 retains quotation S$650, derives actual and payment proposal S$620, rejects a S$650 payment against the S$620 approved proposal, and accepts S$620.
- **Affected:** `work_orders.actual_labour_hours`; `work_order_cost_lines`; `work_order_final_cost_submissions`; `contractor_payment_assessments`; `save_work_order_final_cost`; `submit_physical_completion`
- **Expected:** A single governed reconciliation determines authoritative actual expenditure and labour, with immutable snapshots used by variance and payment.
- **Actual:** Similar labour/cost values are independently entered across Work Order completion payloads, cost lines, final-cost submissions, and payment assessments. No database constraint proves they reconcile.
- **Evidence:** The Release-1 workspace separately renders actual cost lines and final-cost values; the final-cost table stores its own labour and confirmed cost while completion writes Work Order labour.
- **Proposed fix:** Define authoritative cost ledger/snapshot semantics; derive totals server-side; store adjustment/reconciliation entries rather than duplicate free inputs.
- **Verification:** Attempts to submit mismatched totals fail or create a governed variance; payment proposal reads the approved immutable snapshot.

## R1-008 — Full release verification omits current lifecycle/commercial migrations

- **Severity:** High
- **Implementation status (2026-09-24):** **Open and confirmed as a verification blocker.** `scripts/release-verify.mjs` and its SQL runner still stop at migration `0027`; they do not apply `0028`–`0038`, the dated Release-1 migrations, or the WP-2A migration. The WP-2A Vitest suite explicitly asserts this limitation so the application test run cannot be misreported as a complete SQL release gate. No protected database was used as a substitute.
- **Additional evidence (2026-09-24):** The committed WP-2A migration was applied transactionally to authorized Preview project `pvajuywwwpjlikqjnvgv`, recorded in its migration ledger, and behaviorally tested with `tests/sql/20260924040748_release_1_lifecycle_financial_reconciliation.test.sql`. That targeted evidence verifies WP-2A but does not cure the incomplete clean-install release gate or its historical migration-ledger drift.
- **Affected:** `scripts/release-verify.mjs`; `tests/sql/`; migrations `0028`–`0038` and `20260918*`–`20260921*`
- **Expected:** The isolated release gate applies the exact complete migration sequence and behaviorally tests current Release-1 RPCs, ACLs, RLS, and rollback safety.
- **Actual:** The script constructs and applies only migrations `0012` through `0027`. Current Release-1 tests often read files and assert strings rather than execute SQL.
- **Evidence:** `release-verify.mjs` creates a 16-item chain ending at `enterprise_ai_document_gateway`; unit tests such as `release-one-commercial-payment.test.ts` use `readFileSync(...).toContain(...)`.
- **Proposed fix:** Build a canonical manifest covering every tracked migration in order; run disposable Postgres behavioral tests for all Release-1 functions and privilege matrices.
- **Verification:** Clean disposable database reaches latest schema; positive/negative role cases pass; function ACL/search-path and RLS enumeration pass; drift/missing migration fails the gate.

## R1-009 — Browser acceptance cannot run standalone and was not completed

- **Severity:** Medium
- **Affected:** `playwright.config.ts`; `tests/e2e/pilot-helpers.ts`; `scripts/release-verify.mjs`
- **Expected:** Documented command provisions isolated synthetic identities and runs browser acceptance without remote data.
- **Actual:** `npm run test:e2e` fails collection when gate-only `E2E_ADMIN_EMAIL` variables are absent. The wrapper process remained alive after collection failure and required termination.
- **Evidence:** Local run reported `E2E_ADMIN_EMAIL must be supplied by the isolated release gate.`
- **Proposed fix:** Make the public command invoke a safe isolated setup or fail immediately with a precise instruction; ensure the web server tears down on collection error.
- **Verification:** One documented command provisions disposable data, runs all Playwright projects, exits deterministically, and leaves no server/container behind.

## R1-010 — Legacy public-table security change is untracked and outside the gate

- **Severity:** High
- **Affected:** untracked `supabase/migrations/0011_secure_legacy_public_tables.sql`; `technicians`; `work_order_number_counters`; `next_work_order_number`; migration manifest
- **Expected:** Security changes are reviewed, tracked, ordered, and verified before any environment application.
- **Actual:** A migration securing legacy tables/counter function exists only as an untracked working-tree artifact, while tracked history advances from `0010` to `0012`. Its provenance/application status is undetermined.
- **Evidence:** Git status shows the migration untracked; its content enables RLS/revokes access and changes `next_work_order_number` to `SECURITY DEFINER`.
- **Proposed fix:** Determine provenance and target state, compare against actual isolated schema, review function privileges/search path, then adopt under an approved non-conflicting migration plan. Do not execute the current artifact implicitly.
- **Verification:** Clean migration manifest applies once; RLS/ACL tests prove anon denial and least-privilege authenticated behavior; no duplicate version ambiguity exists.

## R1-011 — Contractor and rate administration lacks transactional domain audit

- **Severity:** Medium
- **Affected:** `app/api/admin/contractors/route.ts`; `vendors`; `contractor_rate_items`; administrative audit views
- **Expected:** Contractor qualification, emergency capability, rates, effective dates, and payment terms change through authorized RPCs that atomically write attributable audit events.
- **Actual:** The route uses the service-role client to insert directly into tables. Successful changes do not create domain activity/audit rows.
- **Evidence:** Route lines 15–30 and 35 onward call `admin.from(...).insert(...)`; no audit RPC or activity insert accompanies them.
- **Proposed fix:** Replace direct service-role writes with administrator-only transactional RPCs, validation, effective-date overlap controls, and audit events.
- **Verification:** Every create/update/deactivate/rate revision yields one attributable audit record; unauthorized callers and overlapping invalid rates fail.

## R1-012 — Release-1 operational email delivery is not configured or verified

- **Severity:** Medium
- **Affected:** `lib/notifications/provider.ts`; assignment/payment notification flows; Auth invitation environment/runbook
- **Expected:** Approved email delivery for assignments, approvals, payment events, and account invitations has observable delivery/failure records, or Release 1 explicitly accepts a documented `NOT_CONFIGURED` limitation.
- **Actual:** The application provider is a no-op and exposes SMS/WhatsApp emergency methods plus assignment `NOT_CONFIGURED`; no application email channel/provider exists. Auth invitation email depends on external Supabase configuration not verified by repository tests.
- **Evidence:** `getNotificationProvider()` always returns `NoopNotificationProvider`; email is described in docs as an extension channel.
- **Proposed fix:** Decide Release-1 email scope. If required, implement a server-only provider, outbox worker/idempotency, safe diagnostics, templates, and delivery UAT. Otherwise document and approve the limitation.
- **Verification:** Synthetic recipient receives approved test email with outbox correlation, retry/idempotency, safe failure behavior, and no secret/PII leakage in logs.

## R1-013 — Product documentation contradicts the implemented Release-1 scope

- **Severity:** Medium
- **Implementation status (2026-09-24):** **Verified.** `PRD.md`, `COMMERCIAL.md`, `TASKS.md`, and `WORKFLOW.md` now define Release-1 operational commercial control while preserving the boundary that FMWorks is not an accounting ledger. The documents explicitly separate physical completion, verification, documentary completion, actual-cost reconciliation, payment, no-payment disposition, and closure, and record the below/at-or-above S$1,000 quotation rules. `tests/release-one-governance-docs.test.ts` passes.
- **Affected:** `docs/PRD.md`; `docs/TASKS.md`; `docs/COMMERCIAL.md`; Release-1 work-package documents and migrations
- **Expected:** The controlling PRD/data model/workflow state whether commercial billing/payment is in Release 1 and define its acceptance criteria.
- **Actual:** Core documents call commercial billing/inventory “planned” or out of scope, while dated migrations/UI implement quotation, final account, approval, payment, and closure-related behavior.
- **Evidence:** PRD out-of-scope section and TASKS “Inventory and commercial — planned” conflict with Release-1 migrations and workspace.
- **Proposed fix:** Approve one Release-1 specification covering physical, documentary, commercial, payment, exception, and closure state machines before implementation changes.
- **Verification:** Requirements traceability maps every approved rule to UI, RPC, schema, tests, and UAT with no contradictory scope labels.

## R1-014 — Build success can conceal skipped type/lint validation

- **Severity:** Low
- **Implementation status (2026-09-24):** **Verified.** `.github/workflows/ci.yml` runs TypeScript, ESLint, Vitest, and the Next.js production build as four explicit commands. The governance regression asserts all four remain present, and the checks pass locally.
- **Affected:** Next.js build configuration/output; CI/release interpretation
- **Expected:** Release reporting distinguishes compilation from type/lint quality gates.
- **Actual:** `next build` reports “Skipping validation of types” and “Skipping linting.” This audit ran both separately and they passed, but build alone does not prove them.
- **Evidence:** Build output from 24 September 2026.
- **Proposed fix:** Keep separate mandatory CI jobs and prevent release evidence from labeling build as covering type/lint.
- **Verification:** CI fails independently on injected type and lint violations even when Next compilation would otherwise succeed.

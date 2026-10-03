# Release-1 incremental rectification — 3 October 2026

Branch: `reconciliation/release1-incremental-repair`, PR #5. No merge, main change, Production database access, or Production deployment.

## Continuation baseline and evidence

- Synchronized PR #5 at `0107811adb40a9a634eb084d2f14dbbd5b7d65a4`.
- Run #9 (`37089747193`) passed 0037 through 0043, then failed at the fixture-dependent UAT block in `20260918083838`. The SQL readiness and 0031/0032/0033/0037 investigations were not restarted.
- Six historical Preview corrections now return with a notice only when their target Work Order/profile is absent. DDL and existing-target prerequisite checks remain. This is a replay correction to those historical files; it does not require reapplying already-applied migrations to Preview.
- Run #10 (`37093926434`, commit `596c5bc`) passed the complete canonical migration replay, then failed on an ambiguous local `facility_id` in the field-owner regression.
- Run #11 (`37094228994`, commit `767bfb1`) also passed complete replay including procurement policy; it stopped at the same field-owner test before the following repairs were published.

## Defect families repaired

### Company procurement policy

The low-value threshold is company policy, initially S$1,000. Only Facility Manager and Administrator may change it. The new administration page and authenticated API call a database-authorized RPC. Changes create immutable policy/band versions, retain actor/reason/time and transactional activity audit, and reject stale concurrent edits. Existing Work Order financial controls retain their policy version. Draft quotation edits preserve the governed estimate, serialized on the Work Order. Policy changes never rebind previous decisions. Single-customer deployment is the approved company boundary.

### Contractor/rate administration (R1-011)

The existing create-contractor/create-rate flows now use an authenticated, database-authorized RPC rather than direct service-role inserts. The established Supervisor/Facility Manager/Administrator master-data roles are retained; procurement threshold changes remain exclusively Facility Manager/Administrator. Creates and their domain audit commit atomically. Invalid references/dates/non-finite rates fail safely. Vendor-row serialization prevents overlapping active rate periods for the same category/type/description/unit. Update/deactivate capabilities are not claimed: the current administration UI exposes creates only.

### Field-owner authority overwritten by later commercial migrations

Behavioral replay after fixing the test ambiguity exposed two genuine regressions:

- Physical-completion readiness was evaluated before assigned-owner authority.
- The correction-aware evidence RPC restored broad management/requester authority, allowing a Supervisor/Administrator cross-owner call to reach storage validation.

A new migration restores the four-role assigned same-facility owner requirement before readiness/storage checks. It retains explicit post-completion correction windows, real storage-object validation, audit, and last-After-evidence protection. Evidence removal also requires the assigned owner. Actual execution costing/confirmation supports the same four assigned-owner roles, and the UI exposes those controls only to the assigned owner. Commercial proposal/payment authority is not broadened.

## Validation

- Local TypeScript, ESLint, Vitest and production build pass separately.
- Full canonical replay and rollback-only behavioral SQL regressions pass in PGlite PostgreSQL with the repository's minimal managed-Supabase schema contract. This is supplementary evidence, not a replacement for Docker/Supabase CI or browser UAT.
- SQL tests cover procurement role negatives, stale edits, boundaries, immutable history, audit rollback; contractor audit, role negatives, overlap and audit rollback; four-role cross-owner completion/evidence denial, unchanged records on denial, protected removal, and each assigned role's costing → stored After evidence → physical completion → audit path.
- Release verification now executes the new policy and contractor SQL regressions against isolated Supabase alongside the field-owner test.

## Remaining release gates and decisions

Continue the isolated Docker verification and authenticated browser workflows until technical failures are resolved. Recheck the current application against the whole existing defect register; no release acceptance is claimed by these repairs alone.

Existing owner-controlled decisions remain: emergency commercial-exception authorizer/deadline (R1-003), operational email provider or acceptance of NOT_CONFIGURED (R1-012), legacy 0011 provenance/disposition, and final protected Preview UAT access where required. They do not prevent unrelated authorized technical rectification. PR #5 remains unmerged.

## Full-chain privilege and browser-harness follow-up

Catalog inspection found authenticated EXECUTE retained on `submit_physical_completion_20260921_core(uuid,jsonb)`. The new hardening migration revokes that inherited private-core entry point so callers cannot bypass costing confirmation. It also revokes inherited service-role INSERT/UPDATE/DELETE/TRUNCATE on policy bands and enables RLS on the two private counter tables. The counter tables already denied anon/authenticated table access.

Browser acceptance is updated to use the assigned Technician for execution/evidence, then a separate Administrator for verification and independently approved no-payment disposition. Synthetic field identities receive active memberships on isolated active sites. A new browser test verifies persisted/audited Administrator and Facility Manager policy edits and Supervisor API denial. Administrator assigned owners retain ordinary field actions; the exception UI applies when the Administrator is not the owner.

## Run #12 and current-schema regression coverage

Run #12 (`37094725421`, commit `56dc4f0`) passed the complete native Docker/Supabase replay, all three new behavioral SQL regressions, typecheck, lint, unit tests and build. Browser acceptance recorded 26 passing tests, one lifecycle failure, and one Asset test that passed initially but failed during serial-suite retries. Its lifecycle evidence shows the expected approval-readiness gate: structured proposed cost, cost basis, execution arrangement and safety/isolation information were absent. The browser journey now records that basis before requesting approval. Asset tags include the retry index so retries cannot collide with a previous successful create.

The release harness additionally runs full-schema catalog assertions for public-table RLS, privileged-function anonymous denial and pinned search paths, private-core ACLs, and invoker-RLS views. A portable three-quotation regression uses isolated actors and exercises governed-estimate preservation, insufficient-quotation denial, three distinct contractors, explicit selection and independent approval against the final schema. Both additional regressions pass the supplementary PostgreSQL runtime; native CI remains the acceptance gate.

A portable financial regression now also runs against the complete schema with rollback-only fixtures: unresolved closure is denied, S$650 quotation cannot be paid against S$620 approved actual, S$620 payment is accepted, physical completion succeeds without final cost/invoice, Technician no-payment self-approval is denied, independent no-payment approval permits closure, final account derives S$620 from the actual ledger, and missing invoice still blocks payment-proposal submission. The supplementary PostgreSQL execution passes.

## Run #13 and special numeric values

Run #13 (`37095003404`, commit `89979ac`) passed replay and behavioral SQL and reached 26 passing browser tests. Its lifecycle test predates the approval-basis correction. The policy test matched its editable textarea reason before awaiting the save; the trace records the POST aborted (`status -1`) when the test immediately reloaded. It now waits for the POST response and persisted history, with retry-specific reasons and a threshold target different from the current value. Run #14 was superseded while pending by Run #15, rather than executing.

The financial defect-family review found that PostgreSQL accepts `NaN` despite non-negative numeric checks. A new migration adds finite-value constraints across Work Order numeric data and financial controls, cost/rate/quotation lines, final-cost submissions, payments and procurement commitments. It validates existing rows without rewriting historical decisions. Release-1 and execution APIs reject non-finite and malformed supplied financial numbers before dispatch. A direct RPC NaN proposal regression proves its financial control, quotation and audit mutations roll back. The complete supplementary replay and six current-schema behavioral/security suites pass. Local typecheck, lint, 742 unit tests and build pass; native verification of this head remains required.

## Run #15: acceptance/start and commercial scope repairs

Run #15 (`37095804482`, commit `72f43c9`) passed full replay and all six current-schema SQL suites, including three-quotation and financial reconciliation. Browser acceptance recorded 27 passes. The remaining lifecycle failure reached assignment acceptance but never exposed Start: the current acceptance RPC treated an existing assignment as `NO_CHANGE` even when `accepted_at` was empty. The new migration makes that shortcut conditional on an actual prior acceptance. It also aligns Start with the established four assigned field-owner roles, enforcing active facility authority and prior acceptance, and preserving idempotent timestamps/audit. The expanded behavioral test exercises accept/start/cost/evidence/completion for all four roles, including pre-accept denial and repeat-call audit counts.

The whole-application financial data-access review identified broad active-account SELECT policies on actual cost lines, financial controls and payment assessments. A restrictive Work Order visibility policy now intersects those policies. Thirty-one commercial read/mutation RPCs preserve their existing domain implementations behind private cores and enforce the established Work Order visibility boundary before dispatch. The workspace API checks row visibility before loading child data or invoking mutations, rejects malformed payloads and contains transport exceptions. A new SQL regression denies direct financial reads and all 31 RPCs to unrelated Reviewer/Initiator and out-of-facility field/management actors, verifies unchanged audit/financial state, and proves authorized requester/facility/Approver/Administrator reads remain available.

Browser invocation without gate identities now fails during configuration load, before a web server starts, with `npm run release:verify` as the setup instruction. The release runner stops disposable local Supabase without retaining test data on success or failure. The lifecycle fixture uses a complete synthetic PNG and precise status assertions. Local typecheck, lint, 757 unit tests, build, full supplementary replay and seven current-schema SQL suites pass. Native verification of the latest head is still required.

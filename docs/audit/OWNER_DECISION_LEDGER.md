# FMWorks Owner Decision and UAT Fault Ledger

Recovered 20 October 2026 (SGT) from the owner's local Codex history
(`~/.codex/thread_history_1.sqlite`, 8 July – 24 September 2026). Every entry quotes
the date the owner stated it. Conversations after 24 September (including the
October defect review and the four owner decisions) were not stored locally and
are **not** recovered here.

Status key: **IMPLEMENTED** = current code matches (checked at `488dc28`);
**CONFIRM** = code differs from an earlier instruction or documents disagree, owner
must choose; **PREVIEW CHECK** = needs visual/hosted confirmation; **OPEN** = owner
decision still outstanding.

## A. Business rules stated by the owner

| ID | Date | Rule (owner's words, condensed) | Current code | Status |
|---|---|---|---|---|
| B-01 | 11 Sep | Assigned Technician is the field witness/recorder. Facility-wide Technician READ; upload/mutation only for the Work Order's assigned Technician UUID. Job title/trade must not decide authority. | Assigned-owner checks in field-evidence and execution RPCs (0036, 0039, 0040, 20261003034657). | IMPLEMENTED |
| B-02 | 11 Sep | After submission as Completed – Awaiting Verification, Technician evidence becomes read-only; corrections via governed reject/reopen. | Evidence lifecycle and rework controls (0017, 20260920223606, 20260921123840). | IMPLEMENTED |
| B-03 | 9 Sep (WP-FMW-020) | Technician/Reviewer may RECORD work but must NOT formally set Completed; Administrator may. Supervisor/Facility Manager authority left for a later decision. | Superseded in practice: from 14 Sep the owner asked for Technician "Submit Completed Work / Submit for Verification"; 24 Sep confirms Technician submits physical completion. Since 0040 any **assigned** Technician, Supervisor, Facility Manager or Administrator can submit physical completion; Administrator exception completion needs a reason. `docs/WORKFLOW.md` still says Technician only. | SUPERSEDED by D-01 |
| B-04 | 9 Sep (CW-05) | Wording "Verify Completed Work" / "Reject & Reopen". Administrator may self-verify only with mandatory override reason, audited. | Old strings absent from app; `verify_completed_work` requires reason for Administrator self-verification and denies other self-review. | IMPLEMENTED |
| B-05 | 13 Sep | Supervisor approval authority up to S$250,000; not above. | 0037: <=S$250k Supervisor/FM/Admin; S$250k–500k FM/Admin; >S$500k Admin only. **Approver role cannot approve Work Orders.** `docs/WORKFLOW.md` and unused `lib/permissions.ts` still say Approver approves. | SUPERSEDED by D-02 |
| B-06 | 18–19 Sep | Technician records/recommends cost and quotation; must not approve own expenditure; independent Facility Manager/Approver approval. | Proposal and payment approval with self-approval denial (20260919064024 onward). | IMPLEMENTED |
| B-07 | 18 Sep, configurable 3 Oct | Below S$1,000 one quotation; at/above, three distinct eligible-contractor quotations. Threshold is company policy changeable only by Facility Manager/Administrator with audit; past Work Orders keep their version. | 20261003033514, 20260924044237–045239. | IMPLEMENTED |
| B-08 | 19 & 24 Sep | Approved quotation (S$650) distinct from actual cost (S$620); never summed. Payment proposal and Finance payment recorded separately. | Ledger-derived actual cost; WO-TEST-012 reconciles 650/620/620/620. | IMPLEMENTED |
| B-09 | 19 Sep | Previously agreed 30-day payment commencement rule. | `interval '30 days'` in 0030 payment assessment. | SUPERSEDED by D-05.3 |
| B-10 | 21 Sep | Final cost above approved expenditure requires additional authorization. | Variance approval in final-cost submission (20260921122902). | PREVIEW CHECK |
| B-11 | 21 Sep | Verified Work Orders: document-only correction without reversing physical completion; Closed: authorized reopening. | Supporting-document corrections (20260920223606). | IMPLEMENTED |
| B-12 | 24 Sep | Physical completion must not require final invoice; closure requires recorded payment or approved no-payment disposition. | R1-001, R1-004, R1-005 verified. | IMPLEMENTED |
| B-13 | 9–12 Sep | Never invent drawing coordinates; a human Administrator places markers via the location configuration page. | Facility location configuration (WP-FMW-025L2). | IMPLEMENTED |

## B. Work Order faults observed by the owner in Preview UAT

| ID | Date | Work Order | Fault | Recorded outcome | Status |
|---|---|---|---|---|---|
| AUTH-01 | 9 Sep | — | Only Administrator could log in. | Committed "fix: unblock governed first-login password setup"; Playwright role logins pass locally. | PREVIEW CHECK |
| CW-01 | 9 Sep | WO-TEST-013 | Socket SOCKET-L2-P-04 (PAN-01, FW-002) not shown on plan. | Needs human coordinate placement. | PREVIEW CHECK |
| CW-05 | 9 Sep | — | Old wording; Administrator could not verify Completed Work. | See B-04. | IMPLEMENTED |
| UB-01 | 12 Sep | WO-TEST-001 | Utility Block (P-CHW-01, Chiller Plant Room, FW-001) location marker missing. | Configuration page added; human placement of CPR-01 pending. | PREVIEW CHECK |
| WO-004 | 14 Sep | WO-TEST-004 | Assigned Technician saw "No workflow action is currently available". | Technician field-work screen implemented. | PREVIEW CHECK |
| VIS-01 | 18 Sep | WO-001–WO-015 | Duty Technician Yang got 404 on same-facility Work Orders. | Facility read baseline repaired. | PREVIEW CHECK |
| RS-01a | 18 Sep | WO-012 | No drawing markup tool; evidence read-only; no cost workflow. | Markup, evidence and cost workflow added. | PREVIEW CHECK |
| RS-01b | 19 Sep | WO-TEST-012 | RS-01 marker on parking canopy instead of Main Building loading dock. | Migration 20260919002732 relocates marker. | PREVIEW CHECK |
| Q-01 | 19 Sep | WO-TEST-012 | Quotation section not operational. | Proposal → approval → final account flow added. | PREVIEW CHECK |
| DOC-01 | 20 Sep | WO-TEST-012 | Evidence read-only with no attachments; no way to attach quotation. | Supporting document upload added. | PREVIEW CHECK |
| EV-01 | 21 Sep | — | Need replace/remove of wrong evidence and final-cost section. | 20260921122902, 20260921123840. | PREVIEW CHECK |

## C. Code findings while recovering (20 Oct)

- `lib/permissions.ts` is not used by any page or API, encodes superseded rules
  (Approver-only approval; Technician-only start/complete) and is the subject of
  `tests/permissions.test.ts` (27 tests). Those passing tests do not verify the live
  permission rules in `lib/work-orders/permissions.ts`. Owner decision needed
  before removal (see Defect family 19, 3 Oct review).


## E. Owner decisions — 20 October 2026 (stated directly to Claude)

Rule of precedence (owner): **the latest statement supersedes earlier ones.**

### D-01 Work Order lifecycle (supersedes B-03)

1. The **assigned Technician creates** the Work Order and submits it with supporting
   material: photos, videos, voice messages, the reason the work is needed, and the
   contractor's **quotation**.
2. **Supervisor / Facility Manager / Administrator approves** (within their monetary
   authority, D-02). Only then may the contractor proceed.
3. **Work variation:** a revised quotation is **resubmitted by the Technician** and must
   be re-approved.
4. **Every Work Order is reviewed** by Supervisor / Facility Manager / Administrator, who
   approves the **work done together with the cost and substantiating documents**.
   Only that approval moves the Work Order to **"Completed"**.
5. After "Completed", **Finance pays the contractor** under the contractual payment
   terms; the app tracks whether payment has or has not been made.
6. **Emergency:** the contractor is told of the urgency and fixes the fault **without a
   prior quotation**. The quotation follows after the work, with evidence. It must
   **tally with the contractor's pre-agreed labour and material rates**, which are held
   in the app for reference. The **same review/approval** as a normal Work Order then
   applies before "Completed".

### D-02 Approval authority and terminology (supersedes B-05)

1. Work Order approval: Supervisor up to S$250,000, Facility Manager up to S$500,000,
   Administrator any amount (current code).
2. ~~"Approver" is a generic term and is excluded for now.~~ Superseded by D-04.
3. Role names must be **renameable**, because companies use different terminology.
4. Approval amounts are **adjustable, by the Administrator only**.

### D-03 Follow-up answers — 20 October 2026

1. **Closed stage retained:** Completed → Finance records payment → Closed.
2. **New Finance role** records contractor payments only; it cannot approve work.
3. **Emergency quotation:** no fixed deadline. The Work Order cannot reach "Completed"
   until the after-the-fact quotation is submitted and tallies with the contract rates;
   outstanding emergency quotations remain visible. (Resolves R1-003.)
4. **Quotation threshold** (1 vs 3 quotations, initially S$1,000) becomes
   **Administrator-only**, like the approval limits, with an audit reason.

### D-04 Approver role retained — 20 October 2026 (supersedes D-02.2)

The **Approver** role stays in the app. It represents anyone authorised to approve the
completion of a Work Order who has not yet been assigned a specific position
(Supervisor, Facility Manager or Administrator). Owner answers the same day:

1. **Monetary limit:** same as Supervisor — initially S$250,000, adjustable by the
   Administrator only.
2. **Facility scope:** own facilities only, through facility membership, like
   Supervisor and Facility Manager.
3. **Powers:** same as Supervisor, including assigning and cancelling Work Orders.
   Contractor payments are recorded by the Finance role (D-03.2), not by Approver.
4. Independence still applies: nobody approves a Work Order they requested or are
   assigned to carry out (existing self-approval/self-review denial).

### D-05 Lifecycle design questions — 20 October 2026

1. **Emergency:** the Technician may tell the contractor to start immediately; approvers
   are notified.
2. **Only Technicians create Work Orders.** (System-generated PM/Incident Work Orders
   are assigned to a Technician, who completes them — confirmed by approval 13:41.)
   **Amended 13:38:** when the Technician is unavailable, **his superior can open the Work
   Order**, so the process need not depend only on the Technician. (Design: Approver,
   Supervisor, Facility Manager, Administrator; a creating superior cannot also approve it.)
3. **Invoice:** the contractor issues the invoice when final approval ("Completed") is
   received and gives it to the Technician, who uploads it. Payment starts when
   **Finance receives the invoice**, according to the stipulated payment terms — **not**
   on the completion date. The invoice amount must tally with the approved revised
   quotation. The upload goes to Finance and copies the Technician, the Approver,
   Supervisor/Facility Manager, Administrator, or whichever parties were copied on the
   Work Order. (Supersedes B-09's 30-day-from-completion rule.)
4. **Rate differences:** owner gave no preference; default adopted — allowed with a
   written reason, clearly flagged to the approver.
5. **Finance scope:** not asked; default adopted — company-wide.

### D-06 Design sign-off — 20 October 2026 13:41

`docs/design/WORK_ORDER_LIFECYCLE_V2.md` approved by the owner.

## D. Decisions still open (not recoverable locally)

1. ~~Emergency commercial exception (R1-003)~~ resolved by D-01.6 and D-03.3.
2. Operational email: provider or accept `NOT_CONFIGURED` (R1-012).
3. Disposition of untracked `0011_secure_legacy_public_tables.sql` (R1-010).
4. Vercel deployment-protection access for hosted UAT (R1-009).
5. ~~B-03 and B-05~~ resolved by D-01/D-02 on 20 Oct. Follow-up questions: see chat 20 Oct.

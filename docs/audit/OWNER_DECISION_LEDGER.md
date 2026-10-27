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

### D-07 In-house work — 20 October 2026 16:53

Owner: "Work order will be carried out as per normal and the pricing part will be waived. I think
we can create the same workflow except to declare that services are provided in-house. No
pricing is required."

Design: the preparer declares **Services provided in-house** on the Work Order. The same
approval, execution and review apply (approval authority, facility, independence). No quotation,
final cost, invoice or payment is required; after the review to "Completed" the Work Order closes
automatically with an audited in-house no-payment record. (Resolves KNOWN_ISSUES LC2-001.)

### D-08 Site location, Before evidence and final quotation — 20 October 2026 22:32

1. **Layout plan (owner):** marking the location on the layout plan is **required**, "as we do
   not assume everyone is familiar with the factory layout, eg. a finance person". Required before
   submission; for emergency work (which starts on submission) owner gave no answer — default
   adopted: required before the review to "Completed".
2. **Before evidence:** owner "no preference"; default adopted (consistent with D-01.1, the
   Technician creates the Work Order with photos/video/voice): at least one Before photo, video,
   voice note or PDF is required before submission; emergency work exempt.
3. **Variation (owner):** "usually the variation will not be too significant … we have the
   contractor's labour and materials rates to justify the work variation and hence the final
   quotations will be submitted based on the actual work performed with variations." Adopted:
   the variation is approved **at the review**; when the final cost differs from the approved
   quotation, the contractor's final quotation for the work actually performed must be attached;
   the reviewer's limit applies to the final cost and the invoice must equal it.
4. Work duration (start → submitted as done) and overall duration are shown on the Work Order.

Owner clarification, 22:42 (supersedes the defaults above where different):
"When the work order is issued, the location of work to be performed will be highlighted, eg
utility block, electrical room … the app will be intelligent enough to point to the correct
specific location. In an emergency … the technician in charge will add in the work order plus a
quotation that is site-verified by him upon submission … the photos before and after work have to
be uploaded … Good to show the before work photo uploaded by the technician. The revised final
quotation will be submitted and verified by the technician who supervises the work to ensure
that the quoted materials and labour are properly accounted for."

- The creator chooses the **area/room**; an area already placed on the layout plan is
  highlighted automatically and satisfies the location requirement; otherwise the spot is marked
  by hand. The area must belong to the Work Order's facility.
- Emergency: Before **and** After evidence and the location are required before the review (the
  work is not delayed at the start).
- Before (then After) photos are shown inline on the Work Order.
- The final quotation is saved with the supervising Technician's site-verification declaration
  (materials and labour match the work actually performed).
- Follow-up: areas need their layout-plan positions configured by an Administrator for automatic
  highlighting (currently none of the 25 standard areas are placed).

### D-09 Start and end times — 21 October 2026 16:43

Owner: "automatic logging is good." Work start and end times stay automatic: logged when the
assigned Technician clicks **Start work** and **Submit Physical Completion**. No manual entry of
actual times.

### D-10 Sharing for quick creation on phone and computer — 21 October 2026 17:04

Owner: "prepare this app to be shared with the Technician, Facility Manager, Administrator,
Approver to quickly populate the work order info for creation … in a computer or through a mobile
phone. He can partially complete the app and later continue on his computer before submission."
Agreed batch (built after the 21 Oct demo, nothing applied before the owner's go-ahead):
"My Drafts" shortcut; phone-friendly quick create with next steps after Create Draft; the
Technician guide built into the app; installable on phones from the browser. Sharing still needs
a Vercel link that works without a Vercel login (R1-009) and accounts for each person.

### D-11 UAT feedback — 22 October 2026 23:38 (supersedes D-09)

1. **Location pin:** automatic from the Work Order's area, placed once per area by the
   Administrator (Facility Locations); manual marking only optional. The mock-up drawings are
   placeholders; the commercial version uses the facility's own PDF layout drawings (Stage 2).
   Add a Generator Room to the Utility Block mock-up. The facility uses split air-conditioning,
   not chillers. Owner gave no preference on the UAT data; default adopted: chiller items are
   renamed to split air-conditioning equivalents (Preview data change needs the owner's go-ahead).
2. **Finance as copied party:** not selectable while drafting; added automatically when the Work
   Order reaches Completed.
3. **Second-Technician endorsement:** the Technician who raised the Work Order may update it to the
   end, but a second Technician must endorse that it is authentic; joint and several
   responsibility. Owner: the stage is a per-facility setting on the facility configuration form,
   with three choices: before submission, before the Approver's review, or both.
   Owner's preferred default (23:43): before the Approver's review.
   Confirmed (23:48): every facility starts on the recommended default (before the Approver's review);
   the Administrator may select either of the other two options on that facility's settings form.
   Implemented as: no settings row = before the review; changes are audited in facility settings history.
4. **Approver per facility:** the Approver is configured per facility by the Administrator on a
   facility settings form (varies by facility); Facility Manager or Supervisor may also act.
   Owner gave no preference on exclusivity; default adopted: the designated Approver is the
   default and is notified, and that facility's Facility Manager or Supervisor may also act.
5. **Start and end times (supersedes D-09):** entered and editable by the Technician, not
   automatic, so they can be filled in later; the duration is computed from them. Owner gave no
   preference on timing; default adopted: required before the Approver's review, not at
   submission of the work.
6. "Withdraw Completion for Correction" behaviour confirmed as useful.

Implementation (WP-LC2-M7, migration `20261022120000_lifecycle_v2_facility_settings.sql`; owner said GO 23:57):
Administration → Facilities (designated Approver, endorsement stage, reason, history) and a Facility
Locations link; Second Technician endorsement panel (a Technician of the same facility, not the
responsible one; a fresh endorsement after each return to Draft or each completion submission);
Actual work times panel (assigned Technician; start now, end later; locked after the review);
Finance hidden from the copy lists and copied automatically at Completed. FW-001 Utility Block:
the Outdoor Service Area became the Generator Room (4.0 x 6.0 m). Split-AC data:
`scripts/rollout/preview-split-ac-inventory-20261022.sql` (read-only) and
`scripts/rollout/preview-split-ac-rename-20261022.sql` (dry run by default; not applied).

### D-12 Name the assigned Technician on every Work Order — 27 October 2026 13:51

Owner: "It may be good to name the assigned Technician for the work order so that it is evident the
assigned technician can only make changes to the work order." Implemented: the Next action box on the
Work Order names the Assigned Technician and states that only they (or the superior who created it, while
a Draft) can change the details, evidence, quotation and work record; other viewers also see who they are
signed in as. "No action available for your role" is replaced by plain guidance ("Finish the next steps
below, then submit for approval" for the preparer of an incomplete Draft).
Context: UAT on WO-TEST-010, where the page was viewed while not signed in as the assigned Technician.

### D-13 Attached quotation is the official record — 27 October 2026 14:25

Owner (UAT on WO-TEST-010): itemized charges "may not be suitable to cut and paste from contractor's
quotation"; agreed (14:25) to make the box optional. Implemented: the field is now "Summary of charges
(optional — the attached quotation is the official record)". Submission still requires the attached
authentic quotation (QUOTATION_DOCUMENT_REQUIRED), unchanged; the database never required the summary.

### D-14 "Other supporting document" evidence option — 27 October 2026 15:59

Owner: "For field evidence filing, please include 'Other supporting document' as another option for
Technician to input." Implemented (WP-LC2-M8, migration `20261027100000_lifecycle_v2_supporting_document.sql`):
the Evidence category list offers Before, After and **Other supporting document** (stored as the existing
category `document`). It does not satisfy the Before or After evidence requirements. Same upload rules
(photo, video, voice, PDF; assigned Technician or the creating superior while drafting).

### Preview rollout record — 21 October 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 15:44 | Backup of `public` + `supabase_migrations` (942,261 bytes, owner's `.git` folder) | Owner, guided |
| 15:47 | Lifecycle v2 upgrade applied in one transaction (adapter sha256 `d059dc59…`, identical to the rehearsed build); ledger 38 → 56, last `20261020110000` | Owner, guided |
| 16:15 | Facility membership added: approver sctpec2413@gmail.com at the Technician's facility | Owner, guided |
| 16:20 | engchian@yahoo.com role reviewer → finance (through the profile-admin guard) | Owner, guided |
| 22:55 | Backup of `public` (1,013,705 bytes) before the UAT conversion | Owner, guided |
| 22:58 | UAT conversion (`scripts/rollout/preview-uat-conversion-20261021.sql`): FW-2026-0001, WO-TEST-002, 005, 007, 010, 011, 015 returned to Draft and assigned to Technician koi.kpr@gmail.com; WO-TEST-008 (Submitted for Review) assigned to him. One audited `work_order_converted_lifecycle_v2` entry each; a repeat run was refused | Owner, guided |
| 23:20 | Second Technician ec@glorybene.com created by the Administrator; technician facility membership added (facility 8416e544…) | Owner, guided |

Connection: Supabase CLI temporary login (`cli_login_postgres.pvajuywwwpjlikqjnvgv`) with
`set role postgres`; the Preview database password was reset the same day. Vercel Preview
deployment `f9bef5e` (branch `uat/claude-review`). Production untouched.

### Preview rollout record — 23–24 October 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 23 Oct 22:57 | `release:verify` PASS on the owner's computer (`fwm-uat`), incl. the endorsement-panel fix; 1 known flaky AI-PDF test passed on retry | Owner |
| 23 Oct 23:56 | Commit `48f377f` pushed to `uat/claude-review` (33 files); Vercel Preview build triggered | Owner |
| 24 Oct 00:00 | Backup of `public` + `supabase_migrations` (2,002,645 bytes, `.git/preview-backup-20261023-pre-m7.sql`) | Owner, guided |
| 24 Oct 10:17 | WP-LC2-M7 upgrade applied in one transaction (`scripts/rollout/build-preview-lc2-m7.mjs`); preflight 56 ledger entries, latest `20261020110000`; ledger now 57, last `20261022120000`; COMMIT | Owner, guided |
| 24 Oct 22:20 | Split air-conditioning rename applied (`scripts/rollout/preview-split-ac-rename-20261022.sql`, owner-approved after the dry run): CPR-01 Chiller Plant Room → GNR-01 Generator Room; 4 assets renamed (ACCU-01, ACCU-02-FAN, ACCU-03-CMP, SAC-L2-08); WO-TEST-011 and WO-TEST-015 retitled with an audited `work_order_uat_data_corrected` entry; closed WO-TEST-001 and WO-TEST-014 kept as recorded; COMMIT | Owner, guided |

## D. Decisions still open (not recoverable locally)

1. ~~Emergency commercial exception (R1-003)~~ resolved by D-01.6 and D-03.3.
2. Operational email: provider or accept `NOT_CONFIGURED` (R1-012).
3. Disposition of untracked `0011_secure_legacy_public_tables.sql` (R1-010).
4. Vercel deployment-protection access for hosted UAT (R1-009).
5. ~~B-03 and B-05~~ resolved by D-01/D-02 on 20 Oct. Follow-up questions: see chat 20 Oct.

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

### D-15 Passed due date shown clearly before submission — 27 October 2026 16:41

UAT on WO-TEST-010: "Submit for approval" failed with "The workflow service is temporarily unavailable".
Diagnosis (`scripts/rollout/preview-diagnose-submit.sql`, rolled back): the due date (3 Sep 2026) was
before the submission date, which the long-standing check `work_orders_due_date_check` refuses. Fix (added
to the not-yet-applied migration `20261027100000_lifecycle_v2_supporting_document.sql`): a Draft with a passed
due date lists "Due date has passed — update the due date" in Next steps (linked to Edit Work Order), and
submission returns DUE_DATE_PASSED with a clear message. Workaround until applied: edit the due date first.

### D-16 Shorter Work Order page: scrollable audit history — 27 October 2026 17:18

Owner: "I suggest you can scroll the audit history to shorten the work order." Implemented: the Audit
history on the Work Order page sits in a fixed-height box (about 28 rem) that scrolls inside, newest first,
with the number of entries shown. Nothing is removed from the history.

### D-17 Administrator sets up facilities, drawings and staff — 27 October 2026 17:59

Owner: "Allow Administrator to add in new facilities, and their drawings to be downloaded,
including staff of that facility." Read as: the Administrator adds and edits facilities,
uploads their drawings (staff view and download them), and assigns the facility's staff.

1. **Administration → Facilities** (Administrator only): add a facility (code, name, address),
   optionally starting with the 25 standard areas (Generator Room GNR-01, not Chiller); edit
   details or mark it not in use (refused while it has open Work Orders); add areas; upload and
   remove drawings; add and remove staff (Technician, Approver, Supervisor, Facility Manager).
   Every change needs a reason and is recorded in the activity log.
2. A new facility starts on the recommended settings (D-11): endorsement before the Approver's review.
3. Drawings: PNG, JPEG, WebP or PDF up to 50 MB, stored privately; a drawing number may be used
   once per facility while active (FW-001 to FW-005 stay reserved for the mock-ups). Removing a
   drawing keeps its record and file for the audit trail. Any signed-in staff member can view or
   download drawings from the new **Drawings** page and on each Work Order of that facility, through
   a link valid for 5 minutes.
4. A facility's own image drawings replace the mock-ups for area pins (Facility Locations) and
   Work Order markup at that facility; facilities without uploaded drawings keep the mock-ups.
5. Area codes are now unique per facility (the same code may be used at two facilities).
6. Database: migration `20261027120000_facility_setup.sql` (WP-FS-M9); applied to Preview together
   with `20261027100000` (D-14/D-15) by `scripts/rollout/build-preview-increment.mjs`, rehearsed
   locally on an M7-state copy (ledger 57 → 59; wrong target and repeat refused).
7. Still open: whether "Both" should become the default endorsement stage for new facilities.

### D-18 Archive and off-site copy, set per facility — 27 October 2026 18:42 (Stage 2)

Owner: closed Work Orders are saved in an archive and can be saved to a disk off-site; "after how
many months a closed Work Order should move to the archive" and "how often the off-site copy should
be made" "should be based on each facility's practices. Therefore this will be included in the
configuration requirements setup."

1. Two new facility settings, chosen by the Administrator in Administration → Facilities with a reason,
   recorded like the other settings: **archive after N months closed** and **off-site copy frequency**.
2. Archived Work Orders leave the everyday list but stay viewable and searchable with their full audit
   history, evidence and documents; nothing is deleted.
3. The off-site copy is a downloadable bundle per facility and period: register, audit trail,
   evidence, quotations, invoices and drawings, for the facility to save to its own off-site disk.
   The app reminds the facility when a copy is due.
4. Not built yet (Stage 2). Defaults to propose with the Advisor; until then closed Work Orders stay in
   the main list and the CSV register export remains available.

### D-19 Variation order stated at the final cost — 27 October 2026 19:04 (refines D-08)

Owner: "I need you to confirm if a variation order is included in the work order carried out or the
pricing remains the same. If it is the same, then enter the same quotation in the final quotation after
work order is performed. Otherwise, include a new quotation with revised pricing." 19:10: "We use
variation and submit a revised quotation with justification for Voltquay."

1. After the work, the assigned Technician must answer "Was there a variation order from the contractor?"
   before the final cost can be saved (contractor work with a quotation; not in-house work, and not an
   emergency job whose after-the-fact quotation does not exist yet).
2. **No, price unchanged:** the approved quotation is recorded as the final quotation; the final
   contractor charge is fixed at the approved amount.
3. **Yes, variation order:** the Technician enters the revised charge and a justification (why the price
   changed), and must attach the contractor's revised quotation; the review is refused without it. A
   revised amount above the approved amount still needs the reviewer's recorded reason (unchanged rule).
4. Final costs saved before this change keep the D-08 rule.
5. Display fixes in the same batch: the Cost Summary shows the approved, else recommended, quotation (it
   showed the last one entered, which named Northline instead of the recommended Voltquay on WO-TEST-010);
   the Status card shows the stage name ("Awaiting Approval", not "submitted").
6. Database: migration `20261027140000_final_quotation_variation.sql` (WP-FQ-M10); joins M8 and M9 in the
   next Preview increment.
7. UAT data for WO-TEST-010: Voltquay revised quotation VQ-Q-2026-0957 Rev 1 / VO VQ-VO-2026-0957-01,
   S$13,500.00 before GST (+S$1,737.50: extra 70 litres of oil and disposal, seized drain valve replaced,
   half a day more filtration).

### D-20 Second Technician endorses the final cost and any variation order — 27 October 2026 19:22 (refines D-11)

Owner: "Technician 2 has to endorse the work order, Shouldn't this work order needs to be modified following
the addition of the VO by Technician 1?" Confirmed 19:24: yes.

1. The review endorsement can be given only once the final cost is saved and, for a variation order, the
   revised quotation is attached (in-house work: no final cost needed).
2. The endorsement panel shows what is endorsed: final contractor charge, variation yes/no, justification,
   and whether the revised quotation is attached.
3. A change to the final charge, the variation answer, the justification or the attached quotation after the
   endorsement cancels it; the panel says so, and the review is refused until the second Technician endorses
   again. A review endorsement given before this change must be given again once a final cost exists.
4. Database: in migration `20261027140000_final_quotation_variation.sql` with D-19.

### D-21 Correct an actual cost typed in by mistake before the review — 28 October 2026 11:52

Owner: "The Technician is unable to change the actual repair cost which was typed in by mistake. Can you allow
amendment?" (WO-TEST-010: S$13,770,000.00 entered instead of S$13,500.00.)

1. While the Work Order is Submitted for Review, the assigned Technician may edit their actual-cost lines,
   without the Approver having to Reject & Reopen. After the review, costs stay locked.
2. Any correction clears the costing confirmation and resets the saved final cost to draft; the Technician
   confirms the costing and saves the final cost again (with the variation answer, D-19).
3. The second Technician's endorsement covers the confirmed actual cost too (D-20), so it must be given again.
4. Also fixed: Return to Draft is shown even when approval is not available to the signed-in user.
5. Database: migration `20261028100000_actual_cost_correction_before_review.sql` (WP-AC-M11).

### D-22 Contractor actual cost = final contractor charge — 28 October 2026 22:55

Owner (22:53): "Why do I need to fill in this pricing info since i have already updated the contractor's quotation
line-by-line … what is the purpose?" Offered: take the Actual Cost automatically from the final contractor charge.
Owner (22:55): "Yes, please make the changes as required."

1. For contractor work, the actual cost of the job is the final contractor charge entered in Final Cost
   Reconciliation (the attached quotation, or revised quotation for a variation, is the official breakdown).
   The amount payable, the variance and the invoice check follow from it.
2. The Actual Cost lines become an "Itemised cost record (optional)", e.g. own staff's labour or materials
   supplied; they do not change the actual cost. The record is still confirmed (even if empty) before the work
   is submitted for review.
3. In-house work is unchanged: its actual cost is the total of the cost lines.
4. Database: migration `20261028120000_actual_cost_from_contractor_charge.sql` (WP-AC-M12).

### D-23 Delete a mistaken cost line; single-line form removed; work times editable until the review — 28 October 2026 23:25

Owner: "Item 1 cannot be deleted. There should be option to delete line item in this case." / single-line form:
"remove this item as it is not relevant" / "work started and work stopped date/time should be editable as more
work may be required."

1. The Technician may delete their own uncertified, unapproved cost line (Delete line → Confirm delete); the
   deleted line is kept in the audit trail and the costing must be confirmed again.
2. Cost lines are added only through the multi-line table; the single-line form appears only to correct a saved line.
3. Actual work start and end times can be changed by the assigned Technician until the Approver's review (no stale
   upper limit in the form; the database still refuses times in the future).
4. Database: added to migration `20261028120000_actual_cost_from_contractor_charge.sql` (not yet applied anywhere).

### D-24 Work is submitted for review with the official quotation — 28 October 2026 23:29 (refines D-08, D-19)

Owner: "The actual official quotation should be attached together with the submission of work order."

1. For contractor work with an approved quotation, Submit Physical Completion is refused until the Final Cost
   Reconciliation is saved: price unchanged (the approved quotation is the final quotation) or a variation order
   with the contractor's revised quotation attached. The page lists what is missing before submission.
2. The Approver therefore receives one complete package: work record, evidence, work times, final charge and the
   official (final) quotation, then the second Technician's endorsement.
3. Emergency work keeps its after-the-fact quotation route; in-house work has no quotation.
4. Database: added to migration `20261028120000_actual_cost_from_contractor_charge.sql` (not yet applied anywhere).

### D-25 Technician 2 as the independent checker — 30 October 2026 16:09 (refines D-11, D-20)

Owner: flash Technician 2's responsibility on screen with a checklist of to-dos; copied parties should include
Technician 2's name; "Technician 2 as a minimum must check the supervised work, against the materials and labour
performed, review it against Contractor's final quotation, review the site field evidence of work completed,
awarded contractor's quotation shall be reviewed with other competitors' quotations and justify the basis of the award."

1. When an endorsement is due, an eligible Technician sees a banner "You are the independent checker for this
   Work Order" linking to the endorsement panel.
2. The panel states the responsibility and lists the minimum checks to tick (review stage: supervised work against
   materials and labour; the contractor's final quotation, with any variation; the site field evidence; with
   competing quotations, the awarded quotation against the competitors). With competing quotations the checker also
   writes the basis of the award. The quotations are shown for comparison. Endorse is enabled only when all are done.
   Owner 16:36: Technician 2 "need not supervise the work but he has to verify the work is done according to the
   materials installed and quotation justified it" - the first two checks are worded as on-site verification of the
   work and materials against the final quotation, and the quotation justifying them.
   Submission stage (if the facility uses it): site evidence; quotation scope; award basis when quotations compete.
3. The database refuses an endorsement without every check (CHECKLIST_REQUIRED) or, with competing quotations,
   without the basis of the award (AWARD_BASIS_REQUIRED); the ticked checks are stored with the endorsement.
4. The endorsing Technician is added to the copied parties automatically and cannot be removed from them.
5. Database: migration `20261030100000_independent_checker.sql` (WP-IC-M13).

### D-26 Commercial forms only for the assigned Technician; contractor CSV panel retired — 30 October 2026 19:45 (refines D-22, D-25)

Owner 19:41 asked what the "Contractor actual costs" CSV upload is for, and noted that the statement "I supervised
this work…" was not what had been agreed for Technician 2.

1. The "I supervised this work…" box is Technician 1's declaration in Final Cost Reconciliation, not Technician 2's
   endorsement. It now reads "As the assigned Technician, I supervised this work and verified on site…".
2. Final Cost Reconciliation, the revised-quotation attachment and the invoice and payment entries appear only for
   the assigned Technician. Other Technicians, including the independent checker, no longer see them. The database
   already refused anyone else.
3. Technician 2's only endorsement remains the D-25 checklist panel ("verify, need not supervise").
4. The contractor-CSV upload panel is removed from the Work Order page: under D-22 the actual cost is the final
   contractor charge backed by the attached quotation, and the optional itemised record uses the multi-line table.
   The component and API route stay unused until Stage 2 decides on CSV import.
5. Owner 19:53: highlight the endorsement so the Technician does not miss it. While the work is under way, a
   Technician who may be the checker sees a non-flashing note ("No action yet…"). Once Physical Completion is
   submitted and the endorsement is due, the banner flashes with a red border and the endorsement panel at the end
   of the page has a red border and an "Action needed — your endorsement" label.
6. Owner 19:56: Technician 2 keeps seeing the costs (quotation prices, final charge, variation order and the
   quotation documents), because the D-25 award-basis check needs the competing prices. No change.
7. Owner 21:54: the selected variation choice and Save Final Cost Reconciliation are red until the final cost is
   saved; Attach Revised Quotation is red while the revised quotation is missing. A chosen file that has not been
   uploaded is flagged in red ("File chosen but not attached yet"), and a successful upload shows "Attached ✓" next
   to the button and refreshes the page's action box. The "Record Work Done" button is renamed "Physical Completion".
8. Owner 22:08: the "Next authorized action" button (e.g. Submit Physical Completion, Approve as Completed) is red,
   labelled "yours to click", since it is shown only to the person who must act.
9. Owner 22:23: the Approver sees Technician 2's endorsement in full: who and when, the statement, each check
   confirmed (ticked labels) and the basis of the award. A saved final cost shows as a "Saved ✓" summary; the form
   reopens only on "Change the final cost".
10. Owner 22:24: every Approver action is red for consistency: the independent approval forms (quotation approval,
    final cost variance authorisation, payment and no-payment approval) carry an "Action needed — your approval"
    label, a red button and a reason of at least 10 characters; the Approver's confirm buttons are red too.
11. Owner 23:25: once saved, the Technician is no longer prompted: the site-verification box, Save Final Cost
    Reconciliation and Replace Revised Quotation are hidden behind "Change the final cost" (a change cancels the
    endorsement), so they cannot be clicked unknowingly.
12. Owner 23:26: invoice and quotation must not be confused at final submission. The invoice was listed twice
    (the same list rendered in two places); it is now listed once. Upload Invoice is red until done; afterwards an
    "Uploaded ✓" summary replaces the form, with "Replace the invoice" behind a button. The amount field is labelled
    "before GST" to match the approved amount.
13. Owner 23:42: Finance's actions are red too ("Action needed — Finance"): Confirm Invoice Received and Record
    Payment and Close.
14. Owner 23:47: payment amounts are labelled "before GST" where they are pre-GST (approved amount, invoice amount,
    recommended payment, paid amount and the recorded payment). GST is paid with the invoice but not entered.
15. Owner 23:49: while Finance has to act, the whole Contractor Invoice and Payment section is outlined in red with
    "Action needed — Finance: confirm the invoice was received" or "… record the payment and close".
16. Owner 2 Nov 00:43: Technician 1's Draft sections needing attention are red: "Next steps before you submit"
    (red with the number of steps left; green when ready), the Evidence section while a Before photo is missing,
    the layout plan while the location is not marked, the Proposal / Quotation section while a quotation is
    needed, and Edit Work Order while the due date has passed or the reason is missing.

### D-27 All facilities overview (view only) — 30 October 2026 23:54

Owner: "The App is intended to service multiple facilities, therefore there should be a page to list down all the
facilities, all users related to each facility and the unique features/requirement for each facility should be
listed down as previously discussed. Kindly work out this page for viewing first."

1. **Administration → All Facilities** (`/administration/facilities/overview`, Administrator only, view only):
   a summary table of every facility (status, staff, areas, drawings, open and closed Work Orders), then one panel
   per facility with its users (role, name, email, assigned since; Designated Approver marked) and its requirements:
   Designated Approver, endorsement stage, independent checker (D-25), areas and pins, layout drawings, archive
   period and off-site copy frequency (D-18, Stage 2, shown "not set yet"), Work Order counts.
2. A company-wide panel shows what is set once for all facilities today: approval limits, quotations required,
   contractor payment terms, and the Finance and Administrator users. Open question for the owner: should any of
   these differ by facility?
3. Linked from the header ("All Facilities") and from Facilities setup. Editing stays in Facilities setup.

### D-28 Approval limits, quotations rule and payment terms set per facility — 1 November 2026 23:42 (refines D-27)

Owner: "All facilities approval limits, quotations rule or contractor payment terms should differ by facility, However,
they should be defaulted to a standardised limits including rules and payment terms but they can be changed via a
definition page."

1. A company standard (today: Approver and Supervisor S$250,000, Facility Manager S$500,000, Administrator no limit;
   three quotations from S$1,000; 30-day payment terms) applies to every facility by default.
2. The Administrator may give a facility its own value for any of these, with a reason, on a **Facility Definitions**
   page; "Return to standard" removes it. Every change is kept in an unchangeable history.
3. Owner 23:46: a facility without its own value follows later changes to the standard automatically.
4. Owner 23:46: review a mock-up first. Mock-up published 1 Nov 23:47 (interactive, no data saved). Building the
   page and applying the facility's values in the approval, quotation and payment steps (one database change, M14)
   waits for the owner's review.
5. Owner 2 Nov 00:28: the facility's payment terms take priority over a contractor's own agreed terms.
6. Owner 2 Nov 00:17: the holding company is Facility Supreme Pte Ltd with 10 facilities, all managed by the
   Administrator, who can choose to view any one of them. The facility used so far in UAT is named **Facility One**
   (fictitious). It has its own Facility Manager, Approver, Supervisor and Technicians 1 and 2, and each facility may
   rename these roles on the Facility Definitions page. Renaming changes only the name shown, not what the role may
   do. Mock-up updated 2 Nov 00:20.
7. Owner 2 Nov 00:28: run UAT on one or two more Work Orders at Facility One before building D-28 or creating a
   new facility. D-28 (M14) is on hold until then.

### D-29 Choosing in-house staff at any point in the Draft — 2 November 2026 01:20 (refines D-07)

Owner: "The 'in-house work' statement has disappeared. It should be able to select this option and close the
contractor option. This is not too intuitive at the moment." (The option was hidden once a contractor quotation had
been started, and the database refused the switch until the quotation was withdrawn, which nothing could do.)

1. While the Work Order is a Draft, the preparer always sees **Who will do this work?** with two choices: **A
   contractor** (quotation, invoice and payment) or **In-house staff** (no pricing; closes when approved as
   Completed). The selected one is ticked and outlined. With in-house staff chosen, the contractor sections are
   not shown.
2. Switching to in-house staff when a contractor quotation has been started asks first: "The draft quotation from
   … will be withdrawn." On confirming, the open quotation (draft, submitted or returned) is marked withdrawn,
   kept in the history, logged and no longer listed. Approved quotations are untouched. Switching back to a
   contractor starts a fresh quotation.
3. Database: migration `20261102100000_in_house_withdraws_draft_quotation.sql` (WP-IH-M14): quotation status
   'withdrawn'; `set_work_order_in_house` withdraws the open quotations; the quotation list (scope core) leaves
   them out. Rehearsed locally on a copy at 63 entries: applied (ledger 64), repeat refused, wrong target refused;
   increment sha256 `0924fe3f…bf4ab`.

### D-30 The preparer removes evidence added by mistake while drafting — 4 November 2026 10:58

Owner: an After photo added by mistake to a Draft (WO-TEST-011) could not be removed. The page offered Delete, but
the database allowed removal only from Assigned onwards by the field owner, so the Draft's preparer was refused.

1. While the Work Order is a Draft or Submitted, its preparer may remove a photo, video, voice note or document,
   with a reason, matching who may add evidence then. The item is voided and kept in the audit history.
2. Other people still cannot; from Assigned onwards the existing field-owner rule applies unchanged, including the
   rule that the last After item cannot be removed once the work is submitted as complete.
3. Database: migration `20261104100000_preparer_removes_draft_evidence.sql` (WP-EV-M15). Rehearsed locally on a
   copy at 64 entries: applied (ledger 65), repeat refused; increment sha256 `2cba857b…070ba1`.
4. Owner 11:17: the timeline showed the submission at 2:58 am instead of 10:58 am. Times were formatted in the
   server's time zone (UTC). Every date and time on the Work Order, incident, asset, approval-limit and user
   screens is now shown in Singapore time. Stored times are unchanged; only the display was wrong.
5. Owner 11:27: removing evidence asked for confirmation and a reason through browser pop-ups, which some browsers
   block, and showed the result at the bottom of the panel. It is now confirmed inside the item's card, with the
   reason typed there and any refusal shown under the item.
6. Owner 11:39: "Technician 1 is not able to record start work". The screenshot was taken signed in as Ying Zhang
   (ec@glorybene.com, Technician 2), not the assigned Technician Yang Ying Zhang, so no start action was offered,
   correctly. It also showed Technician 2 the "Action needed before Submit Physical Completion" checklist, which is
   now shown only to the assigned Technician.

### D-31 In-house work sent to Finance for reference — 4 November 2026 13:58 (refines D-07)

Owner: "Even if the work order is completed by the in-house team, it should be sent to Finance for reference purpose
as there is a quotation for material and labor used for the work order."

1. Finance is already copied and notified when any Work Order, in-house included, is approved as Completed (D-11).
2. The Finance page now also lists **In-house work (for reference)**: every completed in-house Work Order with its
   facility, completion date and confirmed actual cost split into materials, labour, equipment and services
   ("Confirmed as no cost" when no lines were recorded), marked "Closed — no payment". Each row opens the Work Order.
3. Database: migration `20261104120000_in_house_cost_register_for_finance.sql` (WP-FN-M16), a read-only list for
   Finance and the Administrator. Rehearsed with M15 on a copy at 64 entries: both applied (ledger 66); combined
   increment sha256 `4f2d0a04…584185`.

### D-32 Duplicate as draft works for overdue Work Orders — 4 November 2026 23:08

Owner: "Duplicate as draft" on WO-TEST-007 (due 21 Aug 2026) failed with "The workflow service is temporarily
unavailable". Cause: the copy kept the passed due date, and a new Work Order may not start overdue
(work_orders_due_date_check), so the database refused the copy.

1. The copy now leaves a passed due date empty; the preparer sets a new one in the Draft (a future due date is
   still copied). Everything else is copied as before; the copy is a Draft for the person who duplicated it.
2. Database: migration `20261104140000_duplicate_drops_past_due_date.sql` (WP-WO-M17). Rehearsed on a copy at 64
   entries with M15 and M16 (all three applied, ledger 67; sha256 `8b7585ad…fb8561`) and on a copy at 66 entries
   alone (sha256 `761433ac…126139`).
3. Duplicate as draft is for the Approver, Supervisor, Facility Manager and Administrator; a Technician starts a new
   Work Order with + New Work Order.
4. Owner 4–5 Nov: Save Final Cost Reconciliation on WO-TEST-008 "did not respond". The browser showed the save sent
   and refused (403): another tab had changed the shared browser sign-in, so the page still showed Yang Ying Zhang
   while actions were sent as another account. Every page now checks, on focus, interaction and every two minutes,
   which account the browser is signed in as; if it changed, a red banner says so and offers "Reload this page".
   The result of a Final Cost save is also shown under its button.

### D-33 Technician 2's endorsement survives the Approver's variance authorisation — 5 November 2026 00:50 (refines D-20)

Owner: on WO-TEST-008 Technician 2 endorsed (5 Nov 00:36, final charge S$380, no variation), then the page said
"The final cost or variation order changed after the last endorsement, so it no longer counts", although the cost
had not changed.

1. The endorsement stops counting only when what was endorsed changes: the final charge, the variation answer and
   justification, the confirmed actual cost, the attached quotation, or the final cost being reopened to draft.
2. Cause: the fingerprint also used the exact final-cost status, which the Approver's "Authorize Final Cost
   Variance" (or a re-save of the same figures) changes. The status now counts only as saved or draft.
3. Endorsements already given for an unchanged final cost are carried over, so WO-TEST-008's endorsement counts
   again if only the status moved; if the attached quotation changed, Technician 2 endorses again.
4. Database: migration `20261105100000_endorsement_survives_variance_approval.sql` (WP-EN-M18). Rehearsed on a copy
   at 67 entries (applied, ledger 68; carry-over re-keyed a test endorsement); increment sha256 `8f6c9d3d…4b027e780`.

### D-34 The Workflow timeline shows who is next and links there — 5 November 2026 13:30

Owner: three people (Technician 1, Technician 2, the Approver, plus Finance) share each Work Order; from the timeline
it was not clear "who is next responsible to perform the role", and it should "bring him/her to the right
page/section quickly by clicking on the link".

1. Above the timeline, a **Next step** box names the next step, the person and role responsible (for example "the
   Approver (Approver) to review the work and approve it as Completed"), with a link to that section of the page.
   For the person whose turn it is, it is red: "Next step — yours … Go to Work Order actions →".
2. Every timeline card shows the role and person responsible; the next step's card has a red "Next" label and link.
3. Responsibilities: Draft and submission, start, work times and Physical Completion: Technician 1 (assigned);
   endorsements: Technician 2 (any other Technician of the facility, or the one who endorsed); approval and review:
   the Approver (the facility's designated Approver when set); closing: Technician 1 uploads the invoice, then
   Finance confirms receipt and records the payment; in-house work closes automatically.

### D-35 A cancelled Work Order is raised again as a new Draft by its Technician — 5 November 2026 20:09

Owner (20:05): "Once the Approver has cancelled the work order it cannot be resumed. Why is this so?" WO-TEST-005 had
been approved as contractor work but was meant to be in-house; on Claude's advice the Approver cancelled it to
re-raise it, but Technicians could not duplicate. Owner (20:09): "go ahead with D-35".

1. A cancelled Work Order stays cancelled; it is never resumed, because its approval and spending authority ended
   with the cancellation.
2. Its Technician (the assigned Technician or the preparer, in a facility they belong to) sees **Raise again as new
   Draft**, with a note explaining why it cannot be resumed. The new Draft copies the details, is assigned to that
   Technician, keeps the link to the cancelled one, and goes through approval again (in-house or contractor chosen
   on the Draft).
3. Approval roles keep "Duplicate as draft" for any Work Order, unchanged.
4. Migration `20261105140000_technician_raises_cancelled_again.sql` (M20).

Bug fix the same day (no owner decision): approving a contractor quotation failed on WO-TEST-005 because the Work
Order still carried an in-house team from imported test data; approving a contractor now releases that team
(migration `20261105120000_contractor_approval_releases_team.sql`, M19).

### D-36 Field work never waits for the app; emergency work already done is recorded on one screen — 6 November 2026 11:06

Owner (6 Nov 00:32): "this should be categorised as a plumbing emergency and therefore emergency work will be carried
out without a work order. Work order will be submitted after fixing the problem. If this task is dependent on this work
order, the facility will fail miserably". Owner (00:38): "As this is an emergency, should the workflow be different from
a normal one?" Owner (11:06): "Go ahead with D-36".

1. Field work never waits for the app. If the app is unavailable or misbehaving, the Technician fixes the problem, takes
   photos, notes the times, and records it afterwards.
2. Emergency work may be done by in-house staff or a contractor. The New Work Order form says so ("Emergency — work
   starts immediately (in-house staff or contractor)"); before work starts, no approval, location mark, before photo
   or quotation is needed, and approvers review it afterwards.
3. A Technician records emergency work already done on one screen, **Record emergency work already done** (red header
   button "Emergency work done"): what happened, where, in-house or contractor, start and end times (in the past),
   work performed, labour hours, and photos. One step creates the emergency Work Order assigned to them, submits it,
   records the times, statement and hours, and confirms there are no separate costs; if any part is refused, nothing
   is saved. The photos are then attached and physical completion is submitted from the same screen. The Approver's
   review is unchanged (location and before evidence are checked there; for contractor work, the quotation follows).
4. The new-facility UAT guide states rule 1.
5. Migration `20261106100000_record_emergency_work_done.sql` (M21).

### D-37 Contractor register, facility shortlists and adding a new contractor — 6 November 2026 20:35–21:00

Context: WO-TEST-007 needed a solar specialist (Sunvane) who was not approved for Facility One, so Prepare Proposal
offered only a general building contractor. Owner (20:24): "Should there be a shortlisted contractor list for all
services in the facility? What if a new contractor is required to be added like in this case?"

Decided (owner, 20:35):

1. New contractors are pre-qualified by a **Procurement Manager**, either of the facility itself or of the holding
   company (Facility Supreme Pte Ltd) that manages the facilities.
2. Adding a new contractor is a decision for the **facility owner**. A recommendation may be proposed by the Facility
   Manager, an Administrator or a Procurement Manager, because they have run many facilities and know contractors
   proficient in specific work.
3. At onboarding, the facility owner company fills in the full list of specialty services the facility has.
4. (20:36) A recommendation may be added by the Facility Manager, an Administrator or a Procurement Manager, but the
   contractor's performance must be formally evaluated before admission into the facility's list.
5. (20:44) A new contractor may do trial jobs; **2 completed trial jobs** are needed to qualify for the list.
6. (21:00) A trial job may be scored by the Facility Manager, the Approver, Technician 1 or Technician 2.
7. (21:00) Pass mark: an average of 3.5 out of 5 across quality, on time, safety, documents and price, with no score
   of 1 on safety.
8. (21:00) The facility owner's approval is recorded in the app by the Facility Manager or the Procurement Manager.
9. (21:00) These settings (specialty services, preferred contractors, who scores, pass mark, who records the owner's
   approval) are furnished in the onboarding form for each facility.

Proposed by Claude, awaiting the owner:

10. One company-wide contractor register (entered once, reused by all facilities), with services and document expiry
   dates; a shortlist per facility by service; Prepare Proposal shows the Work Order's service first.
11. When no suitable contractor is on the shortlist, Technician 1 raises "Contractor needed" for the service, which
   notifies the Facility Manager and Procurement Manager; the Draft cannot be submitted with an unapproved contractor.
12. Emergencies never wait (D-36): an unlisted contractor may be used; they go through steps 1 and 2 before the
   quotation is approved at review.

Open: none of the owner's points. Owner (21:02): "start D-37 now".

Built (6 Nov 2026), migration `20261106120000_contractor_admission.sql` (M22):
- An Administrator designates Procurement Managers (one facility, or company-wide) on the Contractor Admission page.
- Technician 1 raises **Contractor needed** on a Draft or submitted contractor Work Order.
- Recommend (Facility Manager, Administrator, Procurement Manager; from the register or a new company by UEN) →
  Pre-qualify (Procurement Manager) → Record the owner's approval (Facility Manager or Procurement Manager; the
  contractor appears in Prepare Proposal as "trial contractor") → trial jobs scored on the Work Order once approved as
  Completed → Admit (Procurement Manager, only when passed) or Reject (Facility Manager or Procurement Manager).
- Standard settings per facility (2 trial jobs, pass mark 3.5, scorers Facility Manager / Approver / Technician 1 /
  Technician 2) are stored in facility settings, to be edited from the onboarding / Facility Definitions page (D-28).
- Not yet built: notifications by email (the red highlights show whose turn it is); filtering Prepare Proposal by service.


Interim (6 Nov): the six UAT contractors from the test documents are added to Preview by script
`scripts/rollout/preview-uat-contractors-20261106.sql`, as fictional, pre-approved test data.

### D-38 My notices page, bell and the Administrator's notice view — 7 November 2026 11:13

Owner (10:28): "So there is not to view the email status except for the way you have instructed me to query via coded
instruction?" Owner (10:52): "where can i see the notices sent to him? Is there a single page to log in all the notices
for his action and a link to his email messages to connect to this app?" Owner (11:13): "Shall we proceed?"

1. Every user has **My notices** (bell "Notices" with a red unread count in the header): every notice sent to them,
   newest first, with an Open link to the right section of the Work Order; Work Orders still waiting for them are
   listed first, outlined in red; opening a notice marks it read; "Mark all as read".
2. Administrators have **All notices and delivery status**, filterable by status and event.
3. Email delivery stays open (R1-012). When connected, each email will carry the same text and an "Open in FMWorks"
   link. Until then notices are delivered in the app.
4. Migration `20261107100000_notices_and_finance_register.sql` (M23), shared with D-39.

### D-39 Finance summary on each Work Order and the completed work register — 7 November 2026 11:13

Owner (11:03): Finance could not find the invoice on FW-2026-0005 and the work done description was not clear.
Owner (11:11): "it may make sense to have a summary of completed work orders and their status whether in-house or
contracting work have been carried out with dates of completion and the grace period to carry out the payment following
invoice submission."

1. Finance and Administrators see a **For Finance** box at the top of each completed Work Order: in-house (no invoice,
   no payment) or the contractor; who approved it and when; who approved it as Completed and when; the work performed,
   hours and actual times; approved and final amounts; the invoice (before GST, GST 9%, total; uploaded and received
   dates); payment due date and days left, or paid date and reference; a red action when Finance must act.
2. **Finance › Completed work register**: every Work Order approved as Completed, in-house or contractor, with facility,
   who approved it, completion date, invoice, received date, payment due date with days left (amber within 7 days, red
   overdue), paid and status; totals (outstanding, due in 7 days, overdue, paid this month); filters by status,
   in-house/contractor, month and facility; CSV download.
3. Payment terms run from the date Finance confirms the invoice was received, using the standard terms until each
   facility's own terms are set (D-28).

### D-40 Facility Overview and Contractor directory — 7 November 2026 11:39 (to build after D-38/D-39 are verified)

Owner (11:25): "a summary page can also be provided to the Administrator, Approver and Supervisor for them to have a
good overview of the facility services and work order carried out. This includes a directory of contractor's contact
list to call for emergencies/ normal ops." Owner (11:39): "Yes, agree the Technician in charge of the work order has
access to the directory." and "Proceed as per your suggestion" (build after the D-38/D-39 batch is verified).

1. **Facility Overview** for Administrators, Approvers, Supervisors and Facility Managers, per facility: Work Order
   counts by stage (incl. overdue and emergencies this month), this month and year to date (completed in-house and by
   contractor, contractor spend before GST, average days approval to completion, awaiting payment and overdue),
   services with their jobs and approved contractors (services without an approved contractor flagged red), and the
   last 20 completed jobs.
2. **Contractor directory**: contractors approved for the facility by service, contact person, phone (tap to call),
   email, payment terms, listed or on trial; emergency-available contractors first; link to the On-call roster.
3. The Technician in charge of a Work Order has read-only access to the directory for that facility (linked from the
   Work Order).

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

### Preview rollout record — 27 October 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 23:13 | `release:verify` PASS on the owner's computer (`fwm-uat`): unit tests, SQL gate, 30/30 authenticated Playwright tests | Owner |
| 23:16 | Commit `e23b7dc` pushed to `uat/claude-review` (49 files: D-15 to D-17, D-19, D-20, Work Order page tidy-up, sign-in header fix); Vercel Preview build triggered | Owner |
| 23:18 | Target checked: `cli_login_postgres.pvajuywwwpjlikqjnvgv` at `aws-0-ap-southeast-1.pooler.supabase.com` | Owner, guided |
| 23:18 | Backup of `public` + `supabase_migrations` (2,137,696 bytes, `.git/preview-backup-20261027-pre-m8-m10.sql`) | Owner, guided |
| 23:21 | Increment applied in one transaction (`scripts/rollout/build-preview-increment.mjs`, sha256 `e794f90c…93aef`, matching the local rehearsal): `20261027100000` supporting document and due date, `20261027120000` facility setup, `20261027140000` variation order and endorsement; preflight 57 ledger entries, latest `20261022120000`; ledger now 60; COMMIT | Owner, guided |

### Preview rollout record — 28 October 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 00:02 | `release:verify` PASS; commit `d5eabe7` pushed (Administrator approval of a Work Order they raised, with an audited reason); no database change | Owner |
| 22:17 | `release:verify` PASS; commit `973f263` pushed (D-21 cost correction before the review, multi-line cost entry, Return to Draft shown on its own) | Owner |
| 22:20 | Target checked: `cli_login_postgres.pvajuywwwpjlikqjnvgv` at `aws-0-ap-southeast-1.pooler.supabase.com` | Owner, guided |
| 22:22 | Backup of `public` + `supabase_migrations` (2,248,611 bytes, `.git/preview-backup-20261028-pre-m11.sql`) | Owner, guided |
| 22:28 | Increment applied (`build-preview-increment.mjs … 20261027140000`, sha256 `da0f60f5…1458b`, matching the local rehearsal): `20261028100000` actual-cost correction before the review; preflight 60 ledger entries; ledger now 61; COMMIT (first attempt refused at login, EAUTHQUERY, nothing changed) | Owner, guided |

### Preview rollout record — 29 October 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 00:34 | `release:verify` PASS (30/30 Playwright) after fixing the invoice-received date to use the Singapore calendar | Owner |
| 00:36 | Commit `fea8de6` pushed (D-22, D-23, D-24, Singapore invoice date) | Owner |
| 00:38 | Target checked: `cli_login_postgres.pvajuywwwpjlikqjnvgv` at `aws-0-ap-southeast-1.pooler.supabase.com` | Owner, guided |
| 00:38 | Backup of `public` + `supabase_migrations` (2,275,752 bytes, `.git/preview-backup-20261029-pre-m12.sql`) | Owner, guided |
| 00:40 | Increment applied (sha256 `972b877f…42fc8f`, matching the local rehearsal): `20261028120000` contractor actual cost from the final charge, cost-line delete, submission with the official quotation; preflight 61; ledger now 62; COMMIT | Owner, guided |

### Preview rollout record — 30 October 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| Before 18:14 | Increment built (sha256 `890177de…`, matching the local rehearsal) and applied: `20261030100000` independent checker (D-25: endorsement checklist, basis of award, Technician 2 auto-copied); ledger now 63. The exact apply time was not captured, because a later attempt failed at login (EAUTHQUERY) | Owner, guided |
| 18:14 | A repeat apply was refused by the preflight ("Preview ledger ends at 20261030100000, expected 20261028120000"); rolled back, nothing changed | Owner, guided |
| 18:15 | Read-only check: latest ledger entry `20261030100000 independent_checker`; `work_order_endorsements.checklist` present; `endorse_work_order(p_work_order_id uuid, p_statement text, p_checklist jsonb)` | Owner, guided |
| 19:03 | `release:verify` PASS (30/30 Playwright); commit `4687b4d` pushed to `uat/claude-review` (9 files: review-order Work Order layout with the timeline first and the decision last, red action highlights, verify-not-supervise checklist wording, Closure label, copied-parties note, this M13 record); Vercel Preview build triggered; no database change | Owner |
| 21:24 | Commit `a86ae03` pushed (D-26: commercial forms only for the assigned Technician, endorsement highlight and advance notice, CSV panel retired); no database change | Owner |
| 22:04 | Commit `071220d` pushed (red final-cost and revised-quotation highlights, attach confirmation, Physical Completion button); its new unit test had a fixture error, fixed in `8633869` | Owner |
| 23:12 | `release:verify` PASS (30/30 Playwright); commit `8633869` (Approver actions in red, endorsement checks and award basis shown to the Approver, saved final-cost summary, red next-action button) | Owner |
| 31 Oct 00:01 | Commit `b3b421f` (Finance actions in red, payment amounts before GST, saved controls hidden, invoice listed once, D-27 All Facilities overview); `8633869` and `b3b421f` on `uat/claude-review` (confirmed 1 Nov 23:16, "Everything up-to-date"); no database change | Owner |

### Preview rollout record — 3 November 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 22:40 | Commit `dd46b4b` pushed to `uat/claude-review` (D-29 in-house choice with M14 migration, Technician 1 Draft highlights, D-28 records); Vercel Preview build triggered. M14 not yet applied to the Preview database | Owner |
| 22:50 | Target checked: `cli_login_postgres.pvajuywwwpjlikqjnvgv` at `aws-0-ap-southeast-1.pooler.supabase.com`; backup of `public` + `supabase_migrations` (2,373,419 bytes, `.git/preview-backup-20261102-pre-m14.sql`, written 3 Nov 22:40 SGT) | Owner, guided |
| 22:51 | Increment applied (sha256 `0924fe3f…bf4ab`, matching the local rehearsal): `20261102100000` in-house choice withdraws the draft quotation (D-29); preflight 63 ledger entries; ledger now 64; COMMIT | Owner, guided |

### Preview rollout record — 4 November 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 15:05 | `release:verify` PASS (30/30 Playwright, one passed on retry); commit `05e27e0` pushed (D-30, D-31, Singapore times, in-card evidence removal, completion checklist for the assigned Technician only) | Owner |
| 15:05 | Target checked; backup of `public` + `supabase_migrations` (2,431,476 bytes, `.git/preview-backup-20261104-pre-m15.sql`); increment built (sha256 `4f2d0a04…584185`) | Owner, guided |
| 15:07–23:32 | Increment applied: `20261104100000` preparer removes Draft evidence (D-30) and `20261104120000` in-house cost register for Finance (D-31); ledger now 66. The apply output was not captured; confirmed at 23:33 when the M15–M17 file was refused with "Preview ledger ends at 20261104120000" | Owner, guided |
| 23:32 | M15–M17 apply refused at login (EAUTHQUERY), nothing changed | Owner, guided |
| 23:33 | M15–M17 apply refused by the preflight (ledger already at 20261104120000), rolled back, nothing changed | Owner, guided |
| 23:25 | Commit `185e847` pushed to `uat/claude-review` (D-32 Duplicate as draft fix with M17) | Owner |
| 23:35 | Increment applied (sha256 `761433ac…126139`, matching the local rehearsal): `20261104140000` Duplicate as draft leaves a passed due date empty (D-32); preflight 66; ledger now 67; COMMIT | Owner, guided |

### Preview rollout record — 5 November 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 01:03 | Commit `bdf19c4` pushed (D-33 with M18, sign-in change warning, Final Cost result under Save, red final cost while Technician 2 waits) | Owner |
| 07:30 | Increment built (sha256 `8f6c9d3d…4b027e780`, matching the local rehearsal) | Owner, guided |
| 10:33 | Backup of `public` + `supabase_migrations` (2,486,455 bytes, `.git/preview-backup-20261105-pre-m18.sql`); increment applied right after: `20261105100000` endorsement survives variance authorisation (D-33). Apply output not captured | Owner, guided |
| 12:42 | Read-only check: WO-TEST-008 completed, final cost variance_approved S$380.00, 1 review endorsement, endorsement_missing false, so the carried-over endorsement counts (M18 in effect) | Owner, guided |
| 16:39 | Read-only check (rolled back): approving WO-TEST-005 failed on `work_orders_primary_assignment_check`, because the Work Order still carried an in-house team from imported test data | Owner, guided |
| ~17:00 | Commit `5817bc1` pushed (M19, action buttons hidden after a confirmed action) | Owner |
| before 18:27 | Increment applied: `20261105120000` contractor approval releases a leftover in-house team (M19); ledger now 69. No backup was taken first and the apply output was not captured; confirmed by the WO-TEST-005 approval succeeding and by the M20 preflight (69 entries, latest `20261105120000`) | Owner, guided |
| 20:35 | `release:verify` PASS (29 passed, 1 flaky browser test passed on retry); commit `ba6023c` pushed (D-35 with M20, Final Cost hours hint) | Owner |
| 20:36 | Backup failed: Claude gave a `pg_dump -Fc` command without the schema limits, which tried to read `auth` and was refused; it left an empty `.git/preview-backup-20261105-before-m20.dump`. Nothing was changed | Owner, guided |
| 20:37 | Increment applied (sha256 `95181635…`, matching the local rehearsal): `20261105140000` Technician raises a cancelled Work Order again (D-35, M20); preflight 69; ledger now 70; COMMIT. No backup before it (see 20:36). M19 and M20 only replace functions; the earlier definitions are in migrations `20260924044237`/`20261020070000` and `20261104140000` if a rollback is needed | Owner, guided |
| 6 Nov 17:48 | `release:verify` failed 1 browser test: the in-house approval test still expected "Approved — Contractor to Proceed" after the 5 Nov label change; Claude updated the test | Owner |
| 6 Nov 18:1x | `release:verify` PASS (30 passed); commit `be221c1` pushed (D-36 with M21) | Owner |
| 6 Nov 18:1x | Backup failed again: Claude's corrected command still lacked `--role=postgres`, so `public.profiles` was refused. Nothing was changed | Owner, guided |
| 6 Nov 18:1x | Increment applied: `20261106100000` record emergency work already done (D-36, M21); preflight 70; ledger now 71; COMMIT. No backup before it (see above). M21 only adds a new function, so removing it (`drop function public.record_emergency_work_done(jsonb)`) undoes it | Owner, guided |
| 6 Nov 23:40 | `release:verify` failed 1 unit test: the guided-work-stage order test still looked for `<ReleaseOneWorkspace` after D-37 grouped the commercial section as `workspaceEl`; Claude updated the test | Owner |
| 7 Nov 00:25 | `release:verify` browser run timed out at different steps on each attempt (slow machine, 8.3 min); no code change | Owner |
| 7 Nov 00:45 | `release:verify` PASS (30 browser tests, 5.6 min); commit `fc2eb92` pushed (D-37 with M22) | Owner |
| 7 Nov 00:5x | Backup taken with `pg_dump --role=postgres -n public -n supabase_migrations`: `.git/preview-backup-20261107-pre-m22.sql` (2,593,409 bytes) | Owner, guided |
| 7 Nov 00:5x | Increment applied (sha256 `16a89a3e…`): `20261106120000` contractor admission (D-37, M22); preflight 71; ledger now 72; COMMIT | Owner, guided |

## D. Decisions still open (not recoverable locally)

1. ~~Emergency commercial exception (R1-003)~~ resolved by D-01.6 and D-03.3.
2. Operational email: provider or accept `NOT_CONFIGURED` (R1-012).
3. Disposition of untracked `0011_secure_legacy_public_tables.sql` (R1-010).
4. Vercel deployment-protection access for hosted UAT (R1-009).
5. ~~B-03 and B-05~~ resolved by D-01/D-02 on 20 Oct. Follow-up questions: see chat 20 Oct.

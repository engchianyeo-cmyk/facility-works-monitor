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
   not chillers (superseded in part by D-47, 10 Nov 2026: a central chilled-water plant is added). Owner gave no preference on the UAT data; default adopted: chiller items are
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

### D-41 Payment records Finance can trust — 7 November 2026 (owner: "Yes on D-41")

Found in UAT: WO-TEST-007 (Sunvane) was marked paid with the invoice number and payment reference of WO-TEST-010
(VQ-INV-2026-1219, FS-FAST-20261030-0418, filled in by the browser's autofill), and with a payment time 8 hours late
(the "Paid on" time was sent without its time zone). Finance could also confirm an invoice without opening it.
Owner: "Yes on D-41. WO-TEST-012 and FW-2026-0003 be marked as test data."

1. Finance must open the contractor invoice (button on the Work Order) and tick "I have checked the invoice against
   the approved amount" before "Confirm Invoice Received"; the app records who opened it and when.
2. An invoice number already recorded on another payment, or a payment reference already used, is refused, naming
   the Work Order and contractor it belongs to. Browser autofill is off for both fields.
3. "Paid on" is sent with its time zone and cannot be in the future (5 minutes' allowance).
4. Work Orders marked as test data leave the Finance tracker and the completed work register (their own Work Order
   page still shows the For Finance box). WO-TEST-012 and FW-2026-0003 are marked as test data.
5. WO-TEST-007 is corrected on Preview: invoice SVS-INV-2026-0544 (the Sunvane invoice attached), payment reference
   FS-UAT-20261107-0007 (fictional UAT reference) and paid at 12:36 SGT; the correction is in the activity log.
6. Migration `20261107120000_payment_record_controls.sql` (M24); data script
   `scripts/rollout/preview-d41-corrections-20261107.sql` (dry run by default).

### D-42 Email delivery for UAT (R1-012) — 7 November 2026 16:46

Owner (16:36): Finance "is very busy and has priorities and will not be so free to open up the app regularly", so an
email should prompt them. Owner (16:46): "Yes, agree to use fmworks.notices@gmail.com".

1. During UAT the app sends email from a dedicated Gmail account, fmworks.notices@gmail.com (created and secured by
   the owner; its app password is entered by the owner in Vercel and never shared). Before Production it moves to the
   company's own email domain.
2. Emails go out at once only when the reader must act (for Finance: contractor invoice uploaded); information-only
   notices stay on My notices.
3. A daily reminder email lists invoices not yet confirmed and payments due within 7 days or overdue.
4. The Administrator's notices page shows each email's delivery status. Repeat notices for the same Work Order and
   event show once, with the latest time.
5. Build after D-41 is applied and verified.
6. Update 17:23: the Gmail sign-up code never arrived. Owner: "Shall signup for a yahoo account,
   fmworks.notices@yahoo.com instead?" — agreed. The sending account is fmworks.notices@yahoo.com (Yahoo app
   password), which supersedes the Gmail account in item 1.
7. Built 8 Nov 2026 (Yahoo was still holding back the app password on the new account; the owner retries later).
   Sending is off until the Vercel variables `EMAIL_SMTP_USER` and `EMAIL_SMTP_PASSWORD` exist (Preview only). The app
   sends through Yahoo's mail server with its own small mail client (no new package). Emails go out right after the
   action that queued them; Finance's daily reminder goes out from 8 am SGT with the first app activity of the day
   (there is no scheduler on Preview). Only notices from the previous 24 hours are emailed when sending starts, so
   the old backlog is not sent. Who gets an email at once: Finance for an uploaded invoice; the Technician when the
   Work Order is approved, assigned to them or returned to Draft; approvers for submissions, emergency starts and
   endorsements. Everything else shows "in app only".
8. Update 13 Nov 2026 00:56: the owner renamed one of his Gmail accounts to **fmworks.notices@gmail.com**, which now
   replaces the Yahoo account. No code change: the mail server is set by Vercel variables. Preview only:
   `EMAIL_SMTP_HOST=smtp.gmail.com`, `EMAIL_SMTP_PORT=465`, `EMAIL_SMTP_USER=fmworks.notices@gmail.com`,
   `EMAIL_SMTP_PASSWORD` = a Google app password (needs 2-Step Verification), entered by the owner in Vercel and never
   shared. Takes effect from the next Preview deployment.

### D-43 Only current notices shown first — 9 November 2026 19:08

Found in UAT: the Approver's My notices listed 19 "New" notices, most about steps long finished (e.g. WO-TEST-010
"submitted for approval" after it was closed). Owner: "update the notices so that it is the most current appear.
Leave the unread, old notices in a separate folder and only appear which the approver wants to read them by
clicking on this folder."

1. My notices shows, in order: Work Orders waiting for you (red); then **Current notices** — the newest notice of each
   Work Order still open, anything under two days old, and today's daily payment reminder — each with the Work
   Order's current status ("now: …").
2. All other notices, read or not, sit in a closed **Earlier notices** folder, opened by clicking it.
3. The bell counts only current notices not yet opened.
4. No database change.

### D-44 Facility drawings kept as PDF, with automatic pin images — 9 November 2026 19:51

Owner: "On drawings, keep the current layouts in this folder [the Facility drawings page], preferred in PDF format."
Owner (19:55): "Yes, build D-44".

1. The PDF is the master copy: staff view and download it from the Facility drawings page.
2. On upload, the Administrator's browser turns page 1 of the PDF into an image (about 3,500 pixels on the long side),
   stored with it, so Technicians can pin and mark up Work Orders on PDF drawings. Image drawings work as before.
3. Uploading a new revision with the same drawing number supersedes the current one; the old revision moves to
   "Earlier revisions" on the Facility drawings page, kept for reference. The same revision cannot be uploaded twice.
4. Migration `20261109100000_drawing_pdf_master.sql` (M25). Uses the PDF library already in the app (pdfjs-dist).

### D-45 Site SLA for everyone, and an SLA countdown on each Work Order — 9 November 2026 19:55

Owner asked that "every individual can comprehend the SLA expectation for the site"; owner: "Yes, build D-45".

1. A **Site SLA** page for every role (header link): approved times by priority to acknowledge, respond, attend,
   make safe and fix, the KPI target, what each step means and what it means for each role.
2. Each Work Order with an SLA clock shows an **SLA countdown**: per step, time left (green), 75% used (amber),
   missed (red), or met.
3. The managers' SLA page is reworded in plain language (SLA documents and rules), without the technical wrapper text.
4. Staff can read approved SLA rules and the clocks of Work Orders they can already see; writing is unchanged.
   Migration `20261109120000_site_sla_visibility.sql` (M26).

### D-46 Test data hidden from working lists — 9 November 2026 19:55

Owner: "Yes, mark and hide". FW-2026-0001 and FW-2026-0002 (old automated test records) are marked as test data
(script `preview-d46-test-data-20261109.sql`). FW-2026-0004 was first listed in error: it is a real UAT Draft (a copy of
WO-TEST-008); owner, 20:58: "No" to hiding it. All test-data Work Orders are hidden from the Operations
Workspace and the Work Orders list (a "show" link on the list brings them back; direct links still work).

### UAT fixes 9 November 2026 (no owner decision needed)

- A Work Order approved as Completed with no contractor payment (no contractor quotation approved, not in-house)
  no longer asks for a contractor invoice: the timeline step reads "No payment required (no contractor payment)"
  and points the assigned Technician, Supervisor or Facility Manager to Propose No Payment Required, then a
  different approver to Approve No Payment Required (found on WO-TEST-008).
- Approve as Completed shows the final cost and approved amount beside the review note, and says plainly when no
  amount was approved.
- A Draft with no Technician yet gives its next step (and the red box and link) to the person who created it.
- Timeline steps are named as actions ("Submit for approval", "Approve as Completed", …) with "Done · date"; "Field-witness
  Technician" is renamed "Technician 1 (does and records the work)" (owner: "Agree and execute", 20:49).
- (owner: "Go ahead with A and B", 23:07) The person who raised a Work Order is no longer pointed to approve it, and is
  told plainly that a different approver must; the Cost Summary says who confirmed the costing and asks Technician 1 to
  confirm it personally; audit entries record the person's name instead of "Unknown user" (migration
  `20261109140000_audit_names_and_technician_emails.sql`, M27, which also adds emails to the Technician picker);
  user presence reads "Online / Idle — last active N min ago / Not active"; guides, AI knowledge pack (version 2) and
  drawing HLH-A-101 updated to today's features.

### D-47 Central Plant Block with an AHU Room and a Chiller Plant Room — 10 November 2026 13:34 (supersedes D-11.1 in part)

Owner (13:02): "Are there rooms for AHUs and chillers? If not, we may have to create the 2 rooms. One recommended space is
in between the main building and the utility block." Neither room was on the mock-up drawings (AHU-02 was recorded in a
"Level 2 AHU Room" that no drawing showed), and D-11 had said the facility uses split air-conditioning, not chillers.
Owner (13:34), choosing option 1 of 3: "Proceed with No. 1 option and please modify the layouts accordingly."

1. **The facility now has a central chilled-water plant** as well as its split air-conditioning and VRF units. This
   replaces D-11's "split air-conditioning, not chillers"; the split-AC renames already applied on 24 Oct stay as they are.
2. **Central Plant Block** (1 storey, 8.0 x 24.0 m). Owner (13:59): "join the 2 buildings and cover up the opening in
   between the buildings": the block fills the opening wall to wall, sharing 2-hour fire walls with the Main Building
   (west) and the Utility Block (east); doors open north to the fire access road and south to the service road; vehicle and
   fire access stay on the perimeter road. AHU Room `AHR-01` (8.0 x 8.0 m, AHU-01 and AHU-02, ducts through the west wall)
   and Chiller Plant Room `CPR-01` (8.0 x 16.0 m: chillers CH-01/CH-02, chilled water pumps CHWP-01/02, condenser water
   pumps CWP-01/02, panel MCC-CP-01), cooling towers CT-01/CT-02 on the roof above.
   Owner (14:00) asked to turn the Utility Block 90 degrees; its layout plan is 12 m wide by 24 m deep, so it already runs
   north to south as on the site plan, and turned it would not fit beside the Plant Block within the site. Owner (after 14:01):
   keep the Utility Block as it is and close the gap.
3. **Drawings:** new mock-up sheet FW-006 (Central Plant Block layout and roof plan), reserved as a mock-up drawing
   number for uploads. FW-001 and FW-005 were first amended in place; that was replaced by new Rev B sheets (point 5).
4. **Preview data:** script `preview-d47-central-plant-20261110.sql` (dry run by default): both areas pinned on FW-006
   (the Administrator can move them), 9 new synthetic assets, AHU-02 moved to the AHU Room, WO-TEST-002 location
   follows AHU-02 while open; every change written to the activity log. Rehearsed locally (13 changes; second run
   changes nothing). Not applied until the owner runs it.

5. **One building, drawn to scale (FW-001 Rev B, FW-005 Rev B).** Owner (14:53): "The overall facility layout (plot plan)
   and the new proposed HVAC plant room, utility block need to be fused into one building. Note that the existing utility
   room is not drawn to scale which have to be modified to scale proportionally." Owner asked for a 3D perspective as well;
   owner (14:59): "Yes, make them larger if necessary" (the Utility Block holds both room sets).
   - FW-001 Rev B: to-scale site plot plan (site 130 x 80 m, 10,400 m²) and 1st storey layout of the one building,
     88 x 24 m: Main Building 48 m (2 storeys), Central Plant Block 8 m, Utility Block 32 m, joined by 2-hour fire walls.
   - FW-005 Rev B: 3D perspective drawn from the same to-scale model (simplified massing, not a photo render) and the
     Utility Block layout plan to scale. The Utility Block (32 x 24 m, 768 m²) holds the former FW-001 electrical rooms and
     the former FW-005 fire protection rooms: maintenance workshop, fire pump room, water tank room, sprinkler tank room,
     fire control centre, substation, transformer room, electrical switch room, generator room, solar PV rectifier room,
     battery room, store, lobby and corridor. Total GFA 3,264 m².
   - Rev A images are kept unchanged; markups saved on Rev A stay in the record but are not drawn on Rev B.
   - The D-47 script also pins the 1st storey and site areas on FW-001 Rev B, adds 7 Utility Block areas, clears pins
     left on the old FW-001 / FW-005 for the Administrator to place again, and moves TR-01 and INV-PV-02 indoors.
   - FW-004 Rev B (owner, 15:13: "proceed to elevation drawings"): north, south, east and west elevations of the one
     building, to scale from the same model; the front is the south elevation (main entrance, loading dock RS-01). Areas
     pinned on the old FW-004 lose their pin for the Administrator to place again. FW-002 and FW-003 are unaffected.
   - Owner (15:13) also asked for a quotation for WO-TEST-002: `KB-Q-2611-0002` from Kelvinbay ACMV Engineering Pte Ltd
     (UAT), S$551.00 before GST (S$600.59 with 9% GST; V-belts S$56 only if replaced), marked as a UAT test document.

### D-48 Safe access to clean and maintain the car park solar PV canopy — 10 November 2026 15:30

Owner: "For the solar panel mounted above the car park, it needs men to access the panels for cleaning and maintenance.
What you have provided cannot allow any cleaning, even with a robot to do the work. Please make provision for the
required tasks." Owner (15:33) also noted that a water-cooled chiller system needs cooling towers on the roof: already
provided by D-47 (CT-01 and CT-02 on the Central Plant Block roof, on FW-006, FW-001/004/005 Rev B and the 3D view).

1. **Canopy layout (FW-007 Rev A, new):** 60 x 17 m canopy, deck +3.90 m, headroom +3.60 m. Five east-west PV rows, each
   2 panels deep (2.3 m), tilted 10 degrees to the south; 0.8 m grated walkways between rows; 1.0 m perimeter walkway
   (1.4 m on the east side) with a 1.1 m guardrail all round; horizontal lifeline on every walkway.
2. **Access:** dog-leg stair at the north-west corner with a lockable gate (permit-to-work); caged ladder at the north-east
   corner as a second way down.
3. **Cleaning:** water points at the west end of every walkway; gutters at the low edge of every row to downpipes at the
   columns, so cleaning water does not fall on parked cars; one robot docking station per row at the east end and a
   transfer trolley on a rail to move the robot between rows.
4. **Structure:** columns on the aisle edges (every 12 m), clear of the parking bays.
5. **Drawings and data:** FW-007 added to the app (reserved as a mock-up number); FW-001 Rev B, FW-005 Rev B (3D) and the
   rendered site plan show the rows, walkways, guardrail, stair, ladder and robot docks. The D-47 script adds area SPV-01
   "Solar PV Canopy (Car Park)" pinned on FW-007, so cleaning and maintenance Work Orders can point to it.

### D-49 Technician 2 is named on the Work Order — 10 November 2026 18:29 (refines D-11, D-25)

Owner (18:28): "For Technician 2, who is assigned to verify the work order completion. He was not given any notice to
work with Technician 1 for the work order. Is this correct?" Until now no Technician 2 was named: any other Technician
of the facility could endorse, and notices reached the checker only after endorsing. Owner chose "Name Technician 2".

1. An Approver, Supervisor, Facility Manager or Administrator of the facility names Technician 2 on the Work Order
   (section "Technician 2 (independent checker)"): another active Technician of the same facility, not Technician 1 and
   not the person who raised it. It can be changed until Technician 2 has endorsed for review.
2. Technician 2 is notified when named ("you are Technician 2 — work with Technician 1") and again when the
   endorsement is due (work Submitted for Review; or a Draft at a facility that endorses before submission); both
   are emailed once email is switched on. Technician 2 is copied on the Work Order; a replaced Technician 2 who has not
   endorsed is removed from the copied parties.
3. Only the named Technician 2 may endorse. A Work Order with no Technician 2 named works as before (any other
   Technician of the facility). Technician 1 cannot be the named Technician 2.
4. My notices keeps the Work Order outlined in red for Technician 2 until they have endorsed it.
5. Migration `20261110100000_named_second_technician.sql` (M28); SQL test `named_second_technician.test.sql`.

### Drawings on the Work Order page — 10 November 2026 15:41

Owner: "you may now include them in the work order page." Every Work Order of a facility with no uploaded drawings now shows
FW-001 to FW-008 (site plan and 1st storey, 2nd storey, roof, elevations, 3D and Utility Block, Plant Block, solar PV canopy
access, rendered site plan); each can be opened, pinned and marked up. A facility with its own uploaded drawings (D-17,
D-44) shows only those, as before. FW-008 is reserved as a mock-up number for uploads.

### D-50 Facility One, Facility 2 and a Super-Administrator — 11 November 2026 15:53 (proposed; owner to confirm)

Owner: "Shall we call it 'Facility One' for the existing work order handled? ... when I introduce 'Facility 2', it will
be separate ... There will be a Super-Administrator who can oversee all the facilities under the care of this app. The
account is engchian.yeo@gmail.com." Proposed (mock-up "FMWorks Archive and Facilities mock-up", 11 Nov):
1. The existing trial facility is renamed **Facility One**; the pharma warehouse (layouts PB-001 to PB-201, Rev P2,
   awaiting approval) becomes **Facility 2 — Pharma Warehouse**. Each keeps its own Work Orders, numbering, staff,
   drawings, areas, contractors, settings and Archive (facility memberships already separate them).
2. The everyday Work Orders list shows open work only; Closed and Cancelled Work Orders leave it at once, stay under
   "Closed and cancelled" for N months, then move to the read-only, searchable Archive (D-18; N and the off-site copy
   frequency set per facility).
3. **Super-Administrator** (one account, engchian.yeo@gmail.com): adds facilities, appoints each facility's
   Administrator, sees and searches every facility and Archive; approves or pays only where also a facility member.
   The existing Administrator role becomes **Facility Administrator**, limited to its own facilities.
4. Not built yet: needs a migration (role and facility-scoped Administrator), the Archive view (D-18), a facility
   switcher, and a Preview script to rename the facility. To be planned after the owner confirms.

### Final cost wording — 10 November 2026 23:35 (refines D-19)

Owner: "Yes, relabel the option to 'Yes — price changed (higher or lower)'." The Final Cost Reconciliation choice now
reads "Yes — price changed (higher or lower)": any change from the approved quotation, lower as well as higher, is a
variation order with a revised charge, a reason and the contractor's revised quotation. The saved summary shows
"Yes — price changed (revised quotation)".

### Timeline after approval — 10 November 2026 22:13 (UAT fix, no new decision)

Owner (WO-TEST-012, approved as Completed in Sept): the timeline said "Next step — yours: record when the work started
and ended", but the times can no longer be entered after the review. Now, once a Work Order is approved as Completed,
an earlier step that was never recorded shows "Not recorded (passed over before the approval; can no longer be added)"
and is never the next step; the next step is the first open step after the approval (e.g. upload the contractor
invoice). Before the review, missing times are still required and remain the next step.

### D-51 Facility 2 drawings, equipment and Work Order list — 12 November 2026 15:09

Owner's answers on the Facility 2 (pharma warehouse) material:
1. **Drawing set P2 (PB-001 to PB-304) is approved as the set used for pinning Work Order locations** (not for
   construction). Re-traced from the owner's reference drawings; the ramp stays as built.
2. Possible Work Orders (P-01 to P-76) and the equipment list go to the facility manager for review and testing;
   the FM marks each Keep / Drop / Change. Quotations are prepared only for those kept.
3. AHU-G1 (GMP suite) and the purified-water system stay in the equipment list for now.
4. Car park east side is open to the east road; 3D views keep the car park at ground level.
5. Level 1 docks: 20 ft container trucks reverse in at an angle under a road marshal (no traffic lights).
   Level 2 docks take 20 ft and 40 ft trucks by the west ramp.
6. No lift to the roof: Cargo Lift 2 stops at the Level 2 mezzanine. Materials and PV cleaning robots are raised by
   davit DV-01 at the east parapet; robots are stored and charged in R.07.
7. West ramp shown with 1.2 m concrete crash barriers, hazard band and guardrail on both edges.
8. Closed and cancelled Work Orders of Facility One are archived away from daily work (see D-50 point 2); whether
   Facility 2 technicians may consult them read-only is still open.
9. Open: email route to Finance (to retry later); the Production rollout plan and running costs (Vercel, Supabase,
   GitHub) are not final; a full document set for the Facility 2 team is to be proposed.

### D-52 Work Orders list filters and remaining test Work Orders — 12 November 2026 17:00 (extends D-46)

Owner: "I saw the item 'Submitted for Review', this should be work still in progress." and "Yes, mark the remaining
WO-TEST items as test data."
1. The Status filter gains two choices: **Open work (not yet Completed)** = Draft, Awaiting Approval, Approved,
   Assigned, In Progress and Submitted for Review; **Finished (Completed, Closed, Cancelled)**. Submitted for Review
   counts as work still under way, because its review is still outstanding.
2. Fix (owner, 16:48, "Nothing works"): after Clear or Back, the filter boxes kept showing the old choice while the
   list had already changed. The filter form now redraws whenever the page address changes.
3. Every remaining WO-TEST-### Work Order is marked as test data on Preview (script
   `preview-d52-wo-test-data-20261112.sql`, dry run first). FW-2026-0004 stays visible (D-46).
4. Owner, 17:32: "What i want is to remove those which are cancelled, closed to be hidden from the team for now."
   The Work Orders list now hides Closed and Cancelled by default ("Current work (Closed and Cancelled hidden)").
   They stay in the app: choose "Finished", "Closed", "Cancelled" or "All statuses, including Closed and Cancelled"
   to see them. Completed (reviewed) Work Orders stay visible, as invoices and payments may still follow. This is the
   interim step towards the Archive (D-18, D-50 point 2); nothing is deleted or moved.

### D-53 One account as Facility One Administrator and Super-Administrator — 12 November 2026 23:12 (refines D-50 point 3)

Owner: "engchian.yeo@gmail.com can be the Administrator for Facility One and also the Super-Administrator for all
other facilities (to be created and named in future) but cannot take on other roles like Approver, Administrator of
other facilities apart from Facility One."
1. engchian.yeo@gmail.com: Facility One Administrator and Super-Administrator (adds facilities, appoints each
   facility's Administrator, oversees all). It never acts as Approver or any other working role, and is not the
   Administrator of any facility other than Facility One.
2. Each other facility (Facility 2 first) gets its own Facility Administrator account.
3. Explained to the owner: "FMWorks" is the app's name and covers every facility; user accounts belong to the app
   and are linked to a facility only through "Add a staff member" (no automatic link to Facility One). The trial
   facility is not yet renamed "Facility One" (D-50 point 1).
4. Not built yet: today every Administrator covers all facilities and there is no Super-Administrator role. Needs the
   D-50 build (migration, facility-limited Administrator, Super-Administrator, facility switch, rename script).

### D-54 Facility Administrators, Finance per facility and the Super-Administrator's start view — 12 November 2026 23:20 (builds D-50, D-53)

Owner: "Yes, proceed" (plan `docs/design/D-50_FACILITIES_AND_SUPER_ADMINISTRATOR_PLAN.md`), then chose:
1. The Super-Administrator (engchian.yeo@gmail.com, the existing `administrator` role) **keeps emergency approval and
   field powers**, used only with an audited reason when no Approver is available.
2. A **Facility Administrator** (new role) may create user accounts for **its own facility only**; they are added to
   that facility at once; it can never create Administrator or Super-Administrator accounts.
3. **Finance is per facility**: Finance sees only the facilities it is staff of. Existing Finance accounts are added
   to Facility One's staff so nothing changes for them. Owner, 23:25: "Finance can use the same email account for all
   facilities so he can be a single person or separate persons." One Finance account may be staff of several
   facilities (it then sees each of them and gets the facility switch); or each facility has its own Finance account.
4. The Super-Administrator's start view is **All facilities**, with a facility switch in the header.
5. Found while planning: the trial facility is "FMWorks UAT Facility" (code UAT-FAC-001), which is why "FMWorks"
   looked like the facility's name. It is renamed **Facility One** by the Administrator in the app (Facilities ›
   Details › Facility name, with a reason); the code UAT-FAC-001 stays, so Work Order numbers are unaffected.

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
| 7 Nov 01:5x | Contractor script `preview-uat-contractors-20261106.sql` applied (dry run, then apply) for WO-TEST-007's facility: Kelvinbay, Polarline, Coolharbour, Gensteady, Aquaroute and Sunvane (all "(UAT)") added and approved | Owner, guided |
| 7 Nov 15:5x | `release:verify` PASS (30 browser tests, 5.7 min); commit `a8cb83d` pushed (D-38, D-39 with M23; timeline and list fixes) | Owner |
| 7 Nov 15:5x | Backup `.git/preview-backup-20261107-pre-m23.sql` (2,710,241 bytes, `--role=postgres`) | Owner, guided |
| 7 Nov 15:5x | Increment applied (sha256 `7958caa0…`): `20261107100000` notices and Finance register (D-38, D-39, M23); preflight 72; ledger now 73; COMMIT | Owner, guided |
| 7 Nov 21:5x | `release:verify` failed 1 unit test: the 30 Oct red-button test expected the old "Confirm Invoice Received" style; D-41 added a greyed-out style until the invoice is opened. Claude updated the test | Owner |
| 7 Nov 23:1x | `release:verify` PASS; commit `bce4ede` (D-41 with M24; D-42 recorded) | Owner |
| 7 Nov 23:17 | Backup `.git/preview-backup-20261107-pre-m24.sql` (2,721,621 bytes, `--role=postgres`) | Owner, guided |
| 7 Nov 23:1x | Increment applied (sha256 `a43d1ac5…`): `20261107120000` payment record controls (D-41, M24); preflight 73; ledger now 74; COMMIT. Commit `bce4ede` pushed afterwards | Owner, guided |
| 7 Nov 23:21 | Data script `preview-d41-corrections-20261107.sql` (dry run, then apply): WO-TEST-007 invoice VQ-INV-2026-1219 → SVS-INV-2026-0544, payment reference FS-FAST-20261030-0418 → FS-UAT-20261107-0007, paid 20:35 → 12:35 SGT; FW-2026-0003 and WO-TEST-012 marked as test data; COMMIT | Owner, guided |
| 9 Nov 20:51 | `release:verify` PASS (incl. `site_sla.test.sql`, 30 browser tests); commit `10a68df` (D-43 to D-46) | Owner |
| 9 Nov 20:52 | Backup `.git/preview-backup-20261109-pre-m25.sql` (2,763,276 bytes, `--role=postgres`) | Owner, guided |
| 9 Nov 20:53 | Increment applied (sha256 `b12230da…`): `20261109100000` PDF drawings (D-44, M25) and `20261109120000` Site SLA visibility (D-45, M26); preflight 74; ledger now 76; COMMIT. Commit `10a68df` pushed afterwards | Owner, guided |
| 9 Nov 20:5x | D-46 script dry run listed FW-2026-0004 in error; owner declined hiding it; script corrected to FW-2026-0001 and 0002 only | Owner, guided |
| 9 Nov 21:04 | D-46 script applied (corrected): FW-2026-0001 and FW-2026-0002 marked as test data; FW-2026-0004 not marked; COMMIT | Owner, guided |
| 9 Nov 21:18 | `release:verify` PASS; commit `246ca7d` (timeline steps named as actions, Technician 1 wording, D-46 script correction) pushed | Owner |
| 10 Nov 15:43 | `release:verify` stopped at the database stage: Docker Desktop not running (952 unit tests had passed) | Owner |
| 10 Nov 16:05 | `release:verify` PASS (SQL gate, 30 browser tests) | Owner |
| 10 Nov ~16:10 | Commit `384c67c` (A/B round with M27; D-47/D-48 one building, FW-001 to FW-008 on the Work Order page, PV canopy access) | Owner |
| 10 Nov 16:11 | Backup `.git/preview-backup-20261110-pre-m27.sql` (2,822,725 bytes, `--role=postgres`); later renamed `preview-backup-20261110-pre-d47.sql` (it predates both M27 and the D-47 script) | Owner, guided |
| 10 Nov 16:1x | Target checked (`cli_login_postgres.pvajuywwwpjlikqjnvgv`); increment applied: `20261109140000` audit names and Technician emails (M27); preflight 76; ledger now 77; 79 "Unknown user" audit entries back-filled; COMMIT | Owner, guided |
| 10 Nov 16:1x | D-47/D-48 script dry run: 40 changes (27 areas, 9 new assets, 3 asset moves, WO-TEST-002 to the AHU Room); rolled back | Owner, guided |
| 10 Nov 16:1x–16:49 | D-47/D-48 script applied (output not captured); confirmed at 16:53 when a repeat apply found 0 changes to make | Owner, guided |
| 10 Nov 16:21 | Commit `384c67c` pushed to `uat/claude-review` | Owner |
| 10 Nov 16:49 | A repeat apply was refused at login (EAUTHQUERY, connection details not loaded); nothing changed | Owner, guided |
| 10 Nov 16:53 | Repeat apply after reloading the connection: 0 changes; COMMIT (nothing to change) | Owner, guided |
| 10 Nov 18:59 | `release:verify` PASS (D-49 Technician 2 named, show-password button) | Owner |
| 10 Nov 22:37 | `release:verify` PASS again with the timeline-after-approval fix (SQL gate incl. `named_second_technician.test.sql`, 30 browser tests) | Owner |
| 10 Nov ~22:39 | Commit `d8a84bd` (D-49 Technician 2 named (M28); show-password button; timeline after approval) | Owner |
| 10 Nov 22:41 | Target checked (`cli_login_postgres.pvajuywwwpjlikqjnvgv`, pooler aws-0-ap-southeast-1); backup `.git/preview-backup-20261110-pre-m28.sql` (2,891,736 bytes, `--role=postgres`) | Owner, guided |
| 10 Nov 22:43 | Increment `out/preview-increment-m28.sql` (sha256 `ce67043bb18ac628…`) applied: `20261110100000` named Technician 2 (M28); preflight 77; ledger now 78; COMMIT | Owner, guided |

## D. Decisions still open (not recoverable locally)

1. ~~Emergency commercial exception (R1-003)~~ resolved by D-01.6 and D-03.3.
2. ~~Operational email: provider or accept `NOT_CONFIGURED` (R1-012)~~ decided by D-42 (Yahoo Mail account for UAT, company domain before Production).
3. Disposition of untracked `0011_secure_legacy_public_tables.sql` (R1-010).
4. Vercel deployment-protection access for hosted UAT (R1-009).
5. ~~B-03 and B-05~~ resolved by D-01/D-02 on 20 Oct. Follow-up questions: see chat 20 Oct.
6. New facility UAT kick-off (asked 11 Nov 00:11; owner to discuss with the facility manager first). (a) Where the new
   facility's requirements form lives: a shared web page with an AI assistant, answers saved for setup (recommended);
   a new page inside FMWorks (Stage 2-sized build); or both (page now, app later). (b) Which testing documents: UAT test
   plan and scripts per role; updated Onboarding Guide for a New Facility; role quick-start cards; sign-off sheet and
   defect log (assumed all four unless told otherwise). Archive of closed and cancelled Work Orders: already decided by
   D-18 (Stage 2); recommendation is an in-app Archive view plus the off-site bundle, with the archive settings on the
   new facility form.

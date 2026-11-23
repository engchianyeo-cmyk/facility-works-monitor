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
9. Update 15 Nov 2026 17:27: Google offers only an SMS code to create the app password, and the SMS does not
   arrive on the owner's Singapore number. Offered fallback: a free sending service (Brevo, 300 emails a day) that
   signs in with its own SMTP login and sends as fmworks.notices@gmail.com. Small code change: new Vercel variable
   `EMAIL_FROM_ADDRESS` (the address shown as sender; defaults to `EMAIL_SMTP_USER`); `smtp-test.mts` takes
   `FMW_SMTP_HOST`, `FMW_SMTP_PORT`, `FMW_SMTP_USER` and `FMW_SMTP_FROM`.
10. Status 15 Nov 2026 18:47: email still off. Gmail: 2-step verification on; App passwords page asks for an SMS that
    never arrives. Brevo: Free account created; sending needs a phone check whose SMS also never arrives (possibly
    Singapore's SMS Sender ID Registry filtering overseas senders). Yahoo (fmworks.notices@yahoo.com): 2-step
    verification on (Authenticator), phone +65 on file, but "Create app password" stays greyed out and does not
    respond. Retry in a day or two; any one of the three is enough. Notices remain in the app meanwhile.
11. 15 Nov 2026 22:22: **facility_king@yahoo.com** (an older Yahoo account whose app passwords work) is the UAT
    sender for now. `smtp-test.mts` from the owner's PC: "OK: accepted by the mail server" (Yahoo, port 465). Vercel
    Preview: `EMAIL_SMTP_HOST=smtp.mail.yahoo.com`, `EMAIL_SMTP_PORT=465`, `EMAIL_SMTP_USER=facility_king@yahoo.com`,
    `EMAIL_SMTP_PASSWORD` = its app password (entered by the owner). Switch to fmworks.notices (Yahoo or Gmail) once
    its app password unlocks. The Facility 2 Administrator test login therefore uses engchian.yeo+f2admin@gmail.com
    instead of facility_king@yahoo.com (amends D-57 point 1).

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

### D-55 Personal details must be removable before a client handover — 13 November 2026 22:43 (proposed build)

Owner: "In the future, when we want to sell to a client, we will not want to leave an email account to the clients.
Hence email records must be deletable." Proposed: an Administrator action, with a reason and a confirmation, that
removes a person's email, sign-in and contact number for good and frees the email, while the audit history stays
under a neutral name ("Former user 0012"). Fits Singapore PDPA. Not built yet. Owner also asked whether
facility_king@yahoo.com is already registered on Preview (to be checked in Administration › Users, All statuses).
Update 15 Nov 2026: the Users page already has **Archive** and **Permanent delete** for each person (type the email
or name to confirm; refused for one's own account, the last ready Administrator, or while open Work Orders are
assigned; it fails where retained records still refer to the person). D-55 covers people with history, whose
details must be removed while their records stay. Owner's search for facility_king@yahoo.com (All statuses): no
match, so no profile holds it.

### D-56 Level 2 crash barrier raised to 1.5 m (drawing set Rev P3) — 15 November 2026 14:24

Owner (13:25): "do you think the parapet wall for 2nd storey should be higher to prevent potential accident of trucks
falling over edge?" Advice given: loaded container trucks carry their weight high; barriers tested for 36-tonne
articulated vans are about 1.07 m, a 1.57 m concrete barrier has been crash-tested at the highest (tanker) level.
Owner (14:24): "proceed".
1. The concrete crash barrier on both ramp edges, the north-west curve, the deck road and every open edge of the
   Level 2 apron is 1.5 m (was 1.2 m), hazard band at 1.05-1.35 m, steel guardrail top 2.1 m above the road.
2. Ramp: 10 km/h, speed humps and convex mirrors at the curve (note on PB-304).
3. Final barrier height, impact load and deck anchorage are for the Professional Engineer; the drawings remain for
   pinning Work Orders, not for construction.
4. Drawing set reissued as **Rev P3, 15 November 2026** (all 11 sheets, video, upload PDFs `PB-xxx_RevP3.pdf`);
   status stays "Approved for pinning Work Orders". The vehicles in the 3D views and video were also redrawn
   (cabs, glazing, wheels, containers) on 15 November.

### D-57 Build of D-50 and D-55 (M29) and the Facility 2 test accounts — 15 November 2026 15:24

Owner: "Oops, it should be 'sctpec2413@gmail.com'. 'ec@glorybene.com' is not a gmail ... Can i create
'koi.kpr+two@gmail.com' instead? ... I wanted them delete after testing. Proceed to build D-50 and D-55. Then I shall
create the users when you're done."
1. Test accounts for Facility 2, created by the owner after M29 is on Preview: facility_king@yahoo.com (Facility
   Administrator), sctpec2413+one@gmail.com (Approver), koi.kpr+one@gmail.com and koi.kpr+two@gmail.com
   (Technicians). After testing they are removed with "Remove personal details" (D-55), which frees the emails.
2. Built (migration `20261115120000_facility_administrators_and_personal_data.sql`, M29; SQL test
   `facility_administrators.test.sql`; plan `docs/design/D-50_FACILITIES_AND_SUPER_ADMINISTRATOR_PLAN.md`):
   - the Administrator role is shown as **Super-Administrator** (unchanged powers, all facilities);
   - new role **Facility Administrator**: for its own facilities only, edits details (cannot switch the facility off),
     areas, drawings, staff and settings, creates and edits Technician, Approver, Supervisor, Facility Manager and
     Finance accounts that join its facility at once, and reads its Work Orders; never adds facilities, appoints
     Facility Administrators, approves, executes or pays; sees no other facility's staff or Work Orders;
   - **Finance per facility**: reads, is copied and is notified (including the daily reminder email) only for the
     facilities it is staff of; one Finance account may belong to several facilities;
   - **facility switch** above the Work Orders list ("All facilities" or one facility; shown to anyone who can see
     more than one facility), remembered in the browser;
   - **Remove personal details** (Super-Administrator, type the email and a reason): the name, email and contact
     number leave the profile and the history ("Former user NNNN"), memberships end, the account closes, and the
     sign-in gets a placeholder email, so the real email can be used again. Records stay.
3. Preview script with M29: `preview-m29-finance-to-facility-one-20261115.sql` adds the existing Finance accounts
   to Facility One (UAT-FAC-001), so Finance keeps seeing what it sees today. Existing SQL tests now add Finance to
   the test facility.
4. Not yet: Facility Locations (area pins) stays Super-Administrator only; the Archive (D-18) is still Stage 2.
5. 15 Nov 23:54: `release:verify` PASS (third run; first two caught a Finance test missing its facility membership and
   a header drop-down that slowed pages and confused a browser test; the facility switch moved to the Work Orders list
   and the new checks were made lighter). 30 browser tests passed in 4.0 minutes.
6. 15 Nov ~23:55: commit `2ae6ca3` pushed. 16 Nov 00:30: `out/preview-increment-m29.sql` built (sha256
   `36959c53…bdb0433`) and rehearsed on a local copy; runbook `docs/releases/PREVIEW_M29_RUNBOOK.md`. Preview not yet
   changed.

### UAT fix 16 November 2026 — accounts for every role (M30, no owner decision needed)

Owner (11:09): creating fmworks.notices@yahoo.com as Facility Administrator of Facility 2 failed with "The user
provisioning request could not be prepared". Cause: the provisioning ticket table (`account_invitations`) still had
role checks from October that did not list Facility Administrator (nor, in one of them, Facility Manager and Finance).
Fix: migration `20261116100000_account_invitation_roles.sql` (M30) allows all nine roles; checked on a local copy and
added to `facility_administrators.test.sql`. Until M30 is on Preview: create the person as Reviewer, change the role
in the Users list, then add them to the facility's staff.
Also fixed (11:48): after switching the role to Reviewer, the form still sent the Facility chosen earlier and was
refused ("Only Technicians, ... join a facility"); a facility is now sent only with a role that joins one. Until this is
on Preview: reload the Users page before creating the person as Reviewer.
Also fixed (12:10): in the Users list, saving a person created since the page was opened failed with "Name, an
active department and a valid role are required" (the row had no full editable copy, so only the changed role was
sent; its Status also showed "Inactive" while ticked). New rows now get a full copy. The Actions column (Save,
Archive, Permanent delete, Remove personal details) now stays visible at the right edge instead of needing a sideways
scroll (owner's remark: a new user would not know to scroll). Until this is on Preview: reload the Users page before
changing a new person's role.
Also fixed (12:56): a Facility 2 Technician's Work Orders list did not say which facility it showed, and offered
"4 test Work Orders hidden" that belong to Facility One. The list now names the person's facility when they have only
one, warns when they are not yet staff of any facility, and counts only test Work Orders the person can see.

Owner request (13:09): put the first three Facility 2 Work Orders (entry sheets F2-WO-20, F2-WO-04, F2-WO-01) on
Preview. Claude does not sign in as users, so `scripts/rollout/preview-f2-first-three-work-orders-20261116.sql`
creates them as Drafts through the app's own `create_work_order()` acting as Technician koi.kpr+1 (WO-20, WO-04) and
koi.kpr+2 (WO-01): same checks and audit entry as pressing "+ New Work Order". Dry run by default; refuses without the
Preview project setting, if either Technician is not Facility 2 Technician staff, or if the titles already exist.
Rehearsed on a local copy (dry run, apply, refused re-run, refused non-member, refused wrong project). Photos, layout
mark and quotations are still added in the app. Not yet run on Preview.
13:25 dry run on Preview stopped safely: koi.kpr+2 had not yet changed his temporary password. Owner asked to
proceed (13:46): the script now creates F2-WO-01 as koi.kpr+1 when koi.kpr+2 is not ready (rehearsed both ways);
koi.kpr+2 can be named Technician 2 on it later.
Applied on Preview 16 Nov 2026 ~14:15 by the owner (target checked: cli_login_postgres.pvajuywwwpjlikqjnvgv):
FW-2026-0006 Battery charger BC-05 (in-house, koi.kpr+1), FW-2026-0007 Freezer RU-FZ-B (critical, koi.kpr+1),
FW-2026-0008 CH-01 chiller service (koi.kpr+2), all Draft at Facility 2; no Area set (Facility 2 areas not yet loaded).

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


### Preview rollout record — 16 November 2026

| Time (SGT) | Change on Preview (pvajuywwwpjlikqjnvgv) | By |
| --- | --- | --- |
| 15 Nov 23:54 | `release:verify` PASS (SQL gate incl. `facility_administrators.test.sql`, 30 browser tests) | Owner |
| 15 Nov ~23:55 | Commit `2ae6ca3` pushed to `uat/claude-review` (M29 build) | Owner |
| 16 Nov 09:04 | Target checked (`cli_login_postgres.pvajuywwwpjlikqjnvgv`, pooler aws-0-ap-southeast-1); read-only check: ledger 78 entries, latest `20261110100000`. `psql`/`pg_dump` run through Docker (`postgres:17`), since they are not installed on Windows | Owner, guided |
| 16 Nov 09:05 | First backup attempt refused at login (EAUTHQUERY: the temporary login had expired); nothing changed. Login reloaded | Owner, guided |
| 16 Nov 09:06 | Backup `.git/preview-backup-20261116-pre-m29.sql` (2,925,626 bytes, `--role=postgres`, `public` + `supabase_migrations`) | Owner, guided |
| 16 Nov ~09:11 | Increment `out/preview-increment-m29.sql` (sha256 `36959c53…bdb0433`) applied: `20261115120000` Facility Administrators, Finance per facility, Remove personal details (M29); preflight 78; ledger now 79; COMMIT | Owner, guided |

### UAT change 16 November 2026 — location mark is a star (owner, 14:37)

Owner asked for the location mark on drawings to be a star instead of a circle, and whether a wrong mark can be
deleted. The "Pin" tool is now "★ Location star" and draws a red star (blue when selected), kept star-shaped on wide
drawings. Deleting already existed (select the mark, press Delete; the audit record is kept); the toolbar now says so
in a line under the drawing. File: `components/work-orders/drawing-markup-editor.tsx`. Existing marks redraw as stars.

### UAT change 16 November 2026 — Home page shows facility and open work only (owner, 16:03)

Owner (Super-Administrator view): the Home page "did not look right": "Active facility work" mixed Facility One and
Facility 2 Work Orders with no facility shown, and listed Closed and Cancelled ones. Changed: each entry now shows its
facility name, and Closed / Cancelled are left out of that list (still in Work Orders). Files: `app/page.tsx`,
`components/mission-control/OperationsSummary.tsx`. Noted, not changed: the role chip reads "Administrator" because a
company wording saved under Roles & Stages overrides "Super-Administrator"; the Facility Overview at the bottom is
the development sample layout, not a real facility (proposal to replace it with the facility's own drawings pending).

### D-58 — In-app assistant: built-in Help guide first, AI assistant later (16 Nov 2026)

Owner (13:14–13:20): FMWorks should have an assistant that guides new users around the app. Options set out:
A) an AI assistant inside the app (needs a paid AI service key, billed per question); B) a built-in Help guide with
prepared answers (no running cost); C) B now and A later as an on/off switch. **Owner chose C, starting with B.**

Built (option B): a "Help" button on every page for signed-in people opens "Help on this page": steps for the
person's role on that page; on an open Work Order, its stage and what that person does next; and a question box that
matches prepared answers (drawn from knowledge pack v3.2). No AI service is called and nothing typed is sent anywhere.
Files: `lib/help/guide-content.ts`, `components/help/help-panel.tsx`, `components/help/help-context.tsx`, mounted in
`app/layout.tsx`; stage fed by `app/work-orders/[id]/page.tsx`; tests `tests/help-guide.test.ts`.
Option A later: same content as the assistant's knowledge; it will explain and guide only (no actions, no passwords,
only what that person may see), switched on only when a paying client supplies its own AI service key.

Owner (16:54): "build the assistant now". Built option A behind its switch (off until a key is provided):
`app/api/assistant/route.ts`, `lib/assistant/config.ts`, `lib/assistant/prompt.ts`, `lib/help/knowledge-pack.ts`
(from `docs/assistant/FMWorks_Knowledge_Pack.md`, v3.2 plus an updates note). When the server has
`FMW_ASSISTANT_AI=on` and `ANTHROPIC_API_KEY`, the Help panel shows "Ask the AI assistant": the question, the person's
role, the page and the open Work Order's number and status go to the AI service with the assistant rules (guide only,
no actions, no passwords, safety first, people decide approvals and payments); the answer is shown as "AI answer —
check it against the app". Refused before sending: text that looks like a password, code or card number. Limit 30
questions per person per hour; questions are not stored. Model `FMW_ASSISTANT_MODEL` (default claude-haiku-5-5).
Tests: `tests/assistant.test.ts`. Not switched on anywhere yet; the key is billed per question.

Also (16:54, owner's go-ahead to the Home page proposal): the Home page's "Facility Overview" development sample is
replaced by "Facility drawings": each facility the person can see, its lead plan drawing, links to all its drawings and
its open Work Order count (`components/mission-control/FacilityDrawingsOverview.tsx`). The sample layout component is
kept and still shows when no facility has drawings.
Test `tests/mission-control.test.ts` updated to match (17 Nov, release:verify run 1): the Home page must show
"Facility drawings" after the operational panels, with the sample overview as the fallback.

Owner (17:40): the assistant should have a mascot. Added "Ollie", an original drawing for FMWorks (a blue owl in a
yellow hard hat and orange hi-vis vest), as an SVG component (`components/help/mascot.tsx`) on the Help button
("Help · Ollie"), in the Help panel header and on AI answers; the AI introduces itself as Ollie.

### D-59a — Fault library: the app learns from finished jobs; assistant sounds, voice, picture; phone menu (16–17 Nov 2026)

Owner (14:53–18:00, 16 Nov): the assistant should help Technicians troubleshoot and get smarter from past experience;
the app should ask users for learning tips after every Work Order; the assistant (Ollie) should chime when it wants to
learn and when something urgent needs attention, with a test button, an off switch and a reminder to turn sound back on
after a day; it should speak English; the Administrator can change its picture; the app must work on a phone or tablet.
Owner said "Let's start" (17:59); work resumed 17 Nov.

Built (migration M31 `20261116130000_fault_library_and_assistant_settings.sql`, test `tests/sql/fault_library.test.sql`):
1. **What we learnt** (`work_order_learnings`, `share_work_order_learning`): when a Work Order is Submitted for Review,
   Completed or Closed, the people on it (Technician 1 and 2, the preparer, the facility's approvers) are asked —
   highlighted box and a chime — for the Confirmed cause, the Fix that worked, a Tip, and whether an AI suggestion
   helped. One entry per person per job (can be updated); audited. Seen by whoever may see the Work Order.
2. **Fixed before** (`work_order_learning_matches`, runs with the person's own rights): open Work Orders show
   learnings from similar jobs (same asset first, then shared words such as the tag BC-05). "Proven fix" = Completed
   or Closed and no new Work Order on the same asset within 30 days; otherwise "Fault came back within 30 days".
3. **Hiding** (`hide_work_order_learning`): the Super-Administrator, the facility's Facility Administrator or Facility
   Manager can hide a wrong entry with a reason; it is kept for the record.
4. **Ollie uses it**: when the AI assistant is switched on, the site's learnings on similar jobs are given to it first.
   The app does not learn by itself without people sharing; it ranks and checks what they share automatically.
5. **Sounds and voice** (`lib/help/ollie-voice.ts`, browser only, nothing sent anywhere): a soft chime when asking for
   a tip, a brighter three-note alert when new notices arrive; "Speak in English" reads alerts and answers aloud with
   the device's English voice; "Read aloud" buttons; Test sound / Test alert / Test voice; on/off per device; after
   sound has been off for a day, a reminder offers to turn it on (once a day). Browsers play sound only after the page
   has been tapped once.
6. **Name and picture** (`assistant_settings`, `set_assistant_settings`, page Administration > Assistant): the
   Super-Administrator renames the assistant or uploads a PNG, JPEG, WebP or SVG (≤300 KB; served with a locked-down
   policy); "Use Ollie again" restores the default. Audited.
7. **Phone and tablet**: header links fold under a Menu button below tablet width; the Help panel opens as a bottom
   sheet on phones.
Rehearsed on a local copy: M31 applies after M30; fault_library and facility_administrators tests pass.
release:verify PASSED on the owner's PC, 17 Nov 2026 ~14:19 (typecheck, lint, 980 unit tests, Docker SQL runners
including fault_library, build, 30 browser tests in 4.2 min, diff hygiene). Next: commit, Preview increment M30 + M31
(backup first), then push.
Increment built: `out/preview-increment-m31.sql` (`build-preview-increment.mjs ... 20261115120000`), sha256
`9263c7771ddd48488645fe62e0abc912718bf50496083c38fe7ab9d557f3614e`. Rehearsed on a local copy at M29 with a stand-in
ledger ending 20261115120000: refused without the Preview assertion; applied and committed; a second run refused
("ledger ends at 20261116130000"); fault_library and facility_administrators tests then passed.
Applied on Preview by the owner, 17 Nov 2026 ~16:19 SGT: target checked (`cli_login_postgres.pvajuywwwpjlikqjnvgv`
at aws-0-ap-southeast-1.pooler.supabase.com); read-only check 79 entries, latest 20261115120000; backups
`.git/preview-backup-20261117-pre-m31.sql` and `-b.sql` (3,005,353 bytes each); increment sha256 `9263c777…`
"Preflight passed: 79 ledger entries" and COMMIT; ledger now 81, latest 20261116130000. Production untouched.
Lesson: a fresh Supabase CLI temporary login needs about a minute before the pooler accepts it, and expires a few
minutes later; connect, wait 60 s, then run the step.

UAT 17 Nov 2026 16:57 (owner): asked Ollie "What is Report Emergency Incident" and got no useful answer (AI not
switched on; no prepared answer on incidents; the incident pages had no page guide). Added page guides for Emergency
incidents, Report Emergency Incident, an incident, Assets, Preventive maintenance, Administration and the Assistant
page; prepared answers on what an incident is, incident vs Work Order, the incident response steps and who is
alerted. The best-matching answer now opens by itself, and an unmatched question explains that free questions need
the AI assistant to be switched on.
17:10 (owner): "Explain SLA" gave no answer and there was no button to press. Now an "Ask Ollie" button (and Enter)
is always there; every page guide can also answer questions about its page; "What is an SLA?" added; words such as
"explain", "what", "tell me about" are ignored when matching.
17:17 (owner): on Site SLA › Check each clause found, the unlabelled number box beside "Approve for draft" was unclear.
It is an optional correction of the clause's attend time in minutes; it now has a label and an example. (The owner had
typed 1 and 2; those would have set an attend time of 1 or 2 minutes if approved.)

### D-60 — SLA per facility, set by the Super-Administrator; the assistant learns from questions (17 Nov 2026)

Owner (17:21–17:48): prepare an SLA for the facilities with slight variations (drafted as the Claude doc "Facility
Services SLA — Facility One and Facility 2 (draft)"); the draft is the standard for all facilities and the
Administrator must be able to edit the SLA criteria (for example the time to react to an emergency); the assistant
must pick up questions and their answers to advise better next time; plus UAT findings on SLA clauses, planned
maintenance, drawings and assets.

Built:
1. **M32 `20261117120000_sla_per_facility.sql`** (test `sla_per_facility.test.sql`): `sla_agreements.facility_id`
   (null = standard for all facilities); a new Work Order's clock uses its facility's own SLA first, then the
   standard; `admin_set_sla_times` (Super-Administrator only, reason required, all four priorities, times may not
   run backwards) writes a new approved version and ends the old one (running clocks keep their times);
   `admin_use_standard_sla` puts a facility back on the standard. Page **Administration > SLA times**
   (`/administration/sla`) with minutes / hours / days per box; Site SLA groups "Standard" and each facility's own.
2. **M33 `20261117130000_assistant_learning.sql`** (test `assistant_learning.test.sql`): questions asked in Help are
   kept with role and page only (no person), what answered them and "Did this help?"; passwords and card numbers
   refused. The Super-Administrator, Facility Administrators and Facility Managers write answers from those questions
   under Administration > Assistant; the assistant matches them first and gives them to the AI first. Audited.
3. **SLA clauses** (Management > SLA): the clause list refreshes by itself after reading a document, and reading the
   same document again no longer adds a clause already waiting (the owner's duplicate "MOCK-1" came from pressing
   the button twice; reject one). Button renamed "Find SLA clauses (test reader)"; e2e test updated.
4. **Preventive maintenance:** "Due within 1 / 3 / 6 / 12 months" on Upcoming Maintenance; plain wording for the two
   steps ("List servicing due up to this date", "Create Work Orders for what is due") with quick 1/3/6/12-month dates.
   The list stays empty until PM requirements exist for the equipment.
5. **Assets:** "Download asset list (Excel)" (CSV that Excel opens; current filters applied; row security applies).
6. Script `scripts/rollout/preview-sla-standard-and-facility2-20261117.sql`: loads the draft's times (standard =
   Facility One table, Facility 2 = its own) through `admin_set_sla_times`; working days counted as whole days.
Rehearsed locally: M32 + M33 apply after M31 (increment `out/preview-increment-m33.sql`, sha256 `9d895e7d…`; refused
without the Preview assertion; refused twice); sla_per_facility, assistant_learning, fault_library and site_sla
tests pass; the SLA script's dry run and apply worked.
Noted, not changed: an SLA clock starts when the Work Order is created as a Draft (not when submitted, as the Help
text says); a Draft left for days uses up its SLA time. Owner to decide whether the clock should start on submission.
Facility drawings page is empty because no drawings have been uploaded to Preview yet.

UAT 17 Nov 2026 18:02–18:05 (owner):
- **Operations › Team**: a "Standby Technicians by facility" table (on standby now = active on the on-call roster,
  other Technicians, open Work Orders held), then each facility's Technicians with every open Work Order they hold
  as Technician 1 or Technician 2 (number, title, stage, priority). Previously only Assigned / In progress counted, so
  Drafts held by the Facility 2 Technicians showed "No active assignment recorded".
- **Operations › Schedule**: Today, Tomorrow and Upcoming list open work only (Completed, Closed, Cancelled drop off;
  Submitted for Review stays). The WO-TEST items there are Facility One test data: the D-52 script marks them.
- **Facility drawings**: empty page now says what will appear and links the Administrator to Facilities to upload.
- **Facility drawing locations**: choosing a facility shows its address on a Google Map (embedded, no key), with
  "Open in Google Maps"; without an address it says where to add one.

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

### D-61 — Maintenance plan by frequency, Technician per task, O&M manuals (17 Nov 2026)

Owner (18:14–18:40): "Under maintenance, list the equipment that are designated for daily maintenance, weekly
maintenance, quarterly maintenance and annual maintenance. For each equipment the supervisor can assign the respective
Technicians responsible … It also collect the O&M manual for each equipment for technicians to cross reference to."
Reviewed as a Design mockup (Facility 2: 73 equipment, 97 tasks), then "Let's build all the requirements now".

Built:
1. **M34 `20261117140000_maintenance_plan.sql`** (test `maintenance_plan.test.sql`): `maintenance_requirements`
   gains the Technician responsible (`assigned_technician_id`, by, at); `assign_pm_technician` (Supervisor or
   Facility Manager who is staff of the asset's facility, or the Super-Administrator; Technician must be staff of that
   facility; audited); a Work Order created from a planned-maintenance occurrence goes to that Technician unless one
   is given; facility staff and the assigned Technician can read the plan. `asset_documents` (O&M manual, datasheet,
   certificate, drawing, other; PDF or image up to 50 MB, private storage) with `register_asset_document` /
   `retire_asset_document` (taken out of use with a reason, kept on record; not deleted).
2. **Page Maintenance plan** (`/maintenance-plan`, header link, and a tab in Maintenance): tabs Daily / Weekly /
   Monthly / Quarterly / Six-monthly / Annual with counts; search; Only my tasks; Only unassigned; Technician box for
   planners; O&M manual open / download / upload / take out of use. Open to every signed-in role (Technicians
   included; the /maintenance area stays planner-only). The O&M manual also shows on the Work Order's asset panel.
3. **Script `scripts/rollout/preview-f2-maintenance-plan-20261117.sql`**: loads the reviewed Facility 2 plan — 73
   assets tagged `F2-…` at Facility 2 and 97 tasks; daily checks stay **Draft (proposed)**, others Active; default
   Technician as in the mockup (in-house / both: Electrical, Fire, Safety, Plumbing, Controls → Technician 1
   koi.kpr+1, other → koi.kpr+2 if ready else Technician 1; contractor work → not assigned). Rehearsed: 73 assets,
   97 tasks (85 active, 12 draft), 23 with a Technician; refuses a second run and runs without the Preview assertion.
4. Increment `out/preview-increment-m34.sql` (M32 + M33 + M34 after 20261116130000), sha256 `3e6701a1…021d4`;
   rehearsed on the M31 state: preflight passes, refused without the assertion and refused twice; maintenance_plan,
   sla_per_facility and assistant_learning tests pass on the result. Supersedes `out/preview-increment-m33.sql`.

Owner to decide: confirm the 12 daily checks (then activate them); whether contractor-serviced equipment should still
have an in-house Technician for daily / weekly walk-round checks (default leaves them unassigned).

**Preview rollout (17–18 Nov 2026, owner ran it):** `release:verify` PASS after three test fixes; commit `11555c3`
pushed to `uat/claude-review`. Preview database (host and user checked as `pvajuywwwpjlikqjnvgv`): backup
`.git/preview-backup-20261117-pre-m34.sql`; increment `out/preview-increment-m34.sql` (sha256 `3e6701a1…021d4`)
applied — preflight 81 entries at 20261116130000, COMMIT, ledger 84 entries ending 20261117140000. Data scripts
(dry run checked first; backup `.git/preview-backup-20261117-pre-data-scripts.sql`) all COMMITTED: SLA standard +
Facility 2 times; D-52 (14 WO-TEST Work Orders marked as test data; FW-2026-0004 to 0008 untouched); Facility 2
maintenance plan (73 assets, 97 tasks, 85 active, 12 daily drafts, 23 with a Technician).

### D-62 — Ollie finds places in the facility; no false matches on one shared word (18 Nov 2026)

Owner (14:46): asked Ollie "Is there a room to store morphine?" and got "My room is not in the Area list", which does
not answer it. Fixed (app only, no database change):
1. Prepared answers now need at least half of the question's own words; one shared word ("room") no longer counts.
2. "Ask Ollie" also looks in the facility's equipment locations and area list, with the person's own access, using
   everyday words (morphine / opioid / narcotic / CD → Controlled Drugs Vault; vaccine / insulin / fridge → cold rooms;
   freezer; dangerous goods; quarantine / returns; lift; toilet; first aid / AED; eyewash; generator; docks). Shown as
   "Found in your facilities"; for controlled drugs it adds a caution to follow the facility's controlled-drug procedures
   and ask the Facility Manager or Responsible Person. Facility 2 answers "M1.08 Controlled Drugs Vault" (from the
   intruder alarm IAS-CD at that location) even before its area list is loaded.

### D-63 — Users list filtered by facility (18 Nov 2026)

Owner (16:18): "include the facility name to filter users selected from that facility". Administration > Users now has
a Facility filter (All facilities / each facility / Not in any facility) and shows each user's facilities under the
email (the Super-Administrator shows "All facilities"). Facilities come from active memberships; a Facility
Administrator sees only its own facilities. App only, no database change.

### D-64 — Each facility's staff can see its staffing structure (18 Nov 2026)

Owner (16:35): "for each facility, eg. Facility 2, all staff of this facility will have access to the staffing
structure for Facility 2. The same goes for facility one". New page **Our team** (`/facility-team`, header link, all
roles): per facility, the chain Super-Administrator → Facility Administrator → Facility Manager → Supervisor →
Technicians, with Approver and Finance alongside; each role's duty in one line; name, trade/discipline and work phone
(if recorded); no emails. The server checks the viewer's own active membership first; the Super-Administrator sees
every facility. Built from facility memberships, so it follows Administration › Users. App only, no database change.

### D-65 — SLA clauses: one clause shown once (18 Nov 2026)

Owner (16:39): "Why are these clauses repeated under SLA page?" (four "Clause MOCK-1" cards). Cause: the same test
agreement (FMWorks-Pilot-SLA.txt) is on file more than once and was read more than once before the 17 Nov fix; each
reading kept its own copy of the clause. Section 3 now shows each clause once (the approved one if any, else the
newest waiting one) with "also found N more times", names the agreement it came from, and folds rejected-only clauses
into "Rejected clauses (n)". Approving the one shown settles it; the waiting copies stay hidden. App only.

### D-66 — Facility One's drawings only for Facility One (18 Nov 2026)

Owner (17:07): a Facility 2 Work Order (PM "Run pump 30 min…") showed Facility One's FW/PW drawings — "Please rectify!".
Cause: when a facility had no uploaded drawings, the Work Order page fell back to the built-in FW-series drawings,
which belong to Facility One. Fixed: the built-in set is used only for Facility One (code UAT-FAC-001, or a name
starting "Facility One"); any other facility without uploads shows "No drawings have been uploaded for this facility
yet" and none of Facility One's. The same rule applies to placing areas on drawings (Administration > Facilities).
Facility 2's own drawings PB-001 to PB-304 (Rev P3) were handed to the owner to upload
(`out/facility-2-drawings/`, with UPLOAD-LIST.txt). Until they are uploaded, Facility 2 Work Orders cannot be
submitted (the location mark is required by the database). App only, no database change.

### D-67 — Planned maintenance dates, daily round, contractor safety documents, staff availability (18 Nov 2026)

Owner decisions (21:54 and 23:03), Facility 2 first; every item is to be asked again when a new facility starts
operations (facility onboarding):
- **A. Date windows** agreed: weekly ±1 day, monthly ±3, quarterly ±7, six-monthly ±14, annual ±21, counted from the
  planned date. Dates are proposed by the app's own rules (not AI); no monthly "confirm" chore — dates stand unless a
  Supervisor moves one. Owner asked that the feature can be switched off if paperwork slows the team: per-facility
  setting Off / Plan only / Full (Super-Administrator, with reason). Ollie reminds and warns only.
- **B. Beyond the window**: Super-Administrator or the facility's Facility Administrator approves (per-facility,
  asked at onboarding).
- **C. Weekends**: a planned date on a weekend moves to Friday or Monday, whichever has more manpower available.
- **D. Daily checks**: all 12 confirmed, listed for Technicians daily; each check has a tick-off checklist, and items
  can be added for daily walks. Approver, Supervisor or Facility Manager assigns them to Technicians.
- **E. Days**: every day (all 7).
- **F. One "Daily round" Work Order per day** for Facility 2; routine type — no work permit, method statement or
  risk assessment.
- **G. Facility 2**: Technician 2 does the daily round, Technician 1 covers. Facility One: in-house or contractor is
  chosen on the Work Order (existing option kept).
- **Contractor work**: work permit, method statement and risk assessment are required before a contractor proceeds;
  needed once for the "first of its kind" job; a work permit may cover the whole year when the servicing repeats;
  method statement and risk assessment can be reused.
- **H. H1 for now** (in-house Technician by trade for contractor tasks); more than two Technicians may share the work;
  asked again at start of operations.
- **Staff availability**: everyone enters availability in advance, prompted at the start of each month; where no
  superior has assigned a task, the roster decides; tasks with nobody on duty that day are flagged on the dashboards
  of Administrator, Facility Manager, Approver and Supervisor; urgent leave is entered in the app and that person's
  jobs are flagged for reassignment to someone of equal or lower position.
Status: recorded; build to be phased (owner to confirm order).
Owner answers (23:05): build order left to Claude (1 automatic PM → 2 daily round → 3 contractor safety documents →
4 availability and leave → 5 new-facility questions); Facility 2 starts on **Full for critical equipment only**
(Work Orders for critical equipment, the rest shown as a plan); Daily round ready **07:00, done by 10:00**; work permit,
method statement and risk assessment approved by the facility's **Supervisor or Facility Manager**.

**D-67 part 1 built (18 Nov 2026): M35 `20261118120000_pm_automation.sql`** (test `pm_automation.test.sql`):
per-facility `pm_mode` (off / plan_only default / full_critical / full) set by `admin_set_pm_mode` (Super-Administrator,
reason, history); `pm_window_days` and `reschedule_pm_occurrence` (inside the window: Supervisor / Facility Manager /
planners; beyond: Super-Administrator or the facility's Facility Administrator; earlier moves now allowed, at most 21
days); `defer_pm_occurrence` refuses beyond-window deferrals for others; `materialize_pm_occurrences` skips "off"
facilities and `process_due_pm_work` creates Work Orders only where the setting allows; `pm_daily_run()` (scheduler
only) lists 31 days, moves weekend dates to Friday or Monday with fewer tasks (inside the window; recorded as automatic)
and creates due Work Orders. App: Maintenance shows each facility's setting (Super-Administrator changes it), "Change
the date" on Upcoming, no overdue exceptions where the setting creates no Work Orders; Maintenance plan shows the
setting; `/api/cron/pm-daily` (CRON_SECRET) with `vercel.json` daily 22:00 UTC for Production; Preview uses pg_cron
(`preview-pm-daily-schedule-20261118.sql`). Script `preview-pm-automation-f2-20261118.sql`: Facility 2 → Full for
critical only, H1 Technicians for contractor tasks (rehearsed: 63 tasks; Technician 1 38, Technician 2 47 active), one
daily run. Weekend choice uses "fewer tasks that day" until staff availability (part 4) exists; public holidays not yet.
Increment `out/preview-increment-m35.sql` sha256 `85de91fc…42969`, rehearsed on the M34 state.

**M35 Preview rollout (19 Nov 2026, owner ran it):** `release:verify` PASS (after making two SQL tests use Singapore
dates); commit `f8b422d`. Preview (host and user checked as `pvajuywwwpjlikqjnvgv`): backup
`.git/preview-backup-20261118-pre-m35.sql`; `out/preview-increment-m35.sql` (sha256 `85de91fc…42969`) applied —
preflight 84 entries at 20261117140000, COMMIT, ledger 85 ending 20261118120000. Data (dry run checked first; backup
`.git/preview-backup-20261118-pre-m35-data.sql`) COMMITTED: Facility 2 → Full for critical only, Facility One stays
Plan only; 63 contractor tasks given a Technician (koi.kpr+2 47, Technician 1 38 active tasks); daily run listed 0 and
moved 0 (the month was already listed and its Work Orders created before M35); pg_cron job `fmworks-pm-daily`
at 22:00 UTC (06:00 SGT) active.

**D-67 part 2 built (19 Nov 2026): M36 `20261119120000_daily_round.sql`** (test `daily_round.test.sql`): facility
settings for the Daily round (on/off, ready 07:00, due 10:00, Technician, cover); checklist tables (checks, items with
optional reading unit) editable by the facility's Approver, Supervisor, Facility Manager, Facility Administrator or the
Super-Administrator; one Daily round Work Order per facility per day (`work_orders.daily_round_date`, unique), created
`approved`, in-house, assigned to the Technician (cover if the Technician is not an active member), with no SLA clock and
no permit / method statement / risk assessment / quotation; `record_daily_round_item` (Technician, cover or editor;
reading required where a unit is set; Not OK needs a reason; first item starts the work) and `complete_daily_round`
(all items recorded → closed, faults counted). `pm_daily_run` now also creates each enabled facility's round where the
planned maintenance setting creates Work Orders. App: header "Daily round" (`/daily-round`: today's checklist, OK / Not
OK, readings, Complete, late after the due time, last 14 rounds; "Start today's round now" for editors), set-up page
(`/daily-round/setup`), Work Order page links to the checklist. Script `preview-f2-daily-round-20261119.sql`:
Facility 2's 12 checks with 42 items (16 readings), switched on with Technician 2 and Technician 1 as cover, the 12 Draft
daily tasks taken out of use, today's round created (rehearsed). Increment `out/preview-increment-m36.sql` sha256
`35a50206…45159`, rehearsed on the M35 state. Leave and availability (part 4) will choose the cover automatically.

### D-68 — Slow down the trial: at most 10 open Work Orders, Facility 2 on Plan only (20 Nov 2026)

Owner (11:41): "this is not a real facility in operation yet and my contact will not be able to manage such a high load
without full staff ... reduce to 10 or less work orders ... retain only the interesting ones." Preview had about 590
Work Orders, almost all planned maintenance created before the setting existed (M35).
- **M37 `20261120120000_daily_round_on_plan_only.sql`**: the daily run creates the Daily round on Plan only too (only
  Off stops it), so the routine round keeps going while no other planned-maintenance Work Orders are created.
- **Script `preview-reduce-work-orders-20261120.sql`**: Facility 2 → Plan only; keeps at most 10 open Work Orders (today's
  Daily round; Work Orders raised by staff, newest first; then planned maintenance, one per trade, critical equipment
  first) and cancels every other open one with the reason "Trial load reduced: the facility is not yet fully staffed",
  cancelling its planned date too so it is not created again. Nothing deleted; history kept; test data (D-52) not
  counted. Rehearsed on a copy with 199 open: 10 kept, 189 cancelled; a second run changes nothing.
- Future planned dates stay as a plan (Upcoming, Maintenance plan) and can be turned into Work Orders by switching the
  setting back when the facility is staffed.

**D-68 Preview rollout (20 Nov 2026, owner ran it):** `release:verify` PASS; commit `7aa38d1` pushed; M37 applied
(backup `.git/preview-backup-20261120-pre-m37.sql`; increment `out/preview-increment-m37.sql` sha256 `180c50bf…46c6`).
Clean-up (dry run checked first; backup `.git/preview-backup-20261120-pre-m37-data.sql`) COMMITTED: 589 open Work
Orders → 10 kept (Daily round FW-2026-0594; staff-raised FW-2026-0006/0007/0008; planned maintenance FW-2026-0009,
0012, 0018, 0023, 0051, 0242), 579 cancelled with their planned dates; Facility 2 and Facility One on Plan only.

### D-69 — Facility One's built-in drawings listed; upload message cleared (21 Nov 2026)

Owner (19:06–19:26): could not find Facility One's drawings; an upload as FW-001 failed. FW-001 to FW-008 are the
built-in drawings (reserved numbers since D-47/D-48) and stay in use on Facility One's Work Orders, location marks and
34 area pins; Claude's earlier advice to upload them under those numbers was wrong and withdrawn. App only: they are now
listed, with View and Download, under Administration › Facilities (Facility One) and on the Drawings page, with a note
that the numbers are reserved and that uploading another number replaces them on Work Orders. The upload form clears
its previous message when a new file is chosen (the stale "Drawing uploaded" line misled during Facility 2 uploads).

### D-70 — Ollie walks a first-time Technician through the Work Order (21 Nov 2026)

Owner (20:24): asked Ollie "what should I do now?" on FW-2026-0012 and got unrelated prepared answers; wants Ollie to
guide a first-time Technician through the Work Order. App only:
1. **"Walk me through this Work Order, step by step"** in Ollie's Work Order box: a card at the bottom of the screen
   steps through the page for the Work Order's stage and the person's role (timeline, checklist, location star,
   photos, the action buttons, Technician 2, the equipment), outlining each section and scrolling to it; Back, Next,
   Read aloud, Stop; works on phones.
2. **"What should I do now?"** (and "what's next", "walk me through", "first time", "how do I start") on a Work Order now
   answers with that Work Order's own next step and the walk-through button, instead of unrelated prepared answers.
3. The **first time a Technician opens a Work Order** on a device, Ollie offers the walk-through ("Show me" / "No
   thanks"); it is not offered again on that device.
4. Owner (20:30): "I am new and need you to guide me through the work order" found the Maintenance Workshop and a
   network UPS. Ollie now searches the facility only for place questions (where, room, store, find, is there…, or a
   place word it knows such as morphine or lift), and never on app words (work, order, guide, new, step…).
5. Ollie's Work Order box also lists **what is still missing on this Work Order** (from the page's own readiness
   check, for example "Location marked on the layout plan"), so "What you do next" is specific to the job.

### D-71 — Planned-maintenance Work Orders can be approved; no reaction SLA on them (21 Nov 2026)

Owner (20:36): on FW-2026-0012 (weekly sprinkler pump run, generated by the plan) the timeline told the Approver "Next
step — yours: approve", but "Do this now" led to a box saying "Not ready for approval" (location mark, Before photo,
0 of 1 quotations, recommended quotation) with only Return to Draft. The SLA countdown also showed "Missed by 3 days".
**M38 `20261121120000_planned_work_ready_to_approve.sql`** (test `planned_work_ready.test.sql`): planned-maintenance and
Daily round Work Orders are in-house work (existing open ones updated) — no quotation per visit (contractor visits fall
under the service contract); the approval check no longer asks them for a location mark or Before photo; they get no
reaction SLA clock (they are measured against their due date). App: the SLA countdown is hidden on them; when an
Approver cannot approve yet, the timeline says "not ready to approve yet — n item(s) missing (…). Return it to Draft and
say what to add", and the readiness box explains that Approve appears once the items are in place. Assumption to
confirm with the owner: contractor-serviced planned visits need no quotation each time.

## D-72 — Our team shows the facility's real staff (21 Nov 2026)
- Owner report: Administration › Facilities listed 4 staff for Facility 2, but Our team showed nobody and the Facility 2 Supervisor was told "You are not on the staff of a facility yet". "This is clearly incorrect."
- Cause: Our team (D-64), the users facility filter (D-63), the Facility Administrator's staff list and the Finance payment reminder read `facility_memberships` with the service key, which has no access to that table (0035), so each found no one. Administration › Facilities was right because it reads through `admin_facility_staff`.
- Fix (in M38 `20261121120000`, not yet applied): `visible_facility_memberships()` — signed-in staff see who is on staff of their own facilities (person, facility, role); the Super-Administrator sees every facility; the service key cannot call it. `finance_reminder_facilities()` — server-only, returns only Finance memberships for the reminder. The four app paths now use these.
- Tests: `tests/sql/planned_work_ready.test.sql` (own facility visible, other facility hidden, Super-Administrator sees all, permissions). Increment rebuilt and rehearsed (applies once on 20261120120000, refuses a second run).

## D-73 — Normal ranges for Daily round readings (21 Nov 2026)
- Owner: "For the checklist, it should have a reference temperature for the technician to make an informed decision to tick whether the supply temperature is ok or Not ok."
- Built (in M38, not yet applied): each reading item can carry a lowest and/or highest normal value and a short guide. The Technician sees "Normal: 6 – 8 °C" next to the reading box; a reading outside it turns amber with a warning, and OK can then be ticked only with a reason ("why it is still OK"), checked in the database too. A ranged reading must be a number. Each result keeps the range that applied and an out-of-range flag, so a later change of range does not rewrite history.
- Set up: Daily round › Set up › "Set range" per reading item (Approver, Supervisor, Facility Manager, Facility Administrator, Super-Administrator).
- Facility 2 values (script `preview-f2-reading-ranges-20261121.sql`, after M38) are PROPOSED typical values for UAT, to be confirmed by the facility from the equipment manuals and GMP limits: chilled water supply 6–8 °C, return 11–14 °C; cold rooms 2–8 °C; freezer −20 °C or colder; cleanroom differential at least 10 Pa; purified water conductivity at most 1.3 µS/cm, TOC at most 500 ppb. Compressor current, line pressure and dew point depend on the nameplate or set point, so they get a guide only until the facility enters the figures.
- Tests: `tests/sql/daily_round.test.sql` (range rules, reasons, history kept), `tests/daily-round.test.ts`. Data script rehearsed locally: 15 items set; a second run changes nothing.
- D-73 addendum (21:18): owner asked for acceptable ranges for the compressed air, GMP AHU and purified water checks too. Proposed (to be confirmed by the facility): line pressure 6–7.5 bar; pressure dew point −40 °C or drier (desiccant dryer, ISO 8573-1 Class 2); cleanroom differential 10–15 Pa (EU GMP Annex 1 guidance); conductivity at most 1.3 µS/cm; TOC at most 500 ppb. Tick-only items may now carry a guide on what "OK" looks like (auto-drains, filter gauges, AHU, UV lamp, alarms). Script rehearsed: 22 items set; a second run changes nothing.
- D-73 addendum (21:29): Ollie's Daily round guide and knowledge pack updated for normal ranges, guides and the reason needed to tick OK outside a range (Ollie does not learn by itself; its knowledge is written in, owner asked to confirm).

## D-74 — Ollie stays off the outside world (21 Nov 2026)
- Owner, relaying the facility SVP (20 Nov): connecting Ollie to the outside world risks information leakage; advised against it.
- Recorded: Ollie's AI answers (the only part that sends anything outside FMWorks — to the AI service, D-58 option A) stay switched OFF (`FMW_ASSISTANT_AI` not set). The open decision "switch Ollie's AI on" is closed as No unless the SVP decides otherwise.
- Ollie keeps learning inside FMWorks through M33 (17 Nov): every Help question is kept (role and page only; passwords, codes and card numbers refused); unanswered or unhelpful ones are listed in Administration › Assistant, where the Super-Administrator, a Facility Administrator or a Facility Manager writes the answer; Ollie gives it to everyone from then on.
- Noted for the SVP: FMWorks itself (Preview) is hosted on cloud services (Vercel, Supabase). Whether the live system must be hosted on the facility's own servers is a separate hosting decision for the SVP and IT.

## D-75 — Maintenance plan shows the colleague's name (21 Nov 2026)
- Owner: on the Maintenance plan a Technician saw "Assigned" instead of the name of the Technician responsible.
- Cause: a Technician may not read other people's profiles, and the list of the facility's Technicians is only given to planners.
- Fix (M38, not yet applied): `visible_facility_memberships()` also returns name, trade and work phone (what Our team already shows); the Maintenance plan fills names from it. Test added.
- Owner question (escalation when the assigned Technician cannot do the work) — answered separately; the build is D-67 part 4, awaiting the owner's choices.

## D-76 — Escalation when the assigned Technician cannot do the work (21 Nov 2026) — D-67 part 4
- Owner decisions:
  1. First step: a named backup Technician per maintenance task (like the Daily round's cover); the work moves to the backup automatically, and the Supervisor may choose someone else.
  2. Escalation to the Facility Manager if nobody picks it up: critical equipment within 2 hours, other work after 1 working day — the trial default for Facility 2. These times are a facility setting, decided by the Supervisor or Facility Manager, and are asked of every new facility team at onboarding (D-67 part 5).
  3. Last step: the Super-Administrator.
- Also in scope (proposed, accepted with the plan): an "I can't do this" action with a reason on the Work Order / task; "Needs a Technician" flag on the dashboard; leave recorded ahead moves tasks due during the leave to the backup in advance; critical equipment prompts a contractor call-out when no in-house Technician is free.
- To be built as M39 after M38 has passed release:verify and been applied to Preview, so each release stays reviewable.

## D-77 — Show / hide on every password box (21 Nov 2026)
- Owner agreed Ollie only explains and guides; it never changes settings (D-74 stands). Open question to owner: may the Facility Manager change the planned-maintenance setting for their own facility (today Super-Administrator only)?
- Owner: the temporary password when creating a user had no reveal button; add it wherever a password is entered.
- Done: the temporary password box (Administration › Users › Create or activate a user) now uses the same eye button as sign-in and change-password. Those three are the only password boxes in FMWorks; a test fails if a plain password box is added again.

## D-78 — Shift roster, leave and change requests (21 Nov 2026, 23:49) — extends D-76 / D-67 part 4
- Owner requirements:
  1. The roster shows every duty expected in the facility for each day, one week ahead; staff may be rostered up to 6 months ahead, but weeks beyond the first are hidden from view.
  2. Technicians and Supervisors enter leave in advance; a Technician's leave is approved by the Supervisor or Facility Manager, a Supervisor's by the Facility Manager.
  3. Technicians can view the roster and request a change with a reason, naming the takeover Technician, who must declare he is available; the change is on hold until the Supervisor approves it.
  4. The roster automatically assigns the rostered Technician to the work in his shift: PM daily (Daily round), weekly, monthly checks, ad-hoc and emergency incidents.
  5. Duties are lined up shift by shift so the Supervisor sees who is on and off duty.
  6. 12-hour shifts, 2 duty Technicians per shift, 1 Supervisor per shift; Technician pairs rotate every month so everyone works with everyone.
- Noted by Claude for the owner: 24/7 cover at 2 Technicians + 1 Supervisor per 12-hour shift needs 336 Technician-hours and 168 Supervisor-hours a week — about 56 h a week each with 6 Technicians and 3 Supervisors, before leave. Open questions put to the owner (shift times, head-count, whether the roster replaces the named Technician per task, who sees beyond one week).
- Staffing Recommendation page (/management/staffing, WP-FMW-010, 2026-10): explained to the owner as an advisory head-count estimator; it creates no users.
- Users vs Facility staff: Users lists every account; a facility's Staff lists only people added to that facility whose facility role matches their account role. The Facility Manager and the third Supervisor are not shown on Facility 2 — to be added (or re-added after a role change) under Facilities › Facility 2 › Staff. Proposed for M39: when an account's role changes, its facility role follows.

## D-79 — Roster look-ahead for Technicians; Facility One staff (22 Nov 2026, 00:16) — amends D-78
- Owner: "Please allow Technicians see one month ahead, but each page only show up to one week." Technicians see four weeks ahead, one week per page (Next week / Previous week); Supervisor, Facility Manager, Facility Administrator and Super-Administrator see the full 6 months, also one week per page.
- Owner decisions (23:58): 4 crews; 8 Technicians and 4 Supervisors at Facility 2; remove the Staffing Recommendation page (page, link and API only — its table and data stay); people previously in Facility One go back to Facility One.
- Claude's assumptions told to the owner (not yet confirmed): shifts 07:00–19:00 and 19:00–07:00; 2 days, 2 nights, 4 off; Supervisors stay with their crew, Technician pairs reshuffle monthly; the roster decides who does PM, Daily round and ad-hoc work (backup = the other Technician on shift, then an approved takeover, then escalation per D-76).
- Facility One staff today (owner's screenshot): 2 Technicians, 1 Approver, 1 Finance; no Supervisor or Facility Manager. Read-only report `scripts/rollout/preview-staff-report-20261122.sql` (`out/preview-staff-report.ps1`) lists every account's current and past facilities and Work Orders per facility, to decide who goes back to Facility One. Rehearsed locally.

## D-80 — UAT findings on Preview build 7aa38d1 (22 Nov 2026, 01:08)
Preview still runs 7aa38d1 (before M38), so the Our team fix (D-72) and reading ranges (D-73) are not yet visible there.
1. Facility 2 Facility Manager (fmworks.notices@yahoo.com) sees "not on the staff of a facility": the page bug (fixed in M38) and he is not on Facility 2's staff list (8 staff, no Facility Manager). Owner to add him under Facilities › Facility 2 › Staff.
2. Daily round set-up: the empty "New item / Unit" boxes under each check looked like something to fill in. Now hidden behind "+ Add an item to this check (optional)", with a line saying nothing needs filling in.
3. Reading ranges not shown: needs M38 and the Facility 2 ranges script.
4. Owner: give the Facility Manager access to the On-call Roster. Done (M38): the Facility Manager opens and manages the emergency on-call roster like the Supervisor; Approver stays read-only. Test added.
5. Owner: the assigned Technician saw "No action needed from you right now" on a Work Order awaiting approval and was left clueless. Now the Next action box says "Waiting for <who> to <what>" and, for the assigned Technician, "You are the assigned Technician — nothing to press yet", what button comes next and what to prepare meanwhile.
6. Found while testing (Sunday): the M38 SQL test failed on weekends because the daily run moves weekend due dates; the test now uses the latest weekday.

## M38 rollout (22 Nov 2026)
- `release:verify` PASS 08:16 (third run; the first two ran before the final test file reached the owner's folder).
- Commit 04e0825 (D-70 to D-80), pushed to `uat/claude-review` 08:37 (1cc42fd..04e0825).
- Preview: `out/preview-m38-apply.ps1` 08:21 — hash 21b5a09d…, user cli_login_postgres.pvajuywwwpjlikqjnvgv, backup `.git/preview-backup-20261121-pre-m38.sql` (5,989,192 bytes), preflight at 20261120120000, ledger now ends 20261121120000 (88 entries).
- Facility 2 reading ranges: dry run 08:24 (22 items); `-Apply` run after it (backup `.git/preview-backup-20261121-pre-m38-data.sql` present).

## D-81 — Emergency on-call roster per facility (22 Nov 2026, 08:45)
- Owner: the On-call Roster shows only Yang Ying Zhang, who belongs to Facility One, and no one for Facility 2; "Please provide for all facilities that are operational."
- Found: the emergency on-call roster and emergency incidents were built (0014, Oct 2026) before facilities existed — neither records a facility. An incident's alert goes to the single lowest-order active entry, whichever facility it is in. Adding Facility 2 people to today's roster would make Facility One incidents reach them too (or, with two entries at the same order, nobody would be auto-assigned).
- Decided (Claude's proposal, owner asked for it): first part of M39 — the on-call roster and incidents become per facility: each roster entry and each incident belongs to a facility; reporting an incident asks for the facility (preset for single-facility staff); alerts go to that facility's on-call list; the roster page shows one section per operational facility, offering only that facility's Technicians. Existing entry (Yang Ying Zhang) assigned to Facility One. Facility 2's on-call list then comes from its shift roster (D-78): the 2 Technicians on shift, escalation to the shift Supervisor, then the Facility Manager.
- Until then: no Facility 2 entries are added, for the reason above.

## D-82 — Choose the facility on every page; Facility One live (22 Nov 2026, 09:06)
- Owner (as Super-Administrator): add facility buttons to Work Orders and Notices; show the Super-Administrator unread notices per facility (e.g. from Facility 2); group Assets by facility; Maintenance plan, Operations Workspace, Maintenance, On-call Roster, Contractor Admission (by the facilities a person manages, or by facility name), Procurement Policy, Finance, Contractor rates and Approval limits per facility. Make Facility One live: Work Orders from its asset list, and an active Daily round.
- Found: a facility choice already exists (cookie `fmw_facility`, D-54) but only Work Orders uses it, as a drop-down. The assets on the Asset Registry without an F2- prefix (ACCU-01, AHU-01, CH-01 …) are Facility One's. Facility One has no maintenance tasks, no Daily round checklist, no Supervisor or Facility Manager. Procurement Policy, Contractor rates and Approval limits are company-wide today (no facility in their tables).
- Proposed: one shared row of facility buttons (All facilities · Facility One · Facility 2 …), remembered across pages, on every page that lists facility work; per-facility policy, rates and approval limits as a company default that each facility inherits unless it sets its own. Order and Facility One's planned-maintenance setting put to the owner.
- Seen in passing: Facility 2 now has Technicians 1–8; the Daily round on Preview shows the reading ranges (M38 live).
- Owner answers (09:10): order — M39 facility buttons on every page, notices per facility and on-call per facility (D-81); M40 Facility One live; M41 shift roster, leave and escalation (D-76, D-78, D-79); M42 per-facility procurement policy, contractor rates and approval limits. Facility One's planned maintenance: **Full for critical equipment**. A facility's own procurement policy, contractor rates and approval limits may be changed by the **Super-Administrator and the facility's Facility Manager (the Super-Administrator copied on every change)**, and by the **facility's Facility Administrator when that post is active**.

## M39 built (22 Nov 2026) — facility buttons on every page; on-call and incidents per facility (D-81, D-82)
- App: one row of facility buttons (`components/facility-buttons.tsx`, `lib/facility-scope-server.ts`; remembered in cookie `fmw_facility`) on Work Orders (replaces the drop-down), Notices and All notices (unread count on each facility button), Assets (grouped by facility), Maintenance plan, Maintenance, Operations Workspace (work and team narrow to the facility; the Facility Manager now sees the team), Contractor Admission and Finance. Memberships are read as the signed-in person (visible_facility_memberships).
- Database M39 `20261122120000_facility_on_call.sql`: `emergency_response_roster.facility_id`, `incidents.facility_id`; existing on-call entries take their Technician's facility (Yang Ying Zhang → Facility One); `create_incident` takes the chosen facility (else the asset's, else the reporter's only one) and alerts that facility's on-call entries, its Supervisors and Facility Manager and the Super-Administrator (no longer every Supervisor in the company); the roster is managed per facility (Supervisor / Facility Manager their own, the Super-Administrator all; only that facility's Technicians); the roster lists the facility. Roster page groups entries by facility and flags a facility with no one on call; the incident form asks for the facility.
- Data `preview-on-call-per-facility-20261122.sql`: Facility 2 on call — Technician 1 (order 10), Technician 2 (order 20), until the shift roster (M41).
- Tests: `tests/sql/facility_on_call.test.sql`, `tests/facility-scope.test.ts`; `planned_work_ready.test.sql` now gives the facility for the Facility Manager's roster entry. Rehearsed: increment applies once on 20261121120000 and refuses again; data script adds 2 entries, a second run adds none.
- Deferred: removing the Staffing page moves to M41 (an end-to-end test exercises it and must be rewritten with it).

## Staff report (22 Nov 2026, 22:50) — findings for M40
- M39 rolled out 22:43 (backup `.git/preview-backup-20261122-pre-m39.sql`, ledger ends 20261122120000, 89 entries); Facility 2 on-call dry run 22:45 correct (Technician 1 order 10, Technician 2 order 20; Facility One Yang Ying Zhang order 100).
- Facility 2: 8 Technicians, 4 Supervisors, 1 Facility Manager — the 8 + 4 target is met. Two stale memberships left from earlier roles: Supervisor 1 (sctpec2413+1) and the Facility Manager (fmworks.notices@yahoo.com) are still also "approver" at Facility 2. No account with the Approver role is on Facility 2's staff.
- Facility One: Approver (sctpec2413@gmail.com), Finance (engchian@yahoo.com), Technicians Yang Ying Zhang and Ying Zhang. Nobody now elsewhere was previously at Facility One, so nobody moves back. No Supervisor or Facility Manager.
- Proposed for M40 data: end (not delete) the two stale Facility 2 approver memberships, with reason; Facility One Supervisor and Facility Manager accounts to be created by the owner (fictitious UAT); Facility 2 approvals — owner to decide who approves.
- Owner (22:52): "Make Facility Manager and Supervisor as Approvers" (Facility 2).
  Found: the Facility Manager may already approve by role (approve is allowed for Approver, Facility Manager, Super-Administrator); a Supervisor may not (review, return and close only). The facility's "designated Approver" setting is recorded but not enforced.
  For M40: Supervisors of a facility may approve that facility's Work Orders (never one they raised, as for every approver; within the approval limits, which get a Supervisor line); Facility 2's designated Approver set to the Facility Manager; the two leftover "approver" memberships (Supervisor 1, Facility Manager) ended with reason, since approval follows the account role and the facility membership.

## M40 prepared (22 Nov 2026, 23:55) — data only, no database change
- Correction to the 22:52 note: Supervisors **can already approve** their facility's Work Orders. The current approval path (Lifecycle v2, `work_order_approval_authority`) accepts the Approver, Supervisor, Facility Manager and Super-Administrator of the same facility, never someone approving a Work Order they raised or are assigned to, within the approval limits (seeded: Approver S$250,000, Supervisor S$250,000, Facility Manager S$500,000, Super-Administrator no cap). The 22:52 note read an older, superseded rule. Rehearsed locally: a Supervisor approves a planned-maintenance Work Order. No change needed.
- Owner (23:25–23:43): Facility One Supervisor sctpec2413+0@gmail.com and Facility Manager sctpec2413+f1fm@gmail.com created (facility_king@yahoo.com first used, replaced — it is the app's email sender; to be archived by the owner).
- Data script `preview-m40-facility-one-live-20261122.sql` (`out/preview-m40-data.ps1`): A. ends the leftover Facility 2 approver memberships (Supervisor 1, Facility Manager) and facility_king's Facility One membership, with reasons; Facility 2's designated Approver = its Facility Manager. B. records any asset with no facility as Facility One's (none expected: assets require a facility). C. maintenance tasks for each Facility One asset by type (chiller, cooling tower, pump, AHU, split AC, fan, electrical, transformer, solar, generator, plumbing, lift, fire; else annual), first visits spread over each period; mechanical → Yang Ying Zhang, electrical → Ying Zhang, contractor work unassigned. D. Daily round checklist for the plant that exists (chillers with ranges 6–8 / 11–14 °C, cooling towers ≤32 °C, pumps, AHUs supply air 12–16 °C, split AC, electrical, solar, generator, plant-room walk), every day 07:00–10:00, Yang Ying Zhang, Ying Zhang covers. E. Facility One planned maintenance = Full for critical equipment; today's round created. Rehearsed on a local copy with sample Facility One equipment: 12 assets, 27 tasks, 9 checks, 22 items; a second run changes nothing further.
- M40 applied 23 Nov 2026 00:06 (backup `.git/preview-backup-20261122-pre-m40-data.sql`, 6,077,583 bytes): 3 leftover memberships ended; Facility 2 designated Approver = Facility Manager; Facility One 24 assets, 52 tasks (38 with a Technician), Daily round 11 checks / 26 items, today's round FW-2026-0597; Facility One planned maintenance Full for critical equipment. Noted for the owner: SOCKET-L2-P-04 is marked critical, so it will get Work Orders.

## M41a — Set a temporary password (23 Nov 2026, 00:20–00:45)
- Owner: "Can the Super Admin reset the password for his subordinates?" Then: fmworks.notices@yahoo.com (Facility 2 Facility Manager) cannot sign in and has forgotten the password. "Forgot password" did not arrive; Supabase dashboard "Send password recovery" failed with "email rate limit exceeded" (Supabase's built-in sign-in mail allows only a few emails an hour).
- Built: Users › "Set temporary password" on each person's row (not the Super-Administrator's own, not another administrator's). The Super-Administrator may use it for anyone else; a Facility Administrator only for staff of their own facility. Typed with the show / hide box (at least 12 characters) and a reason; the person must choose a new password at the next sign-in. Migration `20261123120000_admin_password_reset.sql` (`admin_require_password_change`) checks the authority, marks the change required and records who reset whose password and why — never the password, which goes only to the sign-in service. Tests: `tests/sql/admin_password_reset.test.sql`, `tests/admin-password-reset.test.ts`. Claude never enters or sees passwords.
- Noted: Supabase's built-in email for sign-in mail is rate-limited; for reliable reset emails Supabase Auth can be pointed at the app's own SMTP account (owner to decide; entering that password is the owner's step).

## Ollie answers who works at a facility (23 Nov 2026, 08:11)
- M41a committed and pushed (8ef218f).
- Owner (screenshot: Ollie gave unrelated prepared answers to "who are the users in Facility 2?"): "Can you make the change to improve the capability of Ollie?"
- Built (app only, no database change): Ollie recognises questions about people — who / users / staff / team, a role (Technicians, Supervisor, Facility Manager, Approver, Finance, Facility Administrator) and "on call / standby" — and the facility named ("Facility 2", "facility one", a code). It answers from the facility's staff list (`/api/assistant/people`, read as the signed-in person through visible_facility_memberships, so each person sees only their own facilities; the Super-Administrator all) with name, role, trade and work phone, plus who is on call from the on-call roster, and links to Our team. Still no outside connection (D-74). Knowledge pack: people questions and the temporary password. Tests `tests/ollie-people.test.ts`.

## Facility Manager's view of the management pages (23 Nov 2026, 08:29) — findings, M41b proposed
- Owner (signed in as Facility 2 Facility Manager, build 8ef218f): Staffing shows nothing; SLA opens Mission Control; Exports opens the Operations Workspace; Procurement Policy is read-only company-wide; Contractor Admission fine; On-call Roster should reflect 4 Supervisors and 8 Technicians on rotation; Maintenance › PM Requirements should be one line per asset, expanded on demand. Also asked: several users signed in at once.
- Found: the Facility Manager role was added after these pages; the header shows him their links, but the pages (Management SLA, Exports, Staffing) and parts of the database (SLA, reporting, incident and asset read rules — 10 functions and 20 read rules list Approver, Supervisor and Administrator only) still leave him out, so he is sent elsewhere.
- Proposed M41b: the Facility Manager gets the same management views as the Supervisor (SLA, Exports, reports, incidents, assets, planned maintenance); the Staffing link is hidden (page removed with M41 as decided); Maintenance › PM Requirements becomes one line per asset with its tasks folded underneath. On-call from the shift roster stays in M41; per-facility procurement policy in M42 (D-82).
- M41a applied to Preview 23 Nov 2026 07:58 (backup `.git/preview-backup-20261123-pre-m41a-0758.sql`); re-run at 08:50 correctly refused ("ledger ends at 20261123120000"), ledger 90 entries.

## M41b built (23 Nov 2026, 09:10) — before the handover to the facility contact
- Migration `20261123130000_facility_manager_management_views.sql`: 18 read rules (SLA, reports, incidents, assets, planned maintenance, AI prompts, service categories, escalation steps, technicians for assigners) and 9 functions (SLA documents, report schedules, incident operations and evidence, linking Work Orders to incidents, AI operations, Work Order asset) restated with the Facility Manager added — nothing else changed; the migration stops unless exactly those change. Staffing rules unchanged (page retiring). Test `tests/sql/facility_manager_views.test.sql`.
- App: the Facility Manager may open Management SLA, Exports, Reports and the management parts of Site SLA, Mission Control and Operations; Staffing link hidden; Assets one line per asset (tag, name, criticality, status), opened on click; Notices explains what the reader's role receives ("Payment matters go to Finance, not here"; "Nothing here means nothing is waiting for you"). Includes the Ollie people answers (not yet released). Deferred to M41: Maintenance › PM Requirements one line per asset.

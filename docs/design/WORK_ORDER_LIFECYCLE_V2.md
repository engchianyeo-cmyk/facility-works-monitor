# Work Order Lifecycle v2 — Design Specification

Status: **APPROVED by owner, 20 October 2026 13:41 SGT**
Author: Claude, 20 October 2026 (SGT)
Branch: `uat/claude-review` (base `ea584e4`)
Source decisions: `docs/audit/OWNER_DECISION_LEDGER.md` D-01 to D-04

No code or database change is made until the owner signs this off. Every database
change is a **new** migration; applied migrations are never edited.

---

## 1. What changes, in one paragraph

Today a Work Order is raised by a requester, approved on a written "approval basis",
then assigned to a Technician, who only *then* prepares contractor quotations for a
second, separate financial approval. After the work there are up to four more
approvals (completion verification, final-cost variance, payment proposal, payment
approval) before Finance records payment. The owner's model is simpler: **the
Technician raises the Work Order with the quotation; one approval lets the contractor
proceed; one review approves work + cost + documents and makes it "Completed"; Finance
then pays and the Work Order closes.** Emergency work skips the up-front quotation
only.

## 2. Target stages

Database status values are kept, so existing records, reports and audit history stay
valid. Only the labels and the rules between stages change.

| # | Status (database) | Label shown | Who acts | Gate to move on |
|---|---|---|---|---|
| 1 | `draft` | Draft | Assigned Technician (creator) | Title, location, asset/area, reason for work, photos/video/voice as available; **quotation** (not for emergency) |
| 2 | `submitted` | Awaiting Approval | Approval authority (§4) | Quotation count meets policy (1 or 3); rates checked against contract (§5); amount within approver's limit |
| 3 | `approved` / `assigned` | Approved — Contractor to Proceed | Technician (field witness) | Technician is already the assignee; approval authority may reassign |
| 4 | `in_progress` | Work in Progress | Technician | Variation → revised quotation → back to approval for the **difference** (§3.3) |
| 5 | `completed` | **Submitted for Review** | Approval authority | Work notes, labour, After evidence, final cost and supporting documents; for emergency, the after-the-fact quotation |
| 6 | `reviewed` | **Completed** | Technician uploads invoice; Finance | Reviewer approved work + cost + documents within their limit. Contractor then issues invoice; amount must equal the approved (revised) quotation |
| 7 | `closed` | Closed | — | Finance recorded payment in full, or an approved no-payment disposition |
| — | `cancelled` | Cancelled | Approval authority | Before Completed, with reason |

Reject paths: at stage 2 the approver **returns** the Work Order to Draft with a
reason; at stage 5 the reviewer **rejects & reopens** it to Work in Progress with a
reason (existing rework mechanism).

## 3. Rules by step

### 3.1 Creating a Work Order
- **Technicians normally create** Work Orders (Q2). Today Technicians are blocked in
  UI, API and database; v2 reverses this. A Technician creator becomes the assigned
  Technician automatically.
- **When the Technician is unavailable, a superior may create the Work Order**
  (Approver, Supervisor, Facility Manager, Administrator). The superior may attach the
  evidence and quotation and **assigns a Technician** as field witness. Independence
  still applies: the superior who created it cannot also approve it (another approval
  authority must; Administrator self-approval only with an audited reason, as today).
- Initiator, Reviewer and Finance cannot create Work Orders.
- **System-generated** Work Orders (Preventive Maintenance schedules, Incident corrective
  work) are still created by the system. They start in Draft, are assigned to a
  Technician, and that Technician adds the quotation before submission.
- When creating, the Technician chooses the **copied parties** (Approver, Supervisor,
  Facility Manager, Administrator, others as needed). They are notified at each stage
  and on invoice upload.
- Evidence types already supported: photos, video (mp4/webm), voice (mp3/m4a/ogg/wav/webm), PDF.

### 3.2 Approval to proceed (stage 2 → 3)
- One approval covers the work **and** the quotation. The separate "approval basis"
  and later "financial approval" become a single step.
- Quotation count follows the company threshold (initially S$1,000: one quotation
  below, three distinct eligible contractors at or above) — existing logic, moved to
  before approval.
- The approver's monetary limit applies to the selected quotation amount.

### 3.3 Variation (revised quotation)
- During work the Technician submits a revised quotation (existing revision mechanism).
- It returns for approval; the **revised total** must be within the approver's limit.
- Work may continue only on the approved scope until the revision is approved.

### 3.4 Review to "Completed" (stage 5 → 6)
- One review approves: the work done, the final cost, and the substantiating documents.
- Replaces today's separate *completion verification*, *final-cost variance approval*,
  *payment proposal* and *payment approval*.
- The reviewer's monetary limit applies to the final cost.
- Independence: the reviewer cannot be the Work Order's creator or assigned Technician.
  Administrator self-review stays possible only with a mandatory, audited reason.

### 3.5 Invoice, Finance and closure (stage 6 → 7)
- The contractor issues its invoice **after** final approval ("Completed") and gives it
  to the Technician, who **uploads it** to the Work Order (Q3).
- The invoice amount **must equal** the approved final cost (the approved, revised
  quotation). A mismatch is rejected with a clear message; the Technician must obtain a
  corrected invoice.
- Upload notifies **Finance** and copies the Technician and every party copied on the
  Work Order (Approver, Supervisor/Facility Manager, Administrator, others).
- Finance marks the invoice **received**. The **payment due date = invoice received
  date + the contractor's payment terms** — not the completion date. (Replaces the
  earlier fixed 30-day-from-completion rule, B-09.)
- New **Finance** role records payment (amount, date, reference). Finance cannot
  approve work, cost or quotations.
- The Work Order closes automatically when payment is recorded in full, or when a
  no-payment disposition is approved (warranty, in-house, goodwill, zero cost).
- Finance payment tracker: awaiting invoice, invoice received (due date), overdue,
  paid.
- Notifications are in-app now; email/SMS delivery depends on the separate email
  decision (R1-012).

### 3.6 Emergency path
- Technician creates the Work Order with **Emergency** ticked and a reason.
- No quotation is needed to submit. See Q1 for whether a go-ahead is needed before work.
- After the work, the Technician enters the quotation from the contractor. Lines use
  the contractor's **emergency rate** where one exists, otherwise the normal rate
  (existing rate-contract logic, 0041).
- No deadline. The Work Order cannot reach "Completed" until the quotation is in and
  checked. Outstanding emergency quotations are listed on the dashboard.
- Review to "Completed" is the same as §3.4.

### 3.7 In-house work (D-07)
- The preparer ticks **Services provided in-house** (at creation or while Draft).
- Submission needs the reason and an assigned Technician, but **no quotation**.
- Approval uses the same authority rule at S$0; no quotation is approved.
- Execution and evidence are unchanged. The review approves the work and documents; no final
  cost is required. The Work Order then closes automatically with an audited "in-house — no
  payment" record. Emergency in-house work starts immediately and needs no quotation afterwards.

### 3.8 Site location, Before evidence and final quotation (D-08)
- The creator chooses the area/room; an area already placed on a layout plan is highlighted
  automatically. Otherwise the spot is marked on the plan.
- Submission needs the location on a layout plan and at least one **Before** photo, video, voice
  note or PDF. Emergency work is exempt at submission; both are required before the review.
- Before (then After) photos are shown inline. The final quotation carries the supervising
  Technician's site-verification declaration.
- The preparer marks the layout while Draft/Awaiting Approval (choosing the plan when the facility
  area has none configured); the assigned field owner may also mark it during the work and before
  the review.
- Variation is approved at the review (supersedes §3.3 re-approval during work): when the final
  cost differs from the approved (or emergency) quotation, the contractor's final quotation for
  the work actually performed must be attached before the review.
- Work duration and overall duration are shown on the Work Order.

## 4. Who can do what (single authority rule)

**Approval authority** = role is Approver, Supervisor, Facility Manager or
Administrator, **and** (Administrator, or active membership of the Work Order's
facility), **and** the amount is within that role's limit, **and** the person did not
create and is not assigned to the Work Order.

| Action | Technician | Approver | Supervisor | Facility Mgr | Admin | Finance | Reviewer / Initiator |
|---|---|---|---|---|---|---|---|
| Create Work Order | **Yes** (becomes assignee) | Yes, if Technician unavailable | Yes, if Technician unavailable | Yes, if Technician unavailable | Yes, if Technician unavailable | No | No |
| Add evidence / quotation / variation / invoice | Assigned only | When they created it | When they created it | When they created it | When they created it | No | No |
| Mark invoice received | No | No | No | No | No | **Yes** | No |
| Approve to proceed | No | ≤ limit | ≤ limit | ≤ limit | Any | No | No |
| Assign / reassign Technician | No | Yes | Yes | Yes | Yes | No | No |
| Record work done, submit for review | Assigned only | No | No | No | Exception w/ reason | No | No |
| Review → Completed | No | ≤ limit | ≤ limit | ≤ limit | Any | No | No |
| Reject & reopen | No | Yes | Yes | Yes | Yes | No | No |
| Cancel | No | Yes | Yes | Yes | Yes | No | No |
| Record payment | No | No | No | No | No | **Yes** | No |
| Change approval limits / quotation threshold | No | No | No | No | **Yes** | No | No |
| Rename roles and stage labels | No | No | No | No | **Yes** | No | No |
| View | Own facility | Own facility | Own facility | Own facility | All | All (financial view) | Own requests |

Default limits (Administrator-adjustable, audited, versioned like the quotation
policy): Approver S$250,000; Supervisor S$250,000; Facility Manager S$500,000;
Administrator unlimited. Above S$1,000,000 the existing board-approval reference
remains required.

## 5. Contract rate check
Existing (0041): each quotation line must reference an effective rate item for that
contractor; a different rate needs a written **rate exception** reason. v2 shows the
line-by-line comparison to the approver/reviewer and highlights exceptions. Items not
on the rate schedule are rate exceptions. See Q4.

## 6. Settings (Administrator only)
- **Approval limits** per role — new versioned table; each Work Order pins the version
  in force when approved (same pattern as procurement policy).
- **Quotation threshold** — existing policy; change permission narrowed from
  Facility Manager + Administrator to **Administrator only** (D-03.4).
- **Terminology** — role names and stage labels editable per company; the stored role
  codes never change, only what users see.

## 7. Database and code changes (planned)

| Area | Today | v2 change |
|---|---|---|
| `create_work_order`, `canCreate`, create page | Technician denied; all other roles allowed | Technician, or a superior when the Technician is unavailable; Technician auto-assigned or assigned by the superior; copied parties chosen |
| Invoice | Part of payment proposal | Technician uploads after Completed; amount = approved final cost; Finance marks received; due date from contractor terms |
| Quotation RPCs (`prepare/save/submit_work_order_proposal`) | Only after `assigned` | Allowed in `draft` by the creating Technician |
| `transition_work_order` approve, `set_work_order_approval_basis`, `approve_work_order_financial`, `approve_work_order_proposal` | Three separate approvals with different role lists | One approval RPC using the single authority rule and limits table |
| `verify_completed_work`, `approve_work_order_final_cost_variance`, `submit/approve_work_order_payment` | Four approvals, role lists differ (Approver excluded from verification; Supervisor excluded from variance) | One review RPC → `reviewed` ("Completed"); creates the approved payable |
| `record_work_order_finance_payment` | Administrator only | Finance role; auto-close on full payment |
| `assign_work_order` | Approver/Supervisor/Admin (FM excluded) | Single authority rule (adds FM) |
| `change_procurement_policy` | FM + Admin | Admin only |
| Roles | 7 roles; memberships for Technician/Supervisor/FM only | Add `finance`; allow Approver memberships |
| Monetary limits | Hard-coded 250k/500k in 0037 | Limits table, Admin-editable |
| Labels | Fixed in `lib/product-terminology.ts` | Terminology table with fallback to current labels |
| `lib/permissions.ts` + `tests/permissions.test.ts` | Unused, superseded rules | Remove after sign-off; replace with tests of the live rules |
| `tests/e2e/pilot-authentication-rbac.spec.ts` | Asserts Technician **cannot** create | Assert Technician can create; Finance cannot approve |

Old RPCs are not deleted in the first migration; they are wrapped to call the new
logic or revoked, so a partial rollout cannot leave two rule sets live.

## 8. Existing data
- Status values unchanged; existing Work Orders keep their history. In-flight Work
  Orders continue under the new rules from their current stage.
- Payments already "approved for payment" stay valid; Finance records them as before.
- Existing **Approver** accounts must be given facility memberships before UAT or
  they will see no Work Orders. A list will be produced from Preview (read-only).
- WO-TEST-012 (S$650 quotation / S$620 actual / S$620 paid) must still reconcile.

## 9. Testing
- SQL tests for every row of the §4 table, positive and negative, including
  cross-facility, over-limit, self-approval and Finance-cannot-approve.
- End-to-end browser journeys: normal (Technician create → approve → work → review →
  Finance pay → closed); variation; emergency; reject & reopen.
- Full `release:verify` must pass before any Preview step.

## 10. Out of scope for this change
Email/SMS delivery, the untracked `0011` migration, Vercel access (separate decisions),
offline mobile use, accounting/ERP integration.

## 11. Open questions for the owner

| # | Question | Answer (20 Oct) |
|---|---|---|
| Q1 | Emergency: start immediately or go-ahead first? | **Start immediately**; approvers notified and see it on the dashboard |
| Q2 | Can other roles log Work Orders? | **Technicians normally; a superior (Approver, Supervisor, FM, Administrator) may create when the Technician is unavailable.** Initiator/Reviewer/Finance cannot. |
| Q3 | Invoice timing | **After "Completed"**; contractor → Technician uploads; amount must equal approved revised quotation; payment terms run from Finance's receipt of the invoice; Finance and all copied parties notified |
| Q4 | Rate differences | No preference given → **allow with written reason, flagged** (default) |
| Q5 | Finance scope | Not asked → **company-wide** (default) |

## 12. Sign-off

| Role | Name | Decision | Date |
|---|---|---|---|
| Owner | engchianyeo-cmyk | Approved (in chat, incl. system-generated PM/Incident Work Orders assigned to a Technician) | 2026-10-20 13:41 SGT |

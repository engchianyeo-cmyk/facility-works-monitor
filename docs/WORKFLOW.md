# FMWorks Workflow Specification

## Work-order lifecycle (Lifecycle v2, approved 20 October 2026)

Authoritative design: [design/WORK_ORDER_LIFECYCLE_V2.md](design/WORK_ORDER_LIFECYCLE_V2.md). Owner decisions: [audit/OWNER_DECISION_LEDGER.md](audit/OWNER_DECISION_LEDGER.md) D-01 to D-06.

| Status code | Shown as (default; Administrator may rename) |
|---|---|
| `draft` | Draft |
| `submitted` | Awaiting Approval |
| `assigned` | Approved — Contractor to Proceed |
| `in_progress` | Work in Progress |
| `completed` | Submitted for Review |
| `reviewed` | **Completed** |
| `closed` | Closed |
| `cancelled` | Cancelled |

| Action | From | To | Authority |
|---|---|---|---|
| Create | — | Draft | Technician (becomes assignee); a superior (Approver, Supervisor, Facility Manager, Administrator) when the Technician is unavailable, who assigns a Technician |
| Prepare quotation, evidence, copied parties | Draft | Draft | The preparer: assigned Technician, or the creating superior |
| Submit | Draft | Awaiting Approval | Preparer; requires the reason for the work, an assigned Technician and a recommended quotation meeting the company quotation count |
| Submit (emergency) | Draft | Work in Progress | Preparer; no quotation before work; approvers notified |
| Submit / approve (in-house, D-07) | Draft → Awaiting Approval → Approved | — | Declared in-house services: no quotation; approved at S$0 by any approval authority (independence applies) |
| Submit (D-08) | Draft | Awaiting Approval | Also needs the location marked on the layout plan and a Before photo/video/voice note (emergency: both before review); a pre-placed area is highlighted automatically |
| Review (variation, D-08) | Submitted for Review | Completed | Final cost differs from the approved quotation → contractor's final quotation attached; reviewer approves it with the work |
| Review (in-house) | Submitted for Review | Closed | No final cost, invoice or payment; an audited in-house no-payment disposition is recorded and the Work Order closes |
| Approve work and quotation | Awaiting Approval | Approved — Contractor to Proceed | Approval authority within its monetary limit; not the requester or assigned Technician (Administrator with audited reason) |
| Return to Draft | Awaiting Approval | Draft | Approval authority, with reason |
| Start | Approved | Work in Progress | Assigned field owner |
| Variation | Work in Progress | Work in Progress | Technician resubmits a revised quotation; approval authority re-approves within limit |
| Submit for review | Work in Progress | Submitted for Review | Assigned field owner |
| Approve as Completed | Submitted for Review | Completed | Approval authority within its limit on the **final cost**; independent of the requester, assigned Technician and completion submitter |
| Reject & reopen | Submitted for Review | Work in Progress | Approval authority, with reason |
| Upload invoice | Completed | Completed | Assigned Technician; amount must equal the approved final cost |
| Confirm invoice received | Completed | Completed | Finance; payment due date = received date + contractor payment terms |
| Record payment | Completed | Closed | Finance; closes automatically when paid in full |
| Approve no payment required | Completed | Closed | Approval authority (not the proposer) |
| Cancel | Before Completed | Cancelled | Approval authority, with reason |

**Approval authority** = Approver, Supervisor, Facility Manager or Administrator, with active membership of the Work Order's facility (Administrator: all facilities), within the role's monetary limit. Default limits: Approver S$250,000, Supervisor S$250,000, Facility Manager S$500,000, Administrator unlimited; only the Administrator changes them, with history kept. Above S$1,000,000 a board approval reference is required.

Physical completion requires work-performed notes, cumulative non-negative labour hours, confirmed execution costing, and active After evidence—not a final invoice. The review to Completed additionally requires the final cost and, for emergency work, the after-the-fact quotation, which must tally with the contractor's agreed rates (differences need a written reason). Closure additionally requires recorded reconciled payment or independently approved no payment required. Terminal rows are immutable except through the reasoned administrative correction RPC.

## Emergency incident lifecycle

`reported → acknowledged → mobilising → on_site → rescue_in_progress → safe → recovery → closed`

Emergency response is not a work-order status variant. Corrective work orders are linked only when repair or recovery work is required. See [EMERGENCY_RESPONSE.md](EMERGENCY_RESPONSE.md).

## Failure behavior

- Invalid transitions return structured codes and leave state unchanged.
- Audit insertion failure rolls back the mutation.
- Notification failure never rolls back a valid assignment or incident report.
- Inactive or missing identities, references, and assignees fail safely.
- UI visibility supplements, but never replaces, database authorization.

See [API.md](API.md), [SECURITY.md](SECURITY.md), and the role guides.

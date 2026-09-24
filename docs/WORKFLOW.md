# FMWorks Workflow Specification

## Work-order lifecycle

`draft → submitted → approved → assigned → in_progress → completed → reviewed → closed`

`cancelled` is terminal and may be reached before closure by an authorized role. Acceptance is an audited action that sets `accepted_at` while status remains `assigned`.

| Action | From | To | Default authority |
|---|---|---|---|
| Submit | Draft | Submitted | Requester or Administrator |
| Approve | Submitted | Approved | Approver; no self-approval |
| Assign | Approved/Assigned | Assigned | Approver, Supervisor, Administrator |
| Accept | Assigned | Assigned | Assigned Technician or Administrator |
| Start | Accepted assignment | In progress | Assigned Technician or Administrator |
| Complete | In progress | Completed | Assigned Technician |
| Review | Completed | Reviewed | Approver, Supervisor, Facility Manager, or Administrator; independent verification required |
| Close | Reviewed | Closed | Approver, Supervisor, Facility Manager, or Administrator; resolved financial disposition required |
| Cancel | Nonterminal | Cancelled | Approver, Supervisor, Administrator |

Administrator operational override requires an auditable reason where explicitly supported; financial self-approval remains prohibited. Duplicate assignment is a successful `NO_CHANGE`, not a misleading mutation. Physical completion requires work-performed notes, cumulative non-negative labour hours, confirmed execution costing, and active After evidence—not a final invoice. Verification is independent. Document-only correction does not rewrite verified physical-completion history. Closure additionally requires recorded reconciled payment or independently approved no payment required. Terminal rows are immutable except through the reasoned administrative correction RPC.

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

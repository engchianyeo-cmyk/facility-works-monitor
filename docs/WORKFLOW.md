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
| Complete | In progress | Completed | Assigned Technician or Administrator |
| Review | Completed | Reviewed | Approver or Administrator |
| Close | Reviewed | Closed | Approver or Administrator |
| Cancel | Nonterminal | Cancelled | Approver, Supervisor, Administrator |

Administrator self-approval requires an auditable override reason. Duplicate assignment is a successful `NO_CHANGE`, not a misleading mutation. Completion requires notes and non-negative labour hours. Terminal rows are immutable except through the reasoned administrative correction RPC.

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

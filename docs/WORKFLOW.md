# Core Work Order Workflow (0013)

The canonical lifecycle is:

`draft → submitted → approved → assigned → in_progress → completed → reviewed → closed`

`cancelled` is terminal and may be reached from any state before `closed` by an
authorized Approver, Supervisor, or Administrator. Assignment acceptance is an
audited `accepted_at` event while the status remains `assigned`.

Authorization is enforced in PostgreSQL. Reviewers and Initiators request and
submit work; Approvers approve, review, and close; Approvers, Supervisors, and
Administrators assign; the assigned Technician or an Administrator accepts,
starts, and completes. An Approver cannot approve their own request.
Administrator self-approval requires a reason recorded as an override audit.

Assigning an order to its current primary assignee is a successful `NO_CHANGE`
result. It does not update timestamps or write a misleading mutation audit.

Completion requires notes and non-negative actual labour hours. Closed and
cancelled rows are immutable except through the reasoned, audited
`admin_correct_work_order` RPC.

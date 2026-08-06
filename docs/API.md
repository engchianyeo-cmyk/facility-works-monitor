# Core Work Order API (0013)

All mutation endpoints authenticate the request and invoke transaction-safe
PostgreSQL RPCs. Responses use `{ ok, code, message, data }`; raw database and
transport errors are not exposed.

`/work-orders` is the authenticated application. `/works` remains the
established public, read-only compatibility list and reads only a deliberately
limited projection through `list_public_work_orders()`. The public projection
excludes drafts, notes, contact details, assignments, audit history, predictive
metadata, and every mutation capability. Direct anonymous access to the
`work_orders` table remains denied.

- `GET /api/work-orders` — search, filter, sort, and paginate permitted orders.
- `POST /api/work-orders` — create a draft or submitted order.
- `GET /api/work-orders/[id]` — order detail and audit history.
- `PATCH /api/work-orders/[id]` — edit permitted nonterminal fields.
- `DELETE /api/work-orders/[id]` — audited cancellation; never an operational hard delete.
- `POST /api/work-orders/[id]/transition` — perform a workflow action.
- `POST /api/work-orders/[id]/assign` — assign one technician, vendor, or team.
- `POST /api/work-orders/[id]/duplicate` — create a new draft with provenance.

The legacy `/status` and `/assignment` endpoints are compatibility adapters to
the same RPC-backed transition and assignment implementations.

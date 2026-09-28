# FMWorks API Specification

## Contract

Authenticated mutation routes return JSON shaped as `{ ok, code?, message?, data? }`. Validation and domain failures use stable codes; raw Supabase errors, SQL details, stack traces, and secrets are never returned.

## Authentication and administration

- Auth completion and callback routes establish sessions and validate active profiles.
- `/api/admin/users` and `/api/admin/users/direct` provide Administrator-only provisioning paths.
- `/api/admin/users/[id]` manages supported profile state.
- `/api/admin/departments` and `/api/admin/departments/[id]` manage department references under existing permissions.
- `/api/health` returns safe build identity only.

Administrative Auth operations use the server-only client described in [SECURITY.md](SECURITY.md).

## Work orders

| Method and route | Purpose |
|---|---|
| `GET /api/work-orders` | Search, filter, sort, and paginate permitted records |
| `POST /api/work-orders` | Create a Draft or Submitted record |
| `GET /api/work-orders/[id]` | Return permitted detail and audit data |
| `PATCH /api/work-orders/[id]` | Edit permitted nonterminal fields |
| `DELETE /api/work-orders/[id]` | Audited cancellation, not hard deletion |
| `POST /api/work-orders/[id]/transition` | Execute a canonical lifecycle action |
| `POST /api/work-orders/[id]/assign` | Assign one Technician, vendor, or team |
| `POST /api/work-orders/[id]/duplicate` | Produce a new Draft with provenance |

Legacy `/status` and `/assignment` routes are compatibility adapters to the same RPC-backed operations. They must not diverge into a second workflow implementation.

## Incidents

- `GET /api/incidents` lists incidents visible to the current identity.
- `POST /api/incidents` reports an incident, resolves an unambiguous responder, and attempts non-blocking channel notifications.
- `POST /api/incidents/[id]/transition` invokes the authorized incident transition RPC.

Incident APIs become operational only after the separately reviewed incident migration is applied to the target environment.

## Error taxonomy

Common codes include `AUTHENTICATION_REQUIRED`, `ACCESS_DENIED`, `VALIDATION_ERROR`, `NOT_FOUND`, `INVALID_TRANSITION`, `INVALID_ASSIGNMENT`, `INACTIVE_REFERENCE`, `SELF_APPROVAL_DENIED`, `TERMINAL_IMMUTABLE`, and `INTERNAL_ERROR`.

## Versioning and compatibility

The current API is application-internal and evolves with FMWorks releases. Breaking external integrations require an explicit versioning policy before launch. See [ARCHITECTURE.md](ARCHITECTURE.md), [WORKFLOW.md](WORKFLOW.md), and [TEST_PLAN.md](TEST_PLAN.md).

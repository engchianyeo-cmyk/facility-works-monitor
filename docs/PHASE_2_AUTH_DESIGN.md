# Authentication and Authorization Decision Record

## Status

Implemented baseline. This document preserves the decision history; current operational requirements are authoritative in [SECURITY.md](SECURITY.md).

## Decision

FMWorks moved from an anonymous demonstration model to an authenticated application with Supabase Auth, one matching profile per Auth user, six canonical roles, RLS, and RPC-enforced workflow authority.

## Canonical roles

`reviewer`, `initiator`, `approver`, `technician`, `supervisor`, `administrator`

Self-registration, where enabled, receives the least-privileged supported role. Elevated roles are assigned through controlled Administrator provisioning. “Requester” remains a business description for an Initiator.

## Identity reconciliation

Authenticated experience is allowed only when the Auth user has a matching active, non-deleted profile with a canonical role. Display-name fallback is profile name, Auth metadata name, email local part, then `Unknown user`.

## Defense in depth

1. Middleware refreshes/guards sessions.
2. Server identity helper validates Auth and profile state.
3. Routes validate request shape and broad role capability.
4. PostgreSQL RPCs enforce record-specific authority and transitions.
5. RLS limits reads and direct operations.
6. Activity logs provide evidence of protected actions.

## Historical decisions retained

- UI-only authorization is insufficient.
- Human-readable references never replace UUID primary keys.
- Legacy actor text may remain for historical readability.
- Drawing document numbers are independent of work-order numbers.
- Rollout must be rehearsed in a non-production environment before production.

## Superseded assumptions

Earlier notes described authentication and administration as future work and anonymous writes as the current model. Those assumptions are obsolete and must not guide implementation.

See [PRD.md](PRD.md), [DATA_MODEL.md](DATA_MODEL.md), [ADMIN_GUIDE.md](ADMIN_GUIDE.md), and the role guides.

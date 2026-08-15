# FMWorks Security Specification

> The customer, identity, export and notification trust boundaries for the pilot are binding in [PILOT_BOUNDARY.md](./PILOT_BOUNDARY.md), with environment-dependent checks in [PILOT_UAT.md](./PILOT_UAT.md).

## Security model

FMWorks uses Supabase Auth, active profile validation, canonical roles, RLS, server-side route checks, and transaction-safe RPC authorization. No single layer is treated as sufficient on its own.

## Secrets and environment variables

| Variable | Exposure | Use |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Browser-safe | Supabase project endpoint |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Browser-safe | RLS-governed public client key |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only | Administrator Auth operations |
| `NEXT_PUBLIC_APP_URL` | Browser-safe | Stable application/callback origin |

`SUPABASE_SERVICE_ROLE_KEY` must never use a `NEXT_PUBLIC_` prefix, enter client components, appear in responses/logs, or be embedded in notification URLs. The admin client imports `server-only` and returns a safe configuration failure when required variables are missing.

## Identity requirements

- `profiles.id = auth.users.id`.
- Profiles must exist, be active, not deleted, and contain a supported role.
- Missing, inactive, or invalid profiles produce controlled identity failure.
- No invalid identity defaults to a more permissive role.

## Authorization principles

- Reviewers/Initiators access requester-scoped data.
- Technicians access assigned work and authorized team incidents only.
- Approvers authorize and review but cannot self-approve.
- Supervisors coordinate operational assignments and rosters.
- Administrators manage identities/configuration and perform audited overrides.
- Direct DML is revoked where it could bypass workflow or audit rules.

## Data protection

- RLS is enabled on operational and configuration tables.
- Normal deletion is soft cancellation/deactivation.
- Permanent Auth deletion is exceptional: the database records a pending request, the server attempts the external Auth action, and a service-only reconciliation RPC records success or failure afterward. Restrictive historical references may require archive instead.
- Notification records contain safe codes, never raw provider errors or credentials.
- Evidence storage is private and requires protected server endpoints and short-lived access.
- Stable links contain record identifiers, never authentication tokens.

## Audit requirements

Every material transition, assignment, correction, provisioning action, and notification outcome must be attributable and timestamped. A failed audit write must roll back the protected mutation.

## Operational checklist

1. Verify Preview/Production build identity before UAT.
2. Confirm RLS and grants in a non-production database.
3. Confirm service-role code is server-only by static test.
4. Rotate compromised credentials immediately and inspect history/logs.
5. Restrict Supabase redirect URLs to approved origins.
6. Test each role against UI, API, RPC, and direct-DML denial.
7. Back up and rehearse rollback before applying migrations.

See [PHASE_2_AUTH_DESIGN.md](PHASE_2_AUTH_DESIGN.md), [ADMIN_GUIDE.md](ADMIN_GUIDE.md), and [TEST_PLAN.md](TEST_PLAN.md).

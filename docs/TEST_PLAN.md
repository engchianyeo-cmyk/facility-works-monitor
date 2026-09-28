# FMWorks Test Strategy

## Objectives

Testing demonstrates workflow correctness, authorization boundaries, data integrity, safe failure behavior, and regression protection. Production data and users are never used for automated tests.

## Test layers

| Layer | Scope |
|---|---|
| Unit | Validation, permissions, transitions, SLA calculations, provider behavior |
| Route | Authentication, safe errors, RPC mapping, response contracts |
| SQL | Constraints, grants, RLS, RPC authority, atomic audit behavior |
| Build | TypeScript, lint, production compilation, diff hygiene |
| Browser | Authenticated journeys against an isolated test Supabase target only |
| UAT | Role-based Preview verification with build identity confirmed |

## Mandatory local validation

```text
npm run typecheck
npm run lint
npm test
npm run build
git diff --check
```

## Core work-order scenarios

- Every valid and invalid lifecycle transition.
- Self-approval denial and documented Administrator override.
- Assignment to active Technician/vendor/team; inactive reference rejection.
- Assigned Technician acceptance/start/completion and cross-Technician denial.
- Completion notes/labour validation, terminal immutability, duplication provenance.
- Search, filtering, pagination, priority ordering, dashboard reconciliation.
- Audit rollback when audit insertion fails.

## Identity and administration scenarios

- Missing admin configuration and server-only protection.
- Unauthenticated/non-Administrator admin API denial.
- Valid provisioning with `profiles.id = auth.users.id`.
- Duplicate email, malformed fields, invalid role/department, inactive/missing profile.
- Successful login for every canonical active role and Administrator regression.

## Emergency scenarios

- Classification and five-minute SLA.
- Unique responder resolution and unassigned emergency behavior.
- Administrator/Supervisor/assigned responder recipients.
- Independent SMS/WhatsApp `NOT_CONFIGURED` outcomes without incident loss.
- Assigned responder and team-member acknowledgement; unauthorized denial.
- Full incident transition matrix, audit timeline, and normal work-order regression.

## Release gate

All mandatory commands must pass. SQL migrations require disposable-database tests before application. Playwright is skipped—not redirected to production—when isolated credentials are unavailable. UAT must confirm `/api/health` and footer build identity before recording results.

See [SECURITY.md](SECURITY.md), [WORKFLOW.md](WORKFLOW.md), and [EMERGENCY_RESPONSE.md](EMERGENCY_RESPONSE.md).

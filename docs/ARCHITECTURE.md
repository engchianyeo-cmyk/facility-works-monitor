# FMWorks Architecture

> WP-PILOT-001 architecture boundary: [PILOT_BOUNDARY.md](./PILOT_BOUNDARY.md). Auth and PostgreSQL reconciliation deliberately uses inactive/password-pending intermediate states because they cannot share one transaction.

## Architectural principles

FMWorks uses an authenticated, database-first architecture. PostgreSQL RPCs own critical mutations and audit insertion; Next.js routes validate requests and translate safe results; React pages render only data permitted by Supabase Row Level Security (RLS).

## Runtime stack

| Layer | Technology | Responsibility |
|---|---|---|
| Web | Next.js 15 App Router, React 19 | Server-rendered pages, forms, route handlers |
| Styling | Tailwind CSS 4 | Responsive application UI |
| Identity/data | Supabase Auth and PostgreSQL | Authentication, relational state, RLS, RPCs |
| Hosting | Vercel | Preview and Production deployments |
| Testing | Vitest, Playwright where isolated credentials exist | Unit, route, workflow, and browser validation |

## Request path

`Authenticated UI → route handler/server component → current identity → validation/authorization → Supabase RPC or RLS query → audit/result → safe UI response`

The browser uses the public Supabase URL and anon key. Administrative Auth operations use a server-only service-role client. See [SECURITY.md](SECURITY.md).

## Bounded modules

- **Identity and administration:** profiles, canonical roles, user provisioning, departments.
- **Core Work Order Engine:** lifecycle, assignments, timestamps, activity logs, completion foundations.
- **Emergency Incident Management:** independent rescue/response lifecycle with optional linked corrective work orders.
- **Notifications:** server-only provider interface with a safe no-op implementation and durable outbox.
- **Asset Registry:** governed Asset/system identity, lifecycle, criticality, location and operational linkage.
- **Preventive Maintenance:** versioned requirements, dated occurrences, deferrals, manual processing and governed Work Order generation.
- **Future operational modules:** inventory, commissioning, and commercial management.

Emergency incidents do not add emergency statuses to work orders. One incident may link to zero or many corrective work orders. See [EMERGENCY_RESPONSE.md](EMERGENCY_RESPONSE.md).

## Data and mutation rules

- UUIDs are primary keys; human-readable numbers are unique operational references.
- Security-sensitive transitions execute atomically in PostgreSQL.
- Direct authenticated writes are revoked where they could bypass workflow rules.
- Activity history records actor, action, state change, timestamp, and safe context.
- Notification delivery is non-blocking and provider-independent.
- Schema evolution uses new numbered migrations; committed migrations are immutable.

## Deployment identity

`/api/health` and the authenticated footer expose only version, short commit SHA, and environment label. Missing local commit metadata falls back to `local`.

## Integration boundaries

No transactional notification provider, scheduler, ERP, accounting platform, building-management system, or AI provider is assumed. Integrations must be server-side, replaceable, observable, and unable to bypass domain authorization.

## Related specifications

[DATA_MODEL.md](DATA_MODEL.md), [API.md](API.md), [WORKFLOW.md](WORKFLOW.md), [SECURITY.md](SECURITY.md), [INTELLIGENCE_LAYER.md](INTELLIGENCE_LAYER.md), and [PRODUCT_EDITIONS.md](PRODUCT_EDITIONS.md).

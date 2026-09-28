# FMWorks Pilot Boundary

Status: implementation contract for WP-PILOT-001  
Timezone: `Asia/Singapore`  
Data model: one customer per deployment; no tenant discriminator columns

## Customer and deployment boundary

One FMWorks deployment, its Supabase project and its configured application URL serve exactly one agreed customer and one agreed Singapore site/portfolio boundary. Users, departments, Work Orders, Assets, Incidents, maintenance requirements, evidence and audit records inside that deployment belong to that customer boundary.

This pilot is not a safe multi-customer shared environment. A second customer requires a separate application deployment, separate Supabase project, separate secrets, separate storage and a separately reviewed migration history. Adding a `tenant_id`, customer selector or client-side filter is explicitly not an approved substitute for that isolation.

## Identity lifecycle

- Public self-registration is disabled in the application. `/register` redirects to first-time access guidance.
- Accounts are invited or created by an authenticated ready Administrator. The database trigger creates an inactive quarantine profile before any provisioning transaction activates it.
- Administrator-created and invited accounts have `password_change_required = true`. Operational access remains denied until Supabase Auth accepts the new password and the service-only reconciliation function clears the database gate.
- Active, non-archived, canonical role and password-readiness state are checked from `profiles`. Missing, inactive, archived, unsupported-role and password-pending profiles fail closed.
- Role, activation and archive changes use authoritative security-definer operations that update the profile and write the audit record in one PostgreSQL transaction.
- Archive is the normal retention-safe account-removal state. Permanent Auth deletion remains available to Administrators when privileged Auth access is configured and retained operational references permit profile removal. Its request and external result are audited separately so a pending or failed Auth operation is never reported as completed.

## Reconciled cross-system states

Supabase Auth and PostgreSQL cannot be committed in one distributed transaction. The application therefore uses explicit safe intermediate states:

| Auth operation | PostgreSQL operation | Result if PostgreSQL fails |
| --- | --- | --- |
| Create/invite Auth user | Finalize inactive trigger profile and audit atomically | Delete a new Auth user when possible; otherwise leave the profile inactive and report Administrator reconciliation required |
| Activate a pre-existing pending Auth user | Finalize profile and audit atomically | Profile remains inactive/password-pending; report reconciliation required |
| Change Auth password | Clear password gate and audit through service-only RPC | New password may be valid, but operational access remains locked; report reconciliation required |
| Permanently delete Auth user | Record pending request, attempt Auth deletion, then record trusted result | Preserve the failed/pending audit state and direct the Administrator to archive or reconcile; never claim completion before Auth succeeds |

No route reports a fully usable account until the authoritative PostgreSQL state is complete.

## Operational trust boundaries

- Work Orders are private authenticated records. The anonymous `/works` list and anonymous `list_public_work_orders()` execution are retired.
- Approver, Supervisor and Administrator roles are the only roles shown the Approval Centre and controlled CSV exports. A Technician lands on My Work.
- People information is recorded activity and workload, not live presence, availability, attendance or capacity.
- The Incident Operations Board is a recorded authenticated view, not a realtime emergency dispatch system.
- Notification outbox records are queued intent only. A browser cannot write provider outcomes. No SMS or WhatsApp provider is implemented by this work package, and queued never means delivered.
- Export rows are RLS-scoped and contain controlled human-readable operational fields. Auth identifiers, storage object paths, provider payloads/references and raw JSON are excluded. Every CSV field is quoted and spreadsheet-formula prefixes are neutralized.

## Pilot timezone guardrail

Business dates, operational review and export extraction labels use `Asia/Singapore`. The current pilot must not be presented as timezone-configurable or safe for another operating timezone without a separate review of due-date, SLA, recurrence and reporting behavior.

## Product preservation

The deployment boundary does not define a reduced pilot edition. Mission Control, Operations, Work Orders, Technician execution, review/rework, Evidence, Incidents, Assets, Preventive Maintenance, Administration, Departments/Teams, Approvals, audit, notification foundations, reporting and multi-site-capable site fields remain part of the approved baseline.

## Explicit exclusions

The pilot does not add multi-tenancy, customer switching, SMS/WhatsApp delivery providers, cron or background workers, realtime subscriptions, offline synchronization, BI integrations, PDF reporting, public Work Order browsing, live staff availability, or remote deployment operations. These require separate authorization and design review.

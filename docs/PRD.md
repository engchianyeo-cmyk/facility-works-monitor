# FMWorks Product Requirements

> Pilot trust boundary: [PILOT_BOUNDARY.md](./PILOT_BOUNDARY.md). The approved pilot is one customer per dedicated deployment/Supabase project, uses `Asia/Singapore`, and has no public self-registration or anonymous operational Work Order view.

## Purpose

FMWorks is an authenticated facilities-operations platform for reporting, authorizing, assigning, executing, and auditing maintenance work. It replaces fragmented spreadsheets, email, and messaging threads with controlled operational records.

## Product outcomes

- Give facility managers a real-time view of work, risk, ownership, and deadlines.
- Preserve an auditable record of every material workflow action.
- Let each role perform its work without gaining broader data or administrative access.
- Keep emergency response separate from corrective maintenance while allowing linkage.
- Support future inventory, commissioning, commercial, and integration modules on the same identity and audit foundations.

## Current product scope

The implemented baseline comprises Mission Control, Operations, authenticated user and department/team management, the Core Work Order Engine, Technician execution, completion review/rework, protected Evidence, Emergency Incident Management, the Asset Registry, Preventive Maintenance requirements and occurrence processing, Approval Centre, audit history, controlled CSV exports, deployment identity, and a provider-neutral notification foundation.

## Personas

| Role | Primary responsibility |
|---|---|
| Reviewer | Entry-level authenticated access and review-oriented participation |
| Initiator | Report and maintain their own requests before authorization |
| Approver | Approve, review, and close work without self-approval |
| Technician | Accept and execute assigned work only |
| Supervisor | Coordinate assignments, departments, and operational rosters |
| Administrator | Govern users, configuration, overrides, and audit access |

Canonical stored roles are `reviewer`, `initiator`, `approver`, `technician`, `supervisor`, and `administrator`. “Requester” is descriptive language for an Initiator, not a stored role.

## Core capabilities

1. Authenticated identity and active-profile validation.
2. Draft-to-close work-order lifecycle with database-enforced transitions.
3. Technician, vendor, or maintenance-team assignment.
4. Timestamped workflow and activity history.
5. Safe cancellation instead of routine hard deletion.
6. KPI dashboard, filtering, priority ordering, and attention queues.
7. Controlled user and department administration.
8. Provider-neutral, non-blocking notifications.

## Quality requirements

- Authorization is enforced server-side and in PostgreSQL, never only by hiding controls.
- Secrets never enter browser bundles.
- Mutations return structured, non-sensitive errors.
- Terminal records are immutable except through an audited administrative correction.
- Empty, loading, failure, and no-provider states are explicit.
- Accessibility and responsive operation are required for office and field users.

## Out of current scope

Live SMS/WhatsApp/email delivery, automated escalation scheduling, automated PM scheduling, inventory accounting, commissioning workflows, commercial billing, multi-tenancy, and autonomous AI actions are roadmap capabilities, not implied by the current build. Manual PM occurrence processing and Work Order generation remain part of the implemented product.

## Success measures

- Authorized users can complete the full work-order lifecycle with a continuous audit trail.
- A Technician cannot access or act on another Technician’s assignment.
- User provisioning creates an Auth user and matching active profile safely.
- Operational dashboards reconcile with persisted records after refresh.
- Emergency incidents remain valid even when no responder or notification provider is configured.

See [ARCHITECTURE.md](ARCHITECTURE.md), [WORKFLOW.md](WORKFLOW.md), [SECURITY.md](SECURITY.md), [ROADMAP.md](ROADMAP.md), and [TEST_PLAN.md](TEST_PLAN.md).

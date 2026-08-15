# FMWorks Data Model

## Conventions

- UUID primary keys and UTC `timestamptz` audit fields.
- Human-readable work-order and incident numbers are unique and immutable.
- Reference data uses active/deleted markers rather than destructive removal.
- Role and lifecycle values are constrained to canonical enumerations.
- Legacy compatibility columns may remain until a separately approved retirement migration.

## Identity and organization

`profiles.id` equals `auth.users.id`. Profiles contain display identity, email, department association, canonical role, activation/deletion state, contact number, and presence metadata. `departments` provide governed organizational references. Administrators manage users; department operations follow current role policies.

## Core work orders

`work_orders` stores the request, priority, canonical lifecycle status, source, requester/submitter, department, site/location, asset reference, primary assignment, schedule and labour values, completion/cancellation notes, predictive context, and workflow timestamps.

Canonical statuses are `draft`, `submitted`, `approved`, `assigned`, `in_progress`, `completed`, `reviewed`, `closed`, and `cancelled`. Priorities are `low`, `medium`, `high`, and `critical`. Sources are `manual`, `reactive`, `preventive`, `inspection`, `condition_based`, and `predictive`.

Primary assignments are mutually exclusive: Technician, vendor, or maintenance team. `maintenance_team_members` connects active profiles to teams. `vendors` and teams are soft-deactivatable reference data.

## Audit and completion

`activity_logs` stores work-order or incident actions with actor, state change, note, and timestamp. Critical mutations write their domain record and audit entry in one transaction. `work_order_completions` and `work_order_evidence` support protected technician completion/evidence workflows. Storage access remains a protected server concern.

## Notifications

`notification_outbox` is the durable queue/history boundary. It stores event, recipient, channel, provider-safe result metadata, attempts, and references. It must never store credentials, tokens, service-role keys, or raw provider errors.

## Emergency incidents

The approved incident model is separate from work orders. `incidents` stores classification, severity, response status, location, description, reporter, commander, responder/team, acknowledgement deadline, and response timestamps. `emergency_response_roster` selects active response contacts and channel preferences. `work_orders.incident_id` provides optional many-work-orders-to-one-incident linkage.

Incident statuses are `reported`, `acknowledged`, `mobilising`, `on_site`, `rescue_in_progress`, `safe`, `recovery`, `closed`, and `cancelled`. See [EMERGENCY_RESPONSE.md](EMERGENCY_RESPONSE.md).

## Assets and preventive maintenance

`asset_systems` and `assets` form the implemented canonical Asset Registry, including business identifiers, physical location, criticality, lifecycle state, department/team responsibility, and links to Work Orders and Incidents.

`maintenance_requirements`, immutable `maintenance_requirement_revisions`, `pm_occurrences`, and `pm_occurrence_deferrals` form the implemented preventive-maintenance foundation. Occurrence materialization and Work Order generation are explicit governed operations. Compliance state is a derived operational outcome using the Singapore business-date policy; it is not a regulatory certification.

## Planned domains

The following are specifications, not assertions that tables exist:

- Stock and transaction ledger: [INVENTORY.md](INVENTORY.md)
- Handover and defects: [COMMISSIONING_MANAGER.md](COMMISSIONING_MANAGER.md)
- Contracts, costs, and approvals: [COMMERCIAL.md](COMMERCIAL.md)

## Integrity rules

- Foreign keys use restrictive or explicit nulling/cascade behavior appropriate to audit retention.
- Closed/cancelled operational records are not routinely deleted.
- RLS scopes reads; RPCs enforce transitions, role checks, and transactional audit.
- New schema changes require a new migration and disposable-database verification.

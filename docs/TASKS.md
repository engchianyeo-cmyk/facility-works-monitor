# FMWorks Delivery Backlog

## Delivery rules

- Preserve the authenticated Core Work Order architecture.
- Use new migrations; never rewrite applied migrations.
- Validate against isolated environments before production.
- Keep secrets server-only and workflows database-authorized.
- A feature is incomplete if a visible action cannot persist safely.

## Release 1.1 stabilization — complete baseline

- Authenticated dashboard and navigation.
- Canonical-role login/profile validation.
- Administrator provisioning and safe configuration errors.
- Core lifecycle, assignments, audit, and attention views.
- Build identity and notification provider boundary.

## Release 1.2 emergency response — current

- Review and disposable-database test incident migration.
- Complete roster-management UI and contact validation.
- Complete incident-to-corrective-work-order actions.
- Add isolated role/browser tests.
- Select approved SMS/WhatsApp provider and delivery worker.
- Define scheduler and escalation runbook.

## Asset and maintenance foundation — implemented baseline

- Governed Asset Registry, systems, identifiers, lifecycle and criticality.
- Versioned Maintenance Requirements, deterministic recurrence and dated occurrences.
- Manual occurrence processing, Work Order generation, deferral/cancellation controls and operational outcome views.
- Future work: separately approved automated scheduler/worker and broader regulatory reporting.

## Inventory and commercial — planned

- Approve stock ledger and location model.
- Link reservations/issues/returns to work orders.
- Define cost, quotation, approval, tax, currency, and purchase-order boundaries.
- Establish accounting/ERP integration ownership.

## Commissioning — planned

- Define projects, systems, equipment, checklists, tests, punch items, documents, acceptance, and handover to Asset Management.

## SLA document intelligence and staffing - implemented foundation

- Management-authorized, fingerprinted SLA document records with a Pilot-safe storage abstraction.
- Provider-neutral deterministic mock extraction with clause provenance and human review/approval lineage.
- Advisory IN_HOUSE, OUTSOURCED, and HYBRID staffing analysis with explicit UNKNOWN inputs and escalation coverage gaps.
- Structured-metric-only, visibly labelled management commentary integrated with existing JSON/PDF reporting.
- Future work: approved PDF/DOCX text processor, client-approved LLM adapter, approved external document storage, and task-level workforce calibration.
- WP-FMW-011 adds local TXT/PDF/DOCX parsing, governed provider/prompt metadata, safe AI audit/usage controls, and the management AI administration screen. OCR, paid provider activation, and external document storage remain separately approved future work.

## Definition of done

Approved requirements, migration review, automated tests, production build, security review, role-based UAT, operational guide updates, rollback plan, and release note.

See [ROADMAP.md](ROADMAP.md), [TEST_PLAN.md](TEST_PLAN.md), and module specifications.

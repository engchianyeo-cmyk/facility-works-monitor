# FMWorks Product Roadmap

## Roadmap conventions

“Implemented” means present in the repository; “migration pending” means code/schema design exists but requires controlled database rollout; “planned” means specification only. Dates and editions require commercial approval before external commitment.

## Current baseline — FMWorks 1.1

- Authenticated shell and canonical role model.
- Administrator user provisioning and department management.
- Core Work Order Engine with assignment, audit, dashboard, and safe errors.
- Server-only admin client and build identity.
- Provider-neutral no-op notification abstraction.

## FMWorks 1.2 — Emergency response

- Separate Incident module and response lifecycle.
- On-call roster, acknowledgement SLA, audit, and incident/work-order linkage.
- Independent SMS/WhatsApp provider channels.
- Status: implementation and migration review; provider and scheduler infrastructure remain external dependencies.

## Next operational releases

1. Asset register, hierarchy, documents, warranty, and lifecycle history.
2. Preventive-maintenance plans, schedules, generation, and compliance.
3. Inventory catalogue, locations, reservations, issues, returns, and valuation boundaries.
4. Commissioning, handover, defects, and asset acceptance.
5. Commercial controls for budgets, estimates, quotations, purchase references, and cost approval.
6. Approved notification providers, delivery workers, retries, and escalation scheduler.

## Intelligence horizon

Assistive classification, prioritization, anomaly detection, and recommendations may be introduced only with human review, explainability, audit, privacy controls, and deterministic fallback. Autonomous approvals, deletions, purchasing, and safety decisions are prohibited by default.

## Documentation backlog

API versioning, backup/restore runbook, migration runbook, provider integration guides, accessibility standard, data retention policy, disaster recovery, and support/SLA policy.

See each module specification and [PRODUCT_EDITIONS.md](PRODUCT_EDITIONS.md).

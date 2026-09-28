# FMWorks Changelog

This file summarizes product-level changes. Deployment-specific details belong in release records and `/api/health` build identity.

## Unreleased — 1.2

- Defined Emergency Incident Management as a separate operational module.
- Added incident lifecycle, response roster, acknowledgement SLA, notification channels, and corrective-work linkage design.
- Modernized the complete documentation set.

## 1.1 — Stabilization Batch A

- Added authenticated FMWorks dashboard landing page.
- Stabilized Administrator provisioning and canonical non-Administrator login behavior.
- Hardened the server-only Supabase admin client.
- Added build identity to authenticated UI and health reporting.
- Introduced provider-neutral, non-blocking assignment notifications.

## 1.0 — Core Work Order Engine

- Established the canonical Draft-to-Closed workflow.
- Added authenticated role authorization, assignments, activity audit, departments, user profiles, and work-order search/detail experiences.

## Historical prototype

The initial demonstration delivered basic CRUD, dashboard counts, and an early status workflow. Its anonymous-write model and `done/rejected` terminology are superseded and are not current architecture.

See [ROADMAP.md](ROADMAP.md) and [STABILIZATION_BATCH_A.md](STABILIZATION_BATCH_A.md).

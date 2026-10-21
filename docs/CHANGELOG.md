# FMWorks Changelog

This file summarizes product-level changes. Deployment-specific details belong in release records and `/api/health` build identity.

## Unreleased — Work Order Lifecycle v2 (owner-approved 20 October 2026)

- Technicians create Work Orders with photos, video, voice notes, reason and quotation; superiors may create when the Technician is unavailable.
- One approval of work and quotation within role monetary limits (Approver/Supervisor S$250,000, Facility Manager S$500,000, Administrator unlimited; Administrator-adjustable, versioned).
- Emergency work starts immediately; the contractor quotation follows and is approved at review.
- One review approves work, final cost and documents to **Completed**; Approver role included, facility-scoped.
- Contractor invoice uploaded after Completed must equal the approved amount; Finance confirms receipt (payment terms run from receipt) and records payment; Work Order closes automatically.
- New Finance role and payment tracker; copied parties; Administrator-only quotation threshold; renameable roles and stage names.
- Fixed: Completed Work review lacked a facility-membership check (20260921061036).
- In-house services (D-07): declared at creation or in Draft; same approvals and review with pricing waived; closes on approval as Completed.
- Site requirements (D-08): location marked on the layout plan and a Before photo before submission (emergency: both before review); area highlighted automatically when placed on the plan; Before/After photos shown inline; final quotation required when the final cost differs, with the supervising Technician's site-verification; work duration shown.
- Fixed: commercial document upload read contractor_quotations directly (no table grant since 0041) and always failed; now reads through the scoped RPC.
- Migrations 20261020060000–20261020110000; Preview reconciliation adapter extended to include them.

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

# Preventive Maintenance Specification

## Status and purpose

Planned module for converting approved maintenance plans into controlled work orders without creating a second execution workflow.

## Core concepts

Maintenance plan, plan revision, asset/scope, task/checklist, frequency, meter trigger, tolerance window, responsible team/vendor, required skills/parts, next due date, generated work order, compliance result, and deferral.

## Scheduling rules

- Calendar, meter, or condition triggers must be explicit and timezone-aware.
- Generation is idempotent: one occurrence cannot create duplicate work orders.
- Generated work uses source `preventive` and then follows the Core Work Order Engine.
- Deferral/cancellation requires authority, reason, revised due date, and audit.
- A missed occurrence remains reportable; it is not silently advanced.

## User experience

Plan list/detail, upcoming calendar, due/overdue queues, generation history, checklist execution through assigned work, completion evidence, and compliance reporting.

## Dependencies

Asset register, approved scheduler/worker, timezone policy, notification provider, and inventory reservation are separable dependencies. Manual generation must remain available if scheduling is unavailable.

## Acceptance criteria

Deterministic next-due calculations, daylight-saving/timezone tests, duplicate-generation prevention, plan revision history, authorization, audit, and normal reactive-work regression.

See [WORKFLOW.md](WORKFLOW.md), [ASSET_MANAGEMENT.md](ASSET_MANAGEMENT.md), [INVENTORY.md](INVENTORY.md), and [ROADMAP.md](ROADMAP.md).

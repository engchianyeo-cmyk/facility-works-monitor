# Proportionate Work Control

## Purpose

FMWorks must preserve truthful site progress without allowing paperwork convenience to bypass safety-critical authority. Control intensity follows operational and safety risk, not a universal form burden.

## Conceptual operating classes

| Class | Typical work | Minimum control concept |
|---|---|---|
| Routine / standard | Low-risk recurring or minor corrective task | Assignment, concise instruction, truthful progress, proportionate evidence, closure |
| Controlled / high-risk | Isolation, permits, critical systems, regulated work | Verified prerequisites, competent authority, hold/witness points, evidence and independent review |
| Urgent | Time-sensitive fault where delay increases consequence | Rapid authorized start, explicit temporary controls, visible outstanding documentation and retrospective completion deadline |
| Emergency response | Immediate life-safety/property response | Separate incident command; act rapidly under emergency authority, record actual milestones, then link recovery work |

Classification must be governed and auditable. A requester or technician must not self-downgrade work to avoid control.

## Truthful-state rules

1. Physical progress may be recorded when it occurs.
2. Missing documentation remains visible as a separate exception.
3. Outstanding approval remains visible and does not masquerade as physical incompletion.
4. Safety-critical prerequisites and legal authority cannot be bypassed.
5. Emergency response remains rapid and distinct from corrective maintenance.
6. Controlled work may require prerequisites before start or readiness, depending on the control—not merely before data entry.
7. Routine work should not inherit high-risk paperwork without a stated reason.
8. Completion, documentary acceptance and operational readiness are independent determinations.

## Proposed state dimensions

| Dimension | Example values | Question answered |
|---|---|---|
| Physical execution | not started, active, physically complete, unable to proceed | What is true on site? |
| Documentation | not required, incomplete, submitted, rejected, accepted | Is required proof complete? |
| Authority / approval | not required, pending, approved, withdrawn | Is the action authorized? |
| Readiness | unknown, not ready, conditional, ready | Can the affected system operate? |
| Dependency | none, waiting, blocked, cleared | What external condition controls progress? |

These are conceptual recommendations, not a database design.

## Current architecture review

### Supports the principle

- Database-owned transitions and audit protect material actions.
- Completion, review and closure are distinct in the core workflow.
- Emergency incidents have a separate lifecycle and can link corrective work.
- Assignment and role checks reduce unauthorized action.
- Notification failure does not invalidate valid operational records.

### Conflicts or gaps

- One main status sequence is applied broadly to ordinary work.
- Acceptance is a timestamp while status remains assigned, increasing semantic ambiguity.
- Blockers, dependencies, documentation state and readiness are not first-class across work orders.
- The blocked 0010 proposal introduces completion approval status but does not resolve the full multi-dimensional model.
- Current UI labels may imply operational meaning from workflow status.

## Later architecture work package

The future WP should:

1. define governed work classes and who may classify/reclassify;
2. inventory all existing live statuses and historical semantics;
3. define independent state dimensions and transition ownership;
4. specify safety prerequisite/hold-point rules;
5. design explicit blocker/dependency records with owner, consequence and due time;
6. retain idempotent, narrow database functions and `activity_logs`;
7. preserve legacy statuses and reporting compatibility;
8. map UI wording and reporting to each dimension;
9. test routine, controlled, urgent and emergency scenarios with operators;
10. provide reversible migration and reconciliation plans.

Avoid a generic `update_work_order` function, client-controlled lifecycle fields, automatic dynamic constraint rewrites and direct broad technician updates.

## Safety boundary

“Truthful recording” does not authorize work. A technician may record that work occurred or cannot proceed only within policy; controlled actions still require competent authority. Any retrospective-documentation path must define who authorized the urgent action, what temporary controls applied, when evidence is due and what prevents final readiness.

No workflow or schema change is made by this product-definition package.

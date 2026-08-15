# FMWorks Operations Control

## Commercial definition

**Product:** FMWorks Operations Control

**Initial offer:** Single-Site Launch Package

FMWorks Operations Control is a focused engineering-operations product for a facility team that needs to see what needs attention, understand what blocks progress, know who must act, know what should happen next, and keep physical engineering reality separate from documentation and approval status.

It is not a full EAM replacement. ERP, BIM, GIS, BMS and specialist maintenance systems may remain systems of record; FMWorks coordinates accountable operational action.

## Product promise

In one controlled operational workspace, FMWorks will:

- surface abnormal and critical conditions;
- explain blockers and their consequence;
- identify ownership and the next authorized action;
- connect incidents, work and audit history;
- distinguish physical state from documentary/approval state where relevant.

## Principles

### Manage by Exception

Normal operations remain quiet. Abnormal conditions surface. Critical conditions dominate. Blocked work explains why. Decision-required work names the decision and authority. Action-required work names the next action and owner.

### Engineering Reality

Physical/engineering condition and documentation/approval state are independent facts. Submission is not completion; completion is not approval; approval is not automatically operational readiness.

### Proportionate Control

| Operating class | Intended control |
|---|---|
| Routine / standard | Lightweight assignment, execution, evidence and closure |
| Controlled / high-risk | Defined prerequisites, authority, evidence and review |
| Urgent | Rapid authorization and execution with visible exceptions and retrospective completion where safe |
| Emergency response | Separate rapid incident command lifecycle; linked corrective work follows afterward |

The current core lifecycle is uniform and therefore only partially supports proportionality. The separate incident lifecycle supports emergency speed, but later architecture work must introduce governed operating classes without permitting safety-critical bypasses.

### Human-First Operations

FMWorks assists people doing engineering work. It minimizes re-entry, irrelevant fields and administrative navigation; accepts truthful blocker reporting; and never makes a convenient software status more important than safe physical reality.

## Single-Site Launch Package

| Capability | Commercial classification | Launch definition |
|---|---|---|
| Mission Control | Required for sale | Exception-led first screen and clear next action |
| Operations Workspace | Required for sale | Prioritized coordination of critical, overdue, unassigned and approval work |
| Work Orders | Required for sale | Controlled request, approval, assignment, execution, review and audit |
| Incident Command Centre | Required before go-live | Deployed, role-tested incident response and work linkage |
| Approval / Review | Required for sale | Separation of authority and traceable decisions |
| Audit Trail | Required before go-live | Persisted material actions with actor and time |
| Facility Overview | Acceptable beta | Clearly labelled operational context; customer drawing support may be assisted |
| Users / Departments | Required before go-live | Controlled provisioning, roles and departmental scope |
| Emergency Roster | Required before go-live if incidents included | Configured and tested responder selection |
| Notifications | Acceptable beta | In-app/queued truthfulness; external delivery only when a provider confirms it |
| Technician Mobile Experience | Required before go-live | Responsive assigned-work path; offline limitation disclosed |
| Evidence / Attachments | Required before go-live | Secure photographs/documents, metadata, review and audit relationship |
| Basic operational reporting | Required for sale | Counts, ageing, ownership and exception outcomes; not advanced BI |

## What the package excludes

- full asset lifecycle management, PM and inventory accounting;
- offline guarantee until implemented and validated;
- ERP/procurement replacement;
- BIM/GIS authoring or live positioning;
- autonomous AI decisions;
- formal commissioning certification;
- guaranteed message delivery without configured provider confirmation;
- multi-site/global enterprise claims.

## Minimum onboarding

`Customer → site → departments → users/roles → locations → emergency roster → work configuration → facility drawing → notifications → role training → UAT → go-live`

Developer intervention is currently likely for deployment/migration reconciliation, customer data loading, facility-layout source/configuration, notification provider configuration and any workflow variation.

## Scale challenge

| Scale | Principal requirement / risk |
|---|---|
| 10 customers | Repeatable tenant provisioning, configuration templates, support ownership and migration discipline |
| 100 customers | Proven tenant isolation, automated environment/configuration management, observability, provider quotas and support tooling |
| 1,000 customers | Strong multi-tenant architecture, data partitioning, regional deployment, automated recovery, metering and self-service administration |

Customer-specific code forks, per-customer schema changes, hard-coded layouts, shared unscoped tables and manual production SQL would create immediate technical debt.

## Commercial acceptance gates

No paid production launch until the red items in [Commercial Readiness Scorecard](COMMERCIAL_READINESS_SCORECARD.md) are closed. A contract may be accepted earlier only for explicitly scoped implementation services with clear dependencies, acceptance criteria and refund/termination terms—not by representing blocked capability as live.

## Required answers

1. **What are we selling?** A single-site exception-led engineering operations product with controlled work, incident coordination, evidence and audit.
2. **Who buys first?** A Facilities Director or Operations Manager at one operational facility with fragmented work/incident coordination.
3. **Why pay?** Faster ownership and decisions, visible blockers, less reconciliation and defensible records.
4. **Complete before money for live use:** evidence, mobile UAT, deployment reconciliation, security/UAT, notification truthfulness, backup/support/legal basics and authentic demo proof.
5. **Safely incomplete:** offline mode, advanced analytics, asset/PM/inventory, AI and full spatial interaction when explicitly excluded.
6. **Never promise now:** EAM replacement, autonomous AI, formal commissioning, universal industry fit, guaranteed delivery or enterprise scale.
7. **Second paid module:** Technician Evidence & Operational Readiness.
8. **Partner for:** BIM/GIS, ERP/procurement, IoT, messaging, identity, BI and qualified e-signature.
9. **Largest commercial risk:** selling locally implemented or designed capability as deployed, usable and supported product.
10. **Largest opportunity:** own the gap between physical engineering reality, documentary proof, dependencies and operational readiness.

## Related documents

- [Commercial Gap Analysis](COMMERCIAL_GAP_ANALYSIS.md)
- [Technician Experience Standard](TECHNICIAN_EXPERIENCE_STANDARD.md)
- [Proportionate Work Control](PROPORTIONATE_WORK_CONTROL.md)
- [First Customer Profile](FIRST_CUSTOMER_PROFILE.md)
- [Pricing Strategy](PRICING_STRATEGY.md)
- [Commercial Readiness Scorecard](COMMERCIAL_READINESS_SCORECARD.md)
- [Commercial Demo](COMMERCIAL_DEMO.md)

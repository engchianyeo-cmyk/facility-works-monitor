# Commercial Gap Analysis

## Evidence basis

`IMPLEMENTED` means repository artifacts exist. It does not prove that the capability is deployed, usable with customer data or commercially accepted. Applied migrations, runtime configuration, browser behavior, security and UAT remain separate gates.

| Capability | Repository state | Commercial condition | Classification | Gap / required evidence |
|---|---|---|---|---|
| Mission Control | Implemented | Needs UAT and commercial polish | Required for sale | Authentic role/viewport review; verify 30-second decision and live data behavior |
| Operations Workspace | Implemented | Needs UAT and commercial polish | Required for sale | Validate prioritization, actions, empty/degraded states and customer terminology |
| Work Orders | Implemented | Needs UAT | Required for sale | Reconcile deployed schema; end-to-end role tests with real browser/customer configuration |
| Incident Command Centre | Implemented locally | Blocked until migration/deployment verification | Required before go-live | Confirm 0014/0015 rollout, authorization, roster, degraded provider behavior and incident UAT |
| Approval / Review | Implemented for core lifecycle | Needs UAT; proportional model designed only | Required for sale | Verify separation of duties and avoid claiming risk-based workflow classes |
| Audit Trail | Implemented foundation | Needs runtime verification | Required before go-live | Prove every material launch transition persists an attributable activity record |
| Facility Overview | Implemented sample component | Acceptable beta / needs polish | Acceptable beta | Authentic rendering; customer drawing ingestion/configuration remains assisted |
| Users / Departments | Implemented | Needs security and operational UAT | Required before go-live | Provisioning/deactivation/deletion safeguards and department scoping |
| Emergency Roster | Implemented locally | Deployment dependent / needs UAT | Required before go-live with incidents | Configure real contacts, ambiguity behavior and escalation ownership |
| Notifications | Partial | External delivery not configured/proven | Acceptable beta | Provider, worker/retries, monitoring, consent and truthful status; queued is not sent |
| Technician mobile experience | Partial responsive web | Needs device UAT; no offline guarantee | Required before go-live | Prove assigned-only access, touch usability, weak connectivity behavior and field completion |
| Evidence / attachments | Designed in blocked 0010 | Blocked / not implemented at runtime | Required before go-live | Review live status constraint, complete approved migration/routes/UI/security/UAT |
| Basic reporting | Partial | Needs definition and UAT | Required for sale | Agreed KPI definitions, reconciliation, ageing/ownership exports and permission behavior |

## Evidence-management gap

### Minimum viable commercial capability

| Requirement | Minimum behavior | Current evidence |
|---|---|---|
| Work-order photographs | JPEG/PNG/WebP, size/type checks, private storage | Designed in blocked migration 0010; no reviewed application flow |
| Before / after photographs | Explicit type and relationship to one work order | Designed metadata/path convention only |
| Documents | Controlled types, safe filename, private access | Not covered by current image-only bucket proposal |
| Completion evidence | Required rules visible before submission | Designed completion/evidence schema; workflow not live |
| Incident evidence | Reuse protected evidence architecture and link to incident | Designed principle only; no proven incident evidence path |
| Supervisor review | View evidence, accept/reject with reason and immutable history | Designed concept; not implemented as reviewed Stage 2 route/UI |
| Timestamp | Server upload time plus optional capture time | Designed in 0010 |
| Uploader | Authenticated identity, never client-selected | Designed in 0010/security requirements |
| Audit relationship | Evidence add/remove/review linked to `activity_logs` | Required but not implemented in blocked Stage 1 migration alone |

Evidence must be private; access requires work/incident authorization. Signed URLs must be short-lived and server-issued after explicit validation. Deletion must be controlled and audited. Malware handling, document MIME types, retention, metadata privacy and evidence export remain undefined.

## Hard launch blockers

1. Migration 0010 is deliberately blocked pending live status-constraint preflight and does not provide a runnable evidence workflow.
2. Commercial technician completion/evidence routes and UI are absent from the reviewed Stage 1 state.
3. Applied production migration/configuration state is not reconciled with local implementation.
4. Authentic browser product review and role/device UAT are not evidenced.
5. Backup, recovery, retention, support/SLA and legal terms are incomplete.
6. Incident migrations and runtime configuration require verification before incidents enter scope.
7. External notifications lack a proven provider/worker/monitoring operating model.

## Architecture support and conflict

| Principle | Support | Conflict / gap |
|---|---|---|
| Manage by Exception | Mission Control and Operations Workspace prioritize critical, overdue and unassigned records | Explicit blocker/dependency records and decision ownership are incomplete |
| Engineering Reality | Incident and work lifecycles are separate; completion/review are distinct | Core work status still carries too much meaning; readiness/documentation states are not first-class |
| Proportionate Control | Emergency has a separate rapid lifecycle | Routine, controlled and urgent work share a largely uniform core lifecycle |
| Human-first | Role-scoped screens and safe errors | Technician evidence/offline flow and customer configuration remain incomplete |

## What tests do not prove

Automated tests can evidence intended structure, authorization branches and deterministic behavior. They do not prove correct live constraints, migration application, provider delivery, device usability, customer comprehension, accessibility, data quality, recovery, support readiness or commercial value.

## Recommended sequencing

1. Reconcile deployed schema and close 0010 preflight/review.
2. Deliver Technician Evidence & Operational Readiness as the minimum launch completion package.
3. Perform security, browser, device and degraded-state UAT.
4. Establish backup/recovery, support, retention and commercial terms.
5. Run the authentic 10-minute demo and a customer-specific launch rehearsal.

No recommendation in this document authorizes implementation.

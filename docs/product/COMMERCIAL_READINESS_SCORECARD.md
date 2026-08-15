# Commercial Readiness Scorecard

## Rating rule

- **GREEN — sale-ready:** evidence supports a bounded customer commitment.
- **AMBER — manageable launch limitation:** may remain with explicit scope, owner and mitigation.
- **RED — blocks paid customer go-live:** do not represent as production-ready.

This is a repository-based product assessment, not production certification. A passing build or test suite is not sufficient proof.

| Area | Rating | Evidence / gap | Exit criterion |
|---|---|---|---|
| Product completeness | RED | Core coordination exists; required evidence workflow is blocked | Launch scope demonstrable end-to-end with evidence |
| Runtime stability | AMBER | Prior validation reported, but current deployed runtime not independently verified here | Production-like soak and degraded-path UAT |
| Security | AMBER | Server/RLS/RPC controls documented; full launch configuration and migrations need review | Role matrix, migration reconciliation, security UAT and findings closed |
| Mobile usability | RED | Responsive intent; no authentic device/field acceptance evidence and no offline | Technician standard passes representative devices |
| Evidence | RED | Migration 0010 deliberately blocked; routes/UI/review not commercially complete | Private end-to-end evidence flow, audit and UAT |
| Notifications | AMBER | Honest no-op/provider abstraction; delivery worker/provider/monitoring incomplete | Configured provider or explicit in-product-only launch boundary |
| Operational UX | AMBER | Mission/Operations artifacts exist; browser product review pending | Role/scenario product review and 30-second test pass |
| Onboarding | RED | Process defined but automation/templates and developer dependencies remain | Rehearsed customer setup with runbook and handover |
| Documentation | AMBER | Strong product/engineering docs; operating/support/customer docs need consolidation | Approved launch manual, admin guide, limitations and release notes |
| Support | RED | No approved support model/SLA/on-call process | Named ownership, channels, hours, severity and escalation |
| Performance | RED | No commercial workload baseline or SLO | Measured target workload, page/API budgets and monitoring |
| Backup / recovery | RED | Roadmap gap | Tested backup restore, RPO/RTO and customer responsibility statement |
| Demo quality | RED | Script exists; authentic browser product-review evidence unavailable | Rehearsed 10-minute live demo passes scorecard |
| Pricing | AMBER | Hypothesis defined, not buyer validated or approved | Five-buyer validation and approved order form/rate card |
| Legal / commercial | RED | Terms, privacy/DPA, retention, SLA and contracting not evidenced | Approved contract pack and data/security disclosures |

## Capability go-live gates

| Capability | Gate |
|---|---|
| Mission Control | Role/viewport/scenario UAT; critical issue found within 30 seconds |
| Operations Workspace | Correct priority ordering, actions, empty/degraded states and data reconciliation |
| Work Orders | Full role lifecycle, security, audit and live-schema reconciliation |
| Incident Command | Applied reviewed migrations, roster, authorization, provider fallback and scenario drill |
| Evidence | Private storage, safe types/size/path, authorization, review, audit, retention and recovery |
| Technician | Assigned-only access, 390 px usability, camera/error/session/device tests |
| Users/Departments | Provision/deactivate/archive/delete safeguards and least privilege |
| Reporting | Metric definitions reconcile with source rows and permissions |

## Overall decision

**NO-GO for paid production launch today.** The offer and scope are commercially coherent, but evidence, mobile UAT, onboarding, backup/recovery, support, performance, demo proof and legal readiness include red blockers.

It is reasonable to conduct discovery and buyer validation without representing the system as production-ready. Accepting paid implementation services requires a contract that explicitly separates preparatory work from go-live acceptance.

## Safe launch limitations after red gates close

The following can remain amber if disclosed: no offline mode, no full EAM/PM/inventory, assisted facility-layout setup, basic reporting only, provider-dependent external messages, no production AI, one site only and no formal commissioning.

## Review cadence

The product owner, engineering owner, security owner and commercial owner must jointly reassess this scorecard before each customer contract and go-live. Every green rating requires linked evidence, date and accountable approver.

## Related documents

- [Operations Control Product](OPERATIONS_CONTROL_PRODUCT.md)
- [Commercial Gap Analysis](COMMERCIAL_GAP_ANALYSIS.md)
- [Technician Experience Standard](TECHNICIAN_EXPERIENCE_STANDARD.md)
- [Pricing Strategy](PRICING_STRATEGY.md)

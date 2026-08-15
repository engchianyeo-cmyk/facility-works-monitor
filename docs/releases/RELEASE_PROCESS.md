# FMWorks Release Process

## Purpose and authority

This is the permanent release gate for every FMWorks release. A release advances only when its exit criteria are met, evidence is linked, and accountable owners approve. Urgency may compress scheduling but never waives security, data-integrity, backup, or rollback controls.

## Accountabilities

| Role | Accountability |
|---|---|
| Release Manager | Schedule, evidence register, gates, deployment coordination and final record |
| Technical Lead | Code, migration, security, tests, observability and recovery readiness |
| Project Manager | Scope, dependencies, defects, communications and acceptance schedule |
| Business Owner | Business outcomes, known limitations and residual risk |
| UAT Lead | Representative role testing and sign-off |
| Deployment Operator | Approved runbook execution and timestamped output |

Every gate item needs an owner, date, result and durable evidence link. Acceptable evidence includes test output, build identity, migration hashes, database fingerprints, screenshots, issue references and monitoring snapshots. “Done” without evidence is not a pass.

## Lifecycle

`Development → Internal Testing → Code Freeze → Release Candidate → Preview → UAT → Production → Post Validation → Maintenance`

### Development

Approve scope and work packages; implement traceable behavior, additive migrations, tests and documentation. Exit when scope is complete or explicitly deferred and no critical defect is unowned.

### Internal Testing

Run unit, API, SQL/integration, regression, build, accessibility and relevant browser tests in isolated environments. Exit when mandatory validation passes and defects are severity-triaged.

### Code Freeze

Record commit SHA, migration hashes, dependency lockfile, environment-variable inventory, known issues and rollback candidate. Only approved release-blocker fixes may enter; each invalidates affected evidence.

### Release Candidate

Name an immutable candidate such as `FMWorks 1.2 RC1`, produce build identity and release notes, and demonstrate reproducibility. Technical Lead approval is required for Preview.

### Preview

Deploy through the approved Git workflow. Capture database baseline and backup before approved migrations. Verify build identity, schema, fingerprints, smoke tests, logs and monitoring.

### UAT

Administrator, Supervisor, Approver, Technician and Initiator (Requester) execute signed scenarios. Failures become defects and retesting identifies the exact replacement candidate.

### Production

The Go/No-Go meeting reviews evidence, risks, support coverage and recovery readiness. Production requires explicit GO decisions from Release Manager, Technical Lead, Project Manager and Business Owner.

### Post Validation

Run production-safe validation, compare fingerprints, verify representative journeys and inspect monitoring. Any rollback criterion triggers escalation.

### Maintenance

Monitor the stabilization window, triage incidents, publish known issues, complete the retrospective and transfer deferred work to the roadmap.

## Control rules

- Any candidate change increments the RC number and invalidates affected evidence.
- Failed security, authorization, migration, backup or integrity gates cannot be accepted as ordinary residual risk.
- Accepted non-blocking issues require an owner, impact, workaround, target release and Business Owner acceptance.
- Emergency releases use the same controls with a compressed cadence.

Required records: [release gate](RELEASE_1_2_CHECKLIST.md), [UAT](UAT_SIGNOFF.md), [Go/No-Go](GO_NO_GO_MEETING.md), [deployment](DEPLOYMENT_RUNBOOK.md), [rollback](ROLLBACK_PLAN.md), [post-validation](POST_DEPLOYMENT_VALIDATION.md) and [known issues](KNOWN_ISSUES.md).

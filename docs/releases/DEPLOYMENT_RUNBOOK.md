# FMWorks Deployment Runbook

Release candidate/build:  
Environment: Preview / Production  
Operator:  
Approved window:  
Go/No-Go record:

Commands and environment values come from the approved release package. Never put credentials in this document, transcripts, tickets or screenshots.

## Pre-deployment

1. Confirm signed checklist, UAT, GO decision and support coverage.
2. Confirm commit SHA, build identity, migration order and hashes.
3. Confirm environment-variable names and scope without displaying values.
4. Verify backup and restore readiness.
5. Run read-only baseline validation; archive counts and fingerprints.
6. Confirm active operations and expected impact.
7. Announce start and establish the release communication channel.

## Deployment

1. Deploy by approved Git promotion; never deploy uncommitted local files.
2. Confirm the platform reports the expected commit and environment.
3. Apply approved migrations sequentially with stop-on-error enabled.
4. Preserve sanitized command output and timestamps.
5. Stop on error; do not rerun blindly.

## Validation

1. Run post-migration read-only validation.
2. Compare counts, fingerprints, schema inventory, RLS, grants and function security.
3. Verify `/api/health` and authenticated footer identity.
4. Review application, authentication, database and platform logs.

## Smoke tests

1. Administrator authentication and administration.
2. Initiator (Requester) controlled record creation.
3. Supervisor assignment and overview.
4. Technician assigned-only access and permitted action.
5. Approver review and unauthorized denial.
6. Notification outbox/channel status without real contact data.
7. Dashboard/detail persistence after refresh.

## Post-deployment

1. Execute [post-deployment validation](POST_DEPLOYMENT_VALIDATION.md).
2. Monitor the stabilization window and error/performance baselines.
3. Publish status and known limitations.
4. Record sign-off or activate [rollback](ROLLBACK_PLAN.md).
5. Archive evidence, output, approvals and release notes.

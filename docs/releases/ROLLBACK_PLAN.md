# FMWorks Rollback and Recovery Plan

## Philosophy

Rollback restores a known safe service state; it is not an improvised reversal. Application rollback and database recovery are separate decisions. Once a migration accepts live writes, reversing schema may destroy or misinterpret data, so an additive forward fix is preferred unless a rehearsed restore is safer.

## Rollback criteria

Assess rollback immediately for authentication outage, authorization/RLS regression, corruption, failed migration, material workflow failure, secret exposure, sustained severe errors, unacceptable performance or failed fingerprints. The Release Manager and Technical Lead decide; either may stop deployment for a security or integrity incident.

## Prepared recovery assets

- Last known-good commit and deployment identifier
- Database backup identifier, time, retention and restore procedure
- Pre-deployment counts, schema inventory and fingerprints
- Migration hashes and execution logs
- Feature-disable/configuration options
- Communications and escalation contacts

## Recovery process

1. Stop deployment; record time, build, symptoms and affected users.
2. Preserve logs and evidence; do not mutate data speculatively.
3. Restrict risky writes or isolate the affected feature where possible.
4. Choose application rollback, configuration change, database restore or forward fix.
5. Restore the last known-good application through the approved Git path.
6. Restore a database only from an approved backup into a verified target; reconcile later writes.
7. Re-run authentication, authorization, fingerprints, workflows and monitoring checks.
8. Communicate recovery status and obtain sign-off.

## Database rollback limitations

- Applied migrations are never edited in place.
- Dropping new objects may discard post-release records.
- Backup restoration loses or requires replay of later writes.
- Reversal must be rehearsed against representative data.
- If safe reversal is unproven, isolate the feature and issue an approved forward-fix migration.

## Forward-fix standard

A forward fix is narrow, reviewed, isolated-database tested, fingerprint-checked and approved through an expedited release gate. It must not conceal corruption or weaken authorization.

## Recovery sign-off

Recovery decision:  
Data-loss assessment:  
Validation evidence:  
Release Manager:  
Technical Lead:  
Business Owner notified:  
Closed timestamp:

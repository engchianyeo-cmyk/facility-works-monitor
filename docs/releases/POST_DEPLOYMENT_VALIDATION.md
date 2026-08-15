# FMWorks Post-Deployment Validation

Use designated test accounts and marked test records. Never alter real operational records or expose secrets/contact details in evidence.

Release/build:  
Validator:  
Start/end time:  
Monitoring baseline:

## Authentication

- [ ] Active accounts login; logout/session refresh work.
- [ ] Inactive, missing and unsupported profiles fail safely.
- [ ] Build identity matches the candidate.

## Incident Management

- [ ] Authorized creation persists and displays incident number.
- [ ] Unassigned state and SLA are correct.
- [ ] Supervisor assignment and Technician acknowledgement work.
- [ ] Phase/timeline persists after refresh.
- [ ] Corrective work requires explicit action.
- [ ] Unauthorized Technician access is denied.

## Work Orders

- [ ] Create, assign, accept/start, complete, evidence and history work.
- [ ] Role/self-approval restrictions remain enforced.
- [ ] Counts and fingerprints match baseline.

## Notifications

- [ ] Expected recipients and independent channels exist.
- [ ] Channel status is safe and role-visible.
- [ ] Failure or `NOT_CONFIGURED` does not fail business transactions.
- [ ] Private destinations/provider errors are not exposed.

## Dashboard and interface

- [ ] KPIs reconcile with records.
- [ ] Active emergencies sort first.
- [ ] Role navigation/actions are correct.
- [ ] Desktop and mobile critical journeys are usable.

## Performance and operations

- [ ] Error rate and latency remain within baseline.
- [ ] No sustained authentication, database or server errors.
- [ ] Queues show no unexpected growth.
- [ ] Monitoring and support alerts operate.

## Outcome

Result: **HEALTHY / DEGRADED-ACCEPTED / ROLLBACK-REQUIRED**  
Findings/evidence:  
Release Manager:  
Technical Lead:  
Business Owner notified:  
Timestamp:

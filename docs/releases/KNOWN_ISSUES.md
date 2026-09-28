# FMWorks 1.2 Known Issues and Deferred Scope

Each open item needs an owner, impact, workaround, target release and Go/No-Go decision.

## Known limitations

| Issue | Impact | Current behavior/workaround | Decision |
|---|---|---|---|
| SMS provider not approved | No real SMS | Incident succeeds; `NOT_CONFIGURED` | Explicit acceptance or provider completion |
| WhatsApp provider not approved | No real WhatsApp | Incident succeeds; `NOT_CONFIGURED` | Explicit acceptance or provider completion |
| Email incident delivery deferred | No operational incident email | Approved operating procedure | Record in UAT/release notes |
| Retry worker/scheduler deferred | No automatic retry | Monitor outbox and escalate operationally | 1.3 candidate |
| Channel-level result mapping | No per-recipient result | Safe aggregate status | 1.3 migration candidate |
| Realtime board deferred | Refresh after actions/navigation | Manual refresh for continuous monitoring | 1.3 candidate |
| Controlled migration pending | Incident runtime unavailable | Complete backup, Preview rollout and validation | Release blocker |
| Performance baseline incomplete | Scale not evidenced | Run agreed load profile | Release gate |

## Deferred features

- Approved SMS/WhatsApp providers
- Delivery worker, retries, dead-letter handling and escalation scheduler
- Automated roster rotations and handover
- Realtime Command Centre subscriptions
- Asset, preventive maintenance, inventory, commissioning and commercial modules

## Pilot automated-acceptance observations

| ID / severity | Impact | Current behavior/workaround | Decision |
|---|---|---|---|
| WP-PILOT-GO-002-AUTO-001 / P3 | Windows release-gate logs include Node `DEP0190` warnings when invoking `.cmd` tools | The commands and gate results are unaffected; retain the warning in CI evidence | Replace the Windows command launcher without weakening argument handling |
| WP-PILOT-GO-002-AUTO-002 / P3 | Next.js development-server logs repeat a `NO_COLOR`/`FORCE_COLOR` warning during Playwright | Browser journeys and production build are unaffected | Clean up reporter environment variables in a later tooling pass |

No open P2 issue was found by WP-PILOT-GO-002. Neither P3 observation affects safety, authorization, data integrity, or a Pilot core workflow.

## Release 1.3 candidates

1. Provider integration and secure delivery worker.
2. Per-recipient outbox claim/result RPC and retries.
3. Escalation scheduler, runbook and observability.
4. Realtime Command Centre.
5. Roster coverage gaps, rotations and handover reporting.
6. Performance/resilience improvements from 1.2 evidence.

## Issue template

| Field | Value |
|---|---|
| ID / owner | |
| Severity / affected users | |
| Description / evidence | |
| Workaround | |
| Security/data impact | |
| Target release | |
| Accepted by/date | |

Review this register during [UAT](UAT_SIGNOFF.md), [Go/No-Go](GO_NO_GO_MEETING.md) and [post-validation](POST_DEPLOYMENT_VALIDATION.md).

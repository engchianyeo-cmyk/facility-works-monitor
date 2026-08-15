# FMWorks Agentic Automation Policy

## Status

No autonomous operational agent is part of the approved current baseline. This document defines the safety boundary for future automation.

## Risk tiers

| Tier | Examples | Default control |
|---|---|---|
| Assistive | Draft summary, suggest category, identify missing fields | Human reviews before persistence |
| Low-risk automation | Recalculate derived KPI, enqueue approved notification | Deterministic rules and audit |
| Controlled operational | Draft assignment or schedule adjustment | Explicit authorized approval |
| Prohibited autonomous | Approve work, spend money, delete records, declare emergency safe | Human-only authority |

## Tool design

Future tools must be narrow, typed, role-aware, idempotent where possible, and incapable of arbitrary SQL, arbitrary messaging, or unrestricted execution. The service identity receives only the minimum permissions required.

## Audit contract

Record actor/service, tool name and version, target record, sanitized input reference, decision/result code, human approval where required, and timestamp. Never log secrets or raw sensitive provider payloads.

## Failure and rollback

Automation failure must be visible, contained, and unable to corrupt the authoritative workflow. Safety and work reporting continue without AI. Compensating actions must be explicit and audited rather than silently destructive.

## Governance gate

Before enabling an agent: threat model, privacy review, evaluation suite, role authorization tests, kill switch, cost controls, incident response, owner, and approved operating procedure.

See [INTELLIGENCE_LAYER.md](INTELLIGENCE_LAYER.md), [SECURITY.md](SECURITY.md), and [COMMERCIAL.md](COMMERCIAL.md).

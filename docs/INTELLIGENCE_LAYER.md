# FMWorks Intelligence Layer

## Status and intent

The intelligence layer is a roadmap specification. FMWorks core operations must remain fully functional when AI services are absent, unavailable, or disabled.

## Approved use classes

- Suggest category, priority, failure mode, and recommended action.
- Summarize activity or incident history for human review.
- Identify overdue, recurring, or anomalous patterns.
- Assist search and reporting without changing authoritative records silently.

## Prohibited defaults

AI must not independently approve, cancel, delete, close, purchase, dispatch emergency response, declare a situation safe, or override a human safety decision.

## Decision record

Every accepted intelligence result should retain model/provider identifier, timestamp, confidence where meaningful, input/reference provenance, reviewer, and accepted/overridden outcome. Sensitive prompts and outputs require a retention policy before production use.

## Deterministic fallback

Rules and human entry remain authoritative when AI is unavailable. Provider failure cannot block work reporting, assignment, emergency response, or completion.

## Evaluation requirements

- Representative facility terminology and severity cases.
- False-negative review for safety-critical classification.
- Bias and data-leakage assessment.
- Prompt-injection resistance for uploaded or free-text content.
- Cost/latency thresholds and provider outage behavior.
- Human override and audit verification.

See [AGENTIC_LAYER.md](AGENTIC_LAYER.md), [SECURITY.md](SECURITY.md), and [ROADMAP.md](ROADMAP.md).

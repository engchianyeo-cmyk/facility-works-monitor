# Commercial Management Specification

## Status and purpose

Planned controls for maintenance estimates, quotations, approvals, commitments, and actual costs. FMWorks is not an accounting ledger unless explicitly approved and integrated.

## Core concepts

Budget, cost centre, estimate, quotation and revision, vendor, approval threshold, purchase reference, commitment, labour/material/service cost, variation, invoice reference, currency, tax treatment, and cost allocation.

## Control model

- Monetary authority is separate from technical workflow authority.
- Approval thresholds are configurable and auditable.
- A revised quotation never overwrites the accepted historical version.
- Commitment and actual cost are distinct.
- Closed work retains its commercial history.
- AI/agents may summarize but may not approve spend.

## Integrations

ERP/accounting, procurement, tax, exchange rates, and payment remain external boundaries. Integration requires idempotency keys, reconciliation, error queues, least privilege, and an owner.

## Reporting

Budget versus committed/actual, work-order and asset lifecycle cost, vendor performance, variation aging, preventive versus reactive cost, and export with access controls.

## Acceptance criteria

Currency precision, tax rules, threshold tests, separation of duties, revision history, reconciliation, secure exports, and audit.

See [PRODUCT_EDITIONS.md](PRODUCT_EDITIONS.md), [INVENTORY.md](INVENTORY.md), and [SECURITY.md](SECURITY.md).

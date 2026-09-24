# Commercial Management Specification

## Status and purpose

Release-1 operational controls for maintenance estimates, procurement-qualified contractors, quotations, approvals, commitments, actual costs, final accounts, payment proposals, recorded payments, and no-payment dispositions. FMWorks is not an accounting ledger; payment recording is an auditable operational reference to an external Finance transaction.

## Core concepts

Budget, cost centre, estimate, quotation and revision, vendor, approval threshold, purchase reference, commitment, labour/material/service cost, variation, invoice reference, currency, tax treatment, and cost allocation.

## Control model

- Monetary authority is separate from technical workflow authority.
- Approval thresholds are configurable and auditable.
- A revised quotation never overwrites the accepted historical version.
- Commitment and actual cost are distinct.
- Closed work retains its commercial history.
- AI/agents may summarize but may not approve spend.
- Below S$1,000 requires at least one authentic quotation. At or above S$1,000 requires at least three distinct eligible-contractor quotations before selection and independent approval.
- The quotation threshold is determined from the governed estimated repair value and cannot be reduced by splitting or selecting a lower quote.
- Physical completion does not require a final invoice. Invoice receipt is enforced when the payment proposal is submitted.
- The execution actual-cost ledger is the authoritative actual repair cost. Approved quotation is a comparison baseline and is never added to actual cost.
- Closure requires reconciled recorded payment or an independently approved `no_payment_required` disposition.
- Proposal preparers, payment recommenders, and no-payment proposers cannot approve their own financial actions.

## Integrations

ERP/accounting, procurement, tax, exchange rates, and payment remain external boundaries. Integration requires idempotency keys, reconciliation, error queues, least privilege, and an owner.

## Reporting

Budget versus committed/actual, work-order and asset lifecycle cost, vendor performance, variation aging, preventive versus reactive cost, and export with access controls.

## Acceptance criteria

Currency precision, tax rules, S$999.99/S$1,000.00 threshold tests, distinct-vendor quotation count, separation of duties, revision history, actual/payment reconciliation, secure exports, and audit.

See [PRODUCT_EDITIONS.md](PRODUCT_EDITIONS.md), [INVENTORY.md](INVENTORY.md), and [SECURITY.md](SECURITY.md).

# Inventory Management Specification

## Status and purpose

Planned module for accountable spare-parts and consumables management linked to maintenance execution.

## Core records

Item/SKU, unit of measure, category, supplier reference, store/location/bin, stock lot where required, reorder policy, reservation, receipt, issue, return, adjustment, transfer, count, and immutable transaction ledger.

## Principles

- On-hand quantity is derived from ledger transactions, not freely overwritten.
- Reservations do not equal consumption.
- Issues and returns reference an authorized work order where applicable.
- Negative stock and backdating policy require explicit business approval.
- Adjustments require reason, authority, and audit.
- Valuation method, tax, and currency are commercial decisions.

## User experience

Catalogue search, availability by location, low-stock queue, work-order reservation/issue, mobile-friendly scanning, receiving, stocktake, discrepancy approval, and consumption history.

## Roles

Administrators configure; Supervisors approve operational adjustments; store roles require future definition; Technicians request/receive/return parts for assigned work only.

## Acceptance criteria

Ledger reconciliation, concurrency tests, unit conversion rules, duplicate receipt prevention, work-order traceability, audit, and export controls.

See [ASSET_MANAGEMENT.md](ASSET_MANAGEMENT.md), [PREVENTIVE_MAINTENANCE.md](PREVENTIVE_MAINTENANCE.md), and [COMMERCIAL.md](COMMERCIAL.md).

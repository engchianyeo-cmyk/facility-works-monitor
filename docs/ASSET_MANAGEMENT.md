# Asset Management Specification

## Status

Planned module. This document defines product intent; it does not assert current schema or UI availability.

## Objectives

Maintain a trustworthy register of maintainable assets, locations, systems, ownership, criticality, documents, warranties, and lifecycle history. Assets provide context to work orders, preventive maintenance, inventory consumption, commissioning, and cost reporting.

## Core records

- Asset with immutable identifier, human reference, name, type, status, criticality, manufacturer/model/serial, location, department/cost centre, dates, and parent.
- Asset type/classification and configurable attributes.
- Site/location/system hierarchy.
- Documents, warranty, service provider, meter, and lifecycle event.
- Relationship to work orders, incidents, maintenance plans, parts, and commissioning records.

## Lifecycle

Proposed states: proposed, commissioned, active, out_of_service, mothballed, disposed. State transitions require authority and audit. Disposal does not erase maintenance or commercial history.

## Functional requirements

Search/filter, hierarchy navigation, QR/barcode-ready references, criticality display, document history, warranty alerts, related-work timeline, meter readings, import validation, duplicate detection, and controlled bulk updates.

## Authorization

Administrators govern configuration; Supervisors maintain operational asset data; Technicians view assigned-work context and record authorized readings/evidence; commercial values follow [COMMERCIAL.md](COMMERCIAL.md).

## Acceptance criteria

Unique identifiers, no orphan hierarchy, audited status/history, permission tests, valid import rollback, and complete work/incident traceability.

See [DATA_MODEL.md](DATA_MODEL.md), [PREVENTIVE_MAINTENANCE.md](PREVENTIVE_MAINTENANCE.md), [COMMISSIONING_MANAGER.md](COMMISSIONING_MANAGER.md), and [INVENTORY.md](INVENTORY.md).

# Commissioning Manager Specification

## Status and objective

Planned module for structured testing, defects, acceptance, and handover of facilities, systems, and equipment into operations.

## Core records

Project, facility/system, equipment, commissioning plan, checklist revision, test result, witness/approver, document, punch item, defect, certificate, acceptance milestone, and handover package.

## Workflow

`planned → ready_for_test → testing → defects_open/ready_for_acceptance → accepted → handed_over`

Failed tests and punch items remain visible until resolved or formally accepted with recorded authority. Corrective work may use linked work orders. Accepted equipment creates or activates Asset Management records without losing commissioning provenance.

## Functional requirements

Checklist templates/revisions, offline-tolerant field capture strategy, evidence, signatures/attestations, witness roles, retest history, punch-list aging, document completeness, acceptance gates, and handover summary.

## Controls

No Technician self-acceptance where independent witness/approval is required. Signature meaning, legal validity, retention, and document standards require jurisdictional approval.

## Acceptance criteria

Revision integrity, immutable result history, role separation, failed-test retention, complete handover traceability, and asset/work-order linkage.

See [ASSET_MANAGEMENT.md](ASSET_MANAGEMENT.md), [WORKFLOW.md](WORKFLOW.md), and [COMMERCIAL.md](COMMERCIAL.md).

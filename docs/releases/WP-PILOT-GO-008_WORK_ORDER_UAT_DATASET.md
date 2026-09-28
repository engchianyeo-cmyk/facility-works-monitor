# WP-PILOT-GO-008 Work Order UAT Dataset

The authoritative source is `1. foundation/FMWorks Work Order UAT Test Dataset.docx`. The controlled loader is Preview/UAT-only, requires the authoritative Preview project reference explicitly, and is not part of the production migration chain.

## Mapping

The 15 source identifiers, titles, descriptions, locations, dates, priorities, reporters, assignee labels, hours, costs and instructions are retained. Native fields store Work Order number, title, description, site/location, priority, source, department, Asset relationship, due date, hours, canonical status and governed team/vendor assignment. Unsupported work type, category detail, safety instructions, parts, closure code and monetary cost are retained as labelled `internal_notes` (and completion notes where applicable); no unsupported schema was invented.

Source statuses map as follows: Open and both approval-waiting states → `submitted`; Scheduled → `approved`; Pending Vendor and On Hold–Awaiting Parts → `assigned`; In Progress and Reopened → `in_progress`; Completed → `completed`; Closed → `closed`. The exact source status remains in `source_reference` and the loader audit event. Overdue is represented by its historical due date. Reopen rejection, no-fault closure, safety controls, vendor dependencies, PM provenance and high-value approval are retained in labelled notes and native fields.

Internal named technicians are not fabricated as login identities. Governed synthetic UAT teams represent their assignment relationships while the exact source assignee remains visible. The three contractor cases use clearly labelled synthetic UAT vendors. Fifteen controlled synthetic active Assets provide the authoritative Asset tags; the loader refuses a tag collision rather than altering a legitimate Asset.

Reruns preserve existing rows and create no duplicate Work Orders or audit events. Any Work Order-number or Asset-tag collision with a non-UAT identity aborts the transaction. Legitimate non-UAT data is never updated or deleted.

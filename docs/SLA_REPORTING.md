# SLA, Escalation, and Reporting Foundation

WP-FMW-009 adds a governed foundation for maintenance performance without making an AI provider, mail provider, or external scheduler a runtime dependency.

## Contract governance

SLA agreements contain versioned rules by service category and Work Order priority. Each rule retains its source clause and acknowledgement, response, attendance, make-safe, rectification, and KPI targets. Draft or AI-proposed rules are never operational. An active Administrator, Supervisor (the Facility Manager-equivalent Pilot role), or Approver must invoke the audited approval operation before a version can attach clocks to new Work Orders.

## Deterministic runtime

Approved effective rules create persisted Work Order deadlines. Database functions calculate elapsed and remaining minutes, the at-risk state at 75 percent consumption, and breach after the rectification deadline. Escalation matrix steps are configurable; processing is idempotent per Work Order and threshold, supports immediate critical-safety escalation, and records acknowledgement in the activity history. These operations continue when AI is disabled.

## Management access and reporting

The SLA dashboard and management report routes are restricted to Administrator, Supervisor, and Approver roles. Technicians cannot read commercial SLA agreements, management clocks, escalation commentary, or report schedules. Reports derive all numbers from RLS-protected FMWorks records and support facility/location, department, and asset filters. JSON provides the on-screen view, CSV is Excel-compatible, and the PDF response is print-ready.

Schedules support daily, weekly, and monthly cadence with recipients, scope, last-run, and next-run state. Until delivery is configured, the durable status is `NOT_CONFIGURED`.

## AI boundary

`FmIntelligenceProvider` defines extraction, staffing analysis, risk explanation, and management summary operations. The production default is disabled and requires no external credentials. The deterministic test adapter returns review-pending extraction proposals and can only narrate structured metrics supplied by FMWorks; it cannot activate an SLA or invent KPI inputs.

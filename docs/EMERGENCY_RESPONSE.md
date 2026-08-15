# Emergency Response Management

## Purpose and boundary

Emergency Response manages life-safety and urgent facility incidents separately from corrective work. It does not add emergency states to the Core Work Order Engine.

`Emergency Incident → Response/Rescue → Situation Safe → Recovery → Linked corrective work order(s)`

## Classification

Initial types: lift entrapment, fire, flood, major water leak, electrical failure, gas leak, chemical spill, medical emergency, security, and other. Severity values are emergency, critical, high, medium, and low.

## Lifecycle

`reported → acknowledged → mobilising → on_site → rescue_in_progress → safe → recovery → closed`

Cancellation is controlled and audited. The default acknowledgement target is five minutes from reporting. Without an approved scheduler, elapsed time and escalation-needed state are calculated when viewed; automatic escalation is not claimed.

## Response roster

The active roster may reference a Technician or maintenance team, with incident-type scope, effective dates, escalation order, and channel preferences. Automatic assignment occurs only when resolution is unambiguous. Otherwise the incident remains active as an unassigned emergency.

Administrators and Supervisors are always emergency recipients. The assigned/on-call Technician or active team members are additional recipients. Administrators manage all roster configuration; Supervisors manage operational roster assignments.

## Notifications

SMS and WhatsApp are independent channels behind the server-only `NotificationProvider`. No configured provider returns `NOT_CONFIGURED` per channel and never invalidates the incident. Durable outbox records store safe delivery metadata only. Email, Teams, and push remain extension channels.

## Authorization

Assigned Technicians and authorized team members may acknowledge and progress their incident. Another Technician may not. Administrators may override operationally; Supervisors manage/close within approved policy; Approvers are view/approval-oriented by default.

## Audit and evidence

Report, assignment, notification attempt/result, acknowledgement, movement, rescue, safe state, recovery, closure, and corrective linkage must be timestamped. Existing protected evidence architecture should be reused; no parallel file-storage design is permitted.

## Dependencies and acceptance

Runtime use requires reviewed migration rollout, roster configuration, isolated authorization testing, and provider/scheduler decisions. See [DATA_MODEL.md](DATA_MODEL.md), [SECURITY.md](SECURITY.md), [SUPERVISOR_GUIDE.md](SUPERVISOR_GUIDE.md), and [TECHNICIAN_GUIDE.md](TECHNICIAN_GUIDE.md).

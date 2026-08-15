# FMWorks UI/UX Benchmark

**Scope:** product-presentation and interaction lessons from IBM Maximo, SAP Asset Management, Planon, Archibus, MaintainX, Limble and UpKeep.

**Evidence caveat:** this is not a pixel-level visual audit. Public pages, documentation and tours were reviewed; no configured competitor tenant was tested. FMWorks’ own browser product review remains pending, so visual conclusions are design requirements rather than proof of current quality.

## Product presentation benchmark

| Product family | Learn from | Do not copy | FMWorks opportunity |
|---|---|---|---|
| Maximo | Role-aware mobile depth; safety, asset history, parts, tools, maps and evidence at point of work | Suite-first navigation and configuration burden | Retain field depth while reducing every screen to the decision and evidence required now |
| SAP EAM | Enterprise process integrity, cost approvals, dispatch and ERP context | ERP vocabulary and dense transactional forms as the default experience | Translate enterprise controls into plain operational language with progressive disclosure |
| Planon | Integrated facility/space context and configurable workplace services | Treating all FM domains as equal top-level destinations | Use space as operational context, not another module silo |
| Archibus | Governed site/building/floor/room plans, plan redlining and work-location linkage | Form/console density and CAD administration in daily operations | Make drawings useful to operators without becoming a CAD tool |
| MaintainX | Clear action orientation, friendly hierarchy, tours, transparent packaging and modern technician framing | Generic manufacturing-CMMS sameness or feature-led homepage copy | Match its learnability; surpass it in engineering status and exception explanation |
| Limble | Technician shortcuts, QR access, offline bookmarking and honest capability documentation | Editable permissions/status flexibility without strong engineering transition semantics | Give technicians even fewer choices, with safer server-controlled transitions |
| UpKeep | Mobile-first packaging, role-specific value and an easy commercial entry point | AI-first positioning without clear evidence/authority boundaries | Make AI subordinate to traceable operational decisions |

## Universal interaction contract

Every operational surface should answer, in order:

1. **What is wrong or changing?**
2. **What is the operational consequence?**
3. **What is physically true?**
4. **What documentation or approval is missing?**
5. **Who owns the next action and by when?**
6. **What can this user safely do now?**

If a screen begins with charts, module navigation or a generic assistant before answering these questions, it is not meeting the FMWorks 30-Second Decision principle.

## Landing and first screen

### Table stakes

- Role-specific scope, facility/site context and data freshness.
- Critical incident and overdue work visibility.
- Assigned-to-me and approval queues.
- Accessible status language; colour is supporting evidence, never the only signal.
- A clear path from summary to the source record.

### FMWorks should do better

The first screen should be an operational briefing, not a reporting dashboard. Recommended hierarchy:

1. active critical incident or safety condition;
2. decisions overdue or awaiting authority;
3. blocked work with consequence and owner;
4. physical/documentation mismatches;
5. readiness trend and upcoming risk;
6. routine workload and historical KPIs.

Each exception card should contain a single primary action and a secondary “inspect evidence” path. Avoid ambiguous KPI cards whose click destination or required response is unclear.

## Work-order detail

### Recommended information architecture

| Layer | Required content |
|---|---|
| Decision header | ID, concise problem, risk/priority, physical state, documentation state, owner, due/SLA |
| Next action | One role-appropriate primary action and a clear reason if action is unavailable |
| Operational context | site/building/floor/zone, asset/system, incident or dependency links |
| Execution | instructions, safety controls, labor, parts/tools, timestamps, before/after/supporting evidence |
| Control | approvals, rejection reason, concession, completion/sign-off requirements |
| History | immutable activity timeline with actor, time, change and source |

### Anti-patterns

- A single overloaded `status` badge representing authorization, execution and readiness.
- Lifecycle actions scattered across tabs or hidden menus.
- Editable actor IDs or lifecycle timestamps.
- A timeline that records activity but cannot explain why the work is blocked.
- Attachments without type, source, capture time, relationship or review state.

## Technician workflow

Modern CMMS products make assigned work, procedures, offline operation, asset history, QR/barcodes, evidence and parts available at the point of work. FMWorks must meet that baseline before claiming superior technician adoption.

The target field sequence is:

`My work → open assignment → safety/context check → start → execute guided steps → record exception if blocked → capture evidence → submit completion`

Design constraints:

- reachable primary controls with one hand on a 390 px phone;
- no managerial dashboards in the critical path;
- save drafts automatically and expose sync state;
- allow camera-first evidence with type and caption defaults;
- show precisely what completion requires before the technician starts;
- support “cannot proceed” as a first-class, blame-free operational outcome;
- never let the client choose actor identity, assignment or lifecycle timestamps;
- preserve a small, useful offline job pack when offline capability is introduced.

## Exception management

Most products can filter overdue or high-priority work. FMWorks should go further by defining an exception as a record that has:

- triggering condition;
- operational consequence;
- affected system/location;
- severity and time exposed;
- accountable owner;
- dependency or missing proof;
- recommended next action;
- authority required;
- resolution evidence.

Exceptions should collapse when routine and expand when consequential. The default sort is consequence, urgency and age—not record creation time.

## Spatial operations

Planon and Archibus establish the benchmark for governed facility hierarchy and floor-plan use. FMWorks should partner for plan authoring and render customer-supplied drawings as an operational layer.

Target hierarchy:

`Customer → Site → Building → Floor / Zone → Layout`

Target overlays:

- systems and assets;
- active work;
- incidents;
- readiness;
- dependencies;
- utilities and fire safety;
- approved concessions.

Spatial UI rules:

- urgent operations remain above the plan on Mission Control;
- plan objects open governed records, not free-form popovers;
- every overlay has a legend, freshness and empty/degraded state;
- mobile shows a compact preview and an explicit “Open Facility View” action;
- no miniature unreadable floor plan and no forced horizontal scrolling;
- a missing drawing never blocks access to the underlying operational record.

## AI assistant

Competitor AI patterns include natural-language analytics, work/procedure generation, manual-derived PM suggestions, recommendations, anomaly detection, scheduling and summarization. FMWorks should not lead with “Ask anything.”

Every Operational Copilot result should show:

| Element | Requirement |
|---|---|
| Finding | concise operational statement |
| Evidence | links to work, incidents, documents, readings or policies |
| Confidence | explicit uncertainty or missing evidence |
| Consequence | what may happen if no action is taken |
| Recommendation | proposed next action, not an autonomous decision |
| Authority | role or named approver required |
| Control | confirm, edit, reject, or open source records |

AI must never approve spend, sign off engineering readiness, invent evidence, silently change status or conceal an unsuccessful delivery attempt.

## Testing and commissioning

Do not re-label a checklist engine as commissioning. A credible experience needs:

- systems and subsystem hierarchy;
- completion boundaries and responsible parties;
- test packs with revision and prerequisites;
- inspection/test points, witness points and hold points;
- calibrated instrument and procedure references;
- recorded results, limits, evidence and signatures;
- punch items and retest cycles;
- dependencies between systems;
- approved concessions with expiry and residual risk;
- handover dossier completeness;
- separate physical completion, documentation completion and operational readiness.

The commissioning first screen should show systems unable to become operational, the exact blocking dependency, evidence missing, authority needed and planned retest—not only percent complete.

## Visual and accessibility standards

### Hierarchy

- One dominant operational message per viewport.
- Use typography and spacing before colour or borders.
- Reserve red for incident/critical consequence, amber for attention, orange for dependency/waiting, blue for active work, green for verified healthy/operational and purple for approved concession.
- Never use green for “submitted” or “documentation complete” if physical readiness is unknown.

### Density

- Desktop may use compact tables for coordination, with a persistent detail panel.
- Tablet must preserve decision order and touch targets.
- Mobile turns multi-column panels into task sequences; secondary analytics collapse.
- Empty states explain whether the cause is no data, permissions, filters, unavailable service or incomplete configuration.

### Accessibility

- Minimum 44×44 px touch targets for field actions.
- Visible keyboard focus and logical heading order.
- Text equivalents for every icon and status colour.
- Sufficient contrast in light and dark themes.
- Live updates announced without stealing focus.
- Error summaries linked to the invalid field; captured evidence remains recoverable after failure.
- Avoid motion as the only emergency indicator and respect reduced-motion preferences.

## Product-review gates

Before declaring commercial polish, validate with a real browser at 1440 px, 1280 px, tablet landscape/portrait and 390 px mobile, in light and dark themes, for administrator, supervisor and technician roles. Include emergency, normal, empty and degraded scenarios.

Pass conditions:

- an Operations Manager identifies the most important issue in under 30 seconds;
- a technician can start or report a blocker without training;
- the screen distinguishes engineering status, documentation status, readiness and dependencies;
- no important action depends only on colour or hover;
- every displayed claim traces to a persisted record;
- the demo can honestly explain what is implemented, pending and planned.

## Evidence register

- IBM: [Maximo Mobile](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=overview-maximo-mobile), [field service](https://www.ibm.com/products/maximo/field-service-management)
- SAP: [Asset Management](https://www.sap.com/products/erp/s4hana/features/asset-management.html), [mobile functional overview](https://help.sap.com/docs/SAP_ASSET_MANAGER/f15c174c3c3647088d38fb220e42c006/1240293b85724e2aa9f259a9e1a5b4d1.html)
- Planon: [Workplace App and floor plans](https://planonsoftware.com/us/news/planon-launches-enhanced-workplace-app/)
- Archibus: [OnSite](https://help.archibus.com/user_en/Subsystems/webc/Content/onsite/overview.htm), [redlining](https://help.archibus.com/user_en/Subsystems/webc/Content/web_user/on_demand/console/redline_console.htm)
- MaintainX: [product](https://www.getmaintainx.com/), [pricing and features](https://www.getmaintainx.com/pricing)
- Limble: [mobile](https://help.limblecmms.com/en/articles/11698403-using-the-new-limble-mobile-app), [navigation](https://help.limblecmms.com/en/articles/7157630-limble-overview-navigation)
- UpKeep: [CMMS](https://upkeep.com/product/cmms-software/)

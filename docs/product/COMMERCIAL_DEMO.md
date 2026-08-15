# FMWorks Operations Control — 10-Minute Sales Demo

## Objective

Demonstrate the Single-Site Launch Package through one connected operational story: detect an issue, establish consequence, make a decision, assign controlled work, record field action and evidence, preserve approval/documentation status, resolve the operational exception and inspect its audit history.

The demo is not a feature tour. It should make a Facilities Director want a scoped follow-up while making implementation status and limitations unmistakable.

## Preconditions

- Use a real browser and the actual application; never fabricate screenshots or interactions.
- Verify deployed migrations, roles and providers before the session.
- Use clearly labelled fictional data: **Northstar Tower – Demonstration Environment**.
- Prepare Administrator, Supervisor and Technician demo identities with only their intended permissions.
- Seed both a normal-operations state and one emergency scenario.
- If notification delivery is unconfigured, show “queued” or “provider not configured,” never “sent.”
- If technician completion/evidence remains migration pending, omit the live transition and explain the planned controlled review; do not simulate persistence.
- Do not run the commercial version of this demo until evidence is deployed and verified; before then, use the script only for internal product review.
- Keep a tested reset procedure and a static backup narrative, but do not substitute slides for the working product.

## Scenario

A chilled-water pump serving a critical occupied zone shows a leak and abnormal vibration. A supervisor must identify the operational consequence, declare/coordinate an incident, assign an inspection work order, understand a waiting dependency, and review the record. The site remains partially operational under an explicitly recorded control; this is not presented as resolved merely because documentation was submitted.

## Run of show

| Time | Role / view | Demonstration | Buyer message |
|---:|---|---|---|
| 0:00–0:45 | Narrator | State the problem and product boundary | “FMWorks tells an operations team what requires intervention, why, who owns it and what proof is missing.” |
| 0:45–2:00 | Supervisor / Mission Control | Open on the critical exception; show incident, consequence, elapsed time, owner and next action | The first screen is a decision surface, not a tile wall |
| 2:00–3:15 | Supervisor / Incident Command | Open the pump incident, establish command/assignment and link the affected work | Incident response and maintenance remain distinct records with a connected operational chain |
| 3:15–4:30 | Supervisor / Operations Workspace | Filter to unassigned/blocked work, assign the inspection and show workload/context | Coordination is role-controlled and focused on exceptions |
| 4:30–5:45 | Technician / assigned work | Open only the assigned job; show site/system context, instructions and permitted action | The technician sees the work needed, not the management system |
| 5:45–6:45 | Technician / blocker or evidence | Record that isolation approval is required, or perform reviewed evidence flow if deployed | “Cannot proceed safely” is a useful operational result, not hidden failure |
| 6:45–7:45 | Supervisor / review | Show the blocker, physical state versus documentation state, dependency and owner | Submission does not equal completion or readiness |
| 7:45–8:30 | Facility Overview | Locate the affected zone on the labelled sample/customer plan and describe future overlays | Spatial context supports the decision; FMWorks is not pretending to author BIM/GIS |
| 8:30–9:15 | Administrator / audit | Show role boundaries and the activity history for material actions | Decisions are attributable and reviewable |
| 9:15–10:00 | Narrator / close | Return to Mission Control; show resolution, audit trail and the next exception | One connected loop, then introduce the Single-Site Launch Package |

## Narration guide

### Opening

“Most facility teams do not lack data. They lack one operational view of what is physically true, what is documented, what is safe to operate and what decision is overdue. FMWorks is designed around that gap.”

### Mission Control

Ask the buyer to identify the highest-priority issue before pointing at it. If they cannot do so within 30 seconds, record the failure; do not coach around it.

Explain:

- why this item is first;
- the operational consequence;
- current ownership;
- the decision available to this role;
- data freshness and degraded-state behavior.

### Incident and work

Show that the incident is not merely a red work order. The incident captures command and operational response; linked work captures controlled remediation. Demonstrate that an unauthorized role cannot take a privileged action.

### Technician

The technician story should take fewer words than the supervisor story. Confirm assignment, safety/context, immediate action and completion/blocker requirements. Do not navigate through administration or broad dashboards.

### Reality, documentation and readiness

Use precise language:

- **Physical state:** what has actually happened at the equipment/system.
- **Documentation state:** what evidence or review has been recorded.
- **Operational readiness:** whether the system can be placed or kept in service under approved conditions.
- **Dependency:** the external action/evidence preventing the next state.

Never turn all four into one green status.

### Spatial view

Keep the Facility Overview below urgent decision panels. Label sample content “Sample / Development Layout.” Explain that a future customer supplies a governed site/building/floor/layout source and FMWorks adds operational overlays.

### Close

“FMWorks Operations Control is offered through a fixed-scope Single-Site Launch Package. A controlled pilot can be part of implementation. We measure ownership time, critical-response timing, blocker exposure and audit completeness without asking you to replace ERP, BIM or GIS.”

## What to show and what to disclose

| Show live when verified | Disclose as pending/planned |
|---|---|
| Authentication and role-specific access | Enterprise identity integrations until configured |
| Work-order lifecycle and assignment | PM, asset register and inventory modules |
| Mission Control and Operations Workspace | Production AI assistant |
| Incident workflow when its migration is applied | Any unapplied migration or provider-dependent action |
| Activity history | Formal commissioning and handover |
| Sample/customer facility view | BIM/GIS authoring and live positioning |

## Questions to ask the buyer

1. Where does your team currently discover the most consequential operational issue?
2. Which state is hardest to establish: physical completion, documentation, approval or readiness?
3. What commonly prevents technicians from completing work safely on the first visit?
4. Which systems must remain authoritative—ERP, BMS, BIM, GIS, identity or an existing CMMS?
5. What measurable outcome would justify a single-site pilot?

## Demo failure handling

- **No data:** explain required configuration and switch only to a pre-tested fictional scenario.
- **Provider unavailable:** show truthful queued/failed state; never claim delivery.
- **Permission denial:** use it to explain the boundary if expected; otherwise record as a defect.
- **Slow or failed page:** acknowledge it, preserve the record and move to the next connected view. Do not invent an outcome.
- **Browser unavailable:** stop visual review and record “Browser rendering environment unavailable; not an application defect.”
- **Migration mismatch:** stop that workflow. Never run SQL during a commercial demo.

## Commercial qualification gate

After the demo, qualify the opportunity only if:

- the buyer’s problem fits exception-led operations;
- required current capabilities were demonstrated rather than promised;
- exclusions are acceptable;
- one site and accountable sponsor are available;
- success can be measured within a bounded pilot;
- security, data and integration discovery can occur before production use.

## Review scorecard

| Test | Pass condition |
|---|---|
| Commercial | Facilities Director requests a scoped follow-up demonstration/pilot discussion |
| Engineering | Operations Manager identifies the most important issue and correct next action within 30 seconds |
| Reality | Screen distinguishes physical, documentation, readiness and dependency state |
| Technician | Assigned user reaches the safe next action without coaching |
| Trust | Every mutation persists, every important claim is traceable, and unavailable delivery is not called sent |
| Differentiation | Buyer can repeat the exception/readiness proposition without describing FMWorks as “another CMMS” |

## Required authentic screenshots

The landing page and sales material require real application captures—never mock or fabricated UI—covering:

- Mission Control in normal, emergency and degraded states;
- Operations Workspace with a meaningful blocker;
- work-order decision header and audit history;
- technician My Work and evidence capture at 390 px;
- Incident Command Centre and roster context;
- Facility Overview labelled with its true customer/sample state;
- light and dark desktop views plus tablet and mobile;
- Administrator, Supervisor and Technician roles.

## Landing-page narrative

`Hero → operational problem → Manage by Exception → Mission Control → Operations → Technician Experience → Incident Command → Engineering Reality → Facility Context → Evidence/Audit → implementation → call to action`

The hero promise is: **See what needs attention. Understand what is blocking progress. Know who needs to act and what should happen next.** The call to action is **Book an Operations Control demonstration**, subject to authentic demo readiness.

## Related documents

- [First Commercial Package](FIRST_COMMERCIAL_PACKAGE.md)
- [FMWorks Differentiation](FMWORKS_DIFFERENTIATION.md)
- [UI/UX Benchmark](UI_UX_BENCHMARK.md)
- [Operations Control Product](OPERATIONS_CONTROL_PRODUCT.md)
- [Commercial Readiness Scorecard](COMMERCIAL_READINESS_SCORECARD.md)

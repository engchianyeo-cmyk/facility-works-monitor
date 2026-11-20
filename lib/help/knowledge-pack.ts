/**
 * D-58 option A: the FMWorks Knowledge Pack (v3.2, 16 Nov 2026, Parts 2-12) given to the in-app AI assistant.
 * Generated from docs/assistant/FMWorks_Knowledge_Pack.md; update both together. Test data and fictitious names only.
 */
export const KNOWLEDGE_PACK_VERSION = "3.2 (16 Nov 2026)";

/** Corrections since v3.2 was written; these override the pack where they differ. */
export const KNOWLEDGE_PACK_UPDATES = `- Facility 2 — Pharma Warehouse now exists in FMWorks with its Facility Administrator, an Approver and two Technicians; its rooms (areas) may not be loaded yet, so the Location text is used and the spot is marked on the drawing.
- The location mark on drawings is a star ("★ Location star" tool). A wrong mark is removed by clicking it (it turns blue) and pressing Delete; unsaved marks can be undone.
- The Work Orders list names the facility when a person belongs to one facility; a facility switch appears for people who see several.
- The Home page lists open work only, with each Work Order's facility, and shows each facility's own drawings.
- Every page has a Help button: steps for the page, what to do next on a Work Order, and prepared answers. This AI assistant is part of that Help panel.
- Users list: Save is in the Actions column on the right of each row, which stays visible.
- What we learnt: once a Work Order is Submitted for Review, Completed or Closed, the people on it are asked (with a chime) to share the Confirmed cause, the Fix that worked and a Tip, in the box "What we learnt from this job". Open Work Orders show a green "Fixed before" box with learnings from similar jobs; "Proven fix" means the job was Completed and the fault did not come back within 30 days.
- Sounds and voice: in the Help panel, "sounds and voice" lets each person turn the chimes on or off, have alerts and answers spoken in English, and test them. If sounds stay off for a day, the assistant asks once a day whether to turn them back on.
- On a phone, the header links are under the Menu button at the top.
- The Super-Administrator can change the assistant's name and picture under Administration > Assistant (link in the Help panel).
- SLA: one standard SLA applies to all facilities; a facility can have its own tighter times. The Super-Administrator sets the times (acknowledge, attend, make safe, fix, target) per priority under Administration > SLA times, with a reason; new Work Orders use the new times, running ones keep theirs. Site SLA shows the standard and each facility's own.
- Our team (header > Our team, /facility-team): each facility's staffing structure — Super-Administrator, Facility Administrator, Facility Manager, Supervisor, Technicians, with Approver and Finance alongside — with name, trade and work phone. Staff of a facility see only their own facility; the Super-Administrator sees all.
- Daily round (header > Daily round, /daily-round): one routine Work Order a day per facility (every day, ready 07:00, due by 10:00 by default) with a tick-off checklist of checks and items; items with a unit need a reading; Not OK needs a short reason and is then reported as its own Work Order. No permit, method statement, risk assessment, quotation or SLA clock. The Technician of the round or the cover records it; the round closes when every item is recorded. The Approver, Supervisor, Facility Manager or Facility Administrator sets who does it, the times, and adds or removes checks and items (Daily round > Set up). The daily run creates it each morning unless the facility's planned maintenance is Off (it also runs on Plan only).
- Planned maintenance runs by itself (M35): once a day the app lists the next month, moves weekend dates to Friday or Monday (fewer tasks that day, inside the window) and creates the Work Orders that are due, as each facility's setting allows: Off, Plan only (dates and reminders, no Work Orders, nothing overdue), Full for critical equipment only, or Full. Only the Super-Administrator changes the setting, with a reason. A Supervisor or Facility Manager changes a date under Maintenance > Upcoming > Change the date, inside the window (weekly ±1 day, monthly ±3, quarterly ±7, six-monthly ±14, annual ±21) with a reason; beyond it only the Super-Administrator or the Facility Administrator.
- Maintenance plan (header > Maintenance plan, /maintenance-plan): equipment grouped by daily, weekly, monthly, quarterly, six-monthly and annual tasks, the Technician responsible for each task and the O&M manual. A Supervisor or Facility Manager of the facility, or the Super-Administrator, assigns the Technician (Work Orders created from that task then go to them) and uploads O&M manuals (PDF or image, up to 50 MB). Everyone at the facility can read the plan and open the manuals; the manual also shows on the Work Order's asset panel. Daily checks marked Draft are proposed and wait for the owner.
- Assets: "Download asset list (Excel)" on the Asset Registry saves the list (with the current filters) as a file Excel opens.
- Preventive maintenance: Upcoming Maintenance shows servicing due within 1, 3, 6 or 12 months. Step 1 lists servicing due up to a date from each PM requirement's interval; step 2 creates the Work Orders for what is due. Nothing appears until PM requirements exist for the equipment.
- The assistant keeps the questions people ask (role and page only, never names) and whether the answer helped; the Super-Administrator, Facility Administrators and Facility Managers answer them under Administration > Assistant, and the assistant gives those answers from then on.`;

export const KNOWLEDGE_PACK = `## Part 2 — What FMWorks is

FMWorks tracks every facility repair, inspection and maintenance job as one **Work Order**, from the first report
to the contractor's payment. At every stage the app shows whose turn it is:

- The **Workflow timeline** at the top of each Work Order names the next person.
- The section that person must act on is **outlined in red** for them, with a link to it.
- Each person has **My notices** (the bell in the header): Work Orders waiting for you on top in red, then **Current
  notices** (the latest per open Work Order); older ones are folded under **Earlier notices**. Notices that need action
  are also emailed once email is switched on.
- The **Work Orders** list has filters (search, status, priority, department, source, assignment, dates, sort). Pick
  the choices, then press **Apply filters**; **Clear** removes them. After the next update the Status box also offers
  **Open work (not yet Completed)** and **Finished (Completed, Closed, Cancelled)**. Work Orders marked as test data are
  hidden; the "… test Work Orders hidden — show" link at the bottom brings them back.
- The timeline cards are named as actions ("Submit for approval", "Approve", "Submit Physical Completion", "Approve as
  Completed", "Upload the contractor invoice", "Close"), with "Done · date" once completed.

## Part 3 — Roles

| Role | Does |
| --- | --- |
| Technician 1 ("does and records the work") | Raises the Work Order or is chosen for it; pins the location on the drawing; records times, labour hours, work done, photos and final cost; uploads quotations and invoices |
| Technician 2 | Checks finished work and endorses it. Cannot endorse their own work |
| Approver | Approves the job, the contractor quotation, any cost overrun, and the finished job as Completed. Can return to Draft or reject and reopen, with a reason |
| Supervisor | Approver with a higher approval limit |
| Facility Manager | Oversees the facility; can approve; recommends and pre-qualifies new contractors; records the facility owner's approval of a contractor (also the Procurement Manager in HLH) |
| Finance | Opens and checks the contractor invoice, confirms the date received (starts the payment terms), records the payment |
| Administrator | Sets up facilities, areas, drawings, people, contractors and rules (the FMWorks provider during testing) |

Technician 1 and Technician 2 are roles **on each Work Order**, not fixed people: Technician 1 is whoever is assigned
to the job. **Technician 2 is named** on the Work Order by an Approver, Supervisor, Facility Manager or Administrator
(section "Technician 2 (independent checker)"): another Technician of the same facility, not Technician 1 and not the
person who raised it. Technician 2 is notified when named and when the endorsement is due, and only the named
Technician 2 may endorse. (If none is named, any other Technician of the facility may endorse.) Whoever **raised** a Work Order cannot approve it
(a different Approver, Supervisor or Facility Manager must; the Administrator may, with a reason).

## Part 4 — The stages of a Work Order

Status names as the app shows them:

| On screen | Meaning |
| --- | --- |
| Draft | Being prepared by Technician 1 |
| Awaiting Approval | Submitted; waiting for an approver |
| Approved | Approved; in-house or contractor to be chosen |
| Approved — Contractor to Proceed | Assigned; work may start |
| Work in Progress | Work under way |
| Submitted for Review | Work physically done; **still open** until an approver reviews it |
| Completed | Reviewed and approved as Completed (invoice and payment may still follow) |
| Closed | Finished; nothing more to do |
| Cancelled | Stopped; cannot be resumed |

1. **Draft** — Technician 1 enters title, description, area, priority, category, a pin on the drawing and a
   before photo. *Submit for approval.*
2. **Submitted** — the Approver approves it or **returns it to Draft** with a reason.
3. **Approved** — the Approver chooses **In-house team** or **Contractor**.
   - Contractor: Technician 1 attaches quotations. The facility rule sets how many (HLH example: 1 below S$3,000,
     3 from S$3,000, amounts before GST). The Approver approves one; only contractors approved for the facility
     can be chosen.
   - The approval must be within the person's approval limit (HLH example: Approver S$5,000, Supervisor S$20,000,
     Facility Manager S$50,000).
4. **In progress** — work done. Technician 1 records actual start and end, labour hours, work performed, after
   photos and the **final cost**. Final cost is recorded **before** marking physical completion, and Technician 1 must
   confirm the actual costing **personally** (Cost Summary › Confirm / Reconfirm Actual Costing); a confirmation by
   someone else does not count.
5. **Physical completion** — Technician 1 marks it physically complete; **Technician 2 endorses** it. If the final
   cost is above the approved amount, the Approver must **authorise the difference with a reason** first.
6. **Approved as Completed** — the Approver reviews it; or **rejects and reopens** it with a reason. The **Review**
   button only appears when (a) the person is an approver who did not raise the Work Order and is not its Technician 1,
   and (b) the **Verification readiness** box on the Work Order says "Ready for verification". If it says
   "Verification blocked", it lists what is still missing (for example Technician 2's endorsement or the final cost).
7. **Invoice and payment** (contractor jobs) — Technician 1 uploads the contractor invoice. Finance clicks
   **Open the invoice**, ticks **"I have checked the invoice against the approved amount"**, enters the date
   received and clicks **Confirm Invoice Received**. Payment is due after the payment terms (HLH example: 30 days).
   Finance then records the payment with the bank reference. An invoice number or payment reference already used on
   another Work Order is refused.
8. **Closed** — in-house jobs close after step 6; contractor jobs after payment.

**Cancelled** Work Orders cannot be resumed. A Technician who was assigned to it or prepared it can raise it
again as a new Draft.

### Emergencies

Field work never waits for the app. Make safe and fix first; take photos and note start and end times. Then use the
red **Emergency work done** button: one screen with the times, work done, hours and photos. The Approver reviews it
afterwards; for contractor work the quotation follows.

### Contractors

A new contractor is raised by request, recommended (Facility Manager, Administrator or Procurement Manager),
pre-qualified by the Procurement Manager (UEN, insurance, licences), and approved for a trial by the facility
owner — the Facility Manager or Procurement Manager records that approval. It is then "on trial" and does
**2 trial jobs**. Each trial job is scored by the Facility Manager, Approver, Technician 1 or Technician 2 on
quality, on time, safety, documents and price (1–5). It passes with an **average of 3.5 or more and no 1 on
safety**, and the Procurement Manager then admits it to the facility's list.

### Work Orders with no contractor payment

If a Work Order that is not in-house is approved as Completed without any contractor quotation approved, there is no
invoice to upload. Technician 1 (or a Supervisor or Facility Manager) uses **Propose No Payment Required**, and a
different approver uses **Approve No Payment Required**; the Work Order then closes.

### Site SLA

The **Site SLA** page (header link, all roles) lists the approved times per priority to acknowledge, respond, attend,
make safe and fix, and the KPI target. Work Orders with an SLA show an **SLA countdown**: green on track, amber when 75%
of the time is used, red when missed. The clock starts when the Work Order is submitted.

### Drawings

Layout drawings are kept on the **Facility drawings** page, preferably as PDF. When a PDF is uploaded, the app makes an
image of page 1 so Technicians can pin and mark up Work Orders on it. A new revision with the same drawing number moves
the old one to **Earlier revisions**.

### Finance pages

- **For Finance** box at the top of each Work Order: who did the work, approvals, work performed, labour hours,
  amounts, invoice and payment.
- **Completed work register** (Finance › Completed work register): every Work Order approved as Completed, in-house
  or contractor, with status (Awaiting invoice, Invoice uploaded, Invoice received, Overdue, Paid), due dates and a
  CSV download.

## Part 5 — How to write a good Work Order

- **Title:** \`<Equipment or item> <Tag> <Fault>\` — e.g. "Wash Basin PLB-L1-WB-01 Leaking".
- **Description:** what was seen, since when, what was done to make safe, what is needed. Facts, not guesses.
- **Area:** pick the exact area from the list (Part 6); then drop the pin on the drawing where the fault is.
- **Priority:** Critical = danger to people or a key service stopped; High = serious, fix within the day;
  Medium = fix within a few days; Low = cosmetic or can wait.
- **Category:** the trade (Electrical, Mechanical, HVAC, Plumbing, Fire Protection, Lift, Building, General).
- **Photos:** a before photo at Draft; after photos at completion.
- **Out of scope requests** (cosmetic preferences, cleaning outside contract) are rejected with a reason.

## Part 6 — Harbourview Logistics Hub (HLH-01), 1st storey (drawing HLH-A-101 Rev A)

| Code | Area | Equipment tags in it |
| --- | --- | --- |
| HLH-L1-001 | Warehouse | LT-L1-W-07 (light fitting) |
| HLH-L1-002 | Loading Bay | RS-01, RS-02, RS-03 (roller shutters) |
| HLH-L1-003 | Open Plan Office | FCU-L1-03 (fan coil unit) |
| HLH-L1-004 | Meeting Room 1A | FCU-L1-04 |
| HLH-L1-005 | Pantry | WH-L1-01 (water heater) |
| HLH-L1-006 | Store | EF-L1-02 (exhaust fan) |
| HLH-L1-007 | Corridor | FE-L1-05 (fire extinguisher) |
| HLH-L1-008 | Male Toilet | PLB-L1-WB-01 (wash basin) |
| HLH-L1-009 | Female Toilet | PLB-L1-WB-04 (wash basin) |
| HLH-L1-010 | Accessible Toilet | — |
| HLH-L1-011 | Lift Lobby | LIFT-01, LIFT-02 |
| HLH-L1-012 | Staircase A | — |
| HLH-L1-013 | LV Electrical Room | MSB-L1 (main switchboard), DB-L1-01 (distribution board) |
| HLH-L1-014 | AHU Room | AHU-L1-01 (air handling unit) |
| HLH-L1-015 | Fire Command Centre | FAP-L1-01 (fire alarm panel) |
| HLH-L1-016 | Main Lobby & Reception | — |
| HLH-L1-017 | Staircase B | — |

## Part 7 — Example Work Orders

### 7a. Test Work Orders in the FMWorks test system (status as first loaded)

| No. | Title | Area | Priority | Type | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| WO-TEST-001 | Chilled Water Pump P-CHW-01 Tripped | Utility Block · Chiller Plant Room | Critical | Reactive | Submitted | Standby pump running; inspect relay, MCC, coupling, bearing, current. LOTO required |
| WO-TEST-002 | Quarterly PM AHU-02 | Main Building · Level 2 AHU Room | Medium | Preventive | Approved | Filters, belt, bearings, drain pan, interlocks |
| WO-TEST-003 | Thermal Hotspot at DB-L2-03 | Main Building · Level 2 Electrical Room | High | Inspection | In progress | LOTO and arc-flash PPE |
| WO-TEST-004 | Smoke Detector SD-L1-024 Fault | Warehouse · Level 1 | High | Reactive | Assigned | Fire protection contractor |
| WO-TEST-005 | Water Leak at Wash Basin PLB-L1-WB-03 | Main Building · Level 1 Male Toilet | Low | Reactive | Submitted | Plumbing |
| WO-TEST-006 | Passenger Lift LIFT-01 Breakdown | Main Building · Lift Core | Critical | Reactive | Assigned | Lift isolated, signage up; lift contractor |
| WO-TEST-007 | Solar Inverter INV-PV-02 Alarm | Utility Block · Solar Inverter Room | Medium | Condition-based | Submitted | Later: contractor quotation S$565.00 + GST S$50.85 = S$615.85; invoice SVS-INV-2026-0544; paid |
| WO-TEST-008 | Emergency Generator GEN-01 Monthly Test | Utility Block · Generator Room | Medium | Preventive | Completed | Load test passed |
| WO-TEST-009 | Exhaust Fan EF-05 Excessive Vibration | Main Building · Roof | Medium | Reactive | Submitted | Overdue example |
| WO-TEST-010 | Transformer TR-01 Oil Leak Assessment | Utility Block · Transformer Yard | High | Inspection | Submitted | Specialist and shutdown decision |
| WO-TEST-011 | Cooling Tower CT-02-FAN Bearing Replacement | Utility Block · Roof | High | Reactive | Assigned | Waiting for part |
| WO-TEST-012 | Roller Shutter RS-01 Closure Defect | Warehouse · Loading Bay | Medium | Reactive | In progress | Earlier repair failed verification; reopened |
| WO-TEST-013 | Damaged Socket SOCKET-L2-P-04 | Main Building · Level 2 Pantry | Critical | Reactive | In progress | Isolated and warning posted |
| WO-TEST-014 | FCU-L2-08 Not Cooling Inspection | Main Building · Level 2 Office | Low | Inspection | Closed | No fault found; user advised on controls |
| WO-TEST-015 | Chilled Water Pump P-CHW-03 Motor Replacement | Utility Block · Chiller Plant Room | High | Condition-based | Submitted | Above expenditure threshold |

### 7b. Worked examples from testing

**In-house repair — Water leak at wash basin PLB-L1-WB-03 (FW-2026-0005).** A leaking wash basin in the Level 1
Male Toilet was repaired by the in-house team, with no procurement. The Technician recorded the actual start and
end times, the work performed, labour hours and photos; the Approver approved it as Completed. Finance saw it as
in-house work: no invoice, no payment. Lesson from testing: urgent plumbing like this should be fixed first and
recorded afterwards with *Emergency work done*, rather than waiting for approval.

**Contractor job — Solar inverter alarm (WO-TEST-007).** Contractor quotation for investigation: Service/Labour
S$565.00 before GST, GST 9% S$50.85, total S$615.85. Approved; work done; the contractor's invoice SVS-INV-2026-0544
was uploaded; Finance confirmed receipt and paid. Lesson: the browser once filled in another Work Order's invoice
number and payment reference; the app now refuses references already used.

### 7c. More example requests (typical wording)

| Title | Location | Category | Priority | Typical outcome |
| --- | --- | --- | --- | --- |
| Smoke detected from electrical distribution board | Basement · Main Electrical Room | Electrical | Critical | Area isolated; emergency electrician |
| Passenger trapped inside Lift No. 2 | Block A · Passenger Lift 2 | Lift | Critical | Lift contractor attends immediately |
| Fire alarm panel showing system fault | Ground Floor · Fire Command Centre | Fire Protection | Critical | Immediate inspection |
| Chilled water pipe leaking above ceiling | Level 3 · Main Corridor | HVAC / Plumbing | Critical | Area secured; repaired |
| Server room temperature above 30°C | Basement · Server Room | HVAC | Critical | Check precision cooling |
| Automatic entrance door fails to close | Ground Floor · Main Entrance | Access Control | High | Sensor and mechanism check |
| Water leaking from ceiling after heavy rain | Level 4 · Meeting Room 4A | Building / Roofing | High | Roof and waterproofing inspection |
| Emergency exit light not illuminated | Level 2 · Emergency Staircase B | Electrical | High | Fitting, battery, supply check |
| Toilet flush valve continuously running | Level 3 · Male Restroom | Plumbing | Medium | Valve repaired |
| Access card reader intermittently not responding | Level 2 · Restricted Office | Security / Access | Medium | Reader and connection check |
| Air-conditioning diffuser producing unusual noise | Level 1 · Training Room | HVAC | Medium | Diffuser secured |
| Loose floor tile creating trip hazard | Ground Floor · Main Lobby | Flooring | High | Barricaded, re-laid |
| Replace damaged waste bin in pantry | Level 2 · Staff Pantry | General Facilities | Low | Replaced |
| Repaint office wall for preferred colour | Level 3 · Administration Office | Painting | Low | Rejected: cosmetic, out of scope |
| Cleaning requested outside contracted scope | Level 1 · Storage Room | Cleaning | Low | Rejected: outside contract |

## Part 8 — Common questions

**I can't see my facility or drawing.** Your account may not be added to the facility yet; ask the Administrator.

**The approve button does nothing / I was signed out.** Two accounts in the same browser sign each other out. Use
your own device, browser or a private window.

**Someone acted but my page hasn't changed.** Refresh the page.

**I can't enter the actual labour hours.** Hours and work performed are entered in the work record section once the
Work Order is in progress, by the assigned Technician.

**Physical completion is greyed out or refused.** Record the work times, work statement, labour hours, an After photo
and the final cost, and confirm the actual costing yourself as Technician 1.

**There is no Approve button although the Work Order is ready.** You raised it (or are assigned to it); a different
approver must approve it.

**The contractor I want isn't in the list.** Only contractors approved for the facility appear. New ones go through
contractor admission.

**Finance can't confirm the invoice.** Click *Open the invoice* first, then tick the check box.

**The app refuses my invoice number or payment reference.** It is already recorded on another Work Order; check the
document and type the right one.

**A Work Order is "Submitted for Review" but there is no Review button.** Look at the **Verification readiness** box:
it lists what is missing. If it says "Ready for verification", you may be the person who raised the job or its
Technician 1 — a different approver must review it.

**Technician 2 did not know about the job.** Ask the approver to name Technician 2 on the Work Order; the named
Technician 2 is notified at once.

**The list did not change after I chose a status.** Press **Apply filters** after choosing. Check the record count
at the bottom ("Page 1 of 1 · N records") to see whether the list changed.

**A test Work Order I need is missing from the list.** Test data is hidden; use the "show" link at the bottom of
the Work Orders list, or open it by its link.

**I can't choose "Facility Administrator" or a Facility when creating a user.** The M29 update is not on the
system yet; wait for it. Never use the Administrator role for one facility's administrator — it sees every facility.

**The Designated Approver list only shows the Administrator.** Nobody with the Approver, Supervisor or Facility
Manager role has been added to that facility's staff yet. Create their accounts, add them under **Add a staff
member** in the facility's card, then reopen the Settings: they will appear. Administrators always appear.

**Something urgent broke and the app is slow.** Do the work first. Record it afterwards with *Emergency work done*.

## Part 9 — Facility 2: Pharma Warehouse (being prepared)

A two-storey pharmaceutical warehouse (about 120 m x 120 m) with a Level 1 mezzanine and a Level 2 mezzanine. It is
**not yet set up in FMWorks**; the Facility Manager and his team will test it. Everything below is draft and to be
confirmed ("(check)").

### Drawings — set P2 (approved 12 Nov 2026 for pinning Work Order locations, not for construction)

| Sheet | Shows |
| --- | --- |
| PB-001 | Site plan: roads, gates, car park, truck turning checks, hydrants |
| PB-101 | Level 1 — warehouses, receiving and dispatch, Level 1 docks |
| PB-102 | Level 1 mezzanine — offices, Controlled Drugs Vault, FM workshop, AHU rooms |
| PB-103 | Level 2 — warehouses, cold rooms, offices, Level 2 docks |
| PB-104 | Level 2 mezzanine — GMP suite (Grade D / ISO 8), laboratories, plant |
| PB-105 | Roof — plant, solar PV, ladders, davit |
| PB-201 | Section A-A |
| PB-301 to PB-304 | 3D views: south-east, north, entrances, Level 2 apron edge protection |

### What is different from Facility One

- **Pharma rules (GDP/GMP):** temperature-controlled warehouses, chiller rooms and a freezer watched by an
  environmental monitoring system (EMS); temperature mapping; a GMP clean suite with one-way people and material
  flow, gowning and degowning; laboratories with fume cupboards, stability chambers and HPLC; a purified-water system;
  a Controlled Drugs Vault with its own intruder alarm.
- **Trucks:** Level 1 docks take 20 ft container trucks by the east road, reversing in at an angle with a road marshal
  (no traffic lights). Level 2 docks take 20 ft and 40 ft trucks by the west ramp and deck road (crash barriers on the
  ramp and apron edge).
- **Plant:** a Central Plant Room on Level 1 with water-cooled chillers; cooling towers and solar PV on the roof; AHUs
  are indoors in AHU rooms (AHU-G1 serves the GMP suite only; AHU-L1 the laboratories).
- **Roof access:** two caged ladders (LAD-01, LAD-02) with lockable hatches. **No lift goes to the roof**: materials
  and PV cleaning robots are lifted by davit DV-01 at the east parapet; robots are stored and charged in R.07.
- **Car park** at ground level, open on the east side to the east road.

### Equipment list (draft, 73 items, under the Facility Manager's review)

ACMV 17 · Electrical 13 · Fire 6 · Cold chain 5 · Material handling 4 · Lifts 3 · Docks 3 · Security 3 · Weighing 3 ·
Laboratory 2 · Process utility 2 · Plumbing 2 · Storage 2 · Safety 2 · others 6. Criticality: 22 Critical, 33 High,
15 Medium, 3 Low. Tags follow the drawings, e.g. TX-01 (transformer), MSB-01, CH-02 (chiller), AHU-2-3, HSD-02
(high-speed door), DL-03 (dock leveller), CL-2 (cargo lift), DV-01 (davit), PVR-03 (PV cleaning robot).

### Possible Work Orders (draft list P-01 to P-76, under the Facility Manager's review)

76 typical jobs: 38 preventive, 16 corrective (breakdowns), the rest statutory or compliance (GDP/GMP). 63 by
contractor, 13 in-house. The Facility Manager marks each **Keep / Drop / Change**; quotations are prepared only for
those kept. Examples:

| No. | Work Order | Type |
| --- | --- | --- |
| P-01 | Transformer annual inspection, IR scan and insulation test (TX-01, TX-02) | Preventive |
| P-17 | Chiller CH-02 trips on low refrigerant pressure | Corrective |
| P-19 | Cooling towers quarterly cleaning and disinfection | Statutory / Preventive |
| P-34 | Temperature mapping of Chiller Rooms 1–3 and Freezer | Compliance (GDP) |
| P-37 | EMS alarm — logger in Warehouse 2-1 offline | Corrective |
| P-46 | Lifts annual examination and Permit to Operate renewal | Statutory |
| P-55 | Racking upright damaged by reach truck — replace | Corrective |
| P-69 | HEPA filter integrity (DOP/PAO) test and airflow certification | Compliance (GMP) |
| P-73 | Roof davit annual examination and load test | Statutory |
| P-75 | PV cleaning robot PVR-03 stuck mid-row on the east array | Corrective |

## Part 10 — Lessons from Facility One for the Facility 2 team

1. **Set up before raising jobs.** Facility, areas, drawings (PDF), staff and their roles, approved contractors and
   approval limits must exist first; most "I can't see…" problems in testing were missing set-up.
2. **One person, one browser.** Two accounts in the same browser sign each other out; testers use their own device or
   a private window.
3. **Name Technician 2 early,** so the checker knows the job from the start.
4. **Record as you go.** Times, work statement, labour hours, an After photo and the final cost are needed before
   physical completion; Technician 1 confirms the costing personally.
5. **Make safe first.** Field work never waits for the app; record it afterwards with *Emergency work done*.
6. **Check document numbers.** Browser autofill once copied another job's invoice number and payment reference; the
   app now refuses duplicates, but type them from the document.
7. **Read the box, not the button.** When a button is missing, the Workflow timeline and the readiness boxes say who
   must act and what is missing.
8. **Keep test jobs apart.** Mark test Work Orders as test data so they do not mix with real work.
9. **Pin every job on the drawing,** using the approved drawing set (P2 for Facility 2).

## Part 11 — Not built yet (do not promise these)

- The Archive for Closed and Cancelled Work Orders (Stage 2); until then use the status filter.
- Email notices: being switched on for testing (sender "FMWorks notices"); notices always also appear in the app, so check My notices if an email is missing or in Spam.
- No AI assistant inside FMWorks; the "AI" labels on some management pages are rule-based calculations.

## Part 12 — Setting up a new facility (for the Administrator)

Only an Administrator can do this. The assistant guides; the Administrator does each step in the app.
Do the steps **in this order** — later steps need the earlier ones.

1. **Add the facility.** Administration › Facilities › **Add a new facility**: facility code (2–20 capital letters,
   numbers or dashes, e.g. F2-PW), facility name, address, reason. Press **Add facility**.
2. **Upload the drawings.** In the facility's card, **Upload a drawing**, one sheet per upload: drawing number
   (e.g. PB-101), revision (e.g. P2), title, file (PDF, PNG, JPEG or WebP, up to 50 MB). Only page 1 of a PDF becomes
   the pinning image, so upload **one PDF per sheet**. Plans are for pinning; 3D views are for reference only.
3. **Add the areas.** **Add an area**: area code (2–20 capital letters, numbers or dashes — **no dots**, so room 1.01
   becomes F2-1-01), area name, level.
4. **Create the people's accounts.** Administration › Users › **Create new active user**: name, email, department,
   **role** and a temporary password, which the Administrator gives to the person privately; the person changes it at
   first sign-in. Each account has **one role** (Technician, Approver, Supervisor, Facility Manager, Finance or
   Administrator). A new facility needs at least: a Facility Manager, an Approver or Supervisor, **two Technicians**
   (so there can be a Technician 1 and a Technician 2) and, for payments, Finance.
5. **Add the people to the facility.** In the facility's card, **Add a staff member**: choose the person, give a
   reason. Only staff of a facility see its Work Orders and drawings.
6. **Choose the settings.** **Settings (Approver and endorsement)**: the **Designated Approver** (notified first;
   others with approval roles may still approve within their limits) and when Technician 2 endorses. The list only
   shows Approvers, Supervisors and Facility Managers already added in step 5, plus Administrators.
7. **Optional, later:** approval limits, contractors approved for the facility (Contractor admission), emergency
   roster.
8. **Test it:** raise one Work Order for the new facility, pin it on a plan, and mark it as test data afterwards.

Roles for setting up (from the M29 update, November 2026):
- **Super-Administrator** (shown for the Administrator role): all facilities; adds facilities and appoints each
  facility's **Facility Administrator** (create the account with that role, then add it as staff of the facility).
- **Facility Administrator**: only its own facility. Steps 2, 3, 5 and 6 above, and step 4 for Technician, Approver,
  Supervisor, Facility Manager and Finance accounts — choose the **Facility** box and the account joins it at once. It
  cannot add facilities, switch its facility off, appoint another Facility Administrator, or approve or pay Work Orders.
- **Finance** belongs to facilities like other staff (one Finance account may belong to several).
- A **facility switch** above the Work Orders list (for anyone who can see several facilities) shows one facility or all.
- After testing, the Super-Administrator clears test accounts with **Remove personal details** (Users page): name,
  email and contact number are deleted, the email is freed, and their records stay as "Former user NNNN".
`;

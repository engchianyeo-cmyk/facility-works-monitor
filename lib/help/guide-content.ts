/**
 * D-58 (16 Nov 2026): the built-in Help guide ("option B"). Prepared answers drawn from the FMWorks knowledge pack
 * (v3.2). No AI service is called; the same content is meant to feed the optional AI assistant later ("option A").
 * Keep the wording plain and in the app's own button names.
 */
import type { UserRole } from "@/lib/auth";

export type HelpAudience = UserRole | "all";

const APPROVERS: readonly UserRole[] = ["approver", "supervisor", "facility_manager", "administrator"];
const SETUP: readonly UserRole[] = ["administrator", "facility_administrator"];

export type PageGuide = {
  id: string;
  /** Path prefixes this guide covers; the longest matching prefix wins. */
  paths: readonly string[];
  title: string;
  intro: string;
  /** Steps for a role; "all" is used when the role has none of its own. */
  steps: Partial<Record<HelpAudience, readonly string[]>>;
  related?: readonly string[];
  /** When a role has its own steps, show only those (the "all" text is for everyone else). */
  roleStepsOnly?: boolean;
};

export type Faq = {
  id: string;
  question: string;
  answer: string;
  keywords: readonly string[];
  /** Shown first to these roles; everyone can still find it by searching. */
  roles?: readonly UserRole[];
};

export type StageGuide = {
  label: string;
  meaning: string;
  technician: string;
  approver: string;
  finance?: string;
  other: string;
};

export const PAGE_GUIDES: readonly PageGuide[] = [
  {
    id: "home",
    paths: ["/"],
    title: "Home",
    intro: "Your starting page. The header links take you to each part of FMWorks.",
    steps: {
      technician: [
        "Press + New Work Order to report a fault or a job.",
        "My Drafts lists Work Orders you have started but not submitted.",
        "Work already done in an emergency? Press the red Emergency work done button.",
        "Notices (the bell) shows Work Orders waiting for you, in red at the top.",
      ],
      approver: ["Open Notices to see Work Orders waiting for your approval or review.", "Work Orders lists everything at your facility; use the filters, then Apply filters."],
      finance: ["Open Finance › Completed work register for invoices to check and payments due.", "Notices shows invoices waiting for you."],
      facility_administrator: ["Users: create accounts for your facility's staff.", "My Facility: drawings, areas, staff and the Designated Approver."],
      administrator: ["Administration › Facilities to set up or change a facility.", "Administration › Users to create accounts and give roles."],
      all: ["Use Work Orders to find a job, and Notices to see what is waiting for you."],
    },
    related: ["two-accounts", "cant-see-facility"],
  },
  {
    id: "work-orders",
    paths: ["/work-orders", "/works"],
    title: "Work Orders list",
    intro: "Every Work Order you are allowed to see at your facility. Closed and Cancelled ones are hidden unless you choose them.",
    steps: {
      all: [
        "Type in the search box or choose a status, priority or date, then press Apply filters. Clear removes the filters.",
        "Status \"Open work\" = not yet Completed; \"Finished\" = Completed, Closed and Cancelled.",
        "The line at the bottom (Page 1 of 1 · N records) tells you how many were found.",
        "Click a Work Order's number to open it. The Workflow timeline at the top says whose turn it is.",
      ],
      technician: [
        "Start a new job with + New Work Order in the header.",
        "Filter Assignment = Mine to see only your jobs.",
        "An empty list for a new facility is normal until the first Work Order is created.",
      ],
    },
    related: ["filter-no-change", "test-hidden", "cant-see-facility"],
  },
  {
    id: "new-work-order",
    paths: ["/work-orders/new", "/works/new"],
    title: "New Work Order",
    intro: "You create the Work Order as a Draft first. Photos, the pin on the drawing and quotations are added after the Draft is created.",
    steps: {
      all: [
        "Title: <equipment> <tag> <fault>, for example \"Freezer unit RU-FZ-B high head-pressure trip\".",
        "Reason the work is needed: what you saw, since when, what you did to make it safe, what is needed. Facts, not guesses.",
        "Tick In-house services if your own team does the work (no quotation, invoice or payment).",
        "Tick Emergency only if the work must start now without approval.",
        "Choose the Area / room, then check the Location text.",
        "Open More details for priority, category, due date and asset. Priority: Critical = danger or a key service stopped; High = within the day; Medium = within a few days; Low = can wait.",
        "Press Create Draft. Next: add a before photo, pin the location on the drawing and, for contractor work, attach the quotation(s); then Submit for approval.",
      ],
      approver: [
        "You may raise a Work Order when the Technician is unavailable: choose Technician 1 who will do and record the work.",
        "You cannot approve a Work Order you raised yourself; another approver must.",
      ],
    },
    related: ["good-title", "area-missing", "quotations-how-many", "emergency"],
  },
  {
    id: "work-order",
    paths: ["/work-orders/", "/works/"],
    title: "Work Order",
    intro: "The Workflow timeline at the top names the next person. The section that person must act on is outlined in red for them.",
    steps: {
      all: [
        "Read the Workflow timeline: the next card says what must happen and who does it.",
        "If a button you expect is missing, read the readiness boxes: they list what is still missing.",
        "Refresh the page if someone else acted and your page has not changed.",
      ],
    },
    related: ["no-approve-button", "no-review-button", "completion-greyed", "tech2"],
  },
  {
    id: "emergency",
    paths: ["/work-orders/emergency"],
    title: "Emergency work done",
    intro: "For work already done to make safe or fix urgently. Field work never waits for the app.",
    steps: {
      all: [
        "Enter the start and end times, what was done and the labour hours.",
        "Add the photos you took.",
        "Submit. The Approver reviews it afterwards; for contractor work the quotation follows.",
      ],
    },
    related: ["emergency"],
  },
  {
    id: "notices",
    paths: ["/notices"],
    title: "My notices",
    intro: "Work Orders waiting for you are on top in red, then the latest notice for each open Work Order.",
    steps: { all: ["Click a notice to open its Work Order.", "Older notices are under Earlier notices.", "Email copies may land in Spam; the app always has the notice."] },
    related: ["email-missing"],
  },
  {
    id: "finance",
    paths: ["/finance"],
    title: "Finance",
    intro: "Invoices to check and payments to record, for the facilities you belong to.",
    steps: {
      all: [
        "Completed work register: every Work Order approved as Completed, with its invoice and payment status and due dates; CSV download.",
        "On a Work Order, the For Finance box at the top has the approvals, amounts, invoice and payment.",
        "To confirm an invoice: click Open the invoice, tick \"I have checked the invoice against the approved amount\", enter the date received, press Confirm Invoice Received.",
        "Record the payment with the bank reference when paid.",
      ],
    },
    related: ["finance-cant-confirm", "duplicate-reference"],
  },
  {
    id: "drawings",
    paths: ["/drawings"],
    title: "Facility drawings",
    intro: "Layout drawings of your facility. Page 1 of each PDF becomes the image used to pin Work Orders.",
    steps: { all: ["Open a drawing to view it.", "A new revision with the same drawing number moves the old one to Earlier revisions."] },
    related: ["cant-see-facility"],
  },
  {
    id: "sla",
    paths: ["/sla", "/management/sla"],
    title: "Site SLA",
    intro: "The approved times per priority to acknowledge, respond, attend, make safe and fix.",
    steps: { all: ["Work Orders with an SLA show a countdown: green on track, amber at 75 % of the time, red when missed.", "The clock starts when the Work Order is submitted."] },
  },
  {
    id: "operations",
    paths: ["/operations"],
    title: "Operations",
    intro: "Your field view: jobs assigned to you and what needs doing next.",
    steps: { all: ["Open a job to record times, work done, labour hours, photos and the final cost as you go.", "Use + New Work Order for a new fault."] },
    related: ["completion-greyed"],
  },
  {
    id: "users",
    paths: ["/administration/users"],
    title: "Users",
    intro: "Create accounts, change roles and switch accounts on or off.",
    steps: {
      administrator: [
        "Create new active user: name, email, department, role and a temporary password (at least 12 characters). Give the password privately; the person changes it at first sign-in.",
        "For facility staff, choose the Facility box so the account joins that facility at once.",
        "To change someone, edit the row and press Save in the Actions column (right-hand side).",
        "After testing, Remove personal details clears a tester's name and email but keeps the records as \"Former user NNNN\".",
      ],
      facility_administrator: [
        "You can create Technician, Approver, Supervisor, Facility Manager and Finance accounts for your own facility.",
        "Choose your facility in the Facility box; the account joins it at once.",
        "Technicians need a trade (for example Electrical or Mechanical).",
        "To change someone, edit the row and press Save in the Actions column.",
      ],
      all: ["Only an Administrator or Facility Administrator manages accounts."],
    },
    related: ["save-hidden", "one-role", "remove-personal", "designated-approver"],
    roleStepsOnly: true,
  },
  {
    id: "facilities",
    paths: ["/administration/facilities"],
    title: "Facilities",
    intro: "Set up a facility in this order: drawings, areas, staff, then settings.",
    steps: {
      administrator: [
        "Add a new facility: code (capital letters, numbers, dashes), name, address, reason.",
        "Upload a drawing: one PDF per sheet, with drawing number and revision.",
        "Add an area: code without dots (room 1.01 becomes F2-1-01), name, level.",
        "Add a staff member: each person who works there, with their role at the facility.",
        "Settings: choose the Designated Approver and when Technician 2 endorses.",
        "Test it: raise one Work Order and mark it as test data afterwards.",
      ],
      facility_administrator: [
        "You manage your own facility only: drawings, areas, staff and settings.",
        "Add a staff member for each person, then choose the Designated Approver in Settings.",
      ],
      all: ["Only an Administrator or Facility Administrator changes facilities."],
    },
    related: ["designated-approver", "setup-order", "area-codes"],
    roleStepsOnly: true,
  },
  {
    id: "incidents",
    paths: ["/incidents"],
    title: "Emergency incidents",
    intro: "The Incident Operations Board: emergencies happening now (fire, flood, lift entrapment, gas leak and so on) and how the response is going. An incident is for the response; the repair afterwards is a Work Order.",
    steps: {
      all: [
        "Press Report emergency to start a response for something happening now.",
        "Red cards are unacknowledged: the on-call responder must acknowledge before the deadline.",
        "Open an incident to see its phase, responder, timeline and linked corrective Work Orders.",
      ],
    },
    related: ["incident-what", "incident-vs-work-order", "incident-steps"],
  },
  {
    id: "incident-new",
    paths: ["/incidents/new"],
    title: "Report Emergency Incident",
    intro: "Activates an emergency response at once and alerts the on-call responders. Make people safe and call 995 or site security first if lives are at risk.",
    steps: {
      all: [
        "Choose the Incident type (for example Fire, Flood, Lift entrapment, Gas leak, Electrical failure).",
        "Choose the Severity: Emergency or Critical for danger to people or a key service stopped.",
        "Type the exact Location and, if known, the affected Asset.",
        "Under What is happening?, say what you see, who is affected and what has been done so far.",
        "Press Report emergency incident. The incident appears on the board and responders are notified.",
      ],
    },
    related: ["incident-what", "incident-vs-work-order", "emergency"],
  },
  {
    id: "incident",
    paths: ["/incidents/"],
    title: "Incident",
    intro: "One emergency and its response. Only the next allowed response step is offered.",
    steps: {
      all: [
        "Current phase shows where the response is: Reported, Acknowledged, Mobilising, On Site, Rescue In Progress, Safe, Recovery, Closed.",
        "Use Response action for the next step (for example Acknowledge, Mobilise, Arrive, Make safe).",
        "Response timeline records who did what and when.",
        "Corrective Work: once safe, create and link a Work Order for the repair.",
      ],
    },
    related: ["incident-steps", "incident-vs-work-order"],
  },
  {
    id: "assets",
    paths: ["/assets"],
    title: "Assets",
    intro: "The equipment register: each asset's tag, type, location and history. Linking a Work Order to its asset lets the team see past faults and fixes.",
    steps: { all: ["Search by tag or name and open an asset to see its Work Orders.", "New asset adds equipment (Administrators and managers)."] },
  },
  {
    id: "maintenance",
    paths: ["/maintenance"],
    title: "Preventive maintenance",
    intro: "Planned servicing (for example quarterly chiller service): what is due and when.",
    steps: { all: ["Open a plan to see its schedule and the Work Orders it created.", "Due servicing becomes a Work Order like any other job."] },
  },
  {
    id: "facility-team",
    paths: ["/facility-team"],
    title: "Our team",
    intro: "Your facility's staffing structure: who is the Facility Administrator, Facility Manager, Supervisor and Technicians, with the Approver and Finance alongside.",
    steps: { all: ["Find a person by role; Tel. numbers can be tapped on a phone.", "To change who is in a role, ask the Facility Administrator (Administration › Users)."] },
  },
  {
    id: "maintenance-plan",
    paths: ["/maintenance-plan"],
    title: "Maintenance plan",
    intro: "Equipment by daily, weekly, monthly, quarterly, six-monthly and annual checks, the Technician responsible for each task, and the O&M manual to cross-reference.",
    steps: {
      all: ["Pick a tab (Daily, Weekly, …) or search for the equipment.", "Open the O&M manual link to read the manufacturer's instructions before the check.", "Tick Only my tasks to see what you are responsible for."],
      supervisor: ["Choose the Technician in the Technician responsible box; new Work Orders from that task go to them.", "Upload O&M manual (PDF) files the manual with the equipment for everyone at the facility."],
      facility_manager: ["Choose the Technician in the Technician responsible box; new Work Orders from that task go to them.", "Upload O&M manual (PDF) files the manual with the equipment."],
      administrator: ["Assign Technicians and file O&M manuals for any facility.", "Daily checks marked Draft are proposed and wait for your decision."],
    },
  },
  {
    id: "assistant-admin",
    paths: ["/administration/assistant"],
    title: "Assistant",
    intro: "Change the assistant's name or picture. Everyone sees the change.",
    steps: { all: ["Type the name, choose a picture (PNG, JPEG, WebP or SVG, up to 300 KB) and press Save.", "Use Ollie again restores the original."] },
  },
  {
    id: "administration",
    paths: ["/administration"],
    title: "Administration",
    intro: "Set-up pages for the Super-Administrator and managers: users, facilities, departments, contractors, approval limits, roster and wording.",
    steps: { all: ["Choose the page from the header menu.", "Changes are recorded with your name and the time."] },
  },
  {
    id: "password",
    paths: ["/account/password"],
    title: "Password",
    intro: "Set a new password of at least 12 characters. New accounts must do this at the first sign-in before anything else opens.",
    steps: { all: ["Type the new password twice and save.", "Never share your password; nobody from FMWorks will ask for it."] },
  },
];

export const STAGE_GUIDES: Readonly<Record<string, StageGuide>> = {
  draft: {
    label: "Draft",
    meaning: "Being prepared by Technician 1.",
    technician: "Add a before photo, pin the location on the drawing and, for contractor work, attach the quotation(s). Then press Submit for approval.",
    approver: "Waiting for Technician 1 to finish and submit. Nothing for you yet unless you raised it.",
    other: "Technician 1 is preparing it.",
  },
  submitted: {
    label: "Awaiting Approval",
    meaning: "Submitted and waiting for an approver.",
    technician: "Wait for the approver. If it is returned to Draft, read the reason, fix it and submit again.",
    approver: "Check the description, location, photo and quotation, then Approve, or Return to Draft with a reason. You cannot approve a Work Order you raised.",
    other: "Waiting for an approver.",
  },
  approved: {
    label: "Approved",
    meaning: "Approved; the in-house team or a contractor is to be chosen.",
    technician: "For contractor work, attach the quotations the facility rule asks for. Then wait for the approver to choose.",
    approver: "Choose In-house team or Contractor. For a contractor, approve one quotation within your approval limit.",
    other: "Waiting for the in-house team or contractor to be chosen.",
  },
  assigned: {
    label: "Approved — Contractor to Proceed",
    meaning: "Assigned; the work may start.",
    technician: "Start the work. Record the actual start time as you go.",
    approver: "Nothing for you until the work is done. Name Technician 2 now if not named yet.",
    other: "The work may start.",
  },
  in_progress: {
    label: "Work in Progress",
    meaning: "Work under way.",
    technician: "Record the start and end times, work performed, labour hours, after photos and the final cost. Confirm the actual costing yourself, then submit physical completion.",
    approver: "If the final cost is above the approved amount, authorise the difference with a reason when asked.",
    other: "Work is under way.",
  },
  completed: {
    label: "Submitted for Review",
    meaning: "Physically done but still open until an approver reviews it.",
    technician: "Technician 2 endorses the work. If the approver rejects and reopens it, read the reason and fix it.",
    approver: "Read the Verification readiness box. When it says Ready for verification, Review the work and Approve as Completed, or reject and reopen with a reason.",
    other: "Waiting for Technician 2's endorsement and the approver's review.",
  },
  reviewed: {
    label: "Completed",
    meaning: "Approved as Completed. For contractor work the invoice and payment follow.",
    technician: "Contractor work: upload the contractor invoice. In-house work: nothing more.",
    approver: "No contractor payment? Approve No Payment Required when proposed.",
    finance: "When the invoice is uploaded: Open the invoice, tick the check box, enter the date received and Confirm Invoice Received; record the payment when paid.",
    other: "Invoice and payment may still follow.",
  },
  closed: { label: "Closed", meaning: "Finished; nothing more to do.", technician: "Nothing more to do.", approver: "Nothing more to do.", other: "Nothing more to do." },
  cancelled: {
    label: "Cancelled",
    meaning: "Stopped; it cannot be resumed.",
    technician: "If the work is still needed, raise it again as a new Draft.",
    approver: "Nothing more to do.",
    other: "Nothing more to do.",
  },
};

export const FAQS: readonly Faq[] = [
  { id: "two-accounts", question: "I was signed out, or a button does nothing.", answer: "Two accounts in the same browser sign each other out. Use your own device, another browser or a private window for each person.", keywords: ["signed out", "logout", "log out", "browser", "private", "incognito", "button nothing"] },
  { id: "cant-see-facility", question: "I can't see my facility, drawing or Work Orders.", answer: "Your account may not be staff of the facility yet. Ask your Facility Administrator or the Super-Administrator to add you under Facilities › Add a staff member. A new facility also has no Work Orders until the first one is created.", keywords: ["facility", "drawing", "empty", "no work orders", "can't see", "cannot see", "missing", "staff"] },
  { id: "first-password", question: "Every page sends me back to sign in.", answer: "A new account must set its own password first. After Sign in, the Set your password page opens; save a new password of at least 12 characters. Also check you are not signed in as someone else in the same browser.", keywords: ["sign in", "login", "password", "first time", "redirect", "back to sign in"] },
  { id: "refresh", question: "Someone acted but my page has not changed.", answer: "Refresh the page (F5).", keywords: ["refresh", "not updated", "changed", "stale"] },
  { id: "filter-no-change", question: "The list did not change after I chose a status.", answer: "Press Apply filters after choosing. The line at the bottom (Page 1 of 1 · N records) shows whether the list changed. Closed and Cancelled are hidden unless you choose them or \"Finished\".", keywords: ["filter", "status", "apply", "closed", "cancelled", "list"] },
  { id: "test-hidden", question: "A test Work Order is missing from the list.", answer: "Test data is hidden. Use the \"… test Work Orders hidden — show\" link at the bottom of the list, or open it by its link.", keywords: ["test", "hidden", "missing", "WO-TEST"] },
  { id: "good-title", question: "How do I write a good Work Order?", answer: "Title: <equipment> <tag> <fault>. Description: what you saw, since when, what you did to make it safe and what is needed. Pick the exact area and pin the spot on the drawing. Add a before photo at Draft and after photos at completion.", keywords: ["write", "title", "description", "good", "how to", "create"] },
  { id: "priority", question: "Which priority should I choose?", answer: "Critical = danger to people or a key service stopped. High = serious, fix within the day. Medium = fix within a few days. Low = cosmetic or can wait.", keywords: ["priority", "critical", "high", "medium", "low", "urgent"] },
  { id: "area-missing", question: "My room is not in the Area list.", answer: "The facility's areas have not been added yet. Type the room in Location, create the Draft, then pin the spot on the drawing. Ask your Facility Administrator to add the area.", keywords: ["area", "room", "location", "list", "missing", "pin"] },
  { id: "quotations-how-many", question: "How many quotations do I need?", answer: "The facility's rule decides, based on the amount before GST. Facility 2 test data uses 1 quotation below S$1,000 and 3 from S$1,000. Attach them to the Draft before submitting, or after approval when the contractor is chosen.", keywords: ["quotation", "quote", "how many", "three", "contractor", "attach"] },
  { id: "emergency", question: "Something urgent broke. What do I do first?", answer: "Make it safe and fix it first; take photos and note the start and end times. Then use the red Emergency work done button to record it. The Approver reviews it afterwards.", keywords: ["emergency", "urgent", "broke", "breakdown", "safe", "now"] },
  { id: "no-approve-button", question: "There is no Approve button although the Work Order is ready.", answer: "You raised it or you are its Technician 1. A different Approver, Supervisor or Facility Manager must approve it.", keywords: ["approve", "button", "missing", "own"], roles: [...APPROVERS] },
  { id: "no-review-button", question: "\"Submitted for Review\" but there is no Review button.", answer: "Read the Verification readiness box: it lists what is missing, such as Technician 2's endorsement or the final cost. If it says Ready for verification, you may be the person who raised the job or its Technician 1; a different approver must review it.", keywords: ["review", "submitted for review", "verification", "readiness", "button"], roles: [...APPROVERS] },
  { id: "completion-greyed", question: "Physical completion is greyed out or refused.", answer: "Record the work times, the work statement, labour hours, an after photo and the final cost, and confirm the actual costing yourself as Technician 1 (Cost Summary › Confirm Actual Costing).", keywords: ["physical completion", "greyed", "refused", "labour", "final cost", "complete"], roles: ["technician"] },
  { id: "labour-hours", question: "I can't enter the labour hours.", answer: "Hours and work performed are entered in the work record section once the Work Order is in progress, by the assigned Technician.", keywords: ["labour", "hours", "work performed", "record"], roles: ["technician"] },
  { id: "tech2", question: "What does Technician 2 do?", answer: "Technician 2 checks the finished work and endorses it. An approver names Technician 2 on the Work Order; it must be another Technician of the facility, not Technician 1. The named Technician 2 is notified.", keywords: ["technician 2", "endorse", "checker", "second technician"] },
  { id: "contractor-missing", question: "The contractor I want is not in the list.", answer: "Only contractors approved for the facility appear. A new contractor goes through contractor admission: recommended, pre-qualified, approved for 2 trial jobs, then admitted.", keywords: ["contractor", "vendor", "missing", "list", "admission"] },
  { id: "finance-cant-confirm", question: "Finance can't confirm the invoice.", answer: "Click Open the invoice first, then tick \"I have checked the invoice against the approved amount\", enter the date received and press Confirm Invoice Received.", keywords: ["invoice", "confirm", "finance", "received"], roles: ["finance"] },
  { id: "duplicate-reference", question: "The app refuses my invoice number or payment reference.", answer: "That number is already recorded on another Work Order. Check the document and type the right one; don't rely on browser autofill.", keywords: ["invoice number", "payment reference", "duplicate", "refused"], roles: ["finance", "technician"] },
  { id: "no-payment", question: "The job is Completed but there is no invoice.", answer: "If no contractor quotation was approved, Technician 1 (or a Supervisor or Facility Manager) uses Propose No Payment Required, and a different approver uses Approve No Payment Required. The Work Order then closes.", keywords: ["no payment", "no invoice", "close", "completed"] },
  { id: "cancelled", question: "Can a Cancelled Work Order be resumed?", answer: "No. If the work is still needed, the Technician who prepared it can raise it again as a new Draft.", keywords: ["cancelled", "resume", "reopen"] },
  { id: "email-missing", question: "I did not receive the email notice.", answer: "Check Spam. Notices always also appear in the app under Notices (the bell).", keywords: ["email", "notice", "spam", "notification"] },
  { id: "one-role", question: "Can one person have two roles?", answer: "Each account has one role. A person who needs two roles uses two accounts with two different email addresses.", keywords: ["role", "two roles", "both"], roles: [...SETUP] },
  { id: "designated-approver", question: "The Designated Approver list only shows the Administrator.", answer: "No Approver, Supervisor or Facility Manager is staff of that facility yet. Create their accounts, add them under Add a staff member, then reopen Settings.", keywords: ["designated approver", "approver list", "settings"], roles: [...SETUP] },
  { id: "setup-order", question: "How do I set up a new facility?", answer: "In this order: add the facility; upload the drawings (one PDF per sheet); add the areas; create the accounts; add each person as staff; choose the Designated Approver in Settings; then raise one test Work Order.", keywords: ["set up", "setup", "new facility", "order", "steps"], roles: [...SETUP] },
  { id: "area-codes", question: "What area code should I use?", answer: "2–20 capital letters, numbers or dashes, no dots. Room 1.01 of Facility 2 becomes F2-1-01.", keywords: ["area code", "code", "dots", "area"], roles: [...SETUP] },
  { id: "remove-personal", question: "How do I remove a tester after testing?", answer: "Super-Administrator: Users › the person's row › Remove personal details. Their name, email and contact number are deleted and the email is freed; their records stay as \"Former user NNNN\".", keywords: ["delete", "remove", "tester", "personal details", "email"], roles: ["administrator"] },
  { id: "save-hidden", question: "I can't find the Save button in the Users list.", answer: "Save is in the Actions column at the right-hand side of each row. If the table is wider than your screen, scroll it sideways.", keywords: ["save", "users", "button", "scroll", "actions"], roles: [...SETUP] },
  { id: "incident-what", question: "What is Report Emergency Incident?", answer: "It starts an emergency response for something happening now — fire, flood, lift entrapment, gas leak, chemical spill, electrical failure, medical or security emergency. It alerts the on-call responders at once and tracks the response on the Incident Operations Board. Make people safe and call 995 or site security first if lives are at risk. The repair afterwards is done through a Work Order linked to the incident.", keywords: ["report emergency incident", "emergency incident", "incident", "report emergency", "fire", "flood", "lift entrapment", "gas leak", "995"] },
  { id: "incident-vs-work-order", question: "Incident or Work Order — which do I use?", answer: "Incident: an emergency happening now that needs people to respond (danger, a key service stopped). Work Order: work to be done — a repair, servicing or an emergency fix already done (Emergency work done). After an incident is made safe, the repair is raised as a corrective Work Order linked to it.", keywords: ["incident", "work order", "difference", "which", "versus", "vs"] },
  { id: "incident-steps", question: "What are the steps of an incident response?", answer: "Reported → Acknowledged (the responder accepts it, before the deadline) → Mobilising → On Site → Rescue In Progress (if people are trapped) → Safe → Recovery → Closed. Only the next step is offered under Response action. Each step is recorded in the Response timeline.", keywords: ["incident", "steps", "acknowledge", "mobilise", "on site", "safe", "recovery", "response", "phase"] },
  { id: "on-call", question: "Who gets alerted for an emergency incident?", answer: "The on-call responders on the Emergency roster (Administration › On-call Roster). Keep the roster up to date so the right people are alerted.", keywords: ["on-call", "roster", "alert", "who", "notified", "responder"] },
  { id: "sla", question: "What is an SLA?", answer: "SLA (service level agreement) is the time the facility promises to respond to and fix a fault, set per priority: time to acknowledge, respond, attend, make safe and fix. FMWorks starts the clock when a Work Order is submitted and shows a countdown on it: green on track, amber when 75 % of the time is used, red when missed. Site SLA lists the approved times; managers see the results under SLA.", keywords: ["sla", "service level", "response time", "countdown", "deadline", "overdue", "kpi"] },
  { id: "who-acts", question: "Whose turn is it on this Work Order?", answer: "The Workflow timeline at the top of the Work Order names the next person, and the section they must act on is outlined in red for them.", keywords: ["whose turn", "next", "who", "timeline", "waiting"] },
];

export function roleGroup(role: UserRole | null | undefined): "technician" | "approver" | "finance" | "other" {
  if (role === "technician") return "technician";
  if (role && APPROVERS.includes(role)) return "approver";
  if (role === "finance") return "finance";
  return "other";
}

/** The guide for a path: exact "/" for home, otherwise the longest matching prefix. */
export function guideForPath(pathname: string): PageGuide | null {
  const path = pathname.replace(/\/+$/, "") || "/";
  let best: PageGuide | null = null;
  let bestLength = -1;
  for (const guide of PAGE_GUIDES) {
    for (const prefix of guide.paths) {
      const matches = prefix === "/" ? path === "/" : prefix.endsWith("/") ? path.startsWith(prefix) && path.length > prefix.length : path === prefix || path.startsWith(`${prefix}/`);
      if (matches && prefix.length > bestLength) {
        best = guide;
        bestLength = prefix.length;
      }
    }
  }
  return best;
}

export function stepsFor(guide: PageGuide, role: UserRole | null | undefined): readonly string[] {
  const own = (role ? guide.steps[role] : undefined) ?? (roleGroup(role) === "approver" ? guide.steps.approver : undefined);
  if (!own) return guide.steps.all ?? [];
  return guide.roleStepsOnly ? own : [...own, ...(guide.steps.all ?? [])];
}

export function stageAdvice(status: string, role: UserRole | null | undefined, inHouse: boolean): { label: string; meaning: string; advice: string } | null {
  const stage = STAGE_GUIDES[status];
  if (!stage) return null;
  const group = roleGroup(role);
  let advice = group === "technician" ? stage.technician : group === "approver" ? stage.approver : group === "finance" ? stage.finance ?? stage.other : stage.other;
  if (inHouse && status === "reviewed") advice = "In-house work: nothing more to pay. The Work Order closes.";
  if (inHouse && status === "draft" && group === "technician") advice = "In-house work: add a before photo and pin the location on the drawing (no quotation), then press Submit for approval.";
  return { label: stage.label, meaning: stage.meaning, advice };
}

/** Every page guide can also answer "what is ..." questions, so a page's own words are searchable. */
const PAGE_ANSWERS: readonly Faq[] = PAGE_GUIDES.map((guide) => ({
  id: `page-${guide.id}`,
  question: `About the ${guide.title} page`,
  answer: [guide.intro, ...(guide.steps.all ?? Object.values(guide.steps)[0] ?? [])].join(" "),
  keywords: [guide.title.toLowerCase()],
}));

const STOP = new Set(["the", "a", "an", "i", "my", "is", "to", "of", "in", "on", "it", "do", "how", "can", "what", "and", "for", "this", "be", "not", "t", "explain", "tell", "me", "about", "mean", "means", "please", "does", "you", "are", "why", "where", "when", "who", "which", "page", "work", "order", "orders", "app", "fmworks", "there", "any", "or", "we", "our"]);
function words(text: string): string[] {
  return text.toLowerCase().replace(/[^a-z0-9 ]+/g, " ").split(" ").filter((word) => word.length > 1 && !STOP.has(word));
}

/** Simple keyword match over the prepared answers; best first. Role-relevant answers get a small lift. */
/** M33: an answer written by the site team, matched like the built-in ones. */
export type TeamAnswer = { id: string; question: string; answer: string; keywords: string[] };
export function teamFaqs(answers: readonly TeamAnswer[]): Faq[] {
  return answers.map((item) => ({ id: `team-${item.id}`, question: item.question, answer: item.answer, keywords: item.keywords.length ? item.keywords : words(item.question) }));
}

export function searchHelp(query: string, role?: UserRole | null, limit = 5, extra: readonly Faq[] = []): Faq[] {
  const terms = words(query);
  if (terms.length === 0) return [];
  const lowered = query.toLowerCase();
  return [...extra, ...FAQS, ...PAGE_ANSWERS].map((faq) => {
    let score = 0;
    const covered = new Set<string>();
    for (const keyword of faq.keywords) if (lowered.includes(keyword.toLowerCase())) { score += 4; for (const w of words(keyword)) covered.add(w); }
    const questionWords = new Set(words(faq.question));
    const keywordWords = new Set(faq.keywords.flatMap(words));
    const answerWords = new Set(words(faq.answer));
    for (const term of terms) {
      if (keywordWords.has(term)) score += 3;
      if (questionWords.has(term)) score += 2;
      if (answerWords.has(term)) score += 1;
      if (keywordWords.has(term) || questionWords.has(term) || answerWords.has(term)) covered.add(term);
    }
    if (score > 0 && role && faq.roles?.includes(role)) score += 1;
    // UAT 18 Nov 2026: one shared word ("room") is not an answer to "Is there a room to store morphine?".
    // At least half of the question's own words must be found in the answer.
    const coverage = terms.filter((term) => covered.has(term)).length;
    return { faq, score: coverage * 2 >= terms.length ? score : 0 };
  })
    .filter((entry) => entry.score >= 2)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((entry) => entry.faq);
}

export function relatedFaqs(guide: PageGuide | null, role?: UserRole | null): Faq[] {
  const ids = guide?.related ?? [];
  const chosen = ids.map((id) => FAQS.find((faq) => faq.id === id)).filter((faq): faq is Faq => Boolean(faq));
  return chosen.filter((faq) => !faq.roles || !role || faq.roles.includes(role) || chosen.length <= 2);
}

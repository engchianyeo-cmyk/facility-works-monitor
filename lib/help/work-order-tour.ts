import type { UserRole } from "@/lib/auth";

/**
 * UAT 21 Nov 2026: Ollie walks a first-time user through the Work Order in front of them, section by section,
 * for its current stage and the person's role. Targets are found by element id or by heading text on the page.
 */
export type TourTarget = { id?: string; text?: string };
export type TourStep = { target: TourTarget | null; title: string; text: string };

const T = {
  timeline: { text: "Workflow timeline" },
  nextSteps: { id: "next-steps" },
  asset: { text: "Physical Asset" },
  drawings: { id: "drawings-documents-heading" },
  evidence: { id: "work-order-evidence" },
  actions: { text: "Work Order actions" },
  tech2: { id: "technician-2" },
  cost: { id: "cost-summary-heading" },
} as const;

const intro: TourStep = { target: null, title: "Let's go through this Work Order", text: "I'll show you each part of the page you need, one at a time, and what to do there. Press Next to move on; you can stop at any time." };
const timeline: TourStep = { target: T.timeline, title: "1 · Where the job is", text: "The Workflow timeline shows every stage. The highlighted card is where the job is now, and it names who acts next. If that's you, the section you must act on is outlined in red." };
const asset: TourStep = { target: T.asset, title: "The equipment", text: "This is the equipment the job is for, with its location and how critical it is. Open it to see its history and the O&M manual." };

function technicianSteps(status: string, inHouse: boolean): TourStep[] {
  switch (status) {
    case "draft": return [
      { target: T.nextSteps, title: "2 · Your checklist", text: "This box lists what is still missing before you can submit. Each item turns green when done." },
      { target: T.drawings, title: "3 · Mark the location", text: "Choose the layout plan, pick the ★ Location star tool, click the spot where the work is and press Save. Anyone, even Finance, can then find it." },
      { target: T.evidence, title: "4 · Add a Before photo", text: "Take or upload a photo of the problem before you start. Photos are kept with the job." },
      { target: T.actions, title: "5 · Submit for approval", text: inHouse ? "When the checklist is complete, press Submit for approval." : "For contractor work, attach the quotation(s) first, then press Submit for approval." },
    ];
    case "submitted": return [
      { target: T.actions, title: "2 · Waiting for the Approver", text: "Nothing for you to do now. You'll get a notice when it is approved, or returned with a reason to fix." },
    ];
    case "approved": return [
      { target: T.actions, title: "2 · Waiting for the choice of team", text: inHouse ? "The Approver confirms the in-house team. You'll be told when you can start." : "For contractor work, attach any quotations still needed; the Approver then picks one." },
    ];
    case "assigned": return [
      { target: T.actions, title: "2 · Start the work", text: "Press Accept (if shown), then Start when you begin on site. The start time is recorded." },
      { target: T.evidence, title: "3 · Photos as you go", text: "Take Before photos if you have not yet, and After photos when the work is done." },
    ];
    case "in_progress": return [
      { target: T.evidence, title: "2 · After photos", text: "Add After photos of the finished work. A completed job needs them." },
      { target: T.actions, title: "3 · Record what you did", text: "Fill in the work performed, start and end times, labour hours and the final cost, then press Submit physical completion." },
    ];
    case "completed": return [
      { target: T.tech2, title: "2 · Technician 2 checks", text: "A second Technician checks your work and endorses it. If it is reopened, read the reason, fix it and submit again." },
    ];
    default: return [
      { target: T.cost, title: "2 · The record", text: "The job is finished. Everything you recorded stays here: photos, times, cost and who did what." },
    ];
  }
}

function otherSteps(status: string): TourStep[] {
  return [
    { target: T.actions, title: "2 · What can be done now", text: status === "submitted" ? "Approvers check the description, location, photo and quotation here, then Approve or Return to Draft with a reason." : "The buttons here are the actions your role can take at this stage. If one you expect is missing, the readiness boxes say what is still needed." },
    { target: T.drawings, title: "3 · Location on the drawing", text: "The location star shows exactly where the work is." },
  ];
}

export function workOrderTour(status: string, role: UserRole | null | undefined, inHouse: boolean): TourStep[] {
  const middle = role === "technician" ? technicianSteps(status, inHouse) : otherSteps(status);
  return [intro, timeline, ...middle, asset, { target: null, title: "That's it", text: "Ask me any time with the Help button. Tip: Ollie's top box on every Work Order always says what you do next." }];
}

/** "What should I do now?" and similar: answer with the Work Order's own next step and offer the walk-through. */
export function asksForGuidance(question: string): boolean {
  return /\b(what (should|do|must) i do|what('?s| is) next|next step|what now|walk me|guide me|show me how|step by step|first time|new here|how do i (start|begin)|where do i start|help me)\b/i.test(question);
}

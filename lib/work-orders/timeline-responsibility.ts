/**
 * UAT 5 Nov 2026 (D-34): the Workflow timeline says who is responsible for each step, highlights the next one
 * and links to the section of the page where it is done, so anyone looking at it knows whose turn it is.
 */
export type TimelineStepKey =
  | "created" | "endorse-submission" | "submitted" | "approved" | "started" | "finished"
  | "completed" | "endorse-review" | "reviewed" | "invoiced" | "closed" | "cancelled";

export type ResponsibilityContext = {
  technician1Name: string | null;
  technician1Id: string | null;
  approverName: string | null;
  endorserName: { submission: string | null; review: string | null };
  inHouse: boolean;
  invoiceUploaded: boolean;
  viewer: { id: string; role: string };
};

export type Responsibility = {
  role: "Technician 1" | "Technician 2" | "Approver" | "Finance" | "System";
  who: string;
  action: string;
  href: string;
  section: string;
  viewerIsResponsible: boolean;
};

const APPROVERS = ["approver", "supervisor", "facility_manager", "administrator"];

export function responsibilityFor(key: TimelineStepKey, ctx: ResponsibilityContext): Responsibility {
  const t1 = ctx.technician1Name ?? "the assigned Technician";
  const isT1 = Boolean(ctx.technician1Id) && ctx.viewer.id === ctx.technician1Id;
  const isT2 = ctx.viewer.role === "technician" && !isT1;
  const isApprover = APPROVERS.includes(ctx.viewer.role) && !isT1;
  const tech1 = (action: string, href: string, section: string): Responsibility => ({ role: "Technician 1", who: t1, action, href, section, viewerIsResponsible: isT1 });
  const tech2 = (stage: "submission" | "review", action: string): Responsibility => ({
    role: "Technician 2", who: ctx.endorserName[stage] ?? "any other Technician of this facility", action,
    href: "#technician-endorsement", section: "Second Technician endorsement", viewerIsResponsible: isT2,
  });
  const approver = (action: string): Responsibility => ({
    role: "Approver", who: ctx.approverName ?? "the Approver", action, href: "#execution-title", section: "Work Order actions", viewerIsResponsible: isApprover,
  });
  switch (key) {
    case "created": return tech1("prepare the Draft", "#next-steps", "Next steps before you submit");
    case "endorse-submission": return tech2("submission", "check the Draft and endorse it");
    case "submitted": return tech1("submit the Work Order for approval", "#execution-title", "Technician execution");
    case "approved": return approver("approve the Work Order");
    case "started": return tech1("start the work", "#execution-title", "Technician execution");
    case "finished": return tech1("record when the work started and ended", "#actual-work-times", "Actual work times");
    case "completed": return tech1("submit Physical Completion", "#execution-title", "Technician execution");
    case "endorse-review": return tech2("review", "check the work and final cost, then endorse");
    case "reviewed": return approver("review the work and approve it as Completed");
    case "invoiced": return tech1("upload the contractor invoice", "#payment-heading", "Contractor Invoice and Payment");
    case "closed":
      if (ctx.inHouse) return { role: "System", who: "closes automatically", action: "close when approved as Completed (in-house, no payment)", href: "#execution-title", section: "Work Order actions", viewerIsResponsible: false };
      if (!ctx.invoiceUploaded) return tech1("upload the contractor invoice", "#payment-heading", "Contractor Invoice and Payment");
      return { role: "Finance", who: "Finance", action: "confirm the invoice was received and record the payment", href: "#payment-heading", section: "Contractor Invoice and Payment", viewerIsResponsible: ctx.viewer.role === "finance" };
    default: return { role: "System", who: "—", action: "", href: "#", section: "", viewerIsResponsible: false };
  }
}

/** The first step not yet done, unless the Work Order is finished. */
export function nextStepKey(steps: Array<{ key: string; at: string | null }>, status: string): string | null {
  if (["closed", "cancelled"].includes(status)) return null;
  return steps.find((step) => !step.at && step.key !== "cancelled")?.key ?? null;
}

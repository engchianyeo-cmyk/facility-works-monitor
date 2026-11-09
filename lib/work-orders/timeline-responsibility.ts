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
  /** UAT 9 Nov 2026: false when no contractor payment exists (no contractor quotation was approved). Absent = true. */
  contractorPayable?: boolean;
  /** The "No payment required" decision on a Work Order without a contractor payment. */
  noPayment?: { status: string | null; proposedBy: string | null };
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
  // UAT 9 Nov 2026: no contractor was approved, so there is no invoice to upload. The Work Order closes once someone
  // proposes "No payment required" and a different approver approves it.
  const noPaymentStep = (): Responsibility => {
    const status = ctx.noPayment?.status ?? null;
    if (status === "approved") return { role: "System", who: "closes automatically", action: "close now that No payment required is approved", href: "#payment-heading", section: "Contractor Invoice and Payment", viewerIsResponsible: false };
    if (status === "proposed") return { role: "Approver", who: ctx.approverName ?? "an Approver who did not propose it", action: "approve No payment required (no contractor was paid on this Work Order)", href: "#payment-heading", section: "Contractor Invoice and Payment", viewerIsResponsible: isApprover && ctx.viewer.id !== ctx.noPayment?.proposedBy };
    return { role: "Technician 1", who: t1, action: "propose No payment required — no contractor was approved, so there is no invoice", href: "#payment-heading", section: "Contractor Invoice and Payment",
      viewerIsResponsible: isT1 || ["supervisor", "facility_manager", "administrator"].includes(ctx.viewer.role) };
  };
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
    case "invoiced":
      if (!ctx.inHouse && ctx.contractorPayable === false) return noPaymentStep();
      return tech1("upload the contractor invoice", "#payment-heading", "Contractor Invoice and Payment");
    case "closed":
      if (!ctx.inHouse && ctx.contractorPayable === false) return noPaymentStep();
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

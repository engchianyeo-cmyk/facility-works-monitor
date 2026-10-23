/**
 * D-10: turns the Draft readiness list (work_order_approval_summary) into the preparer's next steps,
 * each pointing at the part of the Work Order page where it is done.
 */
export type NextStep = { label: string; how: string; href: string | null };

export function draftNextSteps(missing: readonly string[], workOrderId: string): NextStep[] {
  return missing.map((item) => {
    if (item === "Location marked on the layout plan") {
      return { label: item, how: "In Drawings & Documents, choose the layout plan, select Pin, tap the spot and Save.", href: "#drawings-documents-heading" };
    }
    if (item === "Before photo, video or voice note of the site") {
      return { label: item, how: "In Evidence, set the category to Before, take or attach the photo and tap Add evidence.", href: "#work-order-evidence" };
    }
    if (item === "Recommended contractor quotation" || item.startsWith("Quotations:")) {
      return { label: item, how: "Tap Prepare Proposal, choose the contractor, enter the amount and scope, attach the quotation and submit it.", href: "#proposal-heading" };
    }
    if (item === "Reason the work is needed") {
      return { label: item, how: "Edit the Work Order and explain what is wrong and why it needs fixing.", href: `/work-orders/${workOrderId}/edit` };
    }
    if (item === "Second Technician endorsement") {
      return { label: item, how: "Ask another Technician of this facility to open this Work Order, check it and tap Endorse as authentic.", href: "#technician-endorsement" };
    }
    if (item === "Actual start and end times of the work") {
      return { label: item, how: "In Actual work times, enter when the work started and ended, then Save work times.", href: "#actual-work-times" };
    }
    if (item === "Field-witness Technician") {
      return { label: item, how: "Assign the Technician who will witness the work.", href: null };
    }
    return { label: item, how: "", href: null };
  });
}

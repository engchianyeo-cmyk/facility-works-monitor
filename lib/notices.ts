/**
 * D-38 (7 Nov 2026): what each notice means in plain words, where it leads on the Work Order, and whether it is
 * still waiting for the person reading it.
 */
export type NoticeEvent =
  | "work_order_submitted_for_approval" | "work_order_approved" | "work_order_technician_assigned" | "work_order_emergency_started"
  | "work_order_returned_to_draft" | "work_order_completed" | "work_order_endorsed" | "work_order_invoice_uploaded" | "work_order_closed";

const TEXT: Record<string, { text: string; href: string }> = {
  work_order_submitted_for_approval: { text: "submitted for approval", href: "#execution-title" },
  work_order_approved: { text: "approved — the work can start", href: "#execution-title" },
  work_order_technician_assigned: { text: "assigned to a Technician", href: "#execution-title" },
  work_order_emergency_started: { text: "emergency work started without prior approval — to be reviewed afterwards", href: "#execution-title" },
  work_order_returned_to_draft: { text: "returned to Draft for changes", href: "#next-steps" },
  work_order_completed: { text: "approved as Completed", href: "#payment-heading" },
  work_order_endorsed: { text: "endorsed by the second Technician", href: "#technician-endorsement" },
  work_order_invoice_uploaded: { text: "contractor invoice uploaded — confirm receipt and record the payment", href: "#payment-heading" },
  work_order_closed: { text: "closed", href: "#execution-title" },
};

export function noticeText(event: string): { text: string; href: string } {
  return TEXT[event] ?? { text: event.replace(/^work_order_/, "").replaceAll("_", " "), href: "" };
}

const APPROVERS = ["approver", "supervisor", "facility_manager", "administrator"];

/** Is the Work Order this notice is about still waiting for the reader? Based on its current state, not the notice. */
export function waitingForReader(order: { status: string; assigned_technician_id: string | null; in_house_work: boolean | null } | undefined,
  reader: { id: string; role: string }): boolean {
  if (!order) return false;
  if (reader.role === "finance") return order.status === "reviewed" && !order.in_house_work;
  if (APPROVERS.includes(reader.role)) return ["submitted", "completed"].includes(order.status) && order.assigned_technician_id !== reader.id;
  if (reader.role === "technician") return order.assigned_technician_id === reader.id && ["draft", "approved", "assigned", "in_progress"].includes(order.status);
  return false;
}

/**
 * D-43 (9 Nov 2026): only the most current notices are shown first; older ones wait in "Earlier notices".
 * Current = the newest notice of each Work Order, while that Work Order is still open or the notice is under
 * two days old; and today's daily payment reminder. Everything else is earlier, read or not.
 */
export const CURRENT_WINDOW_HOURS = 48;
const FINISHED = ["closed", "cancelled"];

export function currentNoticeIds(
  rows: Array<{ id: string; work_order_id: string | null; event_type: string; created_at: string }>,
  statusOf: (workOrderId: string) => string | undefined,
  now = Date.now(),
): Set<string> {
  const current = new Set<string>();
  const seen = new Set<string>();
  const sorted = [...rows].sort((a, b) => b.created_at.localeCompare(a.created_at));
  const today = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore" }).format(new Date(now));
  for (const row of sorted) {
    if (row.event_type === "finance_daily_reminder") {
      if (new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore" }).format(new Date(row.created_at)) === today) current.add(row.id);
      continue;
    }
    if (!row.work_order_id || seen.has(row.work_order_id)) continue;
    seen.add(row.work_order_id);
    const status = statusOf(row.work_order_id);
    const recent = now - new Date(row.created_at).getTime() < CURRENT_WINDOW_HOURS * 3_600_000;
    if (recent || (status !== undefined && !FINISHED.includes(status))) current.add(row.id);
  }
  return current;
}

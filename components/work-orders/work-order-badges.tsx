import { STATUS_LABELS } from "@/lib/work-orders/workflow";
import type { WorkOrderPriority, WorkOrderStatus } from "@/lib/work-orders/types";

const STATUS_STYLE: Record<WorkOrderStatus, string> = {
  draft: "border-slate-300 bg-slate-50 text-slate-700",
  submitted: "border-cyan-300 bg-cyan-50 text-cyan-800",
  approved: "border-blue-300 bg-blue-50 text-blue-800",
  assigned: "border-violet-300 bg-violet-50 text-violet-800",
  in_progress: "border-amber-300 bg-amber-50 text-amber-900",
  completed: "border-emerald-300 bg-emerald-50 text-emerald-800",
  reviewed: "border-teal-300 bg-teal-50 text-teal-800",
  closed: "border-slate-400 bg-slate-100 text-slate-900",
  cancelled: "border-red-300 bg-red-50 text-red-800",
};

const PRIORITY_STYLE: Record<WorkOrderPriority, string> = {
  low: "border-slate-200 bg-slate-50 text-slate-600",
  medium: "border-sky-200 bg-sky-50 text-sky-700",
  high: "border-orange-300 bg-orange-50 text-orange-800",
  critical: "border-red-900 bg-red-800 text-white",
};

export function WorkOrderStatusBadge({ status }: { status: WorkOrderStatus }) {
  return <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold ${STATUS_STYLE[status]}`}>{STATUS_LABELS[status]}</span>;
}

export function WorkOrderPriorityBadge({ priority }: { priority: WorkOrderPriority }) {
  return <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold capitalize ${PRIORITY_STYLE[priority]}`}>{priority}</span>;
}

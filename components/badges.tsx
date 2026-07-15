import { STATUS_LABEL, PRIORITY_LABEL, WorkOrderStatus } from "@/lib/status";

const STATUS_COLORS: Record<WorkOrderStatus, string> = {
  submitted: "bg-slate-100 text-slate-700 border-slate-300",
  approved: "bg-blue-100 text-blue-700 border-blue-300",
  in_progress: "bg-amber-100 text-amber-800 border-amber-300",
  done: "bg-green-100 text-green-700 border-green-300",
  rejected: "bg-red-100 text-red-700 border-red-300",
};

const PRIORITY_COLORS: Record<string, string> = {
  low: "bg-slate-50 text-slate-600 border-slate-200",
  medium: "bg-sky-50 text-sky-700 border-sky-200",
  high: "bg-orange-50 text-orange-700 border-orange-200",
  critical: "bg-red-50 text-red-700 border-red-300",
};

export function StatusBadge({ status }: { status: WorkOrderStatus }) {
  return (
    <span
      className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-medium ${STATUS_COLORS[status]}`}
    >
      {STATUS_LABEL[status]}
    </span>
  );
}

export function PriorityBadge({ priority }: { priority: string }) {
  return (
    <span
      className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-medium ${PRIORITY_COLORS[priority] ?? PRIORITY_COLORS.medium}`}
    >
      {PRIORITY_LABEL[priority] ?? priority} priority
    </span>
  );
}

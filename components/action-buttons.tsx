"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { WorkOrderAction, WorkOrderStatus } from "@/lib/status";

const ACTIONS_BY_STATUS: Record<WorkOrderStatus, { action: WorkOrderAction; label: string; style: string }[]> = {
  submitted: [
    { action: "approve", label: "Approve", style: "bg-blue-600 hover:bg-blue-700 text-white" },
    { action: "reject", label: "Reject", style: "bg-white border border-red-300 text-red-700 hover:bg-red-50" },
  ],
  approved: [
    { action: "start", label: "Start", style: "bg-amber-500 hover:bg-amber-600 text-white" },
    { action: "reject", label: "Reject", style: "bg-white border border-red-300 text-red-700 hover:bg-red-50" },
  ],
  in_progress: [
    { action: "complete", label: "Complete", style: "bg-green-600 hover:bg-green-700 text-white" },
    { action: "reject", label: "Reject", style: "bg-white border border-red-300 text-red-700 hover:bg-red-50" },
  ],
  done: [],
  rejected: [],
};

export default function ActionButtons({ id, status }: { id: string; status: WorkOrderStatus }) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const actions = ACTIONS_BY_STATUS[status] ?? [];

  async function handleAction(action: WorkOrderAction) {
    setError(null);
    let note: string | undefined;
    if (action === "reject") {
      note = window.prompt("Reason for rejecting (required):") ?? undefined;
      if (!note) return;
    }

    setLoading(action);
    try {
      const res = await fetch(`/api/work-orders/${id}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, note }),
      });
      const json = await res.json();
      if (!res.ok) {
        setError(json.error || "Something went wrong");
        return;
      }
      router.refresh();
    } catch {
      setError("Network error — is the server running?");
    } finally {
      setLoading(null);
    }
  }

  if (actions.length === 0) {
    return <p className="text-sm text-neutral-400">No further actions — this work order is closed.</p>;
  }

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        {actions.map((a) => (
          <button
            key={a.action}
            onClick={() => handleAction(a.action)}
            disabled={loading !== null}
            className={`px-4 py-2 rounded-lg text-sm font-medium disabled:opacity-50 ${a.style}`}
          >
            {loading === a.action ? "Saving…" : a.label}
          </button>
        ))}
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  );
}

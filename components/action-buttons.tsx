"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { WorkOrderAction, WorkOrderStatus } from "@/lib/status";

const ACTIONS_BY_STATUS: Record<
  WorkOrderStatus,
  { action: WorkOrderAction; label: string; style: string }[]
> = {
  submitted: [
    {
      action: "approve",
      label: "Approve",
      style: "bg-blue-600 hover:bg-blue-700 text-white",
    },
    {
      action: "reject",
      label: "Reject",
      style: "bg-white border border-red-300 text-red-700 hover:bg-red-50",
    },
  ],
  approved: [
    {
      action: "start",
      label: "Start",
      style: "bg-amber-500 hover:bg-amber-600 text-white",
    },
  ],
  in_progress: [
    {
      action: "complete",
      label: "Complete",
      style: "bg-green-600 hover:bg-green-700 text-white",
    },
  ],
  done: [],
  rejected: [],
};

export default function ActionButtons({
  id,
  status,
  allowedActions,
  canEdit,
}: {
  id: string;
  status: WorkOrderStatus;
  allowedActions: WorkOrderAction[];
  canEdit: boolean;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const actions = (ACTIONS_BY_STATUS[status] ?? []).filter(({ action }) =>
    allowedActions.includes(action),
  );

  async function handleAction(action: WorkOrderAction) {
    setError(null);
    let note: string | undefined;
    if (action === "reject") {
      const response = window.prompt("Reason for rejecting (required):");
      if (response === null) return;
      const trimmed = response.trim();
      if (!trimmed) {
        setError("Rejection reason is required.");
        return;
      }
      note = trimmed;
    }

    setLoading(action);
    try {
      const response = await fetch(`/api/work-orders/${id}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, note }),
      });
      const json = await response.json();
      if (!response.ok) {
        setError(json.error || "Something went wrong");
        return;
      }
      router.refresh();
    } catch {
      setError("Network error — please check that the server is running.");
    } finally {
      setLoading(null);
    }
  }

  if (!canEdit && actions.length === 0) {
    return (
      <p className="text-sm text-neutral-400">
        No actions are available for your role.
      </p>
    );
  }

  return (
    <div className="space-y-2">
      {canEdit && (
        <button
          type="button"
          onClick={() => router.push(`/works/${id}/edit`)}
          className="rounded-lg bg-neutral-700 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-800"
        >
          Edit
        </button>
      )}
      <div className="flex gap-2">
        {actions.map((item) => (
          <button
            type="button"
            key={item.action}
            onClick={() => handleAction(item.action)}
            disabled={loading !== null}
            className={`rounded-lg px-4 py-2 text-sm font-medium disabled:opacity-50 ${item.style}`}
          >
            {loading === item.action ? "Saving…" : item.label}
          </button>
        ))}
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  );
}

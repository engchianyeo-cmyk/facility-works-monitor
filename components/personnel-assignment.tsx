"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export type AssignableTechnician = {
  id: string;
  displayName: string;
  tradeDiscipline: string | null;
  department: string | null;
};

export default function PersonnelAssignment({
  workOrderId,
  technicians,
  assignedTechnicianId,
}: {
  workOrderId: string;
  technicians: AssignableTechnician[];
  assignedTechnicianId: string | null;
}) {
  const router = useRouter();
  const [technicianId, setTechnicianId] = useState(
    assignedTechnicianId ?? "",
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function assignPersonnel(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);

    if (!technicianId) {
      setError("Select a technician.");
      return;
    }

    setSaving(true);
    try {
      const response = await fetch(
        `/api/work-orders/${workOrderId}/assignment`,
        {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ technician_id: technicianId }),
        },
      );
      const json = await response.json();

      if (!response.ok) {
        setError(json.error || "Unable to assign personnel.");
        return;
      }

      router.refresh();
    } catch {
      setError("Network error — please try again.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <form onSubmit={assignPersonnel} className="space-y-3">
      <div>
        <label
          htmlFor="assigned-technician"
          className="mb-1 block text-sm font-medium text-neutral-800"
        >
          Assigned technician
        </label>
        <select
          id="assigned-technician"
          value={technicianId}
          onChange={(event) => setTechnicianId(event.target.value)}
          disabled={saving || technicians.length === 0}
          className="w-full rounded-lg border border-neutral-300 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-neutral-100"
        >
          <option value="">Select active personnel…</option>
          {technicians.map((technician) => {
            const detail = [
              technician.tradeDiscipline,
              technician.department,
            ]
              .filter(Boolean)
              .join(" · ");
            return (
              <option key={technician.id} value={technician.id}>
                {technician.displayName}
                {detail ? ` — ${detail}` : ""}
              </option>
            );
          })}
        </select>
      </div>
      {technicians.length === 0 && (
        <p className="text-sm text-amber-700">
          No active Technician accounts are available. An Administrator must
          create or activate one first.
        </p>
      )}
      {error && <p className="text-sm text-red-600">{error}</p>}
      <button
        type="submit"
        disabled={
          saving ||
          !technicianId ||
          technicianId === assignedTechnicianId
        }
        className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {saving
          ? "Assigning…"
          : assignedTechnicianId
            ? "Reassign Personnel"
            : "Assign Personnel"}
      </button>
    </form>
  );
}

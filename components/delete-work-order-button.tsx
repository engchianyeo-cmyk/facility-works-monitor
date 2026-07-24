"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export default function DeleteWorkOrderButton({
  id,
  title,
}: {
  id: string;
  title: string;
}) {
  const router = useRouter();
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleDelete() {
    const confirmed = window.confirm(
      `Permanently delete "${title}"?\n\nThis action cannot be undone.`,
    );

    if (!confirmed) return;

    try {
      setDeleting(true);
      setError(null);

      const response = await fetch(`/api/work-orders/${id}`, {
        method: "DELETE",
      });

      const result = await response.json();

      if (!response.ok) {
        throw new Error(result.error || "Unable to delete work order.");
      }

      router.push("/works");
      router.refresh();
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Unable to delete work order.",
      );
      setDeleting(false);
    }
  }

  return (
    <div>
      <button
        type="button"
        onClick={handleDelete}
        disabled={deleting}
        className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-700 transition hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {deleting ? "Deleting..." : "Delete Work Order"}
      </button>

      {error && (
        <p className="mt-2 text-sm text-red-600">
          {error}
        </p>
      )}
    </div>
  );
}

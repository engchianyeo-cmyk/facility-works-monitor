"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Category = {
  id: string;
  name: string;
};

type WorkOrder = {
  id: string;
  title: string;
  location: string;
  category_id: string | null;
  priority: string | null;
  description: string | null;
  submitted_by: string | null;
  contact_number: string | null;
};

type WorkOrderFormProps = {
  categories: Category[];
  mode?: "create" | "edit";
  workOrder?: WorkOrder;
  loggedBy?: string;
};

export default function WorkOrderForm({
  categories,
  mode = "create",
  workOrder,
  loggedBy,
}: WorkOrderFormProps) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const isEdit = mode === "edit" && Boolean(workOrder);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);

    const form = new FormData(event.currentTarget);

    const body = {
      title: String(form.get("title") ?? "").trim(),
      location: String(form.get("location") ?? "").trim(),
      category_id: form.get("category_id")
        ? String(form.get("category_id"))
        : null,
      priority: String(form.get("priority") ?? "medium"),
      description: String(form.get("description") ?? "").trim() || null,
      contact_number:
        String(form.get("contact_number") ?? "").trim() || null,
    };

    try {
      const url = isEdit
        ? `/api/work-orders/${workOrder!.id}`
        : "/api/work-orders";

      const response = await fetch(url, {
        method: isEdit ? "PATCH" : "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      const json = await response.json();

      if (!response.ok) {
        setError(json.error || "Unable to save the work order.");
        return;
      }

      const savedId = isEdit ? workOrder!.id : json.data.id;

      router.push(`/works/${savedId}`);
      router.refresh();
    } catch {
      setError("Network error — please check that the server is running.");
    } finally {
      setSubmitting(false);
    }
  }

  const inputClass =
    "w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-neutral-400";

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label className="mb-1 block text-sm font-medium">Title *</label>
        <input
          name="title"
          required
          className={inputClass}
          placeholder="e.g. Broken light in corridor"
          defaultValue={workOrder?.title ?? ""}
        />
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium">Location *</label>
        <input
          name="location"
          required
          className={inputClass}
          placeholder="e.g. Block A – Corridor 2"
          defaultValue={workOrder?.location ?? ""}
        />
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-medium">Category</label>
          <select
            name="category_id"
            className={inputClass}
            defaultValue={workOrder?.category_id ?? ""}
          >
            <option value="">— None —</option>

            {categories.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium">Priority</label>
          <select
            name="priority"
            className={inputClass}
            defaultValue={workOrder?.priority ?? "medium"}
          >
            <option value="low">Low</option>
            <option value="medium">Medium</option>
            <option value="high">High</option>
            <option value="critical">Critical</option>
          </select>
        </div>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium">
          Description
        </label>
        <textarea
          name="description"
          rows={4}
          className={inputClass}
          placeholder="Describe the issue..."
          defaultValue={workOrder?.description ?? ""}
        />
      </div>

      <div>
        <span className="mb-1 block text-sm font-medium">Logged by</span>
        <p className="rounded-lg border border-neutral-200 bg-neutral-50 px-3 py-2 text-sm text-neutral-700">
          {isEdit
            ? workOrder?.submitted_by || loggedBy || "Unknown user"
            : loggedBy || "Authenticated user"}
        </p>
        <p className="mt-1 text-xs text-neutral-500">
          Identity is taken from the signed-in account and cannot be edited.
        </p>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium">
          Contact Number
        </label>
        <input
          name="contact_number"
          type="tel"
          className={inputClass}
          placeholder="e.g. +65 9123 4567"
          defaultValue={workOrder?.contact_number ?? ""}
        />
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <button
        type="submit"
        disabled={submitting}
        className="w-full rounded-lg bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
      >
        {submitting
          ? isEdit
            ? "Updating…"
            : "Submitting…"
          : isEdit
            ? "Update Work Order"
            : "Submit Work Order"}
      </button>
    </form>
  );
}

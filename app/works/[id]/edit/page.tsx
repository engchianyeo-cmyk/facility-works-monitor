import { notFound, redirect } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import WorkOrderForm from "@/components/work-order-form";
import { getCurrentIdentity } from "@/lib/auth";
import { canEditWorkOrder } from "@/lib/permissions";
import { WorkOrderStatus } from "@/lib/status";


export default async function EditWorkOrderPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const identity = await getCurrentIdentity();
  if (!identity) redirect(`/login?next=/works/${id}/edit`);

  const supabase = await createClient();

  const [{ data: workOrder }, { data: categories }] = await Promise.all([
    supabase
      .from("work_orders")
      .select("*")
      .eq("id", id)
      .single(),

    supabase
      .from("categories")
      .select("id, name")
      .order("name"),
  ]);

  if (!workOrder) {
    notFound();
  }

  const canEdit = canEditWorkOrder({
    role: identity.role,
    userId: identity.userId,
    ownerId: workOrder.user_id,
    assignedTechnicianId: workOrder.assigned_technician_id,
    status: workOrder.status as WorkOrderStatus,
  });

  if (!canEdit) {
    const isReviewer = ["reviewer", "initiator"].includes(identity.role);
    const reason =
      isReviewer && workOrder.user_id !== identity.userId
        ? "Only the Reviewer who originally submitted this work order can edit it."
        : isReviewer && workOrder.status !== "submitted"
          ? "Reviewer amendments are allowed only while the work order is Submitted."
          : "Your role cannot edit this work order.";

    return (
      <main className="mx-auto max-w-3xl p-6">
        <div className="rounded-xl border border-amber-200 bg-amber-50 p-5">
          <h1 className="text-xl font-semibold text-amber-950">
            Editing is not permitted
          </h1>
          <p className="mt-2 text-sm text-amber-900">{reason}</p>
          <Link
            href={`/works/${id}`}
            className="mt-4 inline-flex rounded-lg border border-amber-300 bg-white px-4 py-2 text-sm font-medium text-amber-950 hover:bg-amber-100"
          >
            Return to work order
          </Link>
        </div>
      </main>
    );
  }

  return (
    <main className="max-w-3xl mx-auto p-6">
      <h1 className="text-3xl font-bold mb-6">
        Edit Work Order
      </h1>

      <WorkOrderForm
        mode="edit"
        workOrder={workOrder}
        categories={categories ?? []}
        loggedBy={identity.displayName}
      />
    </main>
  );
}

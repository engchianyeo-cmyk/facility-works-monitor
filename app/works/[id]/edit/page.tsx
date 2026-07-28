import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import WorkOrderForm from "@/components/work-order-form";
import { getCurrentIdentity } from "@/lib/auth";
import { redirect } from "next/navigation";

type Category = {
  id: string;
  name: string;
};

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

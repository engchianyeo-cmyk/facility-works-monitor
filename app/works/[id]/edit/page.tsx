import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function EditWorkOrderPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const supabase = await createClient();

  const { data: workOrder } = await supabase
    .from("work_orders")
    .select("*")
    .eq("id", id)
    .single();

  if (!workOrder) {
    notFound();
  }

  return (
    <main className="max-w-3xl mx-auto p-6">
      <h1 className="text-3xl font-bold mb-6">
        Edit Work Order
      </h1>

      <pre className="rounded-lg bg-neutral-100 p-4 overflow-auto">
        {JSON.stringify(workOrder, null, 2)}
      </pre>
    </main>
  );
}
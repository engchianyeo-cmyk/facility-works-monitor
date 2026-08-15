import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { canEdit } from "@/lib/work-orders/permissions";
import type { WorkOrderStatus } from "@/lib/work-orders/types";
import WorkOrderForm from "@/components/work-orders/work-order-form";

export default async function EditWorkOrderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params; const identity = await getCurrentIdentity();
  if (!identity) redirect(`/login?next=/work-orders/${id}/edit`);
  const supabase = await createClient();
  const [{ data: order }, { data: categories }, { data: departments }] = await Promise.all([
    supabase.from("work_orders").select("*").eq("id", id).maybeSingle(),
    supabase.from("categories").select("id,name").order("name"),
    supabase.from("departments").select("id,code,name").eq("is_active", true).is("deleted_at", null).order("name"),
  ]);
  if (!order) notFound();
  if (!canEdit({ role: identity.role, actorId: identity.userId, requesterId: order.requested_by, assignedTechnicianId: order.assigned_technician_id, status: order.status as WorkOrderStatus })) redirect(`/work-orders/${id}`);
  return <main className="mx-auto max-w-3xl space-y-6 p-6 lg:p-8"><Link className="text-sm text-blue-700 hover:underline" href={`/work-orders/${id}`}>← Back to work order</Link><h1 className="text-3xl font-bold">Edit {order.work_order_number}</h1><WorkOrderForm categories={categories ?? []} departments={departments ?? []} assets={[]} workOrder={order} /></main>;
}

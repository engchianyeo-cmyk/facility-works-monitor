import type { ReactNode } from "react";
import ContractorActualCostPanel from "@/components/work-orders/contractor-actual-cost-panel";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export default async function WorkOrderFieldLayout({ children, params }: { children: ReactNode; params: Promise<{ id: string }> }) {
  const { id } = await params;
  const identity = await getCurrentIdentity();
  let contractorActualsEnabled = false;

  if (identity) {
    const supabase = await createClient();
    const { data: order } = await supabase
      .from("work_orders")
      .select("assigned_technician_id,assigned_vendor_id,status")
      .eq("id", id)
      .maybeSingle();
    contractorActualsEnabled = Boolean(
      order
      && identity.role === "technician"
      && order.assigned_technician_id === identity.userId
      && order.assigned_vendor_id
      && ["assigned", "in_progress"].includes(String(order.status)),
    );
  }

  return (
    <>
      {children}
      {contractorActualsEnabled && (
        <div className="mx-auto max-w-5xl px-4 pb-8 sm:px-6 lg:px-8">
          <ContractorActualCostPanel workOrderId={id} enabled />
        </div>
      )}
    </>
  );
}

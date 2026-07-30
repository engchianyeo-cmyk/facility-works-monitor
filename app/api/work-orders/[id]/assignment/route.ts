import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { canAssignWorkOrderPersonnel } from "@/lib/permissions";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { WorkOrderStatus } from "@/lib/status";

type RouteContext = {
  params: Promise<{ id: string }>;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function PATCH(
  request: NextRequest,
  { params }: RouteContext,
) {
  try {
    const identity = await getCurrentIdentity();
    if (!identity) {
      return NextResponse.json(
        { error: "Authentication is required." },
        { status: 401 },
      );
    }

    const body = await request.json();
    const technicianId = String(body.technician_id ?? "").trim();
    if (!UUID_PATTERN.test(technicianId)) {
      return NextResponse.json(
        { error: "Select a valid technician." },
        { status: 400 },
      );
    }

    const { id } = await params;
    const supabase = await createClient();
    const { data: order, error: orderError } = await supabase
      .from("work_orders")
      .select(
        "status, assigned_technician_id, assigned_to, assigned_by, assigned_at, updated_at",
      )
      .eq("id", id)
      .single();

    if (orderError || !order) {
      return NextResponse.json(
        { error: "Work order not found." },
        { status: 404 },
      );
    }

    if (
      !canAssignWorkOrderPersonnel(
        identity.role,
        order.status as WorkOrderStatus,
      )
    ) {
      return NextResponse.json(
        {
          error:
            order.status !== "approved"
              ? "Personnel can be assigned only after the work order is approved."
              : "Your role cannot assign work-order personnel.",
        },
        { status: 403 },
      );
    }

    const admin = createAdminClient();
    const { data: technician, error: technicianError } = await admin
      .from("profiles")
      .select("id, display_name, role, is_active, deleted_at")
      .eq("id", technicianId)
      .eq("role", "technician")
      .eq("is_active", true)
      .is("deleted_at", null)
      .maybeSingle();

    if (technicianError || !technician) {
      return NextResponse.json(
        { error: "The selected technician is not active or eligible." },
        { status: 400 },
      );
    }

    if (order.assigned_technician_id === technician.id) {
      return NextResponse.json({
        data: order,
        message: "This technician is already assigned.",
      });
    }

    const assignedAt = new Date().toISOString();
    const update = {
      assigned_technician_id: technician.id,
      assigned_to: technician.display_name,
      assigned_by: identity.displayName,
      assigned_at: assignedAt,
      updated_at: assignedAt,
    };
    const { data, error: updateError } = await supabase
      .from("work_orders")
      .update(update)
      .eq("id", id)
      .eq("status", "approved")
      .select()
      .single();

    if (updateError || !data) {
      return NextResponse.json(
        { error: updateError?.message ?? "Unable to assign personnel." },
        { status: 500 },
      );
    }

    const { error: auditError } = await supabase
      .from("activity_logs")
      .insert({
        user_id: identity.userId,
        work_order_id: id,
        action: order.assigned_technician_id ? "personnel_reassigned" : "personnel_assigned",
        actor: identity.displayName,
        note: JSON.stringify({
          previous_technician_id: order.assigned_technician_id,
          previous_technician_name: order.assigned_to,
          technician_id: technician.id,
          technician_name: technician.display_name,
        }),
      });

    if (auditError) {
      const { error: rollbackError } = await supabase
        .from("work_orders")
        .update({
          assigned_technician_id: order.assigned_technician_id,
          assigned_to: order.assigned_to,
          assigned_by: order.assigned_by,
          assigned_at: order.assigned_at,
          updated_at: order.updated_at,
        })
        .eq("id", id);

      console.error("Personnel assignment audit error:", auditError);
      if (rollbackError) {
        console.error("Personnel assignment rollback error:", rollbackError);
      }
      return NextResponse.json(
        {
          error: rollbackError
            ? "The assignment audit failed and the previous assignment could not be restored automatically."
            : "The assignment audit failed. The previous assignment was restored.",
        },
        { status: 500 },
      );
    }

    return NextResponse.json({ data });
  } catch (error) {
    console.error("Personnel assignment error:", error);
    return NextResponse.json(
      { error: "Unable to assign personnel." },
      { status: 500 },
    );
  }
}

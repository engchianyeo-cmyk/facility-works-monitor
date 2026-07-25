import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { nextStatus, WorkOrderAction, WorkOrderStatus } from "@/lib/status";

type RouteContext = {
  params: Promise<{ id: string }>;
};

const ALLOWED_ACTIONS: WorkOrderAction[] = [
  "approve",
  "reject",
  "start",
  "complete",
];

export async function PATCH(
  request: NextRequest,
  { params }: RouteContext,
) {
  try {
    const { id } = await params;
    const body = await request.json();
    const action = String(body.action ?? "").trim() as WorkOrderAction;
    const note = typeof body.note === "string" ? body.note.trim() : "";

    if (!ALLOWED_ACTIONS.includes(action)) {
      return NextResponse.json(
        { error: `Invalid action: ${action}` },
        { status: 400 },
      );
    }

    const supabase = await createClient();

    const { data: existingOrder, error: fetchError } = await supabase
      .from("work_orders")
      .select("status")
      .eq("id", id)
      .single();

    if (fetchError || !existingOrder) {
      return NextResponse.json(
        { error: "Work order not found." },
        { status: 404 },
      );
    }

    const currentStatus = existingOrder.status as WorkOrderStatus;
    const transition = nextStatus(currentStatus, action);

    if (!transition.ok) {
      return NextResponse.json(
        { error: transition.error },
        { status: 400 },
      );
    }

    if (action === "reject" && !note) {
      return NextResponse.json(
        { error: "Rejection reason is required." },
        { status: 400 },
      );
    }

    const { data, error } = await supabase
      .from("work_orders")
      .update({
        status: transition.to,
        updated_at: new Date().toISOString(),
      })
      .eq("id", id)
      .select()
      .single();

    if (error || !data) {
      return NextResponse.json(
        { error: error?.message ?? "Unable to update work order status." },
        { status: 500 },
      );
    }

    const activityLog = {
      work_order_id: id,
      action: "status_change",
      from_status: currentStatus,
      to_status: transition.to,
      actor: "Practitioner Preview User",
      note: action === "reject" ? note : note || null,
    };

    const { error: logError } = await supabase
      .from("activity_logs")
      .insert(activityLog);

    if (logError) {
      console.error("Activity log insert error:", logError);
      return NextResponse.json(
        { error: "Status updated but activity log failed." },
        { status: 500 },
      );
    }

    return NextResponse.json({ data });

  } catch (err) {
    return NextResponse.json(
      { error: "Internal Server Error" },
      { status: 500 }
    );
  }
}
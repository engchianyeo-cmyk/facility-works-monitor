import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { canCreateWorkOrder } from "@/lib/permissions";

export async function POST(request: Request) {
  try {
    const identity = await getCurrentIdentity();
    if (!identity) {
      return NextResponse.json(
        { error: "Authentication is required." },
        { status: 401 },
      );
    }
    if (!canCreateWorkOrder(identity.role)) {
      return NextResponse.json(
        { error: "Your role cannot create work orders." },
        { status: 403 },
      );
    }

    const body = await request.json();
    const title = String(body.title ?? "").trim();
    const location = String(body.location ?? "").trim();

    if (!title || !location) {
      return NextResponse.json(
        { error: "Title and location are required." },
        { status: 400 },
      );
    }

    const supabase = await createClient();
    const { data, error } = await supabase
      .from("work_orders")
      .insert({
        user_id: identity.userId,
        title,
        location,
        category_id: String(body.category_id ?? "").trim() || null,
        priority: String(body.priority ?? "medium").trim().toLowerCase(),
        description: String(body.description ?? "").trim() || null,
        submitted_by: identity.displayName,
        contact_number: String(body.contact_number ?? "").trim() || null,
        status: "submitted",
      })
      .select()
      .single();

    if (error || !data) {
      console.error("Work-order creation error:", error);
      return NextResponse.json(
        { error: error?.message ?? "Unable to create work order." },
        { status: 400 },
      );
    }

    const { error: activityError } = await supabase
      .from("activity_logs")
      .insert({
        user_id: identity.userId,
        work_order_id: data.id,
        action: "created",
        actor: identity.displayName,
        note: "Work order submitted.",
      });

    if (activityError) {
      const { error: rollbackError } = await supabase
        .from("work_orders")
        .delete()
        .eq("id", data.id);
      console.error("Creation activity-log error:", activityError);
      if (rollbackError) {
        console.error("Creation rollback error:", rollbackError);
      }
      return NextResponse.json(
        {
          error: rollbackError
            ? "Creation audit failed and the work order could not be removed automatically."
            : "Creation audit failed. The work order was not retained.",
        },
        { status: 500 },
      );
    }

    return NextResponse.json({ data }, { status: 201 });
  } catch (error) {
    console.error("Work-order POST error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}

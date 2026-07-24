import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

type RouteContext = {
  params: Promise<{ id: string }>;
};

export async function PATCH(
  request: NextRequest,
  context: RouteContext,
) {
  try {
    const { id } = await context.params;
    const body = await request.json();

    const title = String(body.title ?? "").trim();
    const location = String(body.location ?? "").trim();

    if (!title || !location) {
      return NextResponse.json(
        { error: "Title and location are required." },
        { status: 400 },
      );
    }

    const updateData = {
      title,
      location,
      category_id: body.category_id || null,
      priority: body.priority || "medium",
      description: body.description || null,
      submitted_by: body.submitted_by || null,
      contact_number: 
      String(body.contact_number ?? "").trim() || null,
      updated_at: new Date().toISOString(),
    };

    const supabase = await createClient();

    const { data, error } = await supabase
      .from("work_orders")
      .update(updateData)
      .eq("id", id)
      .select()
      .single();

    if (error) {
      console.error("Work-order update error:", error);

      return NextResponse.json(
        { error: error.message },
        { status: 500 },
      );
    }

    return NextResponse.json({ data });
  } catch (error) {
    console.error("Work-order PATCH error:", error);

    return NextResponse.json(
      { error: "Unable to update the work order." },
      { status: 500 },
    );
  }
}
export async function DELETE(
  _request: NextRequest,
  context: RouteContext,
) {
  try {
    const { id } = await context.params;
    const supabase = await createClient();

    const { error } = await supabase
      .from("work_orders")
      .delete()
      .eq("id", id);

    if (error) {
      console.error("Work-order delete error:", error);

      return NextResponse.json(
        { error: error.message },
        { status: 500 },
      );
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Work-order DELETE error:", error);

    return NextResponse.json(
      { error: "Unable to delete the work order." },
      { status: 500 },
    );
  }
}
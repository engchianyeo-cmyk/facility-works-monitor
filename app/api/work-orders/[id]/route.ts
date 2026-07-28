import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getCurrentIdentity } from "@/lib/auth";
import {
  canDeleteWorkOrder,
  canEditWorkOrder,
} from "@/lib/permissions";
import { WorkOrderStatus } from "@/lib/status";

type RouteContext = {
  params: Promise<{ id: string }>;
};

const EDITABLE_FIELDS = [
  "title",
  "location",
  "category_id",
  "priority",
  "description",
  "contact_number",
] as const;

type EditableField = (typeof EDITABLE_FIELDS)[number];
type EditableValues = Record<EditableField, string | null>;

const FIELD_LABELS: Record<EditableField, string> = {
  title: "Title",
  location: "Location",
  category_id: "Category",
  priority: "Priority",
  description: "Description",
  contact_number: "Contact number",
};

function comparable(value: string | null): string {
  return value ?? "";
}

export async function PATCH(
  request: NextRequest,
  context: RouteContext,
) {
  try {
    const identity = await getCurrentIdentity();
    if (!identity) {
      return NextResponse.json(
        { error: "Authentication is required." },
        { status: 401 },
      );
    }

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

    const updateData: EditableValues & { updated_at: string } = {
      title,
      location,
      category_id: String(body.category_id ?? "").trim() || null,
      priority: String(body.priority ?? "medium").trim().toLowerCase(),
      description: String(body.description ?? "").trim() || null,
      contact_number: String(body.contact_number ?? "").trim() || null,
      updated_at: new Date().toISOString(),
    };

    const supabase = await createClient();

    const { data: existingOrder, error: fetchError } = await supabase
      .from("work_orders")
      .select(
        "title, location, category_id, priority, description, submitted_by, contact_number, updated_at, user_id, status",
      )
      .eq("id", id)
      .single();

    if (fetchError || !existingOrder) {
      return NextResponse.json(
        { error: fetchError?.message ?? "Work order not found." },
        { status: 404 },
      );
    }

    if (
      !canEditWorkOrder({
        role: identity.role,
        userId: identity.userId,
        ownerId: existingOrder.user_id,
        status: existingOrder.status as WorkOrderStatus,
      })
    ) {
      return NextResponse.json(
        { error: "Your role cannot edit this work order." },
        { status: 403 },
      );
    }

    const changedFields = EDITABLE_FIELDS.filter(
      (field) =>
        comparable(existingOrder[field]) !== comparable(updateData[field]),
    );

    if (changedFields.length === 0) {
      return NextResponse.json({ data: existingOrder });
    }

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

    const categoryIds = [
      existingOrder.category_id,
      updateData.category_id,
    ].filter((value): value is string => Boolean(value));
    const categoryNames = new Map<string, string>();

    if (categoryIds.length > 0) {
      const { data: categories, error: categoriesError } = await supabase
        .from("categories")
        .select("id, name")
        .in("id", [...new Set(categoryIds)]);

      if (categoriesError) {
        console.error("Category audit lookup error:", categoriesError);
      } else {
        categories?.forEach((category) =>
          categoryNames.set(category.id, category.name),
        );
      }
    }

    const auditValue = (field: EditableField, value: string | null) => {
      if (field === "category_id" && value) {
        return categoryNames.get(value) ?? value;
      }
      return value;
    };

    const activityLogs = changedFields.map((field) => ({
      user_id: identity.userId,
      work_order_id: id,
      action: "field_changed",
      actor: identity.displayName,
      note: JSON.stringify({
        field,
        label: FIELD_LABELS[field],
        previous_value: auditValue(field, existingOrder[field]),
        new_value: auditValue(field, updateData[field]),
      }),
    }));

    const { error: auditError } = await supabase
      .from("activity_logs")
      .insert(activityLogs);

    if (auditError) {
      const rollbackData = {
        ...Object.fromEntries(
          EDITABLE_FIELDS.map((field) => [field, existingOrder[field]]),
        ),
        updated_at: existingOrder.updated_at,
      };
      const { error: rollbackError } = await supabase
        .from("work_orders")
        .update(rollbackData)
        .eq("id", id);

      console.error("Work-order amendment audit error:", auditError);
      if (rollbackError) {
        console.error("Work-order amendment rollback error:", rollbackError);
      }

      return NextResponse.json(
        {
          error: rollbackError
            ? "The amendment audit failed and the work order could not be restored automatically."
            : "The amendment audit failed. The work order was restored.",
        },
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
    const identity = await getCurrentIdentity();
    if (!identity) {
      return NextResponse.json(
        { error: "Authentication is required." },
        { status: 401 },
      );
    }
    if (!canDeleteWorkOrder(identity.role)) {
      return NextResponse.json(
        { error: "Administrator access is required." },
        { status: 403 },
      );
    }

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

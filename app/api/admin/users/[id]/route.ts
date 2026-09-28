import { NextResponse } from "next/server";
import { getCurrentIdentity, isUserRole } from "@/lib/auth";
import { createAdminClient, isAdminConfigured } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

type RouteContext = { params: Promise<{ id: string }> };

async function requireAdministrator() {
  const identity = await getCurrentIdentity();
  return identity?.role === "administrator" ? identity : null;
}

function databaseMessage(message: string | undefined, fallback: string) {
  if (!message) return fallback;
  const permitted = [
    "Profile not found",
    "Invalid profile values",
    "Technicians require a trade or discipline",
    "Department is unavailable",
    "Administrators cannot demote, deactivate or archive their own account",
    "The final ready Administrator cannot be changed",
    "Archive confirmation does not match",
    "Active work assignments must be reassigned before archive",
    "Administrators cannot permanently delete their own account",
    "Permanent deletion confirmation does not match",
    "Active work assignments must be reassigned before permanent deletion",
    "The final ready Administrator cannot be permanently deleted",
  ];
  return permitted.find((value) => message.includes(value)) ?? fallback;
}

export async function PATCH(request: Request, context: RouteContext) {
  const identity = await requireAdministrator();
  if (!identity) return NextResponse.json({ error: "Access denied." }, { status: 403 });

  try {
    const { id } = await context.params;
    const body = (await request.json()) as Record<string, unknown>;
    const displayName = String(body.display_name ?? "").trim();
    const departmentId = String(body.department_id ?? "").trim();
    const role = String(body.role ?? "");
    const trade = String(body.trade_discipline ?? "").trim();
    if (!displayName || !departmentId || !isUserRole(role)) {
      return NextResponse.json({ error: "Name, an active department and a valid role are required." }, { status: 400 });
    }
    if (role === "technician" && !trade) {
      return NextResponse.json({ error: "Trade or technical discipline is required for Technicians." }, { status: 400 });
    }

    const supabase = await createClient();
    const { data, error } = await supabase.rpc("admin_update_profile", {
      p_target_id: id,
      p_payload: {
        display_name: displayName,
        department_id: departmentId,
        trade_discipline: trade || null,
        contact_number: String(body.contact_number ?? "").trim() || null,
        role,
        is_active: body.is_active === true,
      },
    });
    if (error || !data) {
      return NextResponse.json({ error: databaseMessage(error?.message, "The user profile and audit entry were not changed.") }, { status: 409 });
    }
    return NextResponse.json({ success: true, profile: data });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof SyntaxError ? "The request body must be valid JSON." : "Unable to update user." },
      { status: error instanceof SyntaxError ? 400 : 500 },
    );
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  const identity = await requireAdministrator();
  if (!identity) return NextResponse.json({ error: "Access denied." }, { status: 403 });

  try {
    const { id } = await context.params;
    const body = (await request.json()) as Record<string, unknown>;
    if (body.permanent === true) {
      if (!isAdminConfigured()) {
        return NextResponse.json(
          { error: "Permanent deletion requires configured privileged Auth access." },
          { status: 503 },
        );
      }
      const confirmation = String(body.confirmation ?? "").trim();
      const supabase = await createClient();
      const admin = createAdminClient();
      const { data: prepared, error: preparationError } = await supabase.rpc(
        "admin_prepare_permanent_profile_deletion",
        { p_target_id: id, p_confirmation: confirmation },
      );
      if (preparationError || !prepared) {
        return NextResponse.json(
          { error: databaseMessage(preparationError?.message, "Permanent deletion was not started.") },
          { status: 409 },
        );
      }

      const { error: authDeleteError } = await admin.auth.admin.deleteUser(id);
      const authErrorCode = authDeleteError
        ? String((authDeleteError as { code?: string }).code ?? "AUTH_DELETE_FAILED")
        : null;
      const { error: resultAuditError } = await admin.rpc(
        "admin_record_permanent_delete_result",
        {
          p_actor_id: identity.userId,
          p_target_id: id,
          p_succeeded: !authDeleteError,
          p_error_code: authErrorCode,
        },
      );

      if (authDeleteError) {
        return NextResponse.json(
          {
            error: resultAuditError
              ? "The Auth account was not deleted and the failed attempt requires audit reconciliation. Archive the account and contact the deployment Administrator."
              : "The Auth account could not be permanently deleted, usually because retained operational history still references it. Archive the account instead.",
            auth_deleted: false,
            reconciliation_required: Boolean(resultAuditError),
          },
          { status: resultAuditError ? 409 : 422 },
        );
      }
      if (resultAuditError) {
        return NextResponse.json(
          {
            error: "The Auth account was deleted, but the completion audit requires Administrator reconciliation.",
            auth_deleted: true,
            reconciliation_required: true,
          },
          { status: 409 },
        );
      }
      return NextResponse.json({ success: true, permanently_deleted: true });
    }
    const confirmation = String(body.confirmation ?? "").trim();
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("admin_archive_profile", {
      p_target_id: id,
      p_confirmation: confirmation,
    });
    if (error || !data) {
      return NextResponse.json({ error: databaseMessage(error?.message, "The account and audit entry were not changed.") }, { status: 409 });
    }
    return NextResponse.json({ success: true, profile: data });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof SyntaxError ? "The request body must be valid JSON." : "Unable to archive user." },
      { status: error instanceof SyntaxError ? 400 : 500 },
    );
  }
}

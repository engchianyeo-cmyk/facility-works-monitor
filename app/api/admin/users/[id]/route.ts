import { NextResponse } from "next/server";
import { USER_ROLES, getCurrentIdentity, type UserRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

type RouteContext = { params: Promise<{ id: string }> };

function isUserRole(value: unknown): value is UserRole {
  return USER_ROLES.includes(value as UserRole);
}

async function requireAdministrator() {
  const identity = await getCurrentIdentity();
  return identity?.role === "administrator" ? identity : null;
}

const ACTIVE_STATUSES = [
  "submitted",
  "reviewed",
  "approved",
  "assigned",
  "accepted",
  "in_progress",
];

export async function PATCH(request: Request, context: RouteContext) {
  const identity = await requireAdministrator();
  if (!identity) {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  try {
    const { id } = await context.params;
    const body = await request.json();
    const displayName = String(body.display_name ?? "").trim();
    const department = String(body.department ?? "").trim();
    const tradeDiscipline = String(body.trade_discipline ?? "").trim();
    const contactNumber = String(body.contact_number ?? "").trim();
    const role = String(body.role ?? "") as UserRole;
    const isActive = body.is_active === true;

    if (!displayName || !department || !isUserRole(role)) {
      return NextResponse.json(
        { error: "Name, department/company and a valid role are required." },
        { status: 400 },
      );
    }
    if (role === "technician" && !tradeDiscipline) {
      return NextResponse.json(
        { error: "Trade or technical discipline is required for Technicians." },
        { status: 400 },
      );
    }
    if (id === identity.userId && (!isActive || role !== "administrator")) {
      return NextResponse.json(
        { error: "You cannot demote or deactivate your current account." },
        { status: 400 },
      );
    }

    const supabase = await createClient();
    const admin = createAdminClient();
    const { data: existing, error: existingError } = await supabase
      .from("profiles")
      .select("display_name, email, role, is_active")
      .eq("id", id)
      .single();
    if (existingError || !existing) {
      return NextResponse.json({ error: "User not found." }, { status: 404 });
    }

    if (
      existing.role === "administrator" &&
      existing.is_active &&
      (role !== "administrator" || !isActive)
    ) {
      const { count } = await supabase
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("role", "administrator")
        .eq("is_active", true)
        .is("deleted_at", null);
      if ((count ?? 0) <= 1) {
        return NextResponse.json(
          { error: "The final active Administrator cannot be changed." },
          { status: 400 },
        );
      }
    }

    const { error } = await supabase
      .from("profiles")
      .update({
        display_name: displayName,
        department,
        trade_discipline: role === "technician" ? tradeDiscipline : null,
        contact_number: contactNumber || null,
        role,
        is_active: isActive,
        deleted_at: isActive ? null : body.deleted_at ?? null,
      })
      .eq("id", id);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    const { error: auditError } = await admin.from("activity_logs").insert({
      user_id: identity.userId,
      action: "user_admin_profile_updated",
      actor: identity.displayName,
      note: JSON.stringify({
        target_user_id: id,
        target_email: existing.email,
        previous_role: existing.role,
        role,
        previous_active: existing.is_active,
        is_active: isActive,
      }),
    });
    if (auditError) {
      return NextResponse.json(
        { error: "The profile changed, but the audit entry failed." },
        { status: 500 },
      );
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Unable to update user.",
      },
      { status: 500 },
    );
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  const identity = await requireAdministrator();
  if (!identity) {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  try {
    const { id } = await context.params;
    const body = await request.json();
    const permanent = body.permanent === true;
    const confirmation = String(body.confirmation ?? "").trim().toLowerCase();

    if (id === identity.userId) {
      return NextResponse.json(
        { error: "You cannot delete or archive your current account." },
        { status: 400 },
      );
    }

    const supabase = await createClient();
    const admin = createAdminClient();
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("display_name, email, role, is_active")
      .eq("id", id)
      .single();
    if (profileError || !profile) {
      return NextResponse.json({ error: "User not found." }, { status: 404 });
    }
    if (
      confirmation !== profile.email?.trim().toLowerCase() &&
      confirmation !== profile.display_name.trim().toLowerCase()
    ) {
      return NextResponse.json(
        { error: "Confirmation must exactly match the user email or name." },
        { status: 400 },
      );
    }

    const { count: assignmentCount, error: assignmentError } = await supabase
      .from("work_orders")
      .select("id", { count: "exact", head: true })
      .eq("assigned_technician_id", id)
      .in("status", ACTIVE_STATUSES);
    if (assignmentError) {
      return NextResponse.json(
        { error: assignmentError.message },
        { status: 500 },
      );
    }
    if ((assignmentCount ?? 0) > 0) {
      return NextResponse.json(
        {
          error:
            "This user has active assigned work. Reassign or cancel it before deletion.",
        },
        { status: 409 },
      );
    }

    if (profile.role === "administrator" && profile.is_active) {
      const { count } = await supabase
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("role", "administrator")
        .eq("is_active", true)
        .is("deleted_at", null);
      if ((count ?? 0) <= 1) {
        return NextResponse.json(
          { error: "The final active Administrator cannot be deleted." },
          { status: 400 },
        );
      }
    }

    const action = permanent
      ? "user_admin_permanently_deleted"
      : "user_admin_archived";
    const { error: auditError } = await admin.from("activity_logs").insert({
      user_id: identity.userId,
      action,
      actor: identity.displayName,
      note: JSON.stringify({
        target_user_id: id,
        target_email: profile.email,
        target_display_name: profile.display_name,
        deletion_policy: permanent ? "permanent_auth_delete" : "soft_delete",
      }),
    });
    if (auditError) {
      return NextResponse.json(
        { error: "Deletion was stopped because audit logging failed." },
        { status: 500 },
      );
    }

    if (permanent) {
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) {
        return NextResponse.json({ error: error.message }, { status: 400 });
      }
    } else {
      const { error } = await supabase
        .from("profiles")
        .update({
          is_active: false,
          deleted_at: new Date().toISOString(),
        })
        .eq("id", id);
      if (error) {
        return NextResponse.json({ error: error.message }, { status: 400 });
      }
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Unable to delete user.",
      },
      { status: 500 },
    );
  }
}

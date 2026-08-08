import { createHash, randomBytes } from "node:crypto";
import { NextResponse } from "next/server";
import { getCurrentIdentity, isUserRole, type UserRole } from "@/lib/auth";
import {
  createAdminClient,
  isAdminConfigured,
} from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function apiError(code: string, message: string, status: number) {
  return NextResponse.json({ success: false, code, error: message }, { status });
}

async function requireAdministrator() {
  const identity = await getCurrentIdentity();
  if (!identity) {
    return {
      response: apiError("AUTH_REQUIRED", "Authentication is required.", 401),
      identity: null,
    };
  }
  if (identity.role !== "administrator") {
    return {
      response: apiError("ACCESS_DENIED", "Administrator access is required.", 403),
      identity: null,
    };
  }
  return { response: null, identity };
}

export async function GET() {
  const authorization = await requireAdministrator();
  if (authorization.response) return authorization.response;

  try {
    const supabase = await createClient();
    const { data: departments, error } = await supabase
      .from("departments")
      .select("id, name")
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("name");

    if (error) {
      return apiError(
        "DEPARTMENTS_UNAVAILABLE",
        "Active departments could not be loaded.",
        503,
      );
    }

    return NextResponse.json({
      success: true,
      provisioning_configured: isAdminConfigured(),
      departments: departments ?? [],
    });
  } catch {
    return apiError(
      "PROVISIONING_STATE_UNAVAILABLE",
      "User provisioning status could not be loaded.",
      503,
    );
  }
}

export async function POST(request: Request) {
  const authorization = await requireAdministrator();
  if (authorization.response || !authorization.identity) {
    return authorization.response;
  }

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return apiError("INVALID_JSON", "The request body must be valid JSON.", 400);
  }

  const displayName = String(body.display_name ?? "").trim();
  const email = String(body.email ?? "").trim().toLowerCase();
  const departmentId = String(body.department_id ?? "").trim();
  const tradeDiscipline = String(body.trade_discipline ?? "").trim();
  const contactNumber = String(body.contact_number ?? "").trim();
  const temporaryPassword = String(body.temporary_password ?? "");
  const roleValue = String(body.role ?? "");
  const mode = body.mode;
  const isActive = body.is_active !== false;

  if (!displayName) {
    return apiError("NAME_REQUIRED", "Display name is required.", 400);
  }
  if (!EMAIL_PATTERN.test(email) || email.length > 254) {
    return apiError("INVALID_EMAIL", "Enter a valid email address.", 400);
  }
  if (!isUserRole(roleValue)) {
    return apiError("INVALID_ROLE", "Select a supported role.", 400);
  }
  const role: UserRole = roleValue;
  if (!UUID_PATTERN.test(departmentId)) {
    return apiError("DEPARTMENT_REQUIRED", "Select an active department.", 400);
  }
  if (temporaryPassword.length < 12) {
    return apiError(
      "INVALID_TEMPORARY_PASSWORD",
      "The temporary password must contain at least 12 characters.",
      400,
    );
  }
  if (role === "technician" && !tradeDiscipline) {
    return apiError(
      "TRADE_REQUIRED",
      "Trade or technical discipline is required for Technicians.",
      400,
    );
  }
  if (mode !== "create" && mode !== "activate_pending") {
    return apiError("INVALID_MODE", "Select a supported provisioning action.", 400);
  }
  if (!isAdminConfigured()) {
    return apiError(
      "PROVISIONING_NOT_CONFIGURED",
      "User provisioning is not configured for this deployment.",
      503,
    );
  }

  try {
    const supabase = await createClient();
    const { data: department, error: departmentError } = await supabase
      .from("departments")
      .select("id, name")
      .eq("id", departmentId)
      .eq("is_active", true)
      .is("deleted_at", null)
      .maybeSingle();

    if (departmentError) {
      return apiError(
        "DEPARTMENT_CHECK_FAILED",
        "The selected department could not be verified.",
        503,
      );
    }
    if (!department) {
      return apiError("INACTIVE_DEPARTMENT", "Department is inactive.", 409);
    }

    const admin = createAdminClient();
    const { data: existingProfile, error: profileLookupError } = await admin
      .from("profiles")
      .select("id")
      .ilike("email", email)
      .maybeSingle();
    if (profileLookupError) {
      return apiError(
        "ACCOUNT_CHECK_FAILED",
        "Existing accounts could not be checked.",
        503,
      );
    }

    let existingAuthUser: { id: string; emailConfirmedAt: string | null } | null =
      null;
    for (let page = 1; page <= 100; page += 1) {
      const { data, error } = await admin.auth.admin.listUsers({
        page,
        perPage: 1000,
      });
      if (error) {
        return apiError(
          "ACCOUNT_CHECK_FAILED",
          "Existing accounts could not be checked.",
          503,
        );
      }
      const match = data.users.find(
        (user) => user.email?.trim().toLowerCase() === email,
      );
      if (match) {
        existingAuthUser = {
          id: match.id,
          emailConfirmedAt: match.email_confirmed_at ?? null,
        };
        break;
      }
      if (data.users.length < 1000) break;
      if (page === 100) {
        return apiError(
          "ACCOUNT_CHECK_INCOMPLETE",
          "The account directory is too large to verify safely.",
          503,
        );
      }
    }

    if (mode === "create" && (existingAuthUser || existingProfile)) {
      return apiError(
        "DUPLICATE_EMAIL",
        "User email is already registered.",
        409,
      );
    }
    if (mode === "activate_pending" && !existingAuthUser) {
      return apiError(
        "PENDING_ACCOUNT_NOT_FOUND",
        "No pending authentication user exists for this email.",
        404,
      );
    }
    if (
      mode === "activate_pending" &&
      existingAuthUser?.emailConfirmedAt
    ) {
      return apiError(
        "ACCOUNT_ALREADY_ACTIVE",
        "User email is already registered and confirmed.",
        409,
      );
    }
    if (
      mode === "activate_pending" &&
      existingProfile &&
      existingProfile.id !== existingAuthUser?.id
    ) {
      return apiError(
        "DUPLICATE_EMAIL",
        "The email is linked to a different user profile.",
        409,
      );
    }

    let userId: string;
    let createdNewAuthUser = false;

    if (mode === "create") {
      const rawToken = randomBytes(32).toString("base64url");
      const tokenHash = createHash("sha256").update(rawToken).digest("hex");
      const { data: invitation, error: invitationError } = await admin
        .from("account_invitations")
        .insert({
          email,
          display_name: displayName,
          department: department.name,
          assigned_role: role,
          is_active: isActive,
          token_hash: tokenHash,
          expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
          created_by: authorization.identity.userId,
        })
        .select("id")
        .single();

      if (invitationError || !invitation) {
        if (invitationError?.code === "23505") {
          return apiError(
            "DUPLICATE_EMAIL",
            "An active provisioning request already exists for this email.",
            409,
          );
        }
        return apiError(
          "PROVISIONING_TICKET_FAILED",
          "The user provisioning request could not be prepared.",
          500,
        );
      }

      const { data: created, error: createError } =
        await admin.auth.admin.createUser({
          email,
          password: temporaryPassword,
          email_confirm: true,
          user_metadata: {
            administrator_invitation_token: rawToken,
            trade_discipline:
              role === "technician" ? tradeDiscipline : null,
            contact_number: contactNumber || null,
          },
        });

      if (createError || !created.user) {
        const { error: cleanupError } = await admin
          .from("account_invitations")
          .update({ is_active: false })
          .eq("id", invitation.id);
        return apiError(
          cleanupError
            ? "AUTH_CREATE_FAILED_RECONCILIATION_REQUIRED"
            : "AUTH_CREATE_FAILED",
          cleanupError
            ? "The Auth user was not created and provisioning cleanup requires Administrator review."
            : "The Auth user could not be created.",
          500,
        );
      }

      userId = created.user.id;
      createdNewAuthUser = true;
    } else {
      userId = existingAuthUser!.id;
      const { error: activationError } =
        await admin.auth.admin.updateUserById(userId, {
          password: temporaryPassword,
          email_confirm: true,
          user_metadata: {
            display_name: displayName,
            department: department.name,
            trade_discipline:
              role === "technician" ? tradeDiscipline : null,
            contact_number: contactNumber || null,
          },
        });
      if (activationError) {
        return apiError(
          "AUTH_ACTIVATION_FAILED",
          "The pending authentication user could not be activated.",
          500,
        );
      }
    }

    const { error: profileError } = await admin.from("profiles").upsert(
      {
        id: userId,
        display_name: displayName,
        email,
        department: department.name,
        department_id: department.id,
        trade_discipline: role === "technician" ? tradeDiscipline : null,
        contact_number: contactNumber || null,
        role,
        is_active: isActive,
        deleted_at: null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "id" },
    );

    if (profileError) {
      if (createdNewAuthUser) {
        const { error: cleanupError } =
          await admin.auth.admin.deleteUser(userId);
        return apiError(
          cleanupError
            ? "PROFILE_FAILED_RECONCILIATION_REQUIRED"
            : "PROFILE_PROVISION_FAILED_ROLLED_BACK",
          cleanupError
            ? "The profile could not be completed and automatic Auth cleanup failed. Administrator reconciliation is required."
            : "The profile could not be completed, so the new Auth user was removed.",
          500,
        );
      }
      return apiError(
        "PROFILE_ACTIVATION_FAILED",
        "The Auth account changed, but its profile could not be updated. Administrator reconciliation is required.",
        500,
      );
    }

    const { error: auditError } = await admin.from("activity_logs").insert({
      user_id: authorization.identity.userId,
      action:
        mode === "activate_pending"
          ? "user_admin_pending_activated"
          : "user_admin_direct_created",
      actor: authorization.identity.displayName,
      note: JSON.stringify({
        target_user_id: userId,
        email,
        role,
        department_id: department.id,
        is_active: isActive,
        email_confirmed_by_administrator: true,
      }),
    });
    if (auditError) {
      return apiError(
        "AUDIT_FAILED_RECONCILIATION_REQUIRED",
        "The account was provisioned, but its audit entry failed. Administrator review is required.",
        500,
      );
    }

    const state = isActive ? "active" : "inactive";
    return NextResponse.json({
      success: true,
      user_id: userId,
      message:
        mode === "activate_pending"
          ? `Pending account activated and set ${state}.`
          : `User created and set ${state}.`,
    });
  } catch {
    return apiError(
      "PROVISIONING_FAILED",
      "User provisioning could not be completed.",
      500,
    );
  }
}

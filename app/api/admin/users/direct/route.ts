import { NextResponse } from "next/server";
import { getCurrentIdentity, USER_ROLES, type UserRole } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";

function isUserRole(value: unknown): value is UserRole {
  return USER_ROLES.includes(value as UserRole);
}

function normalizeEmail(value: unknown): string {
  return String(value ?? "").trim().toLowerCase();
}

function badRequest(message: string) {
  return NextResponse.json({ error: message }, { status: 400 });
}

export async function POST(request: Request) {
  const identity = await getCurrentIdentity();

  if (!identity || identity.role !== "administrator") {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  try {
    const body = await request.json();
    const displayName = String(body.display_name ?? "").trim();
    const email = normalizeEmail(body.email);
    const department = String(body.department ?? "").trim();
    const tradeDiscipline = String(body.trade_discipline ?? "").trim();
    const contactNumber = String(body.contact_number ?? "").trim();
    const temporaryPassword = String(body.temporary_password ?? "");
    const role = String(body.role ?? "") as UserRole;
    const mode =
      body.mode === "activate_pending" ? "activate_pending" : "create";

    if (!displayName || !email || !department || !isUserRole(role)) {
      return badRequest(
        "Name, email, department/company and a valid role are required.",
      );
    }

    if (!email.includes("@")) {
      return badRequest("Enter a valid email address.");
    }

    if (temporaryPassword.length < 12) {
      return badRequest(
        "The temporary password must contain at least 12 characters.",
      );
    }

    if (role === "technician" && !tradeDiscipline) {
      return badRequest(
        "Trade or technical discipline is required for Technicians.",
      );
    }

    const admin = createAdminClient();
    const { data: listedUsers, error: listError } =
      await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });

    if (listError) {
      return NextResponse.json(
        { error: "Unable to check existing authentication users." },
        { status: 502 },
      );
    }

    const existingUser = listedUsers.users.find(
      (user) => user.email?.trim().toLowerCase() === email,
    );

    let userId: string;
    let createdNewAuthUser = false;

    if (mode === "activate_pending") {
      if (!existingUser) {
        return NextResponse.json(
          { error: "No pending authentication user exists for this email." },
          { status: 404 },
        );
      }

      const { error: activationError } =
        await admin.auth.admin.updateUserById(existingUser.id, {
          password: temporaryPassword,
          email_confirm: true,
          user_metadata: {
            display_name: displayName,
            department,
            trade_discipline:
              role === "technician" ? tradeDiscipline : null,
            contact_number: contactNumber || null,
          },
        });

      if (activationError) {
        return NextResponse.json(
          { error: activationError.message },
          { status: 400 },
        );
      }

      userId = existingUser.id;
    } else {
      if (existingUser) {
        return NextResponse.json(
          {
            error:
              "An authentication user already exists for this email. Use Activate pending account instead.",
          },
          { status: 409 },
        );
      }

      const { data: created, error: createError } =
        await admin.auth.admin.createUser({
          email,
          password: temporaryPassword,
          email_confirm: true,
          user_metadata: {
            display_name: displayName,
            department,
            trade_discipline:
              role === "technician" ? tradeDiscipline : null,
            contact_number: contactNumber || null,
          },
        });

      if (createError || !created.user) {
        return NextResponse.json(
          { error: createError?.message ?? "Unable to create user." },
          { status: 400 },
        );
      }

      userId = created.user.id;
      createdNewAuthUser = true;
    }

    const profile = {
      id: userId,
      display_name: displayName,
      email,
      department,
      trade_discipline: role === "technician" ? tradeDiscipline : null,
      contact_number: contactNumber || null,
      role,
      is_active: true,
      deleted_at: null,
      updated_at: new Date().toISOString(),
    };

    const { error: profileError } = await admin
      .from("profiles")
      .upsert(profile, { onConflict: "id" });

    if (profileError) {
      if (createdNewAuthUser) {
        await admin.auth.admin.deleteUser(userId);
      }

      return NextResponse.json(
        {
          error: createdNewAuthUser
            ? "The profile could not be created, so the new Auth user was removed."
            : "The pending Auth user was activated, but its profile could not be updated.",
        },
        { status: 500 },
      );
    }

    const { error: auditError } = await admin.from("activity_logs").insert({
      user_id: identity.userId,
      action:
        mode === "activate_pending"
          ? "user_admin_pending_activated"
          : "user_admin_direct_created",
      actor: identity.displayName,
      note: JSON.stringify({
        target_user_id: userId,
        email,
        role,
        email_confirmed_by_administrator: true,
      }),
    });

    if (auditError) {
      return NextResponse.json(
        {
          error:
            "The account is active, but the administrator audit entry could not be recorded.",
        },
        { status: 500 },
      );
    }

    return NextResponse.json({
      success: true,
      user_id: userId,
      message:
        mode === "activate_pending"
          ? "Pending account activated. The user can sign in immediately with the temporary password."
          : "User created and activated. The user can sign in immediately with the temporary password.",
    });
  } catch (error) {
    console.error("Direct administrator user provisioning error:", error);

    return NextResponse.json(
      { error: "Unable to provision the user." },
      { status: 500 },
    );
  }
}

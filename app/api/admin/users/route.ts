import { createHash, randomBytes } from "crypto";
import { NextResponse } from "next/server";
import { USER_ROLES, getCurrentIdentity, type UserRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

function isUserRole(value: unknown): value is UserRole {
  return USER_ROLES.includes(value as UserRole);
}

async function requireAdministrator() {
  const identity = await getCurrentIdentity();
  return identity?.role === "administrator" ? identity : null;
}

export async function GET() {
  const identity = await requireAdministrator();
  if (!identity) {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  try {
    const supabase = await createClient();
    const admin = createAdminClient();
    const [
      { data: profiles, error: profileError },
      { data: authData, error: authError },
      { data: audit, error: auditError },
    ] = await Promise.all([
      supabase
        .from("profiles")
        .select(
          "id, display_name, email, department, trade_discipline, contact_number, role, is_active, deleted_at, created_at, updated_at",
        )
        .order("created_at", { ascending: false }),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
      supabase
        .from("activity_logs")
        .select("id, action, actor, note, created_at")
        .like("action", "user_admin_%")
        .order("created_at", { ascending: false })
        .limit(200),
    ]);

    if (profileError || authError || auditError) {
      return NextResponse.json(
        {
          error:
            profileError?.message ??
            authError?.message ??
            auditError?.message ??
            "Unable to load users.",
        },
        { status: 500 },
      );
    }

    const authUsers = new Map(
      authData.users.map((user) => [
        user.id,
        {
          lastSignInAt: user.last_sign_in_at ?? null,
          emailConfirmedAt: user.email_confirmed_at ?? null,
        },
      ]),
    );

    const users = (profiles ?? []).map((profile) => ({
      ...profile,
      last_sign_in_at: authUsers.get(profile.id)?.lastSignInAt ?? null,
      email_confirmed_at:
        authUsers.get(profile.id)?.emailConfirmedAt ?? null,
    }));

    return NextResponse.json({ users, audit: audit ?? [] });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Unable to load users.",
      },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  const identity = await requireAdministrator();
  if (!identity) {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  try {
    const body = await request.json();
    const displayName = String(body.display_name ?? "").trim();
    const email = String(body.email ?? "").trim().toLowerCase();
    const department = String(body.department ?? "").trim();
    const tradeDiscipline = String(body.trade_discipline ?? "").trim();
    const contactNumber = String(body.contact_number ?? "").trim();
    const role = String(body.role ?? "") as UserRole;
    const isActive = body.is_active !== false;

    if (!displayName || !email || !department || !isUserRole(role)) {
      return NextResponse.json(
        { error: "Name, email, department/company and a valid role are required." },
        { status: 400 },
      );
    }
    if (role === "technician" && !tradeDiscipline) {
      return NextResponse.json(
        { error: "Trade or technical discipline is required for Technicians." },
        { status: 400 },
      );
    }

    const supabase = await createClient();
    const admin = createAdminClient();
    const { data: existingProfile } = await supabase
      .from("profiles")
      .select("id")
      .ilike("email", email)
      .maybeSingle();
    if (existingProfile) {
      return NextResponse.json(
        { error: "A user with this email already exists." },
        { status: 409 },
      );
    }

    const rawToken = randomBytes(32).toString("base64url");
    const tokenHash = createHash("sha256").update(rawToken).digest("hex");
    const expiresAt = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();

    const { data: invitation, error: invitationError } = await supabase
      .from("account_invitations")
      .insert({
        email,
        display_name: displayName,
        department,
        assigned_role: role,
        is_active: isActive,
        token_hash: tokenHash,
        expires_at: expiresAt,
        created_by: identity.userId,
      })
      .select("id")
      .single();

    if (invitationError || !invitation) {
      const duplicate = invitationError?.code === "23505";
      return NextResponse.json(
        {
          error: duplicate
            ? "An active invitation or account already exists for this email."
            : invitationError?.message ?? "Unable to create invitation.",
        },
        { status: duplicate ? 409 : 400 },
      );
    }

    const { data: invited, error: inviteError } =
      await admin.auth.admin.inviteUserByEmail(email, {
        data: {
          administrator_invitation_token: rawToken,
          display_name: displayName,
          department,
          trade_discipline: role === "technician" ? tradeDiscipline : null,
          contact_number: contactNumber || null,
        },
        redirectTo: `${process.env.NEXT_PUBLIC_APP_URL ?? new URL(request.url).origin}/auth/callback`,
      });

    if (inviteError || !invited.user) {
      await supabase.from("account_invitations").delete().eq("id", invitation.id);
      return NextResponse.json(
        {
          error:
            inviteError?.message ??
            "Supabase could not create the invited Auth user.",
        },
        { status: 400 },
      );
    }

    await admin.auth.admin.updateUserById(invited.user.id, {
      user_metadata: {
        display_name: displayName,
        department,
        trade_discipline: role === "technician" ? tradeDiscipline : null,
        contact_number: contactNumber || null,
      },
    });

    const { error: profileUpdateError } = await supabase
      .from("profiles")
      .update({
        display_name: displayName,
        department,
        trade_discipline: role === "technician" ? tradeDiscipline : null,
        contact_number: contactNumber || null,
        is_active: isActive,
        deleted_at: null,
      })
      .eq("id", invited.user.id);

    if (profileUpdateError) {
      return NextResponse.json(
        { error: profileUpdateError.message },
        { status: 500 },
      );
    }

    const { error: auditError } = await admin.from("activity_logs").insert({
      user_id: identity.userId,
      action: "user_admin_invited",
      actor: identity.displayName,
      note: JSON.stringify({
        target_user_id: invited.user.id,
        target_email: email,
        assigned_role: role,
        is_active: isActive,
      }),
    });
    if (auditError) {
      return NextResponse.json(
        { error: "The user was invited, but the audit entry failed." },
        { status: 500 },
      );
    }

    return NextResponse.json(
      {
        success: true,
        message: `Invitation sent to ${email}. It expires in 48 hours.`,
      },
      { status: 201 },
    );
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Unable to invite user.",
      },
      { status: 500 },
    );
  }
}

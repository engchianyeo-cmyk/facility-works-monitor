import { NextResponse } from "next/server";
import { applicationCallbackUrl } from "@/lib/app-url";

const ADMIN_USER_ROLES = [
  "reviewer",
  "initiator",
  "approver",
  "technician",
  "supervisor",
  "administrator",
] as const;

type AdminUserRole = (typeof ADMIN_USER_ROLES)[number];

function isUserRole(value: unknown): value is AdminUserRole {
  return ADMIN_USER_ROLES.includes(value as AdminUserRole);
}

async function requireAdministrator() {
  const { getCurrentIdentity } = await import("@/lib/auth");
  const identity = await getCurrentIdentity();
  return identity?.role === "administrator" ? identity : null;
}

function presenceFor(profile: {
  is_active: boolean;
  deleted_at: string | null;
  last_active_at: string | null;
}) {
  if (!profile.is_active || profile.deleted_at || !profile.last_active_at) {
    return {
      presence_status: "offline" as const,
      session_status: "No recent authenticated heartbeat",
    };
  }

  const age = Date.now() - new Date(profile.last_active_at).getTime();
  if (!Number.isFinite(age) || age > 30 * 60 * 1000) {
    return {
      presence_status: "offline" as const,
      session_status: "No recent authenticated heartbeat",
    };
  }
  if (age > 5 * 60 * 1000) {
    return {
      presence_status: "idle" as const,
      session_status: "Authenticated heartbeat is aging",
    };
  }
  return {
    presence_status: "online" as const,
    session_status: "Recent authenticated heartbeat",
  };
}

export async function GET() {
  try {
    const identity = await requireAdministrator();
    if (!identity) {
      return NextResponse.json({ error: "Access denied." }, { status: 403 });
    }

    const [{ createClient }, adminModule] = await Promise.all([
      import("@/lib/supabase/server"),
      import("@/lib/supabase/admin"),
    ]);
    const supabase = await createClient();
    const provisioningConfigured = adminModule.isAdminConfigured();
    const admin = provisioningConfigured
      ? adminModule.createAdminClient()
      : null;
    const [
      { data: profiles, error: profileError },
      { data: authData, error: authError },
      { data: audit, error: auditError },
      { data: departments, error: departmentError },
    ] = await Promise.all([
      supabase
        .from("profiles")
        .select(
          "id, display_name, email, department, department_id, trade_discipline, contact_number, role, is_active, deleted_at, created_at, updated_at, last_active_at, last_seen_route",
        )
        .order("created_at", { ascending: false }),
      admin
        ? admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
        : Promise.resolve({ data: { users: [] }, error: null }),
      supabase
        .from("activity_logs")
        .select("id, action, actor, note, created_at")
        .like("action", "user_admin_%")
        .order("created_at", { ascending: false })
        .limit(200),
      supabase
        .from("departments")
        .select("id, name")
        .eq("is_active", true)
        .is("deleted_at", null)
        .order("name"),
    ]);

    if (profileError || auditError || departmentError) {
      return NextResponse.json(
        {
          error: "User management data could not be loaded.",
          code: "USER_MANAGEMENT_UNAVAILABLE",
        },
        { status: 503 },
      );
    }

    const authUsers = new Map(
      (authData?.users ?? []).map((user) => [
        user.id,
        {
          lastSignInAt: user.last_sign_in_at ?? null,
          emailConfirmedAt: user.email_confirmed_at ?? null,
        },
      ]),
    );

    const users = (profiles ?? []).map((profile) => {
      const presence = presenceFor(profile);
      return {
        ...profile,
        ...presence,
        last_sign_in_at: authUsers.get(profile.id)?.lastSignInAt ?? null,
        email_confirmed_at:
          authUsers.get(profile.id)?.emailConfirmedAt ?? null,
      };
    });

    return NextResponse.json({
      users,
      audit: audit ?? [],
      departments: departments ?? [],
      provisioning_configured: provisioningConfigured,
      auth_directory_available: provisioningConfigured && !authError,
    });
  } catch {
    return NextResponse.json(
      {
        error: "User management data could not be loaded.",
        code: "USER_MANAGEMENT_UNAVAILABLE",
      },
      { status: 503 },
    );
  }
}

export async function POST(request: Request) {
  try {
    const identity = await requireAdministrator();
    if (!identity) {
      return NextResponse.json({ error: "Access denied." }, { status: 403 });
    }

    const body = await request.json();
    const displayName = String(body.display_name ?? "").trim();
    const email = String(body.email ?? "").trim().toLowerCase();
    const department = String(body.department ?? "").trim();
    const tradeDiscipline = String(body.trade_discipline ?? "").trim();
    const contactNumber = String(body.contact_number ?? "").trim();
    const role = String(body.role ?? "") as AdminUserRole;
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

    const [{ createClient }, { createAdminClient }] = await Promise.all([
      import("@/lib/supabase/server"),
      import("@/lib/supabase/admin"),
    ]);
    const supabase = await createClient();
    const admin = createAdminClient();

    const { data: authUsers, error: authLookupError } =
      await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (authLookupError) {
      return NextResponse.json(
        { error: "Unable to verify whether this Auth user already exists." },
        { status: 502 },
      );
    }

    const existingAuthUser = authUsers.users.find(
      (user) => user.email?.trim().toLowerCase() === email,
    );
    const { data: existingProfile, error: existingProfileError } = await admin
      .from("profiles")
      .select("id")
      .ilike("email", email)
      .maybeSingle();
    if (existingProfileError) {
      return NextResponse.json(
        { error: "Unable to verify whether this user profile already exists." },
        { status: 500 },
      );
    }
    if (existingAuthUser) {
      return NextResponse.json(
        {
          error: existingProfile
            ? "An Auth user and profile already exist for this email."
            : "An Auth user already exists for this email but has no profile. Reconcile that account before retrying.",
        },
        { status: 409 },
      );
    }
    if (existingProfile) {
      return NextResponse.json(
        {
          error:
            "A profile already exists for this email without a matching Auth user. Reconcile that account before retrying.",
        },
        { status: 409 },
      );
    }

    const { createHash, randomBytes } = await import("crypto");
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
            : "Unable to create invitation.",
        },
        { status: duplicate ? 409 : 400 },
      );
    }

    const authErrorResponse = async () => {
      await admin
        .from("account_invitations")
        .delete()
        .eq("id", invitation.id);

      return NextResponse.json(
        {
          error: "Supabase could not create the invited Auth user.",
        },
        { status: 400 },
      );
    };

    let invited: { user: { id: string } } | null = null;
    try {
      const { data, error } =
        await admin.auth.admin.inviteUserByEmail(email, {
          data: {
            administrator_invitation_token: rawToken,
            display_name: displayName,
            department,
            trade_discipline: role === "technician" ? tradeDiscipline : null,
            contact_number: contactNumber || null,
          },
          redirectTo: applicationCallbackUrl(request.url),
        });

      if (error) {
        return await authErrorResponse();
      }
      invited = data;
    } catch {
      return await authErrorResponse();
    }

    if (!invited?.user) {
      return await authErrorResponse();
    }

    const rollbackInvitation = async () => {
      try {
        const [{ error: authDeleteError }, { error: invitationDeleteError }] =
          await Promise.all([
            admin.auth.admin.deleteUser(invited.user.id),
            admin
              .from("account_invitations")
              .delete()
              .eq("id", invitation.id),
          ]);

        if (authDeleteError || invitationDeleteError) {
          return false;
        }
        return true;
      } catch {
        return false;
      }
    };

    const profileValues = {
      id: invited.user.id,
      display_name: displayName,
      email,
      department,
      trade_discipline: role === "technician" ? tradeDiscipline : null,
      contact_number: contactNumber || null,
      role,
      is_active: isActive,
      deleted_at: null,
      updated_at: new Date().toISOString(),
    };
    const { data: triggeredProfile, error: profileLookupError } = await admin
      .from("profiles")
      .select("id")
      .eq("id", invited.user.id)
      .maybeSingle();

    const profileWrite = profileLookupError
      ? { error: profileLookupError }
      : triggeredProfile
        ? await admin
            .from("profiles")
            .update(profileValues)
            .eq("id", invited.user.id)
        : await admin
            .from("profiles")
            .upsert(profileValues, { onConflict: "id" });

    if (profileWrite.error) {
      const rolledBack = await rollbackInvitation();
      return NextResponse.json(
        {
          error: rolledBack
            ? "The Auth invitation was cancelled because its user profile could not be created with the selected role."
            : "The user profile could not be created and automatic cleanup was incomplete. Check Supabase Auth before retrying.",
        },
        { status: 500 },
      );
    }

    const {
      data: verifiedProfiles,
      error: profileVerificationError,
      count: verifiedProfileCount,
    } = await admin
      .from("profiles")
      .select("id, role", { count: "exact" })
      .eq("id", invited.user.id)
      .eq("role", role);

    if (
      profileVerificationError ||
      verifiedProfileCount !== 1 ||
      verifiedProfiles?.length !== 1
    ) {
      const rolledBack = await rollbackInvitation();
      return NextResponse.json(
        {
          error: rolledBack
            ? "The Auth invitation was cancelled because exactly one matching user profile could not be verified."
            : "Profile verification failed and automatic cleanup was incomplete. Check Supabase Auth before retrying.",
        },
        { status: 500 },
      );
    }

    const { error: metadataError } = await admin.auth.admin.updateUserById(
      invited.user.id,
      {
        user_metadata: {
          display_name: displayName,
          department,
          trade_discipline: role === "technician" ? tradeDiscipline : null,
          contact_number: contactNumber || null,
        },
      },
    );

    if (metadataError) {
      const rolledBack = await rollbackInvitation();
      return NextResponse.json(
        {
          error: rolledBack
            ? "The invitation was cancelled because the Auth user metadata could not be finalized."
            : "The Auth user metadata could not be finalized and automatic cleanup was incomplete. Check Supabase Auth before retrying.",
        },
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
      const rolledBack = await rollbackInvitation();
      return NextResponse.json(
        {
          error: rolledBack
            ? "The invitation was cancelled because its audit entry could not be created."
            : "The audit entry failed and automatic cleanup was incomplete. Check Supabase Auth before retrying.",
        },
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
  } catch {
    return NextResponse.json(
      {
        success: false,
        error: "User invitation could not be completed.",
      },
      { status: 500 },
    );
  }
}

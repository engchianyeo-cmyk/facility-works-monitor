import { NextResponse } from "next/server";

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

function logSafeAdminError(
  stage: string,
  error: { code?: string; message?: string } | null | undefined,
) {
  console.error("Administrator user creation failed", {
    stage,
    code: error?.code ?? null,
    message: error?.message ?? "Unknown error",
  });
}

function sanitizedErrorMessage(error: unknown): string {
  if (!(error instanceof Error)) return "Unknown server error.";

  return error.message
    .replace(/\beyJ[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){1,2}\b/g, "[redacted]")
    .replace(/\bsb_(?:secret|publishable)_[A-Za-z0-9_-]+\b/g, "[redacted]")
    .replace(/([?&](?:token|code)=)[^&\s]+/gi, "$1[redacted]")
    .slice(0, 300);
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

    const [{ createClient }, { createAdminClient }] = await Promise.all([
      import("@/lib/supabase/server"),
      import("@/lib/supabase/admin"),
    ]);
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
          "id, display_name, email, department, trade_discipline, contact_number, role, is_active, deleted_at, created_at, updated_at, last_active_at, last_seen_route",
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
  console.info("[admin-users] stage=post-entry");
  let currentStage = "administrator-check";
  try {
    const identity = await requireAdministrator();
    if (!identity) {
      return NextResponse.json({ error: "Access denied." }, { status: 403 });
    }

    currentStage = "request-validation";
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

    currentStage = "supabase-client-initialization";
    const [{ createClient }, { createAdminClient }] = await Promise.all([
      import("@/lib/supabase/server"),
      import("@/lib/supabase/admin"),
    ]);
    const supabase = await createClient();
    const admin = createAdminClient();

    currentStage = "existing-user-check";
    const { data: authUsers, error: authLookupError } =
      await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (authLookupError) {
      logSafeAdminError(currentStage, authLookupError);
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
      logSafeAdminError(currentStage, existingProfileError);
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

    currentStage = "invitation-token-generation";
    const { createHash, randomBytes } = await import("crypto");
    const rawToken = randomBytes(32).toString("base64url");
    const tokenHash = createHash("sha256").update(rawToken).digest("hex");
    const expiresAt = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();

    currentStage = "invitation-creation";
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
      logSafeAdminError(currentStage, invitationError);
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

    currentStage = "auth-user-creation";
    type AuthCreationError = Error & {
      status?: number;
      code?: string;
      cause?: unknown;
    };
    const authErrorResponse = async (
      error: AuthCreationError | null,
    ) => {
      console.error("[admin-users] Auth creation error", {
        name: error?.name ?? null,
        message: error?.message ?? null,
        status: error?.status ?? null,
        code: error?.code ?? null,
        cause:
          error?.cause instanceof Error
            ? error.cause.message
            : error?.cause ?? null,
        stack: error?.stack ?? null,
      });
      await admin
        .from("account_invitations")
        .delete()
        .eq("id", invitation.id);

      return NextResponse.json(
        {
          error: "Supabase could not create the invited Auth user.",
          ...(process.env.NODE_ENV === "development"
            ? {
                details: {
                  message:
                    error?.message ?? "Unknown Supabase Auth error",
                  status: error?.status ?? null,
                  code: error?.code ?? null,
                  name: error?.name ?? null,
                },
              }
            : {}),
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
          redirectTo: `${process.env.NEXT_PUBLIC_APP_URL ?? new URL(request.url).origin}/auth/callback`,
        });

      if (error) {
        return await authErrorResponse(error);
      }
      invited = data;
    } catch (error) {
      return await authErrorResponse(
        error instanceof Error ? (error as AuthCreationError) : null,
      );
    }

    if (!invited?.user) {
      return await authErrorResponse(null);
    }

    const rollbackInvitation = async () => {
      currentStage = "rollback";
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
          logSafeAdminError(
            currentStage,
            authDeleteError ?? invitationDeleteError,
          );
          return false;
        }
        return true;
      } catch (rollbackError) {
        logSafeAdminError(
          currentStage,
          rollbackError instanceof Error ? rollbackError : null,
        );
        return false;
      }
    };

    currentStage = "profile-lookup";
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

    currentStage = "profile-upsert";
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
      logSafeAdminError(
        profileLookupError ? "profile-lookup" : currentStage,
        profileWrite.error,
      );
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

    currentStage = "profile-verification";
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
      logSafeAdminError(currentStage, profileVerificationError);
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

    currentStage = "auth-metadata-update";
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
      logSafeAdminError(currentStage, metadataError);
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

    currentStage = "audit-creation";
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
      logSafeAdminError(currentStage, auditError);
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
  } catch (error) {
    logSafeAdminError(
      currentStage,
      error instanceof Error ? error : null,
    );
    return NextResponse.json(
      {
        success: false,
        stage: currentStage,
        error: sanitizedErrorMessage(error),
      },
      { status: 500 },
    );
  }
}

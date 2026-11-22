import { NextResponse } from "next/server";
import { applicationCallbackUrl } from "@/lib/app-url";

const ADMIN_USER_ROLES = [
  "reviewer",
  "initiator",
  "approver",
  "technician",
  "supervisor",
  "facility_manager",
  "administrator",
  "finance",
] as const;

type AdminUserRole = (typeof ADMIN_USER_ROLES)[number];

function isUserRole(value: unknown): value is AdminUserRole {
  return ADMIN_USER_ROLES.includes(value as AdminUserRole);
}

type VisibleMembership = { profile_id: string; facility_id: string; membership_role: string };
async function visibleMemberships(): Promise<VisibleMembership[]> {
  const { createClient } = await import("@/lib/supabase/server");
  const supabase = await createClient();
  const { data } = await supabase.rpc("visible_facility_memberships");
  return (data ?? []) as VisibleMembership[];
}

// UAT 18 Nov 2026: filter users by facility. Each user's current facilities (active memberships) and the facility list.
type FacilityRef = { id: string; name: string };
// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function facilitiesFor(client: any, profileIds: string[], facilityIds?: string[]) {
  try {
    return await facilitiesLookup(client, profileIds, facilityIds);
  } catch {
    // The facility filter is a convenience; the user list still loads without it.
    return { facilities: [] as FacilityRef[], byProfile: new Map<string, FacilityRef[]>() };
  }
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function facilitiesLookup(client: any, profileIds: string[], facilityIds?: string[]) {
  let siteQuery = client.from("sites").select("id, name").eq("is_active", true).order("name");
  if (facilityIds) siteQuery = siteQuery.in("id", facilityIds.length ? facilityIds : ["00000000-0000-0000-0000-000000000000"]);
  // 21 Nov 2026: memberships are read as the signed-in person (the service key has no access to facility_memberships).
  const wanted = new Set(profileIds);
  const [{ data: sites }, rows] = await Promise.all([siteQuery, visibleMemberships()]);
  const siteList = (sites ?? []) as FacilityRef[];
  const names = new Map(siteList.map((site) => [site.id, site.name]));
  const byProfile = new Map<string, FacilityRef[]>();
  for (const row of rows) {
    if (!wanted.has(row.profile_id)) continue;
    const name = names.get(row.facility_id);
    if (!name) continue;
    const list = byProfile.get(row.profile_id) ?? [];
    if (!list.some((item) => item.id === row.facility_id)) list.push({ id: row.facility_id, name });
    byProfile.set(row.profile_id, list);
  }
  return { facilities: siteList, byProfile };
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
      session_status: "No activity recorded yet",
    };
  }

  const age = Date.now() - new Date(profile.last_active_at).getTime();
  // UAT 9 Nov 2026: plain words instead of "heartbeat is aging".
  const minutes = Math.max(1, Math.round(age / 60000));
  if (!Number.isFinite(age) || age > 30 * 60 * 1000) {
    return {
      presence_status: "offline" as const,
      session_status: "Not active in the last 30 minutes",
    };
  }
  if (age > 5 * 60 * 1000) {
    return {
      presence_status: "idle" as const,
      session_status: `Idle — last active ${minutes} min ago`,
    };
  }
  return {
    presence_status: "online" as const,
    session_status: "Using the app now (last 5 minutes)",
  };
}

export async function GET() {
  try {
    const { getCurrentIdentity } = await import("@/lib/auth");
    const caller = await getCurrentIdentity();
    // D-54: a Facility Administrator sees only the staff of its own facilities (no audit trail of other people).
    if (caller?.role === "facility_administrator") return facilityStaffDirectory(caller.userId);
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
          "id, display_name, email, department, department_id, trade_discipline, contact_number, role, is_active, deleted_at, password_change_required, created_at, updated_at, last_active_at, last_seen_route",
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

    const scope = await facilitiesFor(admin ?? supabase, (profiles ?? []).map((profile) => profile.id));
    const users = (profiles ?? []).map((profile) => {
      const presence = presenceFor(profile);
      return {
        ...profile,
        ...presence,
        facilities: scope.byProfile.get(profile.id) ?? [],
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
      facilities: scope.facilities,
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

async function facilityStaffDirectory(callerId: string) {
  const adminModule = await import("@/lib/supabase/admin");
  if (!adminModule.isAdminConfigured()) {
    return NextResponse.json({ users: [], audit: [], departments: [], provisioning_configured: false, auth_directory_available: false });
  }
  const admin = adminModule.createAdminClient();
  const visible = await visibleMemberships();
  const facilityIds = Array.from(new Set(visible.filter((row) => row.profile_id === callerId && row.membership_role === "facility_administrator").map((row) => row.facility_id)));
  const ids = Array.from(new Set(visible.filter((row) => facilityIds.includes(row.facility_id)).map((row) => row.profile_id)));
  const [{ data: profiles, error }, { data: departments }] = await Promise.all([
    ids.length
      ? admin.from("profiles").select("id, display_name, email, department, department_id, trade_discipline, contact_number, role, is_active, deleted_at, password_change_required, created_at, updated_at, last_active_at, last_seen_route")
        .in("id", ids).order("created_at", { ascending: false })
      : Promise.resolve({ data: [], error: null }),
    admin.from("departments").select("id, name").eq("is_active", true).is("deleted_at", null).order("name"),
  ]);
  if (error) {
    return NextResponse.json({ error: "User management data could not be loaded.", code: "USER_MANAGEMENT_UNAVAILABLE" }, { status: 503 });
  }
  const users = ((profiles ?? []) as Array<{ is_active: boolean; deleted_at: string | null; last_active_at: string | null } & Record<string, unknown>>)
    .map((profile) => profile);
  const scope = await facilitiesFor(admin, ids, facilityIds);
  const listed = users.map((profile) => ({ ...profile, ...presenceFor(profile), facilities: scope.byProfile.get(String(profile.id)) ?? [], last_sign_in_at: null, email_confirmed_at: null }));
  return NextResponse.json({ users: listed, audit: [], departments: departments ?? [], provisioning_configured: true, auth_directory_available: false, facility_scope: true, facilities: scope.facilities });
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

    const { data: departmentRecord, error: departmentError } = await supabase
      .from("departments")
      .select("id, name")
      .ilike("name", department)
      .eq("is_active", true)
      .is("deleted_at", null)
      .maybeSingle();
    if (departmentError || !departmentRecord) {
      return NextResponse.json(
        { error: "Select an active department." },
        { status: departmentError ? 503 : 400 },
      );
    }

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
        // Keep the invitation ticket usable even when the requested profile
        // should begin inactive. Finalization owns the profile state.
        is_active: true,
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

    const { data: reconciledProfile, error: reconciliationError } = await supabase.rpc(
      "admin_finalize_provisioned_profile",
      {
        p_target_id: invited.user.id,
        p_payload: {
          display_name: displayName,
          department_id: departmentRecord.id,
          trade_discipline: role === "technician" ? tradeDiscipline : null,
          contact_number: contactNumber || null,
          role,
          is_active: isActive,
        },
        p_event: "user_admin_invited",
      },
    );
    if (reconciliationError || !reconciledProfile) {
      const rolledBack = await rollbackInvitation();
      return NextResponse.json(
        {
          error: rolledBack
            ? "The invitation was cancelled because the profile and audit transaction could not be completed."
            : "The Auth invitation exists, but its profile remains inactive because reconciliation failed. Administrator review is required.",
        },
        { status: rolledBack ? 500 : 409 },
      );
    }

    return NextResponse.json(
      {
        success: true,
        message: `Invitation requested for ${email}. The user must set a private password before operational access.`,
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

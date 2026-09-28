import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

const CODE_PATTERN = /^[A-Z0-9][A-Z0-9_-]{0,23}$/;
const COLOUR_PATTERN = /^#[0-9A-Fa-f]{6}$/;

function validateDepartment(body: Record<string, unknown>) {
  const code = String(body.code ?? "").trim().toUpperCase();
  const name = String(body.name ?? "").trim();
  const colourTag = String(body.colour_tag ?? "").trim() || null;

  if (!CODE_PATTERN.test(code)) {
    return { error: "Code must be 1–24 characters using letters, numbers, hyphens or underscores." };
  }
  if (!name || name.length > 120) {
    return { error: "Name is required and must not exceed 120 characters." };
  }
  if (colourTag && !COLOUR_PATTERN.test(colourTag)) {
    return { error: "Colour tag must be a six-digit hexadecimal value such as #2563EB." };
  }

  return {
    value: {
      code,
      name,
      description: String(body.description ?? "").trim() || null,
      cost_centre: String(body.cost_centre ?? "").trim() || null,
      manager_id: String(body.manager_id ?? "").trim() || null,
      parent_department_id:
        String(body.parent_department_id ?? "").trim() || null,
      colour_tag: colourTag,
      is_active: body.is_active !== false,
    },
  };
}

async function requireAdministrator() {
  const identity = await getCurrentIdentity();
  return identity?.role === "administrator" ? identity : null;
}

type DepartmentRpcResult = {
  ok: boolean;
  code?: string;
  message?: string;
  active_user_count?: number;
  department?: Record<string, unknown>;
};

function resultStatus(code?: string) {
  if (code === "access_denied") return 403;
  if (code === "not_found") return 404;
  if (code === "duplicate_department" || code === "active_users_assigned") return 409;
  if (code === "internal_error") return 500;
  return 400;
}

function rpcFailure(message: string) {
  return NextResponse.json({ error: message }, { status: 500 });
}

function structuredFailure(result: DepartmentRpcResult) {
  const message =
    result.code === "active_users_assigned" && result.active_user_count
      ? `Department cannot be archived while ${result.active_user_count} active user${result.active_user_count === 1 ? " is" : "s are"} assigned to it.`
      : result.message ?? "Department operation failed.";
  return NextResponse.json(
    { error: message, code: result.code },
    { status: resultStatus(result.code) },
  );
}

export async function GET() {
  const identity = await requireAdministrator();
  if (!identity) {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  const admin = createAdminClient();
  const [{ data: departments, error }, { data: profiles, error: profileError }] =
    await Promise.all([
      admin
        .from("departments")
        .select("id, code, name, description, cost_centre, manager_id, parent_department_id, colour_tag, is_active, created_at, updated_at, deleted_at")
        .order("name"),
      admin
        .from("profiles")
        .select("id, display_name, department_id, role, is_active, deleted_at")
        .is("deleted_at", null),
    ]);

  if (error || profileError) {
    return NextResponse.json(
      { error: error?.message ?? profileError?.message ?? "Unable to load departments." },
      { status: 500 },
    );
  }

  const activeCounts = new Map<string, number>();
  for (const profile of profiles ?? []) {
    if (profile.is_active && profile.department_id) {
      activeCounts.set(
        profile.department_id,
        (activeCounts.get(profile.department_id) ?? 0) + 1,
      );
    }
  }

  return NextResponse.json({
    departments: (departments ?? []).map((department) => ({
      ...department,
      active_user_count: activeCounts.get(department.id) ?? 0,
    })),
    managers: (profiles ?? [])
      .filter((profile) =>
        profile.is_active &&
        ["supervisor", "administrator"].includes(profile.role),
      )
      .map(({ id, display_name }) => ({ id, display_name })),
  });
}

export async function POST(request: Request) {
  const identity = await requireAdministrator();
  if (!identity) {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  try {
    const parsed = validateDepartment(await request.json());
    if (parsed.error || !parsed.value) {
      return NextResponse.json({ error: parsed.error }, { status: 400 });
    }

    const supabase = await createClient();
    const { data, error } = await supabase.rpc("create_department", {
      p_code: parsed.value.code,
      p_name: parsed.value.name,
      p_description: parsed.value.description,
      p_cost_centre: parsed.value.cost_centre,
      p_manager_id: parsed.value.manager_id,
      p_parent_department_id: parsed.value.parent_department_id,
      p_colour_tag: parsed.value.colour_tag,
      p_is_active: parsed.value.is_active,
    });

    if (error) return rpcFailure("Department creation failed.");
    const result = data as DepartmentRpcResult | null;
    if (!result) return rpcFailure("Department creation returned no result.");
    if (!result.ok) return structuredFailure(result);
    return NextResponse.json({ department: result.department }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "Unable to create department." }, { status: 500 });
  }
}

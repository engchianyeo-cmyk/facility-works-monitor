import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

type RouteContext = { params: Promise<{ id: string }> };
type DepartmentRpcResult = {
  ok: boolean;
  code?: string;
  message?: string;
  active_user_count?: number;
  department?: Record<string, unknown>;
};

const CODE_PATTERN = /^[A-Z0-9][A-Z0-9_-]{0,23}$/;
const COLOUR_PATTERN = /^#[0-9A-Fa-f]{6}$/;

function validateDepartment(body: Record<string, unknown>) {
  const code = String(body.code ?? "").trim().toUpperCase();
  const name = String(body.name ?? "").trim();
  const colourTag = String(body.colour_tag ?? "").trim() || null;

  if (!CODE_PATTERN.test(code)) {
    return {
      error:
        "Code must be 1–24 characters using letters, numbers, hyphens or underscores.",
    };
  }
  if (!name || name.length > 120) {
    return { error: "Name is required and must not exceed 120 characters." };
  }
  if (colourTag && !COLOUR_PATTERN.test(colourTag)) {
    return {
      error:
        "Colour tag must be a six-digit hexadecimal value such as #2563EB.",
    };
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

function resultStatus(code?: string) {
  if (code === "access_denied") return 403;
  if (code === "not_found") return 404;
  if (code === "duplicate_department" || code === "active_users_assigned") {
    return 409;
  }
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

async function requireAdministrator() {
  const identity = await getCurrentIdentity();
  return identity?.role === "administrator" ? identity : null;
}

export async function PATCH(request: Request, context: RouteContext) {
  const identity = await requireAdministrator();
  if (!identity) {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  try {
    const { id } = await context.params;
    const parsed = validateDepartment(await request.json());
    if (parsed.error || !parsed.value) {
      return NextResponse.json({ error: parsed.error }, { status: 400 });
    }

    const supabase = await createClient();
    const { data, error } = await supabase.rpc("update_department", {
      p_department_id: id,
      p_code: parsed.value.code,
      p_name: parsed.value.name,
      p_description: parsed.value.description,
      p_cost_centre: parsed.value.cost_centre,
      p_manager_id: parsed.value.manager_id,
      p_parent_department_id: parsed.value.parent_department_id,
      p_colour_tag: parsed.value.colour_tag,
      p_is_active: parsed.value.is_active,
    });

    if (error) return rpcFailure("Department update failed.");
    const result = data as DepartmentRpcResult | null;
    if (!result) return rpcFailure("Department update returned no result.");
    if (!result.ok) return structuredFailure(result);
    return NextResponse.json({ department: result.department });
  } catch {
    return NextResponse.json(
      { error: "Unable to update department." },
      { status: 500 },
    );
  }
}

export async function DELETE(_request: Request, context: RouteContext) {
  const identity = await requireAdministrator();
  if (!identity) {
    return NextResponse.json({ error: "Access denied." }, { status: 403 });
  }

  try {
    const { id } = await context.params;
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("archive_department", {
      p_department_id: id,
    });

    if (error) return rpcFailure("Department archive failed.");
    const result = data as DepartmentRpcResult | null;
    if (!result) return rpcFailure("Department archive returned no result.");
    if (!result.ok) return structuredFailure(result);
    return NextResponse.json({ success: true, department: result.department });
  } catch {
    return NextResponse.json(
      { error: "Unable to archive department." },
      { status: 500 },
    );
  }
}

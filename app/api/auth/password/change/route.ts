import { NextResponse } from "next/server";
import { isUserRole } from "@/lib/auth";
import { validatePasswordChange } from "@/lib/auth/password";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });

  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const validation = validatePasswordChange(body.password, body.confirmation);
  if (!validation.ok) return NextResponse.json({ error: validation.error }, { status: 400 });

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role,is_active,deleted_at")
    .eq("id", user.id)
    .maybeSingle();
  if (profileError || !profile || !profile.is_active || profile.deleted_at || !isUserRole(profile.role)) {
    return NextResponse.json({ error: "This account is not eligible for a password change." }, { status: 403 });
  }

  let admin;
  try {
    admin = createAdminClient();
  } catch {
    return NextResponse.json({ error: "Password administration is not configured." }, { status: 503 });
  }

  const { error: authError } = await admin.auth.admin.updateUserById(user.id, {
    password: validation.password,
  });
  if (authError) {
    console.warn("[password-change] Supabase password update failed", {
      status: authError.status,
      code: authError.code,
      name: authError.name,
    });

    return NextResponse.json(
      { error: "The password could not be changed." },
      { status: 422 },
    );
  }
  const { error: reconciliationError } = await admin.rpc("complete_password_change_trusted", {
    p_user_id: user.id,
  });
  if (reconciliationError) {
    return NextResponse.json({
      error: "The password changed, but account access remains locked because reconciliation did not complete. Contact an Administrator.",
      reconciliation_required: true,
    }, { status: 409 });
  }

  const requestedNext = typeof body.next === "string" && body.next.startsWith("/") && !body.next.startsWith("//")
    ? body.next
    : profile.role === "technician" ? "/operations" : "/";
  return NextResponse.json({ ok: true, next: requestedNext }, { headers: { "cache-control": "no-store" } });
}

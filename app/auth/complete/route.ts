import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { isUserRole } from "@/lib/auth";

export async function GET(request: Request) {
  const requestUrl = new URL(request.url);
  const requestedNext = requestUrl.searchParams.get("next");
  const safeNext =
    requestedNext?.startsWith("/") && !requestedNext.startsWith("//")
      ? requestedNext
      : "/";
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.redirect(
      new URL("/login?error=Your%20session%20could%20not%20be%20started.", requestUrl.origin),
    );
  }

  let admin;
  try {
    admin = createAdminClient();
  } catch {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=Your%20account%20could%20not%20be%20checked.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("role, is_active, deleted_at, password_change_required")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=Your%20account%20could%20not%20be%20checked.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  if (!profile) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=Your%20account%20profile%20is%20missing.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  if (profile.deleted_at) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=This%20account%20has%20been%20archived.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  if (profile.is_active !== true) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=This%20account%20is%20inactive.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  if (!isUserRole(profile.role)) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=Your%20account%20role%20is%20not%20supported.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  if (profile.password_change_required === true) {
    const passwordUrl = new URL("/account/password", requestUrl.origin);
    passwordUrl.searchParams.set("setup", "required");
    passwordUrl.searchParams.set("next", safeNext);
    return NextResponse.redirect(passwordUrl);
  }

  const { data: operationallyReady, error: readinessError } = await supabase.rpc(
    "pilot_account_ready",
    { p_user_id: user.id },
  );
  if (readinessError || operationallyReady !== true) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=Your%20account%20setup%20is%20not%20ready%20for%20operational%20access.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  const roleDefault = profile.role === "technician" ? "/operations" : "/";
  return NextResponse.redirect(new URL(safeNext === "/" ? roleDefault : safeNext, requestUrl.origin));
}

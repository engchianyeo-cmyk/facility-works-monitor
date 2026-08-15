import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
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

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role, is_active, deleted_at, password_change_required")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError || !profile) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=Your%20account%20profile%20is%20not%20available.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  if (profile.is_active !== true || profile.deleted_at) {
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

  const roleDefault = profile.role === "technician" ? "/operations" : "/";
  return NextResponse.redirect(new URL(safeNext === "/" ? roleDefault : safeNext, requestUrl.origin));
}

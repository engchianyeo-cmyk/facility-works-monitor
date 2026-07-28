import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { USER_ROLES, type UserRole } from "@/lib/auth";

function isUserRole(value: unknown): value is UserRole {
  return USER_ROLES.includes(value as UserRole);
}

export async function GET(request: Request) {
  const requestUrl = new URL(request.url);
  const requestedNext = requestUrl.searchParams.get("next");
  const safeNext =
    requestedNext?.startsWith("/") && !requestedNext.startsWith("//")
      ? requestedNext
      : "/works";
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.redirect(
      new URL("/login?error=Your%20session%20could%20not%20be%20started.", requestUrl.origin),
    );
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("role, is_active")
    .eq("id", user.id)
    .maybeSingle();

  if (profile?.is_active === false) {
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL(
        "/login?error=This%20account%20is%20inactive.%20Contact%20an%20Administrator.",
        requestUrl.origin,
      ),
    );
  }

  const role: UserRole = isUserRole(profile?.role)
    ? profile.role
    : "reviewer";
  const destination = role === "technician" ? "/works" : safeNext;

  return NextResponse.redirect(new URL(destination, requestUrl.origin));
}

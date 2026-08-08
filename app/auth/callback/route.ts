import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const requestedNext = requestUrl.searchParams.get("next");
  const nextPath =
    requestedNext?.startsWith("/") && !requestedNext.startsWith("//")
      ? requestedNext
      : "/works";

  if (!code) {
    return NextResponse.redirect(
      new URL("/login?error=Missing%20confirmation%20code", requestUrl.origin),
    );
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    const loginUrl = new URL("/login", requestUrl.origin);
    loginUrl.searchParams.set(
      "error",
      "The confirmation link could not be completed. Request a new link or contact an Administrator.",
    );
    return NextResponse.redirect(loginUrl);
  }

  const completeUrl = new URL("/auth/complete", requestUrl.origin);
  completeUrl.searchParams.set("next", nextPath);
  return NextResponse.redirect(completeUrl);
}

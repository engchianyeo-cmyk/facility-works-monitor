import { createServerClient, type SetAllCookies } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { isUserRole } from "@/lib/auth";

type CookieToSet = Parameters<SetAllCookies>[0][number];

export async function GET(request: NextRequest) {
  const requestUrl = request.nextUrl.clone();
  const code = requestUrl.searchParams.get("code");
  const requestedNext = requestUrl.searchParams.get("next");

  const nextPath =
    requestedNext?.startsWith("/") && !requestedNext.startsWith("//")
      ? requestedNext
      : "/";

  if (!code) {
    return NextResponse.redirect(
      new URL(
        "/login?error=Missing%20confirmation%20code",
        requestUrl.origin,
      ),
    );
  }

  const cookiesToSet: CookieToSet[] = [];

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookies: CookieToSet[]) {
          cookiesToSet.push(...cookies);
        },
      },
    },
  );

  const {
    data: exchangeData,
    error: exchangeError,
  } = await supabase.auth.exchangeCodeForSession(code);

  if (exchangeError || !exchangeData.user) {
    console.warn("[auth-callback] Code exchange failed", {
      status: exchangeError?.status ?? null,
      code: exchangeError?.code ?? null,
      name: exchangeError?.name ?? null,
    });

    const loginUrl = new URL("/login", requestUrl.origin);
    loginUrl.searchParams.set(
      "error",
      "The confirmation link could not be completed. Request a new link or contact an Administrator.",
    );

    return NextResponse.redirect(loginUrl);
  }

  const user = exchangeData.user;

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role, is_active, deleted_at, password_change_required")
    .eq("id", user.id)
    .maybeSingle();

  if (
    profileError ||
    !profile ||
    profile.is_active !== true ||
    profile.deleted_at ||
    !isUserRole(profile.role)
  ) {
    const loginUrl = new URL("/login", requestUrl.origin);
    loginUrl.searchParams.set(
      "error",
      "Your account profile is not available for access. Contact an Administrator.",
    );

    const response = NextResponse.redirect(loginUrl);

    cookiesToSet.forEach(({ name, value, options }) => {
      response.cookies.set(name, value, options);
    });

    return response;
  }

  const roleDefault =
    profile.role === "technician" ? "/operations" : "/";

  const target =
    nextPath === "/"
      ? roleDefault
      : nextPath;

  const destination = new URL(target, requestUrl.origin);

  if (
    target === "/account/password" ||
    profile.password_change_required === true
  ) {
    destination.pathname = "/account/password";
    destination.searchParams.set(
      "next",
      target === "/account/password" ? roleDefault : target,
    );
  }

  const response = NextResponse.redirect(destination);

  cookiesToSet.forEach(({ name, value, options }) => {
    response.cookies.set(name, value, options);
  });

  return response;
}

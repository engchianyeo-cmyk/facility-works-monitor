import { NextResponse } from "next/server";
import { applicationCallbackUrl } from "@/lib/app-url";
import { createClient } from "@/lib/supabase/server";

const GENERIC_RESPONSE = {
  ok: true,
  message: "If the account is eligible, recovery instructions were requested.",
};

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { email?: unknown };
    const email = typeof body.email === "string" ? body.email.trim() : "";
    if (email && email.length <= 320) {
      const callback = new URL(applicationCallbackUrl(request.url));
      callback.searchParams.set("next", "/account/password");
      const supabase = await createClient();
      await supabase.auth.resetPasswordForEmail(email, { redirectTo: callback.toString() });
    }
  } catch {
    // Intentionally return the same response for malformed, unknown, throttled,
    // and unavailable accounts to avoid account enumeration.
  }
  return NextResponse.json(GENERIC_RESPONSE, { status: 202, headers: { "cache-control": "no-store" } });
}

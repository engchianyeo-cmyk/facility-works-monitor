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

      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: callback.toString(),
      });

      if (error) {
        console.warn("[password-recovery] Supabase recovery request failed", {
          status: error.status,
          code: error.code,
          name: error.name,
        });
      }
    }
  } catch (error) {
    console.warn("[password-recovery] Recovery request handling failed", {
      name: error instanceof Error ? error.name : "UnknownError",
    });

    // Intentionally return the same response for malformed, unknown, throttled,
    // and unavailable accounts to avoid account enumeration.
  }

  return NextResponse.json(GENERIC_RESPONSE, {
    status: 202,
    headers: {
      "cache-control": "no-store",
    },
  });
}
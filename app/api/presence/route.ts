import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) {
    return NextResponse.json(
      { error: "Authentication is required." },
      { status: 401 },
    );
  }

  try {
    const body = await request.json().catch(() => ({}));
    const requestedRoute =
      typeof body.route === "string" ? body.route.trim() : "";
    const route =
      requestedRoute.startsWith("/") && !requestedRoute.startsWith("//")
        ? requestedRoute.split("?")[0].slice(0, 200)
        : null;
    const supabase = await createClient();
    const { error } = await supabase.rpc("record_user_presence", {
      presence_route: route,
    });

    if (error) {
      return NextResponse.json(
        { error: "Unable to record activity." },
        { status: 400 },
      );
    }

    return NextResponse.json({ success: true });
  } catch {
    return NextResponse.json(
      { error: "Unable to record activity." },
      { status: 500 },
    );
  }
}

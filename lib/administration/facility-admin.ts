import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { errorResponse } from "@/lib/work-orders/api";

/** D-17: every facility-setup route is Administrator-only; the database checks again. */
export async function requireAdministrator(): Promise<NextResponse | null> {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication required.", 401);
  if (identity.role !== "administrator") return errorResponse("ACCESS_DENIED", "Only the Administrator may set up facilities.", 403);
  return null;
}

export const unavailable = (what: string) => NextResponse.json({ ok: false, code: "SERVICE_UNAVAILABLE", message: `${what} could not be saved. Try again.` }, { status: 503 });

export function text(value: unknown, max = 1000): string | null {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max ? value.trim() : null;
}

export function safeFilename(name: string) {
  const cleaned = name.normalize("NFKD").replace(/[^A-Za-z0-9._-]+/g, "-").replace(/-+/g, "-").replace(/^[-.]+|[-.]+$/g, "");
  return (cleaned || "drawing").slice(-80);
}

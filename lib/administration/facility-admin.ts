import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { errorResponse } from "@/lib/work-orders/api";

/** D-17 / D-54: facility-setup routes are for the Super-Administrator and Facility Administrators; the database
 * limits a Facility Administrator to its own facilities. */
export async function requireAdministrator(): Promise<NextResponse | null> {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication required.", 401);
  if (identity.role !== "administrator" && identity.role !== "facility_administrator") {
    return errorResponse("ACCESS_DENIED", "Only the Super-Administrator or a Facility Administrator may set up facilities.", 403);
  }
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

import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M34: a Supervisor, Facility Manager or the Super-Administrator sets the Technician responsible for a maintenance task. */
export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (typeof body.requirement_id !== "string") return NextResponse.json({ error: "Choose a maintenance task." }, { status: 400 });
  const technician = typeof body.technician_id === "string" && body.technician_id ? body.technician_id : null;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("assign_pm_technician", { p_requirement_id: body.requirement_id, p_technician_id: technician });
  const result = data as { ok?: boolean; message?: string } | null;
  if (error || !result?.ok) return NextResponse.json({ error: result?.message ?? "The Technician could not be assigned." }, { status: 409 });
  return NextResponse.json({ ok: true });
}

import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** M32: the Super-Administrator sets the SLA times for the standard or one facility, or puts a facility back on the standard. */
export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity || identity.role !== "administrator") return NextResponse.json({ error: "Only the Super-Administrator sets SLA times." }, { status: 403 });
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const facilityId = typeof body.facility_id === "string" && body.facility_id ? body.facility_id : null;
  const supabase = await createClient();
  const { data, error } = body.action === "use_standard" && facilityId
    ? await supabase.rpc("admin_use_standard_sla", { p_facility_id: facilityId, p_reason: String(body.reason ?? "") })
    : await supabase.rpc("admin_set_sla_times", { p_facility_id: facilityId, p_rows: body.rows ?? [], p_reason: String(body.reason ?? "") });
  const result = data as { ok?: boolean; message?: string } | null;
  if (error || !result?.ok) return NextResponse.json({ error: result?.message ?? "The SLA could not be saved." }, { status: 409 });
  return NextResponse.json({ ok: true });
}

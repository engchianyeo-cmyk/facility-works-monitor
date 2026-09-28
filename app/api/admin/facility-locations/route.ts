import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { FACILITY_LOCATION_AUDIT_EVENT, validDrawingReference, validNormalizedCoordinate } from "@/lib/facility-location";
import { WORK_ORDER_DRAWINGS } from "@/lib/work-order-drawings";
import { createAdminClient } from "@/lib/supabase/admin";

async function requireAdministrator() {
  const identity = await getCurrentIdentity();
  return identity?.role === "administrator" ? identity : null;
}

export async function GET() {
  const identity = await requireAdministrator();
  if (!identity) return NextResponse.json({ error: "Access denied." }, { status: 403 });
  const admin = createAdminClient();
  const [{ data: facilities, error: facilityError }, { data: areas, error: areaError }] = await Promise.all([
    admin.from("sites").select("id,code,name,is_active").eq("is_active", true).order("name"),
    admin.from("facility_areas").select("id,facility_id,area_code,name,level,drawing_reference,map_x,map_y,active").eq("active", true).order("name"),
  ]);
  if (facilityError || areaError) return NextResponse.json({ error: "Facility locations could not be loaded." }, { status: 503 });
  return NextResponse.json({ facilities, areas, drawings: WORK_ORDER_DRAWINGS.map(({ code, title, src, width, height }) => ({ code, title, src, width, height })) });
}

export async function PATCH(request: Request) {
  const identity = await requireAdministrator();
  if (!identity) return NextResponse.json({ error: "Access denied." }, { status: 403 });
  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return NextResponse.json({ error: "Invalid request." }, { status: 400 }); }
  const facilityId = typeof body.facility_id === "string" ? body.facility_id : "";
  const areaId = typeof body.facility_area_id === "string" ? body.facility_area_id : "";
  if (!facilityId || !areaId || !validDrawingReference(body.drawing_reference) || !validNormalizedCoordinate(body.map_x) || !validNormalizedCoordinate(body.map_y)) {
    return NextResponse.json({ error: "Choose a facility, area, drawing and a valid point within the drawing." }, { status: 400 });
  }

  const admin = createAdminClient();
  const { data: area, error: loadError } = await admin.from("facility_areas")
    .select("id,facility_id,area_code,name,drawing_reference,map_x,map_y")
    .eq("id", areaId).eq("facility_id", facilityId).maybeSingle();
  if (loadError || !area) return NextResponse.json({ error: "Facility area was not found." }, { status: 404 });
  const previous = { drawing_reference: area.drawing_reference, map_x: area.map_x, map_y: area.map_y };
  const next = { drawing_reference: body.drawing_reference, map_x: body.map_x, map_y: body.map_y };
  const { data: updated, error: updateError } = await admin.from("facility_areas").update(next).eq("id", area.id).eq("facility_id", facilityId)
    .select("id,facility_id,area_code,name,level,drawing_reference,map_x,map_y,active").maybeSingle();
  if (updateError || !updated) return NextResponse.json({ error: "Location configuration could not be saved." }, { status: 503 });

  const timestamp = new Date().toISOString();
  const { error: auditError } = await admin.from("activity_logs").insert({
    user_id: identity.userId,
    action: FACILITY_LOCATION_AUDIT_EVENT,
    actor: identity.displayName,
    note: JSON.stringify({ facility_id: facilityId, facility_area_id: area.id, facility_area: `${area.area_code} · ${area.name}`, previous, next, actor_id: identity.userId, timestamp }),
  });
  if (auditError) {
    const { error: compensationError } = await admin.from("facility_areas").update(previous).eq("id", area.id).eq("facility_id", facilityId);
    return NextResponse.json({ error: compensationError ? "Location audit failed and automatic restoration requires investigation." : "Location audit failed; the previous position was restored." }, { status: 503 });
  }
  return NextResponse.json({ area: updated, audit_event: FACILITY_LOCATION_AUDIT_EVENT });
}

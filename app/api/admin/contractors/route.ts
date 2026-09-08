import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";

const AUTHORITIES = ["supervisor", "facility_manager", "administrator"];
const COST_TYPES = ["labour", "material", "equipment", "service", "callout"];

export async function POST(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ message: "Authentication required." }, { status: 401 });
  if (!AUTHORITIES.includes(identity.role)) return NextResponse.json({ message: "Contractor administration authority is required." }, { status: 403 });

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return NextResponse.json({ message: "Invalid request." }, { status: 400 }); }
  const admin = createAdminClient();

  if (body.kind === "vendor") {
    const name = String(body.name ?? "").trim();
    if (!name) return NextResponse.json({ message: "Company name is required." }, { status: 400 });
    const terms = Number(body.payment_terms_days ?? 30);
    if (!Number.isInteger(terms) || terms < 1) return NextResponse.json({ message: "Payment terms must be a positive whole number of days." }, { status: 400 });
    const { error } = await admin.from("vendors").insert({
      name, trade: String(body.trade ?? "").trim() || null,
      contact_name: String(body.contact_name ?? "").trim() || null,
      contact_email: String(body.contact_email ?? "").trim() || null,
      contact_phone: String(body.contact_phone ?? "").trim() || null,
      vendor_type: body.vendor_type === "manpower_provider" ? "manpower_provider" : "specialist_contractor",
      emergency_available: body.emergency_available === "true" || body.emergency_available === true,
      payment_terms_days: terms,
    });
    if (error) return NextResponse.json({ message: "Contractor could not be saved." }, { status: 409 });
    return NextResponse.json({ ok: true });
  }

  if (body.kind === "rate") {
    const vendorId = String(body.vendor_id ?? "");
    const description = String(body.description ?? "").trim();
    const unit = String(body.unit ?? "").trim();
    const costType = String(body.cost_type ?? "");
    const normal = Number(body.normal_unit_rate);
    const emergencyText = String(body.emergency_unit_rate ?? "").trim();
    const emergency = emergencyText === "" ? null : Number(emergencyText);
    const effectiveFrom = String(body.effective_from ?? "");
    if (!vendorId || !description || !unit || !COST_TYPES.includes(costType) || !Number.isFinite(normal) || normal < 0 || (emergency !== null && (!Number.isFinite(emergency) || emergency < 0)) || !/^\d{4}-\d{2}-\d{2}$/.test(effectiveFrom)) return NextResponse.json({ message: "Complete the contractor, rate type, description, unit, rate and effective date." }, { status: 400 });
    const category = String(body.service_category_id ?? "").trim() || null;
    const effectiveTo = String(body.effective_to ?? "").trim() || null;
    const { error } = await admin.from("contractor_rate_items").insert({ vendor_id: vendorId, service_category_id: category, cost_type: costType, description, unit, normal_unit_rate: normal, emergency_unit_rate: emergency, effective_from: effectiveFrom, effective_to: effectiveTo });
    if (error) return NextResponse.json({ message: "Agreed rate could not be saved." }, { status: 409 });
    return NextResponse.json({ ok: true });
  }

  return NextResponse.json({ message: "Unsupported contractor administration action." }, { status: 400 });
}

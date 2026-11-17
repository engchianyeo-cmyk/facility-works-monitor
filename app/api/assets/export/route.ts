import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createCsv, singaporeTimestamp } from "@/lib/exports/csv";

/**
 * UAT 17 Nov 2026 (owner): download the asset list (with the page's filters) as a file Excel opens directly.
 * Row security decides which assets the person may see.
 */
const HEADERS = ["Tag", "Name", "Type", "System", "Criticality", "Lifecycle", "Site", "Location", "Building", "Floor / zone", "Room",
  "Manufacturer", "Model", "Serial number", "In service", "Warranty expires", "Description"];

export async function GET(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const params = new URL(request.url).searchParams;
  const supabase = await createClient();
  let query = supabase.from("assets").select("asset_tag,name,asset_type,criticality,lifecycle_status,site,location,building,floor_zone,room,manufacturer,model,serial_number,in_service_date,warranty_expiry,description,system:asset_systems(system_code,name)");
  const search = (params.get("search") ?? "").replaceAll(/[,%()]/g, " ").trim();
  if (search) query = query.or(`asset_tag.ilike.%${search}%,name.ilike.%${search}%,model.ilike.%${search}%,serial_number.ilike.%${search}%,location.ilike.%${search}%`);
  const system = params.get("system"); const criticality = params.get("criticality"); const status = params.get("status");
  const site = (params.get("site") ?? "").trim(); const type = (params.get("type") ?? "").trim();
  if (system) query = query.eq("system_id", system);
  if (criticality) query = query.eq("criticality", criticality);
  if (status) query = query.eq("lifecycle_status", status);
  if (site) query = query.ilike("site", `%${site}%`);
  if (type) query = query.ilike("asset_type", `%${type}%`);
  const { data, error } = await query.order("asset_tag").limit(5000);
  if (error) return NextResponse.json({ error: "The asset list could not be prepared." }, { status: 503 });
  type Row = { asset_tag: string; name: string; asset_type: string; criticality: string; lifecycle_status: string; site: string; location: string; building: string | null; floor_zone: string | null; room: string | null; manufacturer: string | null; model: string | null; serial_number: string | null; in_service_date: string | null; warranty_expiry: string | null; description: string | null; system: { system_code: string; name: string } | Array<{ system_code: string; name: string }> | null };
  const rows = ((data ?? []) as unknown as Row[]).map((asset) => {
    const system = Array.isArray(asset.system) ? asset.system[0] : asset.system;
    return [asset.asset_tag, asset.name, asset.asset_type, system ? `${system.system_code} ${system.name}` : "", asset.criticality, asset.lifecycle_status.replaceAll("_", " "),
      asset.site, asset.location, asset.building, asset.floor_zone, asset.room, asset.manufacturer, asset.model, asset.serial_number, asset.in_service_date, asset.warranty_expiry, asset.description];
  });
  const stamp = singaporeTimestamp().replaceAll(/[^0-9]/g, "").slice(0, 12);
  return new NextResponse(createCsv(HEADERS, rows), {
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="FMWorks_Asset_List_${stamp}.csv"`,
      "cache-control": "no-store",
    },
  });
}

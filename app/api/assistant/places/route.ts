import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { placeNote, placeTerms, type FoundArea, type FoundPlace } from "@/lib/help/places";

/** Ollie: places in the facilities this person can see (row security decides), from equipment locations and areas. */
export async function GET(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ places: [], areas: [], note: null }, { status: 401 });
  const query = (new URL(request.url).searchParams.get("q") ?? "").slice(0, 200);
  const terms = placeTerms(query);
  if (!terms.length) return NextResponse.json({ places: [], areas: [], note: null });
  const supabase = await createClient();
  const assetFilter = terms.flatMap((term) => [`name.ilike.%${term}%`, `location.ilike.%${term}%`]).join(",");
  const areaFilter = terms.flatMap((term) => [`name.ilike.%${term}%`, `area_code.ilike.%${term}%`]).join(",");
  const [{ data: assets }, { data: areas }] = await Promise.all([
    supabase.from("assets").select("name,location,facility_id").neq("lifecycle_status", "decommissioned").or(assetFilter).limit(40),
    supabase.from("facility_areas").select("area_code,name,facility_id").eq("active", true).or(areaFilter).limit(10),
  ]);
  const facilityIds = [...new Set([...(assets ?? []), ...(areas ?? [])].map((row) => (row as { facility_id: string | null }).facility_id).filter(Boolean))] as string[];
  const { data: sites } = facilityIds.length ? await supabase.from("sites").select("id,name").in("id", facilityIds) : { data: [] as Array<{ id: string; name: string }> };
  const siteName = new Map((sites ?? []).map((site) => [site.id, site.name]));
  // Group by location; a location whose own name matches comes first (it is the place asked about).
  const byLocation = new Map<string, FoundPlace & { score: number }>();
  for (const asset of (assets ?? []) as Array<{ name: string; location: string; facility_id: string }>) {
    const equipment: string[] = [];
    const key = `${asset.facility_id}|${asset.location}`;
    const entry = byLocation.get(key) ?? { facility: siteName.get(asset.facility_id) ?? "", location: asset.location, equipment, score: 0 };
    entry.equipment.push(asset.name);
    entry.score = Math.max(entry.score, terms.some((term) => asset.location.toLowerCase().includes(term)) ? 2 : 1);
    byLocation.set(key, entry);
  }
  const places = [...byLocation.values()].sort((a, b) => b.score - a.score).slice(0, 5)
    .map(({ facility, location, equipment }) => ({ facility, location, equipment: equipment.slice(0, 3) }));
  const foundAreas: FoundArea[] = ((areas ?? []) as Array<{ area_code: string; name: string; facility_id: string }>).map((area) => ({ facility: siteName.get(area.facility_id) ?? "", code: area.area_code, name: area.name }));
  return NextResponse.json({ places, areas: foundAreas, note: places.length || foundAreas.length ? placeNote(query) : null });
}

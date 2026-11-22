import "server-only";
import { cookies } from "next/headers";
import { FACILITY_COOKIE } from "@/lib/facility-scope";
import type { createClient } from "@/lib/supabase/server";

type Supabase = Awaited<ReturnType<typeof createClient>>;
export type ScopeFacility = { id: string; name: string; code: string | null };
export type FacilityScope = {
  /** The facilities this person may choose from (the Super-Administrator: every active facility). */
  facilities: ScopeFacility[];
  /** "all" or one facility id. */
  current: string;
  /** The facility ids the page shows: the chosen one, or all of the above. */
  ids: string[];
  /** Show the facility buttons (more than one facility to choose from). */
  showButtons: boolean;
};

/**
 * D-82 (22 Nov 2026): one facility choice for every page, remembered in the browser (cookie fmw_facility, D-54).
 * `?facility=` on a page wins over the remembered choice. A person sees only the facilities they are staff of
 * (memberships are read as the signed-in person); the Super-Administrator sees every active facility.
 */
export async function facilityScope(supabase: Supabase, identity: { userId: string; role: string }, requested?: string | null): Promise<FacilityScope> {
  const { data: siteRows } = await supabase.from("sites").select("id,name,code").eq("is_active", true).order("name");
  let allowed = (siteRows ?? []) as ScopeFacility[];
  if (identity.role !== "administrator") {
    const { data: own } = await supabase.rpc("visible_facility_memberships");
    const mine = new Set(((own ?? []) as Array<{ profile_id: string; facility_id: string }>).filter((row) => row.profile_id === identity.userId).map((row) => row.facility_id));
    allowed = allowed.filter((site) => mine.has(site.id));
  }
  const wanted = requested ?? (await cookies()).get(FACILITY_COOKIE)?.value ?? "all";
  const current = allowed.some((site) => site.id === wanted) ? wanted : "all";
  return { facilities: allowed, current, ids: current === "all" ? allowed.map((site) => site.id) : [current], showButtons: allowed.length > 1 };
}

/** Group rows by facility id in the order of the facility list; rows of no facility (or another) come last. */
export function groupByFacility<T>(rows: T[], facilityOf: (row: T) => string | null | undefined, facilities: ScopeFacility[]) {
  const groups = facilities.map((facility) => ({ facility, rows: rows.filter((row) => facilityOf(row) === facility.id) }));
  const known = new Set(facilities.map((facility) => facility.id));
  const other = rows.filter((row) => !known.has(String(facilityOf(row) ?? "")));
  return { groups: groups.filter((group) => group.rows.length > 0), other };
}

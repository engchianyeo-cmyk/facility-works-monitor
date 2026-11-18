import "server-only";
import { createAdminClient, isAdminConfigured } from "@/lib/supabase/admin";

/**
 * UAT 18 Nov 2026 (D-64): every member of a facility sees that facility's staffing structure. The server checks the
 * viewer's own active membership (or Super-Administrator) before reading; only name, role, trade and work contact
 * number are shown.
 */
export type TeamPerson = { id: string; name: string; trade: string | null; contact: string | null; you: boolean };
export type TeamTier = { role: string; title: string; duty: string; people: TeamPerson[] };
export type FacilityTeam = { id: string; name: string; address: string | null; tiers: TeamTier[]; side: TeamTier[] };

export const TEAM_ROLES = {
  administrator: { title: "Super-Administrator", duty: "Sets up every facility, its users, SLA times and approval limits." },
  facility_administrator: { title: "Facility Administrator", duty: "Keeps this facility's set-up up to date: staff, areas, drawings and contractors." },
  facility_manager: { title: "Facility Manager", duty: "Runs the facility day to day; reviews performance, SLA and the maintenance plan." },
  supervisor: { title: "Supervisor", duty: "Plans maintenance, assigns Technicians to Work Orders and tasks, checks work before it closes." },
  technician: { title: "Technicians", duty: "Do the checks and repairs, record the work and photos; the second Technician checks it." },
  approver: { title: "Approver", duty: "Approves Work Orders and quotations within the approval limits." },
  finance: { title: "Finance", duty: "Checks invoices against the approved work and records payment." },
} as const;

const CHAIN = ["facility_administrator", "facility_manager", "supervisor", "technician"] as const;
const SIDE = ["approver", "finance"] as const;

type Membership = { facility_id: string; profile_id: string; membership_role: string; effective_from: string | null; effective_to: string | null };
type Profile = { id: string; display_name: string; trade_discipline: string | null; contact_number: string | null; role: string; is_active: boolean; deleted_at: string | null };

function current(row: Membership, now: number) {
  return !(row.effective_from && Date.parse(row.effective_from) > now) && !(row.effective_to && Date.parse(row.effective_to) <= now);
}

export async function loadFacilityTeams(viewer: { userId: string; role: string }): Promise<{ teams: FacilityTeam[]; available: boolean; superAdmins: TeamPerson[] }> {
  if (!isAdminConfigured()) return { teams: [], available: false, superAdmins: [] };
  const admin = createAdminClient();
  const now = Date.now();
  const { data: own } = await admin.from("facility_memberships").select("facility_id, profile_id, membership_role, effective_from, effective_to")
    .eq("profile_id", viewer.userId).eq("active", true);
  const mine = ((own ?? []) as Membership[]).filter((row) => current(row, now)).map((row) => row.facility_id);
  const siteQuery = admin.from("sites").select("id, name, address").eq("is_active", true).order("name");
  const { data: sites } = viewer.role === "administrator" ? await siteQuery : mine.length ? await siteQuery.in("id", mine) : { data: [] };
  const facilityList = (sites ?? []) as Array<{ id: string; name: string; address: string | null }>;
  if (!facilityList.length) return { teams: [], available: true, superAdmins: [] };
  const { data: rows } = await admin.from("facility_memberships").select("facility_id, profile_id, membership_role, effective_from, effective_to")
    .in("facility_id", facilityList.map((site) => site.id)).eq("active", true);
  const members = ((rows ?? []) as Membership[]).filter((row) => current(row, now));
  const ids = [...new Set(members.map((row) => row.profile_id))];
  const [{ data: people }, { data: supers }] = await Promise.all([
    ids.length ? admin.from("profiles").select("id, display_name, trade_discipline, contact_number, role, is_active, deleted_at").in("id", ids) : Promise.resolve({ data: [] }),
    admin.from("profiles").select("id, display_name, trade_discipline, contact_number, role, is_active, deleted_at").eq("role", "administrator").eq("is_active", true).is("deleted_at", null),
  ]);
  const byId = new Map(((people ?? []) as Profile[]).filter((p) => p.is_active && !p.deleted_at).map((p) => [p.id, p]));
  const person = (p: Profile): TeamPerson => ({ id: p.id, name: p.display_name, trade: p.trade_discipline, contact: p.contact_number, you: p.id === viewer.userId });
  const tier = (role: keyof typeof TEAM_ROLES, facilityId: string): TeamTier => ({
    role, title: TEAM_ROLES[role].title, duty: TEAM_ROLES[role].duty,
    people: members.filter((m) => m.facility_id === facilityId && m.membership_role === role)
      .map((m) => byId.get(m.profile_id)).filter((p): p is Profile => Boolean(p))
      .filter((p, index, list) => list.findIndex((q) => q.id === p.id) === index)
      .map(person).sort((a, b) => a.name.localeCompare(b.name)),
  });
  return {
    available: true,
    superAdmins: ((supers ?? []) as Profile[]).map(person),
    teams: facilityList.map((site) => ({ id: site.id, name: site.name, address: site.address, tiers: CHAIN.map((role) => tier(role, site.id)), side: SIDE.map((role) => tier(role, site.id)) })),
  };
}

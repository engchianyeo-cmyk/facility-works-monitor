import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { facilityScope } from "@/lib/facility-scope-server";
import { facilitiesNamed, peopleIntent, ROLE_ORDER, ROLE_TITLES } from "@/lib/help/people";

type Member = { profile_id: string; facility_id: string; membership_role: string; display_name: string | null; trade_discipline: string | null; contact_number: string | null };
type RosterRow = { facility_id: string | null; profile_display_name: string | null; team_name: string | null; escalation_order: number; active: boolean; active_from: string | null; active_to: string | null };

/**
 * Ollie (owner, 23 Nov 2026): who works at a facility, and who is on call — read as the signed-in person, so each
 * person sees only their own facilities (the Super-Administrator sees all). Name, role, trade and work phone only.
 */
export async function GET(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ intent: null, facilities: [] }, { status: 401 });
  const query = (new URL(request.url).searchParams.get("q") ?? "").slice(0, 300);
  const intent = peopleIntent(query);
  if (!intent) return NextResponse.json({ intent: null, facilities: [] });
  try {
    const supabase = await createClient();
    const scope = await facilityScope(supabase, identity);
    const chosen = facilitiesNamed(query, scope.facilities);
    const [{ data: members }, roster] = await Promise.all([
      supabase.rpc("visible_facility_memberships"),
      intent.onCall ? supabase.rpc("get_emergency_roster") : Promise.resolve({ data: [] as RosterRow[], error: null }),
    ]);
    const now = Date.now();
    const facilities = chosen.map((facility) => {
      const people = ((members ?? []) as Member[])
        .filter((m) => m.facility_id === facility.id && (intent.roles.length === 0 || intent.roles.includes(m.membership_role)))
        .sort((a, b) => ROLE_ORDER.indexOf(a.membership_role) - ROLE_ORDER.indexOf(b.membership_role) || String(a.display_name).localeCompare(String(b.display_name)))
        .map((m) => ({ name: m.display_name ?? "Unnamed", role: ROLE_TITLES[m.membership_role] ?? m.membership_role, trade: m.trade_discipline, phone: m.contact_number }));
      const onCall = ((roster.data ?? []) as RosterRow[])
        .filter((r) => r.facility_id === facility.id && r.active && !(r.active_from && Date.parse(r.active_from) > now) && !(r.active_to && Date.parse(r.active_to) <= now))
        .sort((a, b) => a.escalation_order - b.escalation_order)
        .map((r) => ({ name: r.profile_display_name ?? r.team_name ?? "On-call entry", order: r.escalation_order }));
      return { name: facility.name, people, onCall };
    });
    return NextResponse.json({ intent, facilities });
  } catch {
    return NextResponse.json({ intent, facilities: [] });
  }
}

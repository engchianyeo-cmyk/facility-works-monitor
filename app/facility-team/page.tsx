import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { loadFacilityTeams, TEAM_ROLES, type TeamPerson, type TeamTier } from "@/lib/facility-team";

export const dynamic = "force-dynamic";

/** D-64 (UAT 18 Nov 2026): the staffing structure of each facility, open to that facility's own staff. */
export default async function FacilityTeamPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/facility-team");
  const { teams, available, superAdmins } = await loadFacilityTeams({ userId: identity.userId, role: identity.role });
  return (
    <main className="mx-auto max-w-6xl px-4 py-8">
      <p className="text-xs font-black uppercase tracking-widest text-blue-700">Our team</p>
      <h1 className="mt-1 text-3xl font-black text-slate-950">Facility staffing structure</h1>
      <p className="mt-2 max-w-3xl text-sm text-slate-600">Who does what at your facility, from the Facility Administrator down to the Technicians, with the Approver and Finance alongside. Everyone on the staff of a facility can see its structure. To change it, ask the Facility Administrator (Administration › Users).</p>
      {!available && <p className="mt-6 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm font-semibold text-amber-900">The staff list is not available right now. Please try again later.</p>}
      {available && teams.length === 0 && <p className="mt-6 rounded-xl border border-dashed border-slate-300 bg-white p-8 text-center text-sm text-slate-600">You are not on the staff of a facility yet, so there is no structure to show. Ask your Facility Administrator to add you.</p>}
      {teams.length > 1 && (
        <nav aria-label="Facilities" className="mt-6 flex flex-wrap gap-2">
          {teams.map((team) => <a key={team.id} href={`#facility-${team.id}`} className="min-h-11 rounded-full border border-slate-300 bg-white px-4 py-2 text-sm font-bold text-slate-800 hover:bg-slate-50">{team.name}</a>)}
        </nav>
      )}
      <div className="mt-6 space-y-10">
        {teams.map((team) => (
          <section key={team.id} id={`facility-${team.id}`} aria-labelledby={`title-${team.id}`} className="scroll-mt-24 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 id={`title-${team.id}`} className="text-2xl font-black text-slate-950">{team.name}</h2>
            {team.address && <p className="text-sm text-slate-500">{team.address}</p>}
            <div className="mt-5 grid gap-6 lg:grid-cols-[2fr_1fr]">
              <ol className="relative space-y-4 border-l-2 border-blue-200 pl-5">
                <Tier tier={{ role: "administrator", title: TEAM_ROLES.administrator.title, duty: `${TEAM_ROLES.administrator.duty} Covers all facilities.`, people: superAdmins }} />
                {team.tiers.map((tier) => <Tier key={tier.role} tier={tier} />)}
              </ol>
              <div className="space-y-4">
                <p className="text-xs font-black uppercase tracking-widest text-slate-500">Alongside</p>
                {team.side.map((tier) => <TierCard key={tier.role} tier={tier} />)}
              </div>
            </div>
          </section>
        ))}
      </div>
    </main>
  );
}

function Tier({ tier }: { tier: TeamTier }) {
  return (
    <li className="relative">
      <span aria-hidden className="absolute -left-[27px] top-4 h-3 w-3 rounded-full border-2 border-blue-500 bg-white" />
      <TierCard tier={tier} />
    </li>
  );
}

function TierCard({ tier }: { tier: TeamTier }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-slate-50 p-4">
      <h3 className="font-black text-slate-950">{tier.title} <span className="text-sm font-bold text-slate-500">· {tier.people.length}</span></h3>
      <p className="mt-0.5 text-sm text-slate-600">{tier.duty}</p>
      {tier.people.length === 0
        ? <p className="mt-2 text-sm font-semibold text-amber-800">No one in this role yet.</p>
        : <ul className="mt-2 grid gap-2 sm:grid-cols-2">{tier.people.map((p) => <Person key={p.id} person={p} />)}</ul>}
    </div>
  );
}

function Person({ person }: { person: TeamPerson }) {
  return (
    <li className={`rounded-lg border bg-white p-3 ${person.you ? "border-blue-400" : "border-slate-200"}`}>
      <p className="font-bold text-slate-900 break-words">{person.name}{person.you && <span className="ml-2 rounded bg-blue-100 px-1.5 py-0.5 text-xs font-black text-blue-800">You</span>}</p>
      {person.trade && <p className="text-xs text-slate-600">{person.trade}</p>}
      {person.contact && <p className="text-xs text-slate-600">Tel. <a href={`tel:${person.contact.replace(/[^+0-9]/g, "")}`} className="text-blue-700 underline">{person.contact}</a></p>}
    </li>
  );
}

import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { loadChecklist, loadRoundSettings, memberFacilities } from "@/lib/daily-round-data";
import { ChecklistEditor, RoundSettingsForm } from "@/components/daily-round/round-setup";

export const dynamic = "force-dynamic";
type Search = Promise<Record<string, string | string[] | undefined>>;

/** M36: set up a facility's Daily round — who, when, and the checklist. */
export default async function DailyRoundSetupPage({ searchParams }: { searchParams: Search }) {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/daily-round/setup");
  const params = await searchParams;
  const supabase = await createClient();
  const facilities = await memberFacilities(supabase);
  const wanted = Array.isArray(params.facility) ? params.facility[0] : params.facility;
  const facility = facilities.find((f) => f.id === wanted) ?? facilities[0];
  if (!facility) redirect("/daily-round");
  const { data: editor } = await supabase.rpc("daily_round_editor", { p_facility_id: facility.id });
  if (editor !== true) redirect(`/daily-round?facility=${facility.id}`);
  const [settings, checks, { data: technicians }] = await Promise.all([
    loadRoundSettings(supabase, facility.id), loadChecklist(supabase, facility.id, true), supabase.rpc("facility_technicians", { p_facility_id: facility.id }),
  ]);
  return (
    <main className="mx-auto max-w-5xl space-y-5 px-4 py-8">
      <div>
        <Link href={`/daily-round?facility=${facility.id}`} className="text-sm font-bold text-blue-700 underline">← Daily round</Link>
        <h1 className="mt-2 text-3xl font-black text-slate-950">Set up the Daily round · {facility.name}</h1>
        <p className="mt-1 text-sm text-slate-600">The Approver, Supervisor, Facility Manager or Facility Administrator of the facility sets this up. Changes apply from the next round.</p>
      </div>
      <RoundSettingsForm facilityId={facility.id} settings={settings} technicians={(technicians ?? []) as Array<{ id: string; display_name: string; trade_discipline: string | null }>} />
      <ChecklistEditor facilityId={facility.id} checks={checks} />
    </main>
  );
}

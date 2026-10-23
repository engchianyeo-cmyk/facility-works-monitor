import Link from "next/link";
import { redirect } from "next/navigation";
import FacilitySettingsForm from "@/components/administration/facility-settings";
import { getCurrentIdentity } from "@/lib/auth";
import { DEFAULT_ENDORSEMENT_STAGE, endorsementStageLabel, type EndorsementStage } from "@/lib/facility-settings";
import { createClient } from "@/lib/supabase/server";

export const revalidate = 0;

type Settings = { facility_id: string; designated_approver_id: string | null; endorsement_stage: EndorsementStage };
type History = { facility_id: string; reason: string; changed_at: string; next: Settings };

export default async function FacilitiesPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/facilities");
  if (identity.role !== "administrator") return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>Only the Administrator may change facility settings.</p></main>;
  const supabase = await createClient();
  const [facilities, settings, history] = await Promise.all([
    supabase.from("sites").select("id,code,name").eq("is_active", true).order("name"),
    supabase.from("facility_settings").select("facility_id,designated_approver_id,endorsement_stage"),
    supabase.from("facility_settings_history").select("facility_id,reason,changed_at,next").order("changed_at", { ascending: false }).limit(100),
  ]);
  if (facilities.error || settings.error) {
    return <main className="mx-auto max-w-4xl p-8"><h1 className="text-3xl font-black">Facilities</h1><p role="alert" className="mt-4">Facility settings are unavailable in this environment.</p></main>;
  }
  const byFacility = new Map(((settings.data ?? []) as Settings[]).map((row) => [row.facility_id, row]));
  const candidates = await Promise.all((facilities.data ?? []).map(async (facility) => {
    const { data } = await supabase.rpc("facility_approver_candidates", { p_facility_id: facility.id });
    return [facility.id, (data ?? []) as Array<{ id: string; display_name: string; role: string }>] as const;
  }));
  const candidatesByFacility = new Map(candidates);
  const historyRows = (history.error ? [] : history.data ?? []) as History[];

  return <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
    <div>
      <p className="text-sm font-semibold text-blue-700">Administration</p>
      <h1 className="text-3xl font-black">Facilities</h1>
      <p className="mt-1 text-slate-600">Each facility starts on the recommended settings. Change them here to suit the facility; every change is recorded with its reason. Area pins on the layout plans are set in <Link href="/administration/facility-locations" className="font-semibold text-blue-700 underline">Facility Locations</Link>.</p>
    </div>
    {(facilities.data ?? []).length === 0 && <p>No active facilities.</p>}
    {(facilities.data ?? []).map((facility) => {
      const current = byFacility.get(facility.id);
      const people = candidatesByFacility.get(facility.id) ?? [];
      const designated = people.find((person) => person.id === current?.designated_approver_id);
      const changes = historyRows.filter((row) => row.facility_id === facility.id).slice(0, 5);
      return <section key={facility.id} className="space-y-4 rounded-xl border bg-white p-5 sm:p-6" aria-labelledby={`facility-${facility.id}`}>
        <div>
          <h2 id={`facility-${facility.id}`} className="text-xl font-bold">{facility.name} <span className="text-sm font-normal text-slate-500">· {facility.code}</span></h2>
          <p className="mt-1 text-sm text-slate-600">
            {current ? "Customised" : "Recommended defaults"} — Approver: {designated?.display_name ?? "not designated"} · Endorsement: {endorsementStageLabel(current?.endorsement_stage ?? DEFAULT_ENDORSEMENT_STAGE)}
          </p>
        </div>
        <FacilitySettingsForm facilityId={facility.id} facilityName={facility.name} approverId={current?.designated_approver_id ?? null}
          stage={current?.endorsement_stage ?? DEFAULT_ENDORSEMENT_STAGE} candidates={people} />
        {changes.length > 0 && <div>
          <h3 className="font-semibold">Recent changes</h3>
          <ul className="mt-2 space-y-1 text-sm text-slate-600">
            {changes.map((row) => <li key={row.changed_at}>{new Date(row.changed_at).toLocaleString("en-SG", { timeZone: "Asia/Singapore" })} — {endorsementStageLabel(row.next?.endorsement_stage)} — {row.reason}</li>)}
          </ul>
        </div>}
      </section>;
    })}
  </main>;
}

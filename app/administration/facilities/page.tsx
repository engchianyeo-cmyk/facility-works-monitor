import Link from "next/link";
import { redirect } from "next/navigation";
import FacilitySettingsForm from "@/components/administration/facility-settings";
import { AddAreaForm, AddFacilityForm, DrawingList, DrawingUploadForm, FacilityDetailsForm, FacilityStaff } from "@/components/administration/facility-setup";
import { getCurrentIdentity } from "@/lib/auth";
import { FACILITY_DRAWING_COLUMNS, type FacilityDrawingRow } from "@/lib/facility-drawings";
import { DEFAULT_ENDORSEMENT_STAGE, endorsementStageLabel, type EndorsementStage } from "@/lib/facility-settings";
import { createClient } from "@/lib/supabase/server";

export const revalidate = 0;

type Facility = { id: string; code: string; name: string; address: string | null; is_active: boolean };
type Settings = { facility_id: string; designated_approver_id: string | null; endorsement_stage: EndorsementStage };
type History = { facility_id: string; reason: string; changed_at: string; next: Settings };
type Area = { id: string; facility_id: string; area_code: string; name: string; level: string | null; drawing_reference: string | null; active: boolean };
type Staff = { profile_id: string; display_name: string; email: string | null; role: string; member: boolean; member_since: string | null };
type Change = { facility_id: string; when: string; text: string };

const ACTION_LABELS: Record<string, string> = {
  facility_created: "Facility added", facility_updated: "Details changed", facility_area_added: "Area added",
  facility_staff_added: "Staff added", facility_staff_removed: "Staff removed", facility_drawing_added: "Drawing uploaded", facility_drawing_removed: "Drawing removed",
};

function parseNote(note: string | null): Record<string, unknown> {
  try { const value = JSON.parse(note ?? "{}"); return value && typeof value === "object" ? value : {}; } catch { return {}; }
}

function describe(action: string, note: Record<string, unknown>) {
  const label = ACTION_LABELS[action] ?? action.replaceAll("_", " ");
  const area = note.area as { area_code?: string; name?: string } | undefined;
  const detail = [note.code, note.title, area?.area_code, area?.name, note.display_name, note.reason].filter((v) => typeof v === "string" && v).join(" · ");
  return detail ? `${label} — ${detail}` : label;
}

const when = (value: string) => new Date(value).toLocaleString("en-SG", { timeZone: "Asia/Singapore" });

export default async function FacilitiesPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/facilities");
  if (identity.role !== "administrator") return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>Only the Administrator may set up facilities.</p></main>;
  const supabase = await createClient();
  const [facilities, settings, history, areas, drawings, logs] = await Promise.all([
    supabase.from("sites").select("id,code,name,address,is_active").order("is_active", { ascending: false }).order("name"),
    supabase.from("facility_settings").select("facility_id,designated_approver_id,endorsement_stage"),
    supabase.from("facility_settings_history").select("facility_id,reason,changed_at,next").order("changed_at", { ascending: false }).limit(200),
    supabase.from("facility_areas").select("id,facility_id,area_code,name,level,drawing_reference,active").order("area_code"),
    supabase.from("facility_drawings").select(FACILITY_DRAWING_COLUMNS).eq("active", true).order("code"),
    supabase.from("activity_logs").select("action,note,created_at").like("action", "facility\\_%").order("created_at", { ascending: false }).limit(300),
  ]);
  if (facilities.error || settings.error) {
    return <main className="mx-auto max-w-4xl p-8"><h1 className="text-3xl font-black">Facilities</h1><p role="alert" className="mt-4">Facility setup is unavailable in this environment.</p></main>;
  }
  const facilityRows = (facilities.data ?? []) as Facility[];
  const byFacility = new Map(((settings.data ?? []) as Settings[]).map((row) => [row.facility_id, row]));
  const areaRows = (areas.error ? [] : areas.data ?? []) as Area[];
  const drawingRows = (drawings.error ? [] : drawings.data ?? []) as FacilityDrawingRow[];
  const extras = await Promise.all(facilityRows.map(async (facility) => {
    const [candidates, staff] = await Promise.all([
      facility.is_active ? supabase.rpc("facility_approver_candidates", { p_facility_id: facility.id }) : Promise.resolve({ data: [] }),
      supabase.rpc("admin_facility_staff", { p_facility_id: facility.id }),
    ]);
    return [facility.id, { candidates: (candidates.data ?? []) as Array<{ id: string; display_name: string; role: string }>, staff: (staff.data ?? []) as Staff[] }] as const;
  }));
  const extrasByFacility = new Map(extras);
  const changes: Change[] = [
    ...((history.error ? [] : history.data ?? []) as History[]).map((row) => ({ facility_id: row.facility_id, when: row.changed_at, text: `Settings — ${endorsementStageLabel(row.next?.endorsement_stage)} — ${row.reason}` })),
    ...((logs.error ? [] : logs.data ?? []) as Array<{ action: string; note: string | null; created_at: string }>).map((row) => {
      const note = parseNote(row.note);
      const facility = (note.facility_id ?? (note.facility as { id?: string } | undefined)?.id) as string | undefined;
      return { facility_id: facility ?? "", when: row.created_at, text: describe(row.action, note) };
    }),
  ].filter((row) => row.facility_id).sort((a, b) => b.when.localeCompare(a.when));

  return <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
    <div>
      <p className="text-sm font-semibold text-blue-700">Administration</p>
      <div className="flex flex-wrap items-center justify-between gap-3"><h1 className="text-3xl font-black">Facilities</h1><Link href="/administration/facilities/overview" className="min-h-11 rounded-lg bg-blue-700 px-4 py-2 text-sm font-bold text-white">View all facilities, users and requirements →</Link></div>
      <p className="mt-1 text-slate-600">Add facilities, their areas, layout drawings and staff. Each facility starts on the recommended settings; change them to suit the facility. Every change is recorded with its reason. Area pins on the layout plans are set in <Link href="/administration/facility-locations" className="font-semibold text-blue-700 underline">Facility Locations</Link>.</p>
    </div>
    <details className="rounded-xl border bg-white p-5 sm:p-6">
      <summary className="cursor-pointer text-lg font-bold">Add a new facility</summary>
      <div className="mt-4"><AddFacilityForm /></div>
    </details>
    {facilityRows.length === 0 && <p>No facilities yet.</p>}
    {facilityRows.map((facility) => {
      const current = byFacility.get(facility.id);
      const { candidates = [], staff = [] } = extrasByFacility.get(facility.id) ?? {};
      const designated = candidates.find((person) => person.id === current?.designated_approver_id);
      const facilityAreas = areaRows.filter((row) => row.facility_id === facility.id);
      const facilityDrawings = drawingRows.filter((row) => row.facility_id === facility.id);
      const members = staff.filter((row) => row.member);
      const recent = changes.filter((row) => row.facility_id === facility.id).slice(0, 8);
      return <section key={facility.id} className="space-y-4 rounded-xl border bg-white p-5 sm:p-6" aria-labelledby={`facility-${facility.id}`}>
        <div>
          <h2 id={`facility-${facility.id}`} className="text-xl font-bold">{facility.name} <span className="text-sm font-normal text-slate-500">· {facility.code}</span>
            {!facility.is_active && <span className="ml-2 rounded bg-slate-200 px-2 py-0.5 text-xs font-semibold text-slate-700">Not in use</span>}</h2>
          {facility.address && <p className="text-sm text-slate-600">{facility.address}</p>}
          <p className="mt-1 text-sm text-slate-600">
            {current ? "Customised" : "Recommended defaults"} — Approver: {designated?.display_name ?? "not designated"} · Endorsement: {endorsementStageLabel(current?.endorsement_stage ?? DEFAULT_ENDORSEMENT_STAGE)}
            {" "}· {facilityAreas.filter((a) => a.active).length} areas · {facilityDrawings.length} drawings · {members.length} staff
          </p>
        </div>
        <details className="rounded-lg border p-4"><summary className="cursor-pointer font-semibold">Details</summary><div className="mt-3"><FacilityDetailsForm facility={facility} /></div></details>
        {facility.is_active && <details className="rounded-lg border p-4"><summary className="cursor-pointer font-semibold">Settings (Approver and endorsement)</summary>
          <div className="mt-3"><FacilitySettingsForm facilityId={facility.id} facilityName={facility.name} approverId={current?.designated_approver_id ?? null}
            stage={current?.endorsement_stage ?? DEFAULT_ENDORSEMENT_STAGE} candidates={candidates} /></div></details>}
        <details className="rounded-lg border p-4"><summary className="cursor-pointer font-semibold">Areas ({facilityAreas.filter((a) => a.active).length})</summary>
          <div className="mt-3 space-y-3">
            {facilityAreas.length > 0 && <ul className="max-h-72 divide-y overflow-y-auto rounded border text-sm" tabIndex={0}>
              {facilityAreas.map((area) => <li key={area.id} className="flex gap-3 px-3 py-2"><span className="w-24 font-mono">{area.area_code}</span><span className="flex-1">{area.name}{area.level ? ` · ${area.level}` : ""}</span>
                <span className="text-slate-500">{area.active ? (area.drawing_reference ? `Pinned on ${area.drawing_reference}` : "Not pinned") : "Not in use"}</span></li>)}
            </ul>}
            {facility.is_active && <AddAreaForm facilityId={facility.id} />}
          </div></details>
        <details className="rounded-lg border p-4"><summary className="cursor-pointer font-semibold">Drawings ({facilityDrawings.length})</summary>
          <div className="mt-3 space-y-4"><DrawingList drawings={facilityDrawings} canRemove />{facility.is_active && <DrawingUploadForm facilityId={facility.id} />}</div></details>
        <details className="rounded-lg border p-4"><summary className="cursor-pointer font-semibold">Staff ({members.length})</summary>
          <div className="mt-3"><FacilityStaff facilityId={facility.id} staff={staff} /></div></details>
        {recent.length > 0 && <div>
          <h3 className="font-semibold">Recent changes</h3>
          <ul className="mt-2 space-y-1 text-sm text-slate-600">{recent.map((row, index) => <li key={`${row.when}-${index}`}>{when(row.when)} — {row.text}</li>)}</ul>
        </div>}
      </section>;
    })}
  </main>;
}

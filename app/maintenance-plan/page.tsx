import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { planFrequency, type PlanDocument, type PlanTask, type PlanTechnician } from "@/lib/maintenance/plan";
import { recurrenceLabel } from "@/lib/maintenance/presentation";
import MaintenancePlanBoard from "@/components/maintenance-plan/maintenance-plan-board";
import PmModeBanner from "@/components/maintenance/pm-mode-banner";

export const dynamic = "force-dynamic";

type Row = {
  id: string; requirement_number: string; state: string; assigned_technician_id: string | null;
  asset: { id: string; asset_tag: string; name: string; location: string | null; criticality: string; facility_id: string | null } | null;
  current_revision: { title: string; scope: string; interval_value: number; interval_unit: string } | null;
};

/** M34 (UAT 17 Nov 2026): equipment by daily / weekly / monthly / quarterly / annual maintenance, the Technician
 *  responsible for each, and the O&M manual to cross-reference. Open to every signed-in role; only planners change it. */
export default async function MaintenancePlanPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/maintenance-plan");
  const supabase = await createClient();
  const [{ data: rows, error }, { data: docs }] = await Promise.all([
    supabase.from("maintenance_requirements")
      .select("id,requirement_number,state,assigned_technician_id,asset:assets(id,asset_tag,name,location,criticality,facility_id),current_revision:maintenance_requirement_revisions!maintenance_requirements_current_revision_fkey(title,scope,interval_value,interval_unit)")
      .in("state", ["active", "draft"]).order("requirement_number"),
    supabase.from("asset_documents").select("id,asset_id,title,kind,original_filename").eq("active", true).order("uploaded_at", { ascending: false }),
  ]);
  const docsByAsset = new Map<string, PlanDocument[]>();
  for (const d of (docs ?? []) as Array<PlanDocument & { asset_id: string }>) docsByAsset.set(d.asset_id, [...(docsByAsset.get(d.asset_id) ?? []), d]);
  const tasks: PlanTask[] = ((rows ?? []) as unknown as Row[]).filter(r => r.asset && r.current_revision).map(r => ({
    id: r.id, number: r.requirement_number, state: r.state, title: r.current_revision!.title, scope: r.current_revision!.scope,
    frequency: planFrequency(r.current_revision!.interval_value, r.current_revision!.interval_unit), every: recurrenceLabel(r.current_revision!),
    assetId: r.asset!.id, assetTag: r.asset!.asset_tag, assetName: r.asset!.name, location: r.asset!.location ?? "", criticality: r.asset!.criticality,
    facilityId: r.asset!.facility_id, technicianId: r.assigned_technician_id, documents: docsByAsset.get(r.asset!.id) ?? [],
  }));
  const facilityIds = [...new Set(tasks.map(t => t.facilityId).filter((v): v is string => Boolean(v)))];
  const { data: settingRows } = facilityIds.length ? await supabase.from("facility_settings").select("facility_id,pm_mode").in("facility_id", facilityIds) : { data: [] as Array<{ facility_id: string; pm_mode: string }> };
  const modeOf = new Map((settingRows ?? []).map((row) => [row.facility_id as string, row.pm_mode as string]));
  const [{ data: sites }, planner, editor, technicians] = await Promise.all([
    facilityIds.length ? supabase.from("sites").select("id,name").in("id", facilityIds) : Promise.resolve({ data: [] as Array<{ id: string; name: string }> }),
    Promise.all(facilityIds.map(async f => [f, (await supabase.rpc("pm_planner_for", { p_facility_id: f })).data === true] as const)),
    Promise.all([...new Set(tasks.map(t => t.assetId))].map(async a => [a, (await supabase.rpc("asset_document_editor", { p_asset_id: a })).data === true] as const)),
    Promise.all(facilityIds.map(async f => [f, ((await supabase.rpc("facility_technicians", { p_facility_id: f })).data ?? []) as PlanTechnician[]] as const)),
  ]);
  // A Technician sees names of colleagues only through the tasks; give the board the names it can show.
  const names = new Map<string, string>();
  for (const [, list] of technicians) for (const t of list) names.set(t.id, t.display_name);
  const missing = [...new Set(tasks.map(t => t.technicianId).filter((v): v is string => Boolean(v) && !names.has(v as string)))];
  if (missing.length) {
    const { data: people } = await supabase.from("profiles").select("id,display_name").in("id", missing);
    for (const p of people ?? []) names.set(p.id, p.display_name);
  }
  return (
    <main className="mx-auto max-w-7xl px-4 py-8">
      <p className="text-xs font-black uppercase tracking-widest text-blue-700">Maintenance</p>
      <h1 className="mt-1 text-3xl font-black text-slate-950">Maintenance plan</h1>
      <p className="mt-2 max-w-3xl text-sm text-slate-600">Equipment by how often it is checked and serviced, the Technician responsible for each task, and the O&amp;M manual to cross-reference. Supervisors and Facility Managers of a facility, and the Super-Administrator, assign Technicians and file manuals.</p>
      {error && <p className="mt-4 rounded-lg border border-red-200 bg-red-50 p-3 text-sm font-bold text-red-800">The maintenance plan could not be loaded. Please refresh.</p>}
      <div className="mt-4"><PmModeBanner facilities={(sites ?? []).map((site) => ({ id: site.id, name: site.name, mode: modeOf.get(site.id) ?? "plan_only" }))} canChange={identity.role === "administrator"} /></div>
      <MaintenancePlanBoard
        tasks={tasks}
        facilities={(sites ?? []).map(s => ({ id: s.id, name: s.name }))}
        plannerFacilities={planner.filter(([, ok]) => ok).map(([f]) => f)}
        editorAssets={editor.filter(([, ok]) => ok).map(([a]) => a)}
        technicians={Object.fromEntries(technicians)}
        names={Object.fromEntries(names)}
        myId={identity.userId}
      />
    </main>
  );
}

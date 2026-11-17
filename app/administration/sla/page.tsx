import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import SlaTimesEditor, { type SlaScope } from "@/components/sla/sla-times-editor";

/** M32 (owner, 17 Nov 2026): the Super-Administrator sets the SLA times for all facilities, or one facility's own. */
export default async function SlaTimesPage() {
  const identity = await getCurrentIdentity();
  if (!identity || identity.role !== "administrator") {
    return <main className="mx-auto max-w-xl p-8"><div className="rounded-xl border border-red-200 bg-red-50 p-6"><h1 className="text-2xl font-bold text-red-900">Access denied</h1><p className="mt-2 text-sm text-red-800">Only the Super-Administrator sets SLA times.</p></div></main>;
  }
  const supabase = await createClient();
  const [sites, rules] = await Promise.all([
    supabase.from("sites").select("id,name").eq("is_active", true).order("name"),
    supabase.from("sla_rules").select("work_order_priority,acknowledgement_minutes,attendance_minutes,make_safe_minutes,rectification_minutes,kpi_target_percent,version:sla_agreement_versions(agreement:sla_agreements(facility_id))").eq("is_active", true),
  ]);
  type Row = { work_order_priority: string; acknowledgement_minutes: number | null; attendance_minutes: number | null; make_safe_minutes: number | null; rectification_minutes: number; kpi_target_percent: number; version: { agreement: { facility_id: string | null } | null } | null };
  const all = ((rules.data ?? []) as unknown as Row[]);
  const pick = (facilityId: string | null) => all.filter((rule) => (rule.version?.agreement?.facility_id ?? null) === facilityId)
    .map((rule) => ({ priority: rule.work_order_priority, acknowledgement_minutes: rule.acknowledgement_minutes, attendance_minutes: rule.attendance_minutes, make_safe_minutes: rule.make_safe_minutes, rectification_minutes: rule.rectification_minutes, kpi_target_percent: Number(rule.kpi_target_percent) }));
  const scopes: SlaScope[] = [
    { id: null, name: "Standard SLA — all facilities", current: pick(null), ownSla: true },
    ...((sites.data ?? []) as Array<{ id: string; name: string }>).map((site) => ({ id: site.id, name: site.name, current: pick(site.id), ownSla: pick(site.id).length > 0 })),
  ];
  return (
    <main className="mx-auto max-w-5xl space-y-6 p-4 sm:p-8">
      <div>
        <p className="text-sm font-semibold text-blue-700">Administration</p>
        <h1 className="text-3xl font-bold tracking-tight text-slate-900">SLA times</h1>
        <p className="mt-1 text-sm text-slate-500">Set how fast the team must act for each priority. The standard applies to every facility; a facility can have its own tighter times. A change applies to new Work Orders from now on; jobs already running keep their times. Every change is recorded with your reason.</p>
      </div>
      <SlaTimesEditor scopes={scopes} />
    </main>
  );
}

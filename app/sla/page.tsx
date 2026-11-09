import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { SLA_STAGES, durationLabel, groupRules, ruleMinutes, type SlaRuleRow } from "@/lib/sla/card";

export const revalidate = 0;

const PRIORITY_LABEL: Record<string, string> = { critical: "Critical", high: "High", medium: "Medium", low: "Low" };
const day = (value: string | null) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "Asia/Singapore" }).format(new Date(`${value}T00:00:00+08:00`)) : "open-ended";

const FOR_YOU: Array<[string, string]> = [
  ["Technician", "Acknowledge new jobs quickly, get to site within the attend time, make it safe first, then fix within the fix time. Record the actual times on the Work Order: they are the evidence."],
  ["Approver, Supervisor, Facility Manager", "Approve urgent jobs straight away: the clock starts when the job is submitted, not when it is approved. Watch the amber and red countdowns."],
  ["Finance", "No SLA times for you; the KPI targets show how the contractor and the in-house team are performing."],
];

// D-45 (9 Nov 2026): the site's approved service levels in plain words, for every member of staff.
export default async function SiteSlaPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/sla");
  const supabase = await createClient();
  const { data, error } = await supabase.from("sla_rules")
    .select("id,priority_class,work_order_priority,acknowledgement_minutes,response_minutes,attendance_minutes,make_safe_minutes,rectification_minutes,kpi_target_percent,source_clause,service_category:service_categories(code,name),version:sla_agreement_versions(version_number,effective_from,effective_to,agreement:sla_agreements(name,counterparty))")
    .eq("is_active", true);
  const rules = (error ? [] : (data ?? [])) as unknown as SlaRuleRow[];
  const groups = groupRules(rules);
  const agreements = Array.from(new Map(rules.filter((rule) => rule.version?.agreement).map((rule) => [`${rule.version?.agreement?.name}|${rule.version?.version_number}`, rule.version])).values());
  const usedStages = SLA_STAGES.filter((stage) => rules.some((rule) => ruleMinutes(rule, stage.key) !== null));
  const management = ["approver", "supervisor", "administrator"].includes(identity.role);

  return (
    <main className="mx-auto max-w-5xl space-y-6 p-4 sm:p-8">
      <header>
        <p className="text-sm font-black uppercase tracking-widest text-blue-700">For everyone on site</p>
        <h1 className="text-3xl font-black">Site SLA — how fast we must act</h1>
        <p className="mt-2 max-w-3xl text-slate-600">The service levels agreed with the facility owner. The clock starts when a Work Order is submitted. Each Work Order shows its own countdown against these times.</p>
      </header>
      {error && <p role="alert" className="rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950">The Site SLA is not available in this environment yet (database update D-45 not applied).</p>}
      {!error && rules.length === 0 && <section className="rounded-xl border border-dashed p-6 text-slate-700">
        <h2 className="text-lg font-black">No approved SLA yet</h2>
        <p className="mt-1">Times appear here once a manager has checked the service agreement and approved its targets.{management && <> Do that on <Link href="/management/sla" className="font-semibold text-blue-700 underline">SLA documents and rules</Link>.</>}</p>
      </section>}
      {agreements.length > 0 && <p className="text-sm text-slate-600">Agreement: {agreements.map((version) => `${version?.agreement?.name}${version?.agreement?.counterparty ? ` with ${version.agreement.counterparty}` : ""}, version ${version?.version_number}, from ${day(version?.effective_from ?? null)} to ${day(version?.effective_to ?? null)}`).join("; ")}.</p>}
      {groups.map((group) => (
        <section key={group.category} aria-label={`SLA for ${group.category}`} className="overflow-x-auto rounded-xl border bg-white">
          <h2 className="border-b px-4 py-3 text-lg font-black">{group.category}</h2>
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 text-left"><tr><th className="px-4 py-2">Priority</th>{usedStages.map((stage) => <th key={stage.key} className="px-4 py-2">{stage.label} within</th>)}<th className="px-4 py-2">Target met on</th></tr></thead>
            <tbody className="divide-y">{group.rules.map((rule) => (
              <tr key={rule.id}>
                <td className="px-4 py-2 font-black">{rule.priority_class} · {PRIORITY_LABEL[rule.work_order_priority] ?? rule.work_order_priority}</td>
                {usedStages.map((stage) => <td key={stage.key} className="px-4 py-2">{durationLabel(ruleMinutes(rule, stage.key))}</td>)}
                <td className="px-4 py-2">{Number(rule.kpi_target_percent)}% of jobs</td>
              </tr>
            ))}</tbody>
          </table>
        </section>
      ))}
      <section className="grid gap-4 md:grid-cols-2">
        <div className="rounded-xl border bg-white p-4">
          <h2 className="text-lg font-black">What each step means</h2>
          <dl className="mt-2 space-y-2 text-sm">{SLA_STAGES.map((stage) => <div key={stage.key}><dt className="font-bold">{stage.label}</dt><dd className="text-slate-700">{stage.meaning}</dd></div>)}</dl>
        </div>
        <div className="rounded-xl border bg-white p-4">
          <h2 className="text-lg font-black">What it means for you</h2>
          <dl className="mt-2 space-y-2 text-sm">{FOR_YOU.map(([role, text]) => <div key={role}><dt className="font-bold">{role}</dt><dd className="text-slate-700">{text}</dd></div>)}</dl>
          <p className="mt-3 text-sm text-slate-600">On each Work Order: <span className="font-bold text-emerald-700">green</span> on track, <span className="font-bold text-amber-700">amber</span> 75% of the time used, <span className="font-bold text-red-700">red</span> missed.</p>
        </div>
      </section>
    </main>
  );
}

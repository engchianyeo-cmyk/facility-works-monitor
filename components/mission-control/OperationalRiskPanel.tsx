import EmptyState from "@/components/ui/EmptyState";
import SectionTitle from "@/components/ui/SectionTitle";
import StatusChip from "@/components/ui/StatusChip";
import Link from "next/link";

export type OperationalRisk = {
  id: string;
  label: string;
  detail: string;
  impact: string;
  owner?: string;
  dueStatus?: string;
  nextAction: string;
  level: "critical" | "warning" | "info";
  href?: string;
};

export default function OperationalRiskPanel({ risks }: { risks: OperationalRisk[] }) {
  return (
    <section className="rounded-2xl border border-amber-200 bg-white p-5 shadow-sm">
      <SectionTitle title="Operational risk" eyebrow="Attention queue" />
      <div className="mt-4">
        {!risks.length ? (
          <EmptyState
            title="No immediate risks"
            description="No overdue, unassigned or critical work currently requires intervention."
          />
        ) : (
          <ul className="space-y-3">
            {risks.slice(0, 6).map((risk) => (
              <li
                key={risk.id}
                className={`rounded-xl border-l-4 p-4 ${
                  risk.level === "critical"
                    ? "border-y-red-200 border-r-red-200 border-l-red-600 bg-red-50/60"
                    : "border-y-amber-200 border-r-amber-200 border-l-amber-500 bg-amber-50/50"
                }`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-black text-slate-950">{risk.label}</p>
                    <p className="mt-0.5 text-sm text-slate-600">{risk.detail}</p>
                  </div>
                  <StatusChip tone={risk.level === "critical" ? "danger" : risk.level === "warning" ? "warning" : "info"}>
                    {risk.level === "critical" ? "Emergency" : "Attention"}
                  </StatusChip>
                </div>
                <dl className="mt-3 grid gap-2 text-xs sm:grid-cols-2">
                  <div>
                    <dt className="font-bold text-slate-700">Operational impact</dt>
                    <dd className="text-slate-600">{risk.impact}</dd>
                  </div>
                  {(risk.owner || risk.dueStatus) && (
                    <div>
                      <dt className="font-bold text-slate-700">Responsibility / timing</dt>
                      <dd className="text-slate-600">
                        {[risk.owner, risk.dueStatus].filter(Boolean).join(" · ")}
                      </dd>
                    </div>
                  )}
                </dl>
                <p className="mt-3 text-sm text-slate-700">
                  <span className="font-bold">Next action:</span> {risk.nextAction}
                </p>
                {risk.href && <Link href={risk.href} className="mt-3 inline-flex min-h-11 items-center text-sm font-black text-blue-800">Open record →</Link>}
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}

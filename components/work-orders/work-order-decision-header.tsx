import Link from "next/link";
import type { WorkOrderDecisionModel } from "@/lib/work-orders/decision-header";

type Props = {
  reference: string;
  title: string;
  location: string;
  workType: string;
  department: string | null;
  model: WorkOrderDecisionModel;
  incidentHref: string | null;
  nextAction: string | null;
};

const EXCEPTION_STYLES: Record<string, string> = {
  critical: "border-red-300 bg-red-50 text-red-950",
  rework: "border-orange-300 bg-orange-50 text-orange-950",
  overdue: "border-red-300 bg-red-50 text-red-950",
  unassigned: "border-amber-300 bg-amber-50 text-amber-950",
  incident: "border-orange-300 bg-orange-50 text-orange-950",
  unavailable: "border-slate-400 bg-slate-100 text-slate-950",
  review: "border-violet-300 bg-violet-50 text-violet-950",
  approval: "border-blue-300 bg-blue-50 text-blue-950",
};

function Fact({ label, value, detail }: { label: string; value: string; detail?: string }) {
  return (
    <div className="min-w-0 rounded-xl border border-slate-200 bg-white p-3 sm:p-4">
      <dt className="text-xs font-black uppercase tracking-[0.12em] text-slate-500">{label}</dt>
      <dd className="mt-2 break-words text-base font-black text-slate-950">{value}</dd>
      {detail && <dd className="mt-1 break-words text-sm text-slate-600">{detail}</dd>}
    </div>
  );
}

export default function WorkOrderDecisionHeader({
  reference,
  title,
  location,
  workType,
  department,
  model,
  incidentHref,
  nextAction,
}: Props) {
  const leadException = model.exceptions[0] ?? null;
  return (
    <section aria-labelledby="work-order-title" className="overflow-hidden rounded-2xl border border-slate-300 bg-slate-50 shadow-sm">
      <header className="bg-slate-950 px-5 py-6 text-white sm:px-7 sm:py-7">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="font-mono text-sm font-black tracking-wide text-blue-300">{reference}</p>
          <p className="rounded-full border border-slate-600 px-3 py-1 text-xs font-black uppercase tracking-wide">
            {leadException ? `Primary exception · ${leadException.label}` : "Normal operations"}
          </p>
        </div>
        <h1 id="work-order-title" className="mt-4 max-w-4xl break-words text-3xl font-black leading-tight sm:text-4xl">{title}</h1>
        <p className="mt-3 break-words text-base text-slate-200">{location}</p>
      </header>

      <div className="space-y-5 p-4 sm:p-6">
        {model.exceptions.length > 0 ? (
          <section aria-labelledby="decision-exceptions-title">
            <h2 id="decision-exceptions-title" className="text-xs font-black uppercase tracking-[0.14em] text-slate-600">Requires attention</h2>
            <ol className="mt-2 grid gap-2 md:grid-cols-2">
              {model.exceptions.map((exception) => (
                <li key={exception.kind} className={`rounded-xl border p-3 ${EXCEPTION_STYLES[exception.kind]}`}>
                  <p className="font-black">{exception.label}</p>
                  <p className="mt-1 text-sm">{exception.detail}</p>
                </li>
              ))}
            </ol>
          </section>
        ) : (
          <p className="rounded-xl border border-dashed border-slate-300 p-3 text-sm text-slate-600">
            No current operational exception is identified from the available Work Order data.
          </p>
        )}

        <dl aria-label="Work Order decision facts" className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Fact label="Priority" value={model.priority} />
          <Fact label="Status" value={model.status} />
          <Fact label="Owner" value={model.ownership.label} detail={model.ownership.detail} />
          <Fact label="Time exposure" value={model.due.label} detail={model.due.detail} />
        </dl>

        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(16rem,0.42fr)]">
          <dl className="grid min-w-0 gap-3 rounded-xl border border-slate-200 bg-white p-4 text-sm sm:grid-cols-3">
            <div className="min-w-0"><dt className="font-bold text-slate-500">Work type</dt><dd className="mt-1 break-words text-slate-900">{workType}</dd></div>
            <div className="min-w-0"><dt className="font-bold text-slate-500">Department</dt><dd className="mt-1 break-words text-slate-900">{department ?? "Not recorded"}</dd></div>
            <div className="min-w-0"><dt className="font-bold text-slate-500">Evidence</dt><dd className="mt-1 break-words text-slate-900">{model.evidence.label}</dd></div>
            {model.incident && (
              <div className="min-w-0 sm:col-span-3">
                <dt className="font-bold text-slate-500">Related incident</dt>
                <dd className="mt-1 break-words text-slate-900">
                  {model.incident.available && incidentHref ? (
                    <Link href={incidentHref} className="inline-flex min-h-11 items-center rounded-lg font-bold text-blue-700 underline decoration-2 underline-offset-4 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-blue-200">
                      Open incident {model.incident.reference} · {model.incident.severity ?? "Severity unavailable"} · {model.incident.status}
                    </Link>
                  ) : "Related incident details are unavailable for this view."}
                </dd>
              </div>
            )}
          </dl>

          <aside aria-label="Next permitted action" className="order-first rounded-xl border-2 border-blue-200 bg-blue-50 p-4 text-blue-950 lg:order-last">
            <p className="text-xs font-black uppercase tracking-[0.14em] text-blue-700">Next action</p>
            <p className="mt-2 font-black">{nextAction ?? "No action available for your role"}</p>
            <p className="mt-1 text-sm">The execution panel below remains the authoritative place to perform workflow actions.</p>
            {nextAction && (
              <a href="#execution-title" className="mt-3 inline-flex min-h-11 items-center rounded-lg bg-blue-700 px-4 py-2 text-sm font-black text-white hover:bg-blue-800 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-blue-300">
                Continue to {nextAction}
              </a>
            )}
          </aside>
        </div>
      </div>
    </section>
  );
}

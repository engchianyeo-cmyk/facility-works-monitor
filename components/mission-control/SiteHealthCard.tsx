import StatusChip from "@/components/ui/StatusChip";

export default function SiteHealthCard({
  activeIncidents,
  criticalOrders,
  overdueOrders,
  dataAvailable,
}: {
  activeIncidents: number;
  criticalOrders: number;
  overdueOrders: number;
  dataAvailable: boolean;
}) {
  const danger = activeIncidents > 0 || criticalOrders > 0;
  const warning = !danger && overdueOrders > 0;
  return (
    <section
      aria-labelledby="site-health"
      className={`rounded-2xl border-2 p-5 ${
        danger
          ? "border-red-300 bg-red-50"
          : warning
            ? "border-amber-300 bg-amber-50"
            : "border-emerald-300 bg-emerald-50"
      }`}
    >
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-xs font-black uppercase tracking-widest text-slate-600">Current operational summary</p>
          <h2 id="site-health" className="mt-1 text-2xl font-black">
            {!dataAvailable ? "Work information unavailable" : danger ? "Immediate attention" : warning ? "Attention required" : "Operations stable"}
          </h2>
        </div>
        <StatusChip tone={!dataAvailable ? "warning" : danger ? "danger" : warning ? "warning" : "success"}>
          {!dataAvailable ? "Unavailable" : danger ? "Emergency" : warning ? "Attention" : "Operational"}
        </StatusChip>
      </div>
      <dl className="mt-5 grid grid-cols-3 gap-3 text-center">
        <div><dt className="text-xs text-slate-500">Active incidents</dt><dd className="text-2xl font-black">{activeIncidents}</dd></div>
        <div><dt className="text-xs text-slate-500">Critical work</dt><dd className="text-2xl font-black">{criticalOrders}</dd></div>
        <div><dt className="text-xs text-slate-500">Overdue</dt><dd className="text-2xl font-black">{overdueOrders}</dd></div>
      </dl>
    </section>
  );
}

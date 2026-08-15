import Link from "next/link";
import EmptyState from "@/components/ui/EmptyState";
import SectionTitle from "@/components/ui/SectionTitle";
import StatusChip from "@/components/ui/StatusChip";
import { incidentStatusLabel, incidentTypeLabel } from "@/lib/product-terminology";

export type MissionIncident = {
  id: string;
  incident_number: string;
  incident_type: string;
  severity: string;
  status: string;
  location: string;
  acknowledgement_deadline: string;
  acknowledged_at: string | null;
  assigned: boolean;
};

const incidentStatus = (status: string) => {
  if (["reported", "acknowledged", "mobilising", "on_site", "rescue_in_progress"].includes(status)) return "Emergency";
  if (status === "safe") return "Operational";
  return incidentStatusLabel(status);
};

export default function CriticalIncidentPanel({
  incidents,
  available,
}: {
  incidents: MissionIncident[];
  available: boolean;
}) {
  return (
    <section className="rounded-2xl border border-red-200 bg-white p-5 shadow-sm">
      <SectionTitle
        eyebrow="Immediate attention"
        title="Critical incidents"
        action={<Link href="/incidents" className="text-sm font-bold text-red-700 hover:underline">Open board →</Link>}
      />
      <div className="mt-4">
        {!available ? (
          <EmptyState
            title="Incident information is temporarily unavailable"
            description="Work Order operations remain available. Incident visibility will resume when the service is restored."
          />
        ) : !incidents.length ? (
          <EmptyState
            title="No active emergencies"
            description="No emergency incident currently requires attention."
          />
        ) : (
          <ul className="space-y-3">
            {incidents.slice(0, 4).map((incident) => (
              <li key={incident.id}>
                <Link
                  href={`/incidents/${incident.id}`}
                  className="block rounded-xl border-l-4 border-y-red-200 border-r-red-200 border-l-red-600 bg-red-50 p-4 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-red-200"
                >
                  <div className="flex flex-wrap justify-between gap-2">
                    <div>
                      <p className="font-mono text-xs font-black text-red-800">{incident.incident_number}</p>
                      <p className="mt-1 font-black">{incidentTypeLabel(incident.incident_type)}</p>
                      <p className="text-sm font-semibold text-slate-700">{incident.location}</p>
                    </div>
                    <div className="flex h-fit gap-2">
                      <StatusChip tone="danger">{incident.severity === "critical" ? "Emergency" : "Attention"}</StatusChip>
                      <StatusChip tone="warning">{incidentStatus(incident.status)}</StatusChip>
                    </div>
                  </div>
                  {!incident.assigned && <p className="mt-3 text-xs font-black uppercase text-red-800">Response owner required</p>}
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}

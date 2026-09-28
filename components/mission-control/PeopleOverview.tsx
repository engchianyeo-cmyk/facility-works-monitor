import SectionTitle from "@/components/ui/SectionTitle";
import StatusChip from "@/components/ui/StatusChip";

export default function PeopleOverview({
  activeUsers,
  technicians,
  onCall,
  available,
}: {
  activeUsers: number | null;
  technicians: number | null;
  onCall: number | null;
  available: boolean;
}) {
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5">
      <SectionTitle title="Recorded people activity" />
      <dl className="mt-4 grid grid-cols-3 gap-3">
        <div><dt className="text-xs text-slate-500">Active users</dt><dd className="mt-1 text-2xl font-black">{available ? activeUsers ?? 0 : "—"}</dd></div>
        <div><dt className="text-xs text-slate-500">Technicians</dt><dd className="mt-1 text-2xl font-black">{available ? technicians ?? 0 : "—"}</dd></div>
        <div><dt className="text-xs text-slate-500">On call</dt><dd className="mt-1 text-2xl font-black">{available ? onCall ?? 0 : "—"}</dd></div>
      </dl>
      <div className="mt-4">
        <StatusChip tone={available ? "success" : "warning"}>{available ? "Records loaded" : "Records unavailable"}</StatusChip>
      </div>
    </section>
  );
}

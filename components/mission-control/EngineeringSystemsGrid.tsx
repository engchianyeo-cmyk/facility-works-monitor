import KpiCard from "@/components/ui/KpiCard";
import SectionTitle from "@/components/ui/SectionTitle";

export default function EngineeringSystemsGrid({
  open,
  inProgress,
  pendingApproval,
  completed,
  dueToday,
}: {
  open: number;
  inProgress: number;
  pendingApproval: number;
  completed: number;
  dueToday: number;
}) {
  return (
    <section aria-labelledby="work-execution-heading">
      <SectionTitle eyebrow="Today's operations" title="Work execution" />
      <div className="mt-4 grid grid-cols-2 gap-3 xl:grid-cols-5">
        <KpiCard label="Open" value={open} tone="blue" detail="Active work" />
        <KpiCard label="In Progress" value={inProgress} tone="amber" />
        <KpiCard label="Waiting Approval" value={pendingApproval} tone="violet" />
        <KpiCard label="Completed Today" value={completed} tone="green" />
        <KpiCard label="Due Today" value={dueToday} tone={dueToday ? "amber" : "neutral"} />
      </div>
    </section>
  );
}

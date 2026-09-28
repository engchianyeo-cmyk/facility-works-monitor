import StatusChip from "@/components/ui/StatusChip";

export default function MissionHeader({
  name,
  role,
  department,
  generatedAt,
}: {
  name: string;
  role: string;
  department: string | null;
  generatedAt: string;
}) {
  return (
    <header className="overflow-hidden rounded-3xl bg-slate-950 px-6 py-7 text-white shadow-xl sm:px-8">
      <div className="flex flex-wrap items-end justify-between gap-5">
        <div>
          <p className="text-xs font-black uppercase tracking-[.24em] text-blue-300">
            FMWorks Mission Control
          </p>
          <h1 className="mt-2 text-3xl font-black tracking-tight sm:text-4xl">
            Good day, {name}
          </h1>
          <p className="mt-2 text-sm text-slate-300">
            Your current view of operational activity, risk and priorities.
          </p>
        </div>
        <div className="text-right">
          <StatusChip tone="info">{role}</StatusChip>
          <p className="mt-2 text-xs text-slate-400">
            {department || "All assigned operations"} · {generatedAt}
          </p>
        </div>
      </div>
    </header>
  );
}

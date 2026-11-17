import Link from "next/link";

export type LearningMatch = {
  learning_id: string;
  work_order_id: string;
  work_order_number: string;
  work_order_title: string;
  confirmed_cause: string | null;
  fix_that_worked: string | null;
  tip: string | null;
  shared_by_name: string;
  shared_at: string;
  proven: boolean;
  repeat_fault: boolean;
};

/** D-59a: "Fixed before" — what was learnt on similar Work Orders this person may see. */
export default function FixedBefore({ matches }: { matches: LearningMatch[] }) {
  if (!matches.length) return null;
  const date = (value: string) => new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "Asia/Singapore" }).format(new Date(value));
  return (
    <section className="rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4" aria-labelledby="fixed-before-heading">
      <h2 id="fixed-before-heading" className="text-lg font-bold text-emerald-950">Fixed before — what the team learnt</h2>
      <p className="mt-1 text-sm text-emerald-900">Similar Work Orders and what their people shared. Check it fits this case before acting.</p>
      <ul className="mt-3 space-y-3">
        {matches.map((match) => (
          <li key={match.learning_id} className="rounded-lg border border-emerald-200 bg-white p-3 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <Link href={`/work-orders/${match.work_order_id}`} className="font-mono text-xs font-bold text-blue-700 underline">{match.work_order_number}</Link>
              <span className="font-semibold text-slate-900">{match.work_order_title}</span>
              {match.proven && <span className="rounded-full bg-emerald-700 px-2 py-0.5 text-xs font-bold text-white">Proven fix</span>}
              {match.repeat_fault && <span className="rounded-full bg-amber-600 px-2 py-0.5 text-xs font-bold text-white">Fault came back within 30 days</span>}
            </div>
            {match.confirmed_cause && <p className="mt-2"><strong>Cause:</strong> {match.confirmed_cause}</p>}
            {match.fix_that_worked && <p className="mt-1"><strong>Fix that worked:</strong> {match.fix_that_worked}</p>}
            {match.tip && <p className="mt-1"><strong>Tip:</strong> {match.tip}</p>}
            <p className="mt-1 text-xs text-slate-500">Shared by {match.shared_by_name} · {date(match.shared_at)}</p>
          </li>
        ))}
      </ul>
    </section>
  );
}

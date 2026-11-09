import Link from "next/link";
import { clockFinished, clockStages, durationLabel, type SlaClockRow } from "@/lib/sla/card";

const time = (value: string) => new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Singapore" }).format(new Date(value));
const TONE = { met: "border-emerald-300 bg-emerald-50 text-emerald-900", on_track: "border-emerald-300 bg-white text-emerald-900",
  at_risk: "border-amber-400 bg-amber-50 text-amber-950", breached: "border-red-500 bg-red-50 text-red-900", missed: "border-red-300 bg-red-50 text-red-900" } as const;

/** D-45 (9 Nov 2026): this Work Order against the site's SLA, one box per step, so everyone sees the time left. */
export default function SlaCountdown({ clock, status, finishedAt }: { clock: SlaClockRow | null; status: string; finishedAt: string | null }) {
  if (!clock) return null;
  const finished = clockFinished(status);
  const stages = clockStages(clock);
  return (
    <section aria-labelledby="sla-title" className="rounded-xl border border-slate-200 bg-white p-5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="sla-title" className="font-semibold">SLA countdown</h2>
        <Link href="/sla" className="text-sm font-semibold text-blue-700 underline">Site SLA times</Link>
      </div>
      <p className="mt-1 text-xs text-slate-500">Clock started {time(clock.started_at)}.</p>
      <ol className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
        {stages.map((stage) => {
          // A finished Work Order stops the clock: an open step counts as met if the work was completed by its deadline.
          const finishedInTime = finishedAt ? new Date(finishedAt).getTime() <= new Date(stage.deadline).getTime() : stage.state !== "breached";
          const state = finished && !stage.doneAt ? (finishedInTime ? "met" : "missed") : stage.state;
          const text = stage.doneAt ? `${stage.state === "met" ? "Met" : "Missed"} · done ${time(stage.doneAt)}`
            : finished ? (state === "met" ? "Work completed in time" : "Work completed late")
            : stage.state === "breached" ? `Missed by ${durationLabel(-stage.leftMinutes)}` : `${durationLabel(stage.leftMinutes)} left`;
          return (
            <li key={stage.key} className={`rounded-lg border-2 p-3 text-sm ${TONE[state]}`}>
              <p className="font-black">{stage.label}</p>
              <p className="text-xs">by {time(stage.deadline)}</p>
              <p className="mt-1 font-bold">{text}</p>
            </li>
          );
        })}
      </ol>
    </section>
  );
}

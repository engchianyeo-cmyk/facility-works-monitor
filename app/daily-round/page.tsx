import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { hhmm, roundLate, roundProgress, type RoundResult } from "@/lib/daily-round";
import { loadChecklist, loadRoundSettings, memberFacilities } from "@/lib/daily-round-data";
import { workOrderStatusLabel } from "@/lib/product-terminology";
import RoundChecklist from "@/components/daily-round/round-checklist";
import StartRound from "@/components/daily-round/start-round";

export const dynamic = "force-dynamic";
type Search = Promise<Record<string, string | string[] | undefined>>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] ?? "" : v ?? "");

/** M36 (owner D-67 D-G): today's Daily round — one Work Order a day, ticked off item by item. */
export default async function DailyRoundPage({ searchParams }: { searchParams: Search }) {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/daily-round");
  const params = await searchParams;
  const supabase = await createClient();
  const facilities = await memberFacilities(supabase);
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Singapore" }).format(new Date());
  const facility = facilities.find((f) => f.id === first(params.facility)) ?? facilities[0];
  const date = /^\d{4}-\d{2}-\d{2}$/.test(first(params.date)) ? first(params.date) : today;
  if (!facility) return <main className="mx-auto max-w-4xl px-4 py-8"><h1 className="text-3xl font-black">Daily round</h1><p className="mt-4 rounded-xl border border-dashed border-slate-300 bg-white p-8 text-center text-sm text-slate-600">You are not on the staff of a facility yet.</p></main>;
  const [settings, checks, { data: round }, { data: history }, { data: people }, { data: editor }] = await Promise.all([
    loadRoundSettings(supabase, facility.id),
    loadChecklist(supabase, facility.id),
    supabase.from("work_orders").select("id,work_order_number,status,assigned_technician_id,completion_notes,closed_at").eq("facility_id", facility.id).eq("daily_round_date", date).maybeSingle(),
    supabase.from("work_orders").select("id,daily_round_date,status,assigned_technician_id").eq("facility_id", facility.id).not("daily_round_date", "is", null).order("daily_round_date", { ascending: false }).limit(14),
    supabase.rpc("work_order_people_directory"),
    supabase.rpc("daily_round_editor", { p_facility_id: facility.id }),
  ]);
  const names = new Map(((people ?? []) as Array<{ id: string; display_name: string }>).map((p) => [p.id, p.display_name]));
  const name = (id: string | null | undefined) => (!id ? "Not assigned" : id === identity.userId ? "You" : names.get(id) ?? "Assigned Technician");
  const { data: results } = round ? await supabase.from("daily_round_results").select("item_id,ok,reading,note,recorded_at").eq("work_order_id", round.id) : { data: [] };
  const { data: recorder } = round ? await supabase.rpc("daily_round_recorder", { p_work_order_id: round.id }) : { data: false };
  const progress = roundProgress(checks, (results ?? []) as RoundResult[]);
  const closed = Boolean(round && ["closed", "cancelled"].includes(round.status));
  const late = round ? roundLate(date, settings.due, round.status) : false;
  return (
    <main className="mx-auto max-w-5xl px-4 py-8">
      <p className="text-xs font-black uppercase tracking-widest text-blue-700">Maintenance</p>
      <div className="flex flex-wrap items-end justify-between gap-3">
        <h1 className="mt-1 text-3xl font-black text-slate-950">Daily round</h1>
        {editor === true && <Link href={`/daily-round/setup?facility=${facility.id}`} className="min-h-11 rounded-lg border border-slate-300 bg-white px-4 py-2 text-sm font-bold">Set up the round and checklist</Link>}
      </div>
      <p className="mt-2 max-w-3xl text-sm text-slate-600">Routine daily checks, one Work Order a day. No permit, method statement or risk assessment. Record each item as you go; anything Not OK is reported as its own Work Order.</p>
      {facilities.length > 1 && <nav aria-label="Facilities" className="mt-4 flex flex-wrap gap-2">{facilities.map((f) => <Link key={f.id} href={`/daily-round?facility=${f.id}`} aria-current={f.id === facility.id ? "page" : undefined} className={`min-h-11 rounded-full px-4 py-2 text-sm font-bold ${f.id === facility.id ? "bg-slate-900 text-white" : "border border-slate-300 bg-white"}`}>{f.name}</Link>)}</nav>}

      <section className="mt-5 rounded-xl border border-slate-200 bg-white p-5">
        <h2 className="text-lg font-black">{facility.name} · {new Date(`${date}T00:00:00+08:00`).toLocaleDateString("en-SG", { weekday: "short", day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Singapore" })}</h2>
        {!settings.enabled && <p className="mt-2 text-sm text-amber-800">The Daily round is not switched on for this facility.</p>}
        {settings.enabled && <p className="mt-1 text-sm text-slate-600">Ready {hhmm(settings.ready)} · due by {hhmm(settings.due)} · done by {name(settings.technician_id)}{settings.cover_id ? `, covered by ${name(settings.cover_id)}` : ""}</p>}
        {round ? (
          <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
            <Link href={`/work-orders/${round.id}`} className="font-mono font-black text-blue-700 underline">{round.work_order_number}</Link>
            <span className="rounded-full bg-slate-100 px-2.5 py-1 font-black">{closed ? "Completed" : workOrderStatusLabel(round.status)}</span>
            <span>Assigned to {name(round.assigned_technician_id)}</span>
            {late && <span className="rounded-full bg-red-100 px-2.5 py-1 font-black text-red-800">Late — due by {hhmm(settings.due)}</span>}
            {closed && progress.faults > 0 && <span className="rounded-full bg-amber-100 px-2.5 py-1 font-black text-amber-900">{progress.faults} Not OK</span>}
          </div>
        ) : settings.enabled && date === today ? (
          <div className="mt-3 space-y-2 text-sm text-slate-600"><p>Today&apos;s round has not been created yet. The app creates it each morning unless the facility&apos;s planned maintenance is switched Off.</p>{editor === true && <StartRound facilityId={facility.id} />}</div>
        ) : <p className="mt-3 text-sm text-slate-600">No round on this day.</p>}
      </section>

      {round && checks.length > 0 && <div className="mt-5"><RoundChecklist workOrderId={round.id} checks={checks} results={(results ?? []) as RoundResult[]} canRecord={recorder === true} closed={closed} /></div>}
      {round && !recorder && !closed && <p className="mt-3 text-sm text-slate-600">Only the Technician of the round, the cover, or the facility&apos;s Supervisor, Approver or Facility Manager can record it.</p>}

      <section className="mt-8">
        <h2 className="text-lg font-black">Last 14 rounds</h2>
        {(history ?? []).length === 0 ? <p className="mt-2 text-sm text-slate-600">No rounds yet.</p> : (
          <ul className="mt-2 divide-y rounded-xl border border-slate-200 bg-white">
            {(history ?? []).map((h) => <li key={h.id} className="flex flex-wrap items-center justify-between gap-2 p-3 text-sm"><Link href={`/daily-round?facility=${facility.id}&date=${h.daily_round_date}`} className="font-bold text-blue-700 underline">{h.daily_round_date}</Link><span>{name(h.assigned_technician_id)}</span><span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-black">{["closed", "cancelled"].includes(h.status) ? "Completed" : workOrderStatusLabel(h.status)}</span></li>)}
          </ul>
        )}
      </section>
    </main>
  );
}

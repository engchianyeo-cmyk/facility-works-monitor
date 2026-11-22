"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import type { FoundArea, FoundPlace } from "@/lib/help/places";
import WorkOrderTour from "@/components/help/work-order-tour";
import { asksForGuidance, workOrderTour } from "@/lib/help/work-order-tour";
import type { UserRole } from "@/lib/auth";
import { guideForPath, relatedFaqs, searchHelp, stageAdvice, stepsFor, teamFaqs, type Faq, type TeamAnswer } from "@/lib/help/guide-content";
import { subscribeHelpContext, type HelpWorkOrderContext } from "@/components/help/help-context";
import { AssistantAvatar } from "@/components/help/mascot";
import { canSpeak, playTune, readPrefs, shouldRemind, speak, stopSpeaking, writePrefs, type OlliePrefs } from "@/lib/help/ollie-voice";

/**
 * D-58 option B: the built-in Help guide. A button at the bottom right opens "Help on this page": steps for the
 * person's role on this page, what to do next on an open Work Order, and a search over prepared answers.
 * Prepared answers never leave the device. Option A: when the system has the AI assistant switched on, "Ask the AI
 * assistant" sends only the question, the role, the page and the open Work Order's number and status.
 */
export default function HelpPanel({ role, aiEnabled = false, name = "Ollie", pictureUrl = null }: { role: UserRole | null; aiEnabled?: boolean; name?: string; pictureUrl?: string | null }) {
  const pathname = usePathname() ?? "/";
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [expanded, setExpanded] = useState<string | null>(null);
  const [asked, setAsked] = useState(false);
  // M33: questions are kept (role and page only) so the team can teach the assistant; the team's answers are used too.
  const [team, setTeam] = useState<TeamAnswer[]>([]);
  const [questionId, setQuestionId] = useState<string | null>(null);
  const [rated, setRated] = useState<boolean | null>(null);
  const [teamLoaded, setTeamLoaded] = useState(false);
  useEffect(() => {
    if (!open || teamLoaded) return;
    setTeamLoaded(true);
    fetch("/api/assistant/answers", { cache: "no-store" }).then((response) => response.json()).then((result: { answers?: TeamAnswer[] }) => setTeam(result.answers ?? [])).catch(() => undefined);
  }, [open, teamLoaded]);

  async function keepQuestion(answeredBy: "prepared" | "none", matched: string | null) {
    setQuestionId(null); setRated(null);
    try {
      const response = await fetch("/api/assistant/questions", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ question: query.trim(), path: pathname, answered_by: answeredBy, matched }) });
      const result = (await response.json().catch(() => ({}))) as { id?: string | null };
      setQuestionId(result.id ?? null);
    } catch { /* keeping the question is best effort */ }
  }
  async function rate(helpful: boolean) {
    if (!questionId) return;
    setRated(helpful);
    await fetch("/api/assistant/questions", { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ id: questionId, helpful }) }).catch(() => undefined);
  }
  // UAT 18 Nov 2026: places in the person's facilities (equipment locations and areas) that match the question.
  const [places, setPlaces] = useState<{ places: FoundPlace[]; areas: FoundArea[]; note: string | null } | null>(null);
  async function findPlaces() {
    setPlaces(null);
    try {
      const response = await fetch(`/api/assistant/places?q=${encodeURIComponent(query.trim())}`, { cache: "no-store" });
      if (response.ok) setPlaces(await response.json());
    } catch { /* places are a best-effort extra */ }
  }
  // UAT 21 Nov 2026: a step-by-step walk through the Work Order on screen, and "what should I do now?" answered from it.
  const [tour, setTour] = useState(false);
  const [guidance, setGuidance] = useState(false);
  const [firstTip, setFirstTip] = useState(false);
  function startTour() {
    setOpen(false); setFirstTip(false); setTour(true);
    try { window.localStorage.setItem("fmw-ollie-tour-seen", "1"); } catch { /* per-device convenience only */ }
  }
  function ask() {
    if (query.trim().length < 2) return;
    setAsked(true);
    setGuidance(Boolean(workOrder) && asksForGuidance(query));
    void findPlaces();
    if (aiEnabled) void askAi();
    else void keepQuestion(results.length ? "prepared" : "none", results[0]?.id ?? null);
  }
  const [workOrder, setWorkOrder] = useState<HelpWorkOrderContext | null>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  // D-58 option A: the AI answer, only when the system has it switched on.
  const [aiAnswer, setAiAnswer] = useState<string | null>(null);
  const [aiError, setAiError] = useState<string | null>(null);
  const [aiBusy, setAiBusy] = useState(false);

  async function askAi() {
    if (!aiEnabled || aiBusy || query.trim().length < 3) return;
    setAiBusy(true);
    setAiAnswer(null);
    setAiError(null);
    try {
      const response = await fetch("/api/assistant", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ question: query.trim(), path: pathname, workOrder }),
      });
      const result = (await response.json().catch(() => ({}))) as { answer?: string; error?: string; questionId?: string | null };
      if (!response.ok || !result.answer) throw new Error(result.error ?? "The AI assistant could not answer just now.");
      setAiAnswer(result.answer);
      setQuestionId(result.questionId ?? null);
      setRated(null);
      speak(result.answer);
    } catch (error) {
      setAiError(error instanceof Error ? error.message : "The AI assistant could not answer just now.");
    } finally {
      setAiBusy(false);
    }
  }

  useEffect(() => subscribeHelpContext(setWorkOrder), []);
  // First time a Technician opens a Work Order on this device, Ollie offers the walk-through.
  useEffect(() => {
    if (!workOrder || role !== "technician") { setFirstTip(false); return; }
    let seen = false;
    try { seen = window.localStorage.getItem("fmw-ollie-tour-seen") === "1"; } catch { seen = true; }
    setFirstTip(!seen);
  }, [workOrder, role]);

  // D-58: sounds and spoken English (this device only). After sound has been off for a day, offer to turn it on.
  const [prefs, setPrefs] = useState<OlliePrefs>({ sound: true, voice: false, offSince: null, remindedAt: null });
  const [remind, setRemind] = useState(false);
  useEffect(() => {
    const current = readPrefs();
    setPrefs(current);
    setRemind(shouldRemind(current));
    const onChange = (event: Event) => setPrefs((event as CustomEvent<OlliePrefs>).detail);
    window.addEventListener("fmw-ollie-prefs", onChange);
    return () => window.removeEventListener("fmw-ollie-prefs", onChange);
  }, []);
  function updatePrefs(change: Partial<OlliePrefs>) {
    const next = { ...prefs, ...change };
    if (change.sound === false && prefs.sound) next.offSince = Date.now();
    if (change.sound === true) next.offSince = null;
    writePrefs(next);
    setPrefs(next);
  }
  useEffect(() => {
    setQuery("");
    setExpanded(null);
    setAiAnswer(null);
    setAiError(null);
  }, [pathname]);
  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  const guide = useMemo(() => guideForPath(pathname), [pathname]);
  const steps = guide ? stepsFor(guide, role) : [];
  const stage = workOrder ? stageAdvice(workOrder.status, role, workOrder.inHouse) : null;
  const teamList = useMemo(() => teamFaqs(team), [team]);
  const results = useMemo(() => searchHelp(query, role, 5, teamList), [query, role, teamList]);
  const suggestions = relatedFaqs(guide, role);
  const answers: Faq[] = query.trim() ? results : suggestions;

  return (
    <>
      {remind && !open && (
        <div role="status" className="fixed bottom-20 right-4 z-40 w-72 rounded-2xl border border-amber-300 bg-amber-50 p-3 text-sm shadow-lg print:hidden">
          <p className="font-semibold text-amber-950">{name}&apos;s sounds have been off for a day. Turn them on so you don&apos;t miss urgent alerts?</p>
          <div className="mt-2 flex gap-2">
            <button type="button" onClick={() => { updatePrefs({ sound: true }); setRemind(false); playTune("test", true); }} className="rounded-lg bg-amber-600 px-3 py-1.5 font-semibold text-white">Turn on</button>
            <button type="button" onClick={() => { updatePrefs({ remindedAt: Date.now() }); setRemind(false); }} className="rounded-lg border border-amber-400 px-3 py-1.5 font-semibold text-amber-900">Not now</button>
          </div>
        </div>
      )}
      {tour && workOrder && <WorkOrderTour steps={workOrderTour(workOrder.status, role, workOrder.inHouse)} name={name} onClose={() => setTour(false)} />}
      {firstTip && !open && !tour && !remind && (
        <div role="status" className="fixed bottom-20 right-4 z-40 w-72 rounded-2xl border border-violet-300 bg-violet-50 p-3 text-sm shadow-lg print:hidden">
          <p className="font-semibold text-violet-950">First time on a Work Order? I can walk you through this one, step by step.</p>
          <div className="mt-2 flex gap-2">
            <button type="button" onClick={startTour} className="rounded-lg bg-violet-700 px-3 py-1.5 font-semibold text-white">Show me</button>
            <button type="button" onClick={() => { setFirstTip(false); try { window.localStorage.setItem("fmw-ollie-tour-seen", "1"); } catch { /* ignore */ } }} className="rounded-lg border border-violet-400 px-3 py-1.5 font-semibold text-violet-900">No thanks</button>
          </div>
        </div>
      )}
      <button
        type="button"
        onClick={() => {
          setOpen((value) => !value);
          window.setTimeout(() => searchRef.current?.focus(), 50);
        }}
        aria-expanded={open}
        aria-controls="fmw-help-panel"
        className="fixed bottom-4 right-4 z-40 flex items-center gap-2 rounded-full bg-blue-700 py-1.5 pl-1.5 pr-4 text-sm font-semibold text-white shadow-lg hover:bg-blue-800 focus:outline-none focus:ring-4 focus:ring-blue-300 print:hidden"
      >
        <span aria-hidden="true" className="flex h-9 w-9 items-center justify-center rounded-full bg-white"><AssistantAvatar size={32} name={name} pictureUrl={pictureUrl} decorative /></span>
        {open ? "Close help" : `Help · ${name}`}
      </button>

      {open && (
        <aside
          id="fmw-help-panel"
          role="dialog"
          aria-label="Help on this page"
          className="fixed inset-x-0 bottom-0 z-40 flex max-h-[85vh] flex-col overflow-hidden rounded-t-2xl border border-slate-200 bg-white shadow-2xl sm:inset-x-auto sm:bottom-20 sm:right-4 sm:w-[26rem] sm:rounded-2xl print:hidden"
        >
          <div className="flex items-start justify-between gap-3 border-b border-slate-200 bg-blue-50 px-4 py-3">
            <div className="flex items-center gap-3">
              <AssistantAvatar size={48} name={name} pictureUrl={pictureUrl} />
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-blue-700">{name} · Help on this page</p>
                <h2 className="text-lg font-bold text-slate-900">{guide?.title ?? "FMWorks"}</h2>
              </div>
            </div>
            <button type="button" onClick={() => setOpen(false)} className="rounded-md px-2 py-1 text-sm font-semibold text-slate-600 hover:bg-white" aria-label="Close help">
              ✕
            </button>
          </div>

          <div className="space-y-4 overflow-y-auto px-4 py-4 text-sm">
            {stage && workOrder && (
              <section className="rounded-lg border-2 border-amber-300 bg-amber-50 p-3">
                <p className="text-xs font-semibold uppercase tracking-wide text-amber-800">{workOrder.reference} · {stage.label}</p>
                <p className="mt-1 text-slate-700">{stage.meaning}</p>
                <p className="mt-2 font-semibold text-slate-900">What you do next</p>
                <p className="text-slate-800">{stage.advice}</p>
                {(workOrder.missing ?? []).length > 0 && <>
                  <p className="mt-2 font-semibold text-slate-900">Still missing on this Work Order</p>
                  <ol className="mt-1 list-decimal space-y-0.5 pl-5 text-slate-800">{(workOrder.missing ?? []).map((item) => <li key={item}>{item}</li>)}</ol>
                </>}
                {canSpeak() && <button type="button" onClick={() => speak(`${workOrder.reference} is ${stage.label}. ${stage.advice}`, true)} className="mt-1 rounded border border-amber-400 px-2 py-0.5 text-xs font-semibold text-amber-900">🔊 Read aloud</button>}
                <button type="button" onClick={startTour} className="mt-2 block w-full rounded-lg bg-violet-700 px-3 py-2 font-semibold text-white hover:bg-violet-800">Walk me through this Work Order, step by step</button>
              </section>
            )}

            {guide && (
              <section>
                <p className="text-slate-600">{guide.intro}</p>
                {canSpeak() && steps.length > 0 && (
                  <button type="button" onClick={() => speak(`${guide.intro} ${steps.map((step, index) => `Step ${index + 1}. ${step}`).join(" ")}`, true)} className="mt-2 rounded border border-slate-300 px-2 py-1 text-xs font-semibold text-slate-700">🔊 Read aloud</button>
                )}
                {steps.length > 0 && (
                  <ol className="mt-2 list-decimal space-y-1.5 pl-5 text-slate-800">
                    {steps.map((step) => <li key={step}>{step}</li>)}
                  </ol>
                )}
              </section>
            )}

            <section>
              <label htmlFor="fmw-help-search" className="block font-semibold text-slate-900">Ask a question</label>
              <input
                id="fmw-help-search"
                ref={searchRef}
                value={query}
                onChange={(event) => {
                  setQuery(event.target.value);
                  setExpanded(null);
                  setAsked(false);
                  setQuestionId(null);
                  setRated(null);
                  setPlaces(null);
                  setGuidance(false);
                }}
                onKeyDown={(event) => {
                  if (event.key === "Enter") {
                    event.preventDefault();
                    ask();
                  }
                }}
                placeholder="e.g. no approve button, quotation, password"
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-200"
              />
              <button
                type="button"
                onClick={() => ask()}
                disabled={aiBusy || query.trim().length < 2}
                className="mt-2 w-full rounded-lg bg-violet-700 px-3 py-2 font-semibold text-white hover:bg-violet-800 disabled:opacity-50"
              >
                {aiBusy ? `${name} is thinking…` : aiEnabled ? `Ask ${name} (AI assistant)` : `Ask ${name}`}
              </button>
              {asked && questionId && (
                <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-slate-600">
                  {rated === null ? <>
                    <span>Did this help?</span>
                    <button type="button" onClick={() => void rate(true)} className="rounded border border-emerald-300 px-2 py-0.5 font-semibold text-emerald-800">Yes</button>
                    <button type="button" onClick={() => void rate(false)} className="rounded border border-red-300 px-2 py-0.5 font-semibold text-red-800">No</button>
                  </> : <span>{rated ? "Thank you." : `Thank you — the team will see this question and can teach ${name} a better answer.`}</span>}
                </div>
              )}
              {aiError && <p role="alert" className="mt-2 rounded-lg border border-red-200 bg-red-50 p-2 text-red-800">{aiError}</p>}
              {aiAnswer && (
                <div className="mt-2 rounded-lg border border-violet-200 bg-violet-50 p-3">
                  <p className="text-xs font-semibold uppercase tracking-wide text-violet-800">{name} (AI) — check it against the app</p>
                  <p className="mt-1 whitespace-pre-line text-slate-800">{aiAnswer}</p>
                  {canSpeak() && <button type="button" onClick={() => speak(aiAnswer, true)} className="mt-1 rounded border border-violet-300 px-2 py-0.5 text-xs font-semibold text-violet-900">🔊 Read aloud</button>}
                </div>
              )}
              {asked && places && (places.places.length > 0 || places.areas.length > 0) && (
                <div className="mt-2 rounded-lg border border-emerald-200 bg-emerald-50 p-3">
                  <p className="text-xs font-semibold uppercase tracking-wide text-emerald-800">Found in your facilities</p>
                  <ul className="mt-1 space-y-1.5">
                    {places.places.map((place) => <li key={`${place.facility}|${place.location}`} className="text-slate-800"><span className="font-semibold">{place.location}</span>{place.facility ? ` · ${place.facility}` : ""}<span className="block text-xs text-slate-600">Equipment there: {place.equipment.join("; ")}</span></li>)}
                    {places.areas.map((area) => <li key={`${area.facility}|${area.code}`} className="text-slate-800"><span className="font-semibold">{area.name}</span> ({area.code}){area.facility ? ` · ${area.facility}` : ""}</li>)}
                  </ul>
                  {places.note && <p className="mt-2 rounded border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900">{places.note}</p>}
                  <p className="mt-1 text-xs text-slate-600">From the facility&apos;s equipment and area lists. Check on the facility drawings.</p>
                </div>
              )}
              {asked && query.trim() && answers.length === 0 && !aiEnabled && !(places && (places.places.length > 0 || places.areas.length > 0)) && (
                <p className="mt-2 rounded-lg bg-slate-50 p-2 text-slate-700">{name} has no prepared answer for that yet. Try a shorter question with key words (for example &quot;incident&quot;, &quot;quotation&quot;, &quot;approve&quot;), or ask your Facility Administrator. {name} answers any question in your own words once the AI assistant is switched on.</p>
              )}
              {asked && guidance && stage && workOrder && (
                <div className="mt-2 rounded-lg border border-violet-200 bg-violet-50 p-3">
                  <p className="text-xs font-semibold uppercase tracking-wide text-violet-800">On {workOrder.reference} ({stage.label})</p>
                  <p className="mt-1 text-slate-800">{stage.advice}</p>
                  {(workOrder.missing ?? []).length > 0 && <p className="mt-1 text-slate-800">Still missing: {(workOrder.missing ?? []).join("; ")}.</p>}
                  <button type="button" onClick={startTour} className="mt-2 rounded-lg bg-violet-700 px-3 py-1.5 text-sm font-semibold text-white">Show me on the page, step by step</button>
                </div>
              )}
              {answers.length > 0 && !(asked && guidance && stage) && (
                <div className="mt-2">
                  {!query.trim() ? <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">Common questions here</p> : <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">Prepared answers</p>}
                  <ul className="divide-y divide-slate-100 rounded-lg border border-slate-200">
                    {answers.map((faq) => (
                      <li key={faq.id}>
                        <button
                          type="button"
                          onClick={() => setExpanded((expanded ?? (query.trim() ? answers[0]?.id : null)) === faq.id ? "" : faq.id)}
                          aria-expanded={(expanded ?? (query.trim() ? answers[0]?.id : null)) === faq.id}
                          className="flex w-full items-start justify-between gap-2 px-3 py-2 text-left font-medium text-slate-900 hover:bg-slate-50"
                        >
                          <span>{faq.question}</span>
                          <span aria-hidden="true" className="text-slate-400">{(expanded ?? (query.trim() ? answers[0]?.id : null)) === faq.id ? "−" : "+"}</span>
                        </button>
                        {(expanded ?? (query.trim() ? answers[0]?.id : null)) === faq.id && (
                          <div className="px-3 pb-3 text-slate-700">
                            <p>{faq.answer}</p>
                            {canSpeak() && <button type="button" onClick={() => speak(faq.answer, true)} className="mt-1 rounded border border-slate-300 px-2 py-0.5 text-xs font-semibold">🔊 Read aloud</button>}
                          </div>
                        )}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </section>

            <details className="rounded-lg border border-slate-200 p-3">
              <summary className="cursor-pointer font-semibold text-slate-900">{name}&apos;s sounds and voice</summary>
              <div className="mt-2 space-y-2">
                <label className="flex items-center gap-2"><input type="checkbox" checked={prefs.sound} onChange={(event) => updatePrefs({ sound: event.target.checked })} className="h-4 w-4" /> Sounds for alerts and when {name} asks what you learnt</label>
                {canSpeak() && <label className="flex items-center gap-2"><input type="checkbox" checked={prefs.voice} onChange={(event) => updatePrefs({ voice: event.target.checked })} className="h-4 w-4" /> Speak in English (alerts and AI answers read aloud)</label>}
                <div className="flex flex-wrap gap-2">
                  <button type="button" onClick={() => playTune("test", true)} className="rounded border border-slate-300 px-2 py-1 text-xs font-semibold">▶ Test sound</button>
                  <button type="button" onClick={() => playTune("alert", true)} className="rounded border border-slate-300 px-2 py-1 text-xs font-semibold">▶ Test alert</button>
                  {canSpeak() && <button type="button" onClick={() => speak(`Hello, I am ${name}, your FMWorks assistant. I will tell you when something needs your attention.`, true)} className="rounded border border-slate-300 px-2 py-1 text-xs font-semibold">▶ Test voice</button>}
                  {canSpeak() && <button type="button" onClick={() => stopSpeaking()} className="rounded border border-slate-300 px-2 py-1 text-xs font-semibold">■ Stop</button>}
                </div>
                {!prefs.sound && <p className="text-xs text-amber-800">Sounds are off. You may miss urgent alerts; {name} will remind you after a day.</p>}
                <p className="text-xs text-slate-500">Saved on this device only. Sound plays after you have tapped the page once.</p>
              </div>
            </details>

            <p className="border-t border-slate-100 pt-3 text-xs text-slate-500">
              {role && ["administrator", "facility_administrator", "facility_manager"].includes(role) && <><Link href="/administration/assistant#questions" className="font-semibold text-blue-700 underline" onClick={() => setOpen(false)}>Questions people asked {name}</Link>. </>}
              {role === "administrator" && <><Link href="/administration/assistant" className="font-semibold text-blue-700 underline" onClick={() => setOpen(false)}>Change {name}&apos;s name or picture</Link>. </>}
              Full guide: <Link href="/help/work-orders" className="font-semibold text-blue-700 underline" onClick={() => setOpen(false)}>How to fill in a Work Order</Link>.
              {aiEnabled
                ? "Questions you ask are kept with your role and this page (not your name) so the team can improve the answers; AI questions also go to the AI service. Never type passwords."
                : "Questions you ask are kept with your role and this page (not your name) so the team can improve the answers. Never type passwords."}
            </p>
          </div>
        </aside>
      )}
    </>
  );
}

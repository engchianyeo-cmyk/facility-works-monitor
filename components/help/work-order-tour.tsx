"use client";

import { useEffect, useRef, useState } from "react";
import type { TourStep, TourTarget } from "@/lib/help/work-order-tour";
import { canSpeak, speak } from "@/lib/help/ollie-voice";

function findTarget(target: TourTarget | null): HTMLElement | null {
  if (!target) return null;
  if (target.id) {
    const el = document.getElementById(target.id);
    if (el) return (el.closest("section") as HTMLElement | null) ?? el;
  }
  if (target.text) {
    const nodes = Array.from(document.querySelectorAll<HTMLElement>("main h1, main h2, main h3, main p"));
    const hit = nodes.find((node) => node.textContent?.trim().toLowerCase().startsWith(target.text!.toLowerCase()));
    if (hit) return (hit.closest("section") as HTMLElement | null) ?? hit.parentElement ?? hit;
  }
  return null;
}

/** UAT 21 Nov 2026: Ollie's step-by-step walk through the Work Order on screen (highlight + card, phone friendly). */
export default function WorkOrderTour({ steps, name, onClose }: { steps: TourStep[]; name: string; onClose: () => void }) {
  const usable = steps.filter((step, index) => !step.target || index === 0 || typeof document === "undefined" || findTarget(step.target));
  const [index, setIndex] = useState(0);
  const lit = useRef<{ el: HTMLElement; outline: string; offset: string } | null>(null);
  const step = usable[Math.min(index, usable.length - 1)];

  useEffect(() => {
    if (lit.current) { lit.current.el.style.outline = lit.current.outline; lit.current.el.style.outlineOffset = lit.current.offset; lit.current = null; }
    const el = findTarget(step?.target ?? null);
    if (el) {
      lit.current = { el, outline: el.style.outline, offset: el.style.outlineOffset };
      el.style.outline = "4px solid #7c3aed";
      el.style.outlineOffset = "4px";
      el.scrollIntoView({ behavior: "smooth", block: "center" });
    }
    return () => { if (lit.current) { lit.current.el.style.outline = lit.current.outline; lit.current.el.style.outlineOffset = lit.current.offset; lit.current = null; } };
  }, [step]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  if (!step) return null;
  const last = index >= usable.length - 1;
  return (
    <div role="dialog" aria-label={`${name}'s walk-through`} className="fixed inset-x-2 bottom-2 z-50 rounded-2xl border-2 border-violet-500 bg-white p-4 shadow-2xl sm:inset-x-auto sm:bottom-6 sm:right-6 sm:w-[24rem] print:hidden">
      <p className="text-xs font-semibold uppercase tracking-wide text-violet-700">{name} · step {index + 1} of {usable.length}</p>
      <h2 className="mt-1 text-base font-black text-slate-900">{step.title}</h2>
      <p className="mt-1 text-sm text-slate-700">{step.text}</p>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <button type="button" disabled={index === 0} onClick={() => setIndex((i) => Math.max(0, i - 1))} className="min-h-11 rounded-lg border border-slate-300 px-3 text-sm font-semibold disabled:opacity-40">Back</button>
        <button type="button" onClick={() => (last ? onClose() : setIndex((i) => i + 1))} className="min-h-11 rounded-lg bg-violet-700 px-4 text-sm font-black text-white">{last ? "Finish" : "Next"}</button>
        {canSpeak() && <button type="button" onClick={() => speak(`${step.title}. ${step.text}`, true)} className="min-h-11 rounded-lg border border-violet-300 px-3 text-sm font-semibold text-violet-900">🔊 Read aloud</button>}
        <button type="button" onClick={onClose} className="ml-auto text-sm font-semibold text-slate-600 underline">Stop</button>
      </div>
    </div>
  );
}

/** Guided order of the Technician's tasks during the work, each linked to its place on the page. */
export type CompletionStep = { label: string; done: boolean; href: string; note?: string; optional?: boolean };

export default function WorkCompletionSteps({ steps }: { steps: CompletionStep[] }) {
  const next = steps.find((step) => !step.done && !step.optional);
  const doneCount = steps.filter((step) => step.done).length;
  return <section id="work-completion-steps" aria-labelledby="work-completion-steps-title" className="rounded-xl border-2 border-blue-300 bg-blue-50 p-5">
    <div className="flex flex-wrap items-baseline justify-between gap-2">
      <h2 id="work-completion-steps-title" className="text-lg font-black text-blue-950">Steps to submit this Work Order for review</h2>
      <p className="text-sm font-semibold text-blue-900">{doneCount} of {steps.length} done</p>
    </div>
    <p className="mt-1 text-sm text-blue-900">Work down the page in this order. Each step links to the section where it is done.</p>
    <ol className="mt-3 space-y-2">
      {steps.map((step, index) => {
        const current = step === next;
        return <li key={step.label} className={`flex flex-wrap items-center gap-3 rounded-lg border p-3 text-sm ${step.done ? "border-emerald-200 bg-white" : current ? "border-blue-500 bg-white shadow-sm" : "border-slate-200 bg-white/70"}`}>
          <span aria-hidden="true" className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-black ${step.done ? "bg-emerald-600 text-white" : current ? "bg-blue-700 text-white" : "bg-slate-200 text-slate-700"}`}>{step.done ? "✓" : index + 1}</span>
          <span className="min-w-0 flex-1">
            <span className="font-semibold">{step.label}</span>{step.optional && <span className="ml-1 text-slate-500">(optional)</span>}
            <span className="sr-only">{step.done ? " — done" : current ? " — next step" : " — to do"}</span>
            {step.note && <span className="block text-slate-600">{step.note}</span>}
          </span>
          <a href={step.href} className={`min-h-11 rounded-lg px-3 py-2 font-bold ${current ? "bg-blue-700 text-white" : "border border-blue-300 text-blue-800"}`}>{step.done ? "Review" : current ? "Do this now" : "Go to"}</a>
        </li>;
      })}
    </ol>
  </section>;
}

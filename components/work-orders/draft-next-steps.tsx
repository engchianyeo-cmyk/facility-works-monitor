import type { NextStep } from "@/lib/work-orders/next-steps";

/** Shown to the preparer while the Work Order is a Draft (D-10): what is left before submission. */
export default function DraftNextSteps({ steps, justCreated }: { steps: NextStep[]; justCreated: boolean }) {
  return (
    <section id="next-steps" aria-labelledby="next-steps-heading" className={`rounded-xl p-4 sm:p-5 ${steps.length ? "border-4 border-red-600 bg-red-50 text-red-950" : "border-2 border-emerald-300 bg-emerald-50 text-emerald-950"}`}>
      {steps.length > 0 && <p className="mb-2 inline-block rounded bg-red-600 px-3 py-1 text-sm font-black uppercase tracking-wide text-white">Action needed — {steps.length} {steps.length === 1 ? "step" : "steps"} before you submit</p>}
      <h2 id="next-steps-heading" className="text-lg font-bold">{justCreated ? "Draft saved — next steps" : "Next steps before you submit"}</h2>
      <p className="mt-1 text-sm">This Draft is saved. You can finish it now or later on your phone or computer; it stays under <strong>My Drafts</strong> until you submit it. <a href="/help/work-orders" className="font-semibold underline">How to fill in a Work Order</a></p>
      {steps.length === 0 ? (
        <p className="mt-3 rounded-lg bg-white p-3 text-sm font-semibold">Everything is in place. Use <strong>Submit for approval</strong> in Work Order actions below.</p>
      ) : (
        <ol className="mt-3 space-y-2">
          {steps.map((step, index) => (
            <li key={step.label} className="rounded-lg bg-white p-3 text-sm">
              <p className="font-semibold">{index + 1}. {step.href ? <a href={step.href} className="underline">{step.label}</a> : step.label}</p>
              {step.how && <p className="mt-1 text-slate-700">{step.how}</p>}
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}

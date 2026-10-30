import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";

export const metadata = { title: "How to fill in a Work Order" };

const STEPS: Array<{ title: string; when: string; items: string[] }> = [
  {
    title: "1. Create the Draft",
    when: "Phone or computer",
    items: [
      "Tap New Work Order. Enter a short title and the reason the work is needed (what is wrong, why it needs fixing, any safety impact).",
      "Tick Emergency only for urgent work that cannot wait for approval. Tick In-house services when in-house staff do the work (no pricing).",
      "Choose the area or room, and enter the exact location, e.g. \"Utility Block chiller plant room, pump P-CHW-03\".",
      "Asset, priority, due date and people to copy are under More details. Then tap Create Draft — it is saved straight away.",
    ],
  },
  {
    title: "2. Complete and submit",
    when: "Now or later, from My Drafts",
    items: [
      "Mark the location on the layout plan: choose the plan, select Pin, tap the spot, Save (not needed if the area is highlighted automatically).",
      "Add a Before photo, video or voice note in Evidence (category Before). On a phone, the upload button opens the camera.",
      "Attach the contractor's quotation: Prepare Proposal, choose the contractor, enter the amount and scope, attach the quotation, submit it.",
      "The Next steps box lists anything still missing. When it is empty, tap Submit for approval.",
    ],
  },
  {
    title: "3. Do and record the work",
    when: "After approval",
    items: [
      "Tap Start work when the job begins (the start time is logged automatically).",
      "Add After photos, then open Physical Completion and record the work performed and labour hours.",
      "Enter the actual costs, confirm them, and tap Submit Physical Completion (the end time is logged automatically).",
    ],
  },
  {
    title: "4. Final cost, final quotation and invoice",
    when: "After the work",
    items: [
      "Enter the final contractor amount and tick that you verified the materials and labour on site.",
      "If the amount differs from the approved quotation, attach the contractor's final quotation for the work done.",
      "After the work is approved as Completed, upload the contractor's invoice. Its amount must equal the approved final amount; Finance takes it from there.",
    ],
  },
];

export default async function WorkOrderHelpPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/help/work-orders");
  return (
    <main className="mx-auto max-w-3xl space-y-6 p-4 sm:p-6 lg:p-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">How to fill in a Work Order</h1>
        <p className="mt-2 text-sm text-slate-600">For Technicians, and for Approvers, Supervisors, Facility Managers and Administrators who raise a Work Order when the Technician is unavailable. You can start on your phone and finish on your computer: a Draft stays under My Drafts until you submit it.</p>
        <div className="mt-4 flex flex-wrap gap-2">
          <Link href="/work-orders/new" className="min-h-11 rounded-lg bg-blue-600 px-4 py-3 text-sm font-semibold text-white">New Work Order</Link>
          <Link href="/work-orders?view=drafts" className="min-h-11 rounded-lg border border-blue-300 px-4 py-3 text-sm font-semibold text-blue-800">My Drafts</Link>
        </div>
      </div>
      {STEPS.map((step) => (
        <section key={step.title} className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5" aria-label={step.title}>
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="text-lg font-bold text-slate-900">{step.title}</h2>
            <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">{step.when}</span>
          </div>
          <ul className="mt-3 list-disc space-y-2 pl-5 text-sm text-slate-800">
            {step.items.map((item) => <li key={item}>{item}</li>)}
          </ul>
        </section>
      ))}
      <p className="text-sm text-slate-600">Emergency work starts as soon as it is submitted; add the location, Before and After evidence and the contractor&apos;s site-verified quotation before the review. In-house work needs no quotation, invoice or payment and closes when approved as Completed.</p>
    </main>
  );
}

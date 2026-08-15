import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";

const EXPORTS = [
  ["work-orders", "Work Order register", "Visible work, status, dates, assignment and rework count."],
  ["assets", "Asset register", "Visible asset identity, criticality, lifecycle and physical location."],
  ["incidents", "Incident register", "Visible incidents, severity, recorded response state and key dates."],
  ["pm-outcomes", "PM outcomes register", "Visible planned occurrences, due dates, generation, deferral and linked Work Order outcome."],
] as const;

export default async function ExportsPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/exports");
  if (!["approver", "supervisor", "administrator"].includes(identity.role)) redirect("/operations");

  return (
    <main className="mx-auto max-w-4xl space-y-6 p-6 lg:p-8">
      <header>
        <p className="text-xs font-black uppercase tracking-[.2em] text-blue-700">Controlled extract</p>
        <h1 className="mt-1 text-3xl font-black">Operational CSV exports</h1>
        <p className="mt-2 text-sm text-slate-600">Downloads are authenticated, role-controlled and limited by the same database policies as the app. Values are escaped for spreadsheet formula safety.</p>
      </header>
      <ul className="grid gap-4 md:grid-cols-2">
        {EXPORTS.map(([key, title, description]) => (
          <li key={key} className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <h2 className="font-black">{title}</h2>
            <p className="mt-2 text-sm text-slate-600">{description}</p>
            <Link href={`/api/exports/${key}`} className="mt-4 inline-flex min-h-11 items-center rounded-lg bg-blue-700 px-4 text-sm font-bold text-white">Download CSV</Link>
          </li>
        ))}
      </ul>
      <p className="rounded-lg bg-amber-50 p-4 text-sm text-amber-950">Exports reflect recorded data at the Asia/Singapore extraction time. They do not represent live personnel or equipment availability.</p>
    </main>
  );
}

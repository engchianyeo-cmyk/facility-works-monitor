import Link from "next/link";
import type { UserRole } from "@/lib/auth";
import { canReportIncident } from "@/lib/incidents/permissions";
import { canCreate } from "@/lib/work-orders/permissions";
import SectionTitle from "@/components/ui/SectionTitle";

const primary =
  "rounded-xl bg-blue-700 px-4 py-3 text-sm font-black text-white hover:bg-blue-800 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-blue-200";
const emergency =
  "rounded-xl border-2 border-red-600 bg-white px-4 py-3 text-sm font-black text-red-700 hover:bg-red-50 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-red-200";
const secondary =
  "rounded-lg px-3 py-2 text-sm font-bold text-slate-600 hover:bg-slate-100 hover:text-slate-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600";

export default function QuickActions({ role }: { role: UserRole }) {
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5">
      <SectionTitle title="Quick actions" />
      <div className="mt-4 grid gap-2">
        {canCreate(role) && (
          <Link href="/work-orders/new" className={primary}>
            + New Work Order
          </Link>
        )}
        {canReportIncident(role) && (
          <Link href="/incidents/new" className={emergency}>
            Report Incident
          </Link>
        )}
      </div>
      <nav aria-label="Operational shortcuts" className="mt-3 grid gap-1 border-t border-slate-100 pt-3">
        <Link href="/work-orders" className={secondary}>View Work Orders</Link>
        <Link href="/incidents" className={secondary}>Incident Board</Link>
        {role === "administrator" && (
          <>
            <Link href="/administration/users" className={secondary}>Users</Link>
            <Link href="/administration/departments" className={secondary}>Departments</Link>
          </>
        )}
        {["approver", "supervisor", "administrator"].includes(role) && (
          <Link href="/administration/emergency-roster" className={secondary}>On-call Roster</Link>
        )}
      </nav>
    </section>
  );
}

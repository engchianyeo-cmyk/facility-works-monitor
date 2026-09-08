import Link from "next/link";
import { getCurrentIdentity } from "@/lib/auth";
import { operationalLabel } from "@/lib/product-terminology";

export default async function SiteHeader() {
  const identity = await getCurrentIdentity();
  const management = identity && ["approver", "supervisor", "facility_manager", "administrator"].includes(identity.role);
  const contractorAdmin = identity && ["supervisor", "facility_manager", "administrator"].includes(identity.role);

  return (
    <header className="border-b border-slate-200 bg-white">
      <div className="mx-auto flex max-w-7xl flex-col gap-4 px-6 py-4">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <Link href="/" className="text-2xl font-bold tracking-tight text-slate-900">
              <span className="text-blue-600">FM</span>Works
            </Link>
            <p className="mt-1 text-xs text-slate-500">Built with Facility Managers. Designed for Service Teams.</p>
          </div>

          {identity && (
            <div className="flex flex-wrap items-center gap-3 rounded-xl border border-slate-200 bg-slate-50 px-4 py-3">
              <div className="text-right">
                <p className="text-sm font-black text-slate-900">{identity.displayName}</p>
                <p className="text-xs font-semibold text-slate-500">{operationalLabel(identity.role)}</p>
              </div>
              <form action="/auth/logout" method="post">
                <button
                  type="submit"
                  className="min-h-10 rounded-lg bg-slate-900 px-4 text-sm font-black text-white hover:bg-slate-700 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-slate-300"
                >
                  Sign Out
                </button>
              </form>
            </div>
          )}
        </div>

        <nav className="flex flex-wrap items-center gap-2" aria-label="Main navigation">
          <Link href="/" className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Home</Link>
          <Link href="/work-orders" className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Work Orders</Link>
          {identity && <Link href="/assets" className="rounded-lg px-4 py-2 text-sm font-semibold text-emerald-700 hover:bg-emerald-50">Assets</Link>}
          {identity && <Link href="/operations" className="rounded-lg px-4 py-2 text-sm font-semibold text-blue-700 hover:bg-blue-50">Operations</Link>}
          {identity && identity.role !== "technician" && <Link href="/maintenance" className="rounded-lg px-4 py-2 text-sm font-semibold text-teal-700 hover:bg-teal-50">Maintenance</Link>}
          {identity && <Link href="/incidents" className="rounded-lg px-4 py-2 text-sm font-bold text-red-700 hover:bg-red-50">Emergency</Link>}
          {management && <Link href="/administration/emergency-roster" className="rounded-lg px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-50">On-call Roster</Link>}
          {contractorAdmin && <Link href="/administration/contractors" className="rounded-lg px-4 py-2 text-sm font-semibold text-amber-800 hover:bg-amber-50">Contractors & Rates</Link>}
          {management && <Link href="/exports" className="rounded-lg px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-100">Exports</Link>}
          {management && <Link href="/management/sla" className="rounded-lg px-4 py-2 text-sm font-semibold text-indigo-700 hover:bg-indigo-50">SLA</Link>}
          {management && <Link href="/management/staffing" className="rounded-lg px-4 py-2 text-sm font-semibold text-indigo-700 hover:bg-indigo-50">Staffing</Link>}
          {identity ? (
            <>
              {identity.role === "administrator" && (
                <>
                  <Link href="/administration/users" className="rounded-lg px-4 py-2 text-sm font-semibold text-blue-700 hover:bg-blue-50">Users</Link>
                  <Link href="/administration/departments" className="rounded-lg px-4 py-2 text-sm font-semibold text-blue-700 hover:bg-blue-50">Departments</Link>
                </>
              )}
              <Link href="/work-orders/new" className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700">+ New Work Order</Link>
              <Link href="/account/password" className="rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Password</Link>
            </>
          ) : (
            <>
              <Link href="/login" className="rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Sign in</Link>
              <Link href="/first-time" className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700">First-time access</Link>
            </>
          )}
        </nav>
      </div>
    </header>
  );
}

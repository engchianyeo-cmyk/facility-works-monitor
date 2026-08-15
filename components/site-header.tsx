import Link from "next/link";
import { getCurrentIdentity } from "@/lib/auth";

export default async function SiteHeader() {
  const identity = await getCurrentIdentity();

  return (
    <header className="border-b border-slate-200 bg-white">
      <div className="mx-auto flex max-w-7xl flex-col gap-4 px-6 py-4 md:flex-row md:items-center md:justify-between">
        <div>
          <Link
            href="/"
            className="text-2xl font-bold tracking-tight text-slate-900"
          >
            <span className="text-blue-600">FM</span>Works
          </Link>

          <p className="mt-1 text-xs text-slate-500">
            Built with Facility Managers. Designed for Service Teams.
          </p>
        </div>

        <nav
          className="flex flex-wrap items-center gap-2"
          aria-label="Main navigation"
        >
          <Link
            href="/"
            className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
          >
            Home
          </Link>

          <Link
            href="/work-orders"
            className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
          >
            Work Orders
          </Link>

          {identity && (
            <Link
              href="/assets"
              className="rounded-lg px-4 py-2 text-sm font-semibold text-emerald-700 transition hover:bg-emerald-50"
            >
              Assets
            </Link>
          )}

          {identity && (
            <Link
              href="/operations"
              className="rounded-lg px-4 py-2 text-sm font-semibold text-blue-700 transition hover:bg-blue-50"
            >
              Operations
            </Link>
          )}

          {identity && identity.role !== "technician" && (
            <Link
              href="/maintenance"
              className="rounded-lg px-4 py-2 text-sm font-semibold text-teal-700 transition hover:bg-teal-50"
            >
              Maintenance
            </Link>
          )}

          {identity && (
            <Link
              href="/incidents"
              className="rounded-lg px-4 py-2 text-sm font-bold text-red-700 transition hover:bg-red-50"
            >
              Emergency
            </Link>
          )}

          {identity && ["approver", "supervisor", "administrator"].includes(identity.role) && (
            <Link href="/administration/emergency-roster" className="rounded-lg px-4 py-2 text-sm font-semibold text-red-700 transition hover:bg-red-50">On-call Roster</Link>
          )}

          {identity && ["approver", "supervisor", "administrator"].includes(identity.role) && (
            <Link href="/exports" className="rounded-lg px-4 py-2 text-sm font-semibold text-slate-700 transition hover:bg-slate-100">Exports</Link>
          )}

          {identity ? (
            <>
              {identity.role === "administrator" && (
                <>
                  <Link
                    href="/administration/users"
                    className="rounded-lg px-4 py-2 text-sm font-semibold text-blue-700 transition hover:bg-blue-50"
                  >
                    Users
                  </Link>
                  <Link
                    href="/administration/departments"
                    className="rounded-lg px-4 py-2 text-sm font-semibold text-blue-700 transition hover:bg-blue-50"
                  >
                    Departments
                  </Link>
                </>
              )}
              <Link
                href="/work-orders/new"
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700"
              >
                + New Work Order
              </Link>
              <span className="px-2 text-sm text-slate-600">
                {identity.displayName}
              </span>
              <Link href="/account/password" className="rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Password</Link>
              <form action="/auth/logout" method="post">
                <button
                  type="submit"
                  className="rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100"
                >
                  Log out
                </button>
              </form>
            </>
          ) : (
            <>
              <Link
                href="/login"
                className="rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100"
              >
                Sign in
              </Link>
              <Link href="/first-time" className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700">First-time access</Link>
            </>
          )}
        </nav>
      </div>
    </header>
  );
}

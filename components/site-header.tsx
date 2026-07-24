import Link from "next/link";

export default function SiteHeader() {
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
            href="/works"
            className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
          >
            Work Orders
          </Link>

          <Link
            href="/works/new"
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700"
          >
            + New Work Order
          </Link>
        </nav>
      </div>
    </header>
  );
}

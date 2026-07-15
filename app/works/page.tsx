import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { StatusBadge, PriorityBadge } from "@/components/badges";
import { WorkOrderStatus } from "@/lib/status";

export const revalidate = 0;

const STATUSES: WorkOrderStatus[] = ["submitted", "approved", "in_progress", "done", "rejected"];

export default async function WorksPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; sort?: string }>;
}) {
  const { status, sort } = await searchParams;
  const supabase = await createClient();

  let query = supabase.from("work_orders").select("*, categories(name)");

  if (status && STATUSES.includes(status as WorkOrderStatus)) {
    query = query.eq("status", status);
  }

  if (sort === "priority") {
    query = query.order("priority", { ascending: false });
  } else {
    query = query.order("created_at", { ascending: false });
  }

  const { data: orders, error } = await query;

  return (
    <main className="max-w-5xl mx-auto p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Work Orders</h1>
          <Link href="/" className="text-sm text-neutral-500 hover:underline">
            ← Dashboard
          </Link>
        </div>
        <Link
          href="/works/new"
          className="rounded-lg bg-neutral-900 text-white px-4 py-2 text-sm font-medium hover:bg-neutral-700"
        >
          + Submit Work Order
        </Link>
      </div>

      <div className="flex flex-wrap gap-2 text-sm">
        <Link
          href="/works"
          className={`px-3 py-1 rounded-full border ${!status ? "bg-neutral-900 text-white" : "border-neutral-300"}`}
        >
          All
        </Link>
        {STATUSES.map((s) => (
          <Link
            key={s}
            href={`/works?status=${s}`}
            className={`px-3 py-1 rounded-full border ${status === s ? "bg-neutral-900 text-white" : "border-neutral-300"}`}
          >
            {s.replace("_", " ")}
          </Link>
        ))}
        <span className="mx-2 text-neutral-300">|</span>
        <Link
          href={`/works${status ? `?status=${status}&` : "?"}sort=priority`}
          className="px-3 py-1 rounded-full border border-neutral-300"
        >
          Sort by priority
        </Link>
      </div>

      {error && (
        <div className="rounded-lg border border-red-300 bg-red-50 text-red-700 p-4 text-sm">
          Couldn&apos;t load work orders: {error.message}
        </div>
      )}

      {!error && orders?.length === 0 && (
        <div className="rounded-lg border border-dashed border-neutral-300 p-10 text-center text-neutral-400">
          No work orders {status ? `with status "${status}"` : "yet"}.
        </div>
      )}

      {!error && orders && orders.length > 0 && (
        <ul className="divide-y divide-neutral-100 rounded-xl border border-neutral-200">
          {orders.map((o) => (
            <li key={o.id}>
              <Link
                href={`/works/${o.id}`}
                className="flex items-center justify-between gap-4 p-4 hover:bg-neutral-50"
              >
                <div>
                  <div className="font-medium">{o.title}</div>
                  <div className="text-sm text-neutral-500">
                    {o.location} {o.categories?.name ? `· ${o.categories.name}` : ""}
                  </div>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <PriorityBadge priority={o.priority} />
                  <StatusBadge status={o.status as WorkOrderStatus} />
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}

import EmptyState from "@/components/ui/EmptyState";
import SectionTitle from "@/components/ui/SectionTitle";
import { operationalLabel } from "@/lib/product-terminology";

export type TimelineItem = {
  id: string;
  action: string;
  actor: string | null;
  created_at: string;
  work_order_id?: string | null;
  incident_id?: string | null;
};

const format = (value: string) =>
  new Intl.DateTimeFormat("en-SG", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Singapore",
  }).format(new Date(value));

export default function TimelineFeed({ items }: { items: TimelineItem[] }) {
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5">
      <SectionTitle title="Recent activity" />
      <div className="mt-4">
        {!items.length ? (
          <EmptyState title="No recent activity" description="Recent operational updates will appear here." />
        ) : (
          <ol className="border-l-2 border-slate-200 pl-5">
            {items.slice(0, 8).map((item) => (
              <li key={item.id} className="relative pb-5 before:absolute before:-left-[1.55rem] before:top-1 before:h-3 before:w-3 before:rounded-full before:bg-blue-600">
                <p className="font-bold">{operationalLabel(item.action)}</p>
                <p className="text-xs text-slate-500">{item.actor || "System"} · <time dateTime={item.created_at}>{format(item.created_at)}</time></p>
              </li>
            ))}
          </ol>
        )}
      </div>
    </section>
  );
}

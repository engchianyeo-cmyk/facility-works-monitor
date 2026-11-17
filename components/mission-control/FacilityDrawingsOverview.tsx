import Link from "next/link";
import SectionTitle from "@/components/ui/SectionTitle";
import { createClient } from "@/lib/supabase/server";
import { FACILITY_DRAWING_COLUMNS, facilityDrawingSrc, hasPinImage, isImageDrawing, type FacilityDrawingRow } from "@/lib/facility-drawings";
import FacilityLayoutPanel, { sampleFacilityLayoutConfig } from "./FacilityLayoutPanel";

/**
 * UAT 16 Nov 2026 (owner): the Home page shows each facility's own uploaded drawings instead of the development
 * sample layout. Row security limits it to the facilities the person may see. The sample stays as the fallback
 * until a facility has drawings.
 */
const PLAN_HINT = /(^|[^0-9])1\d\d($|[^0-9])|plan|level|storey/i;

function previewable(row: FacilityDrawingRow) {
  return isImageDrawing(row) || hasPinImage(row);
}

export default async function FacilityDrawingsOverview() {
  const supabase = await createClient();
  const [sites, drawings, open] = await Promise.all([
    supabase.from("sites").select("id,code,name").eq("is_active", true).order("name"),
    supabase.from("facility_drawings").select(FACILITY_DRAWING_COLUMNS).eq("active", true).order("code"),
    supabase.from("work_orders").select("facility_id").not("status", "in", "(closed,cancelled)"),
  ]);
  const rows = (drawings.error ? [] : drawings.data ?? []) as FacilityDrawingRow[];
  const facilities = ((sites.data ?? []) as Array<{ id: string; code: string; name: string }>).filter((site) => rows.some((row) => row.facility_id === site.id));
  if (facilities.length === 0) return <FacilityLayoutPanel config={sampleFacilityLayoutConfig} />;
  const openCount = new Map<string, number>();
  for (const row of (open.data ?? []) as Array<{ facility_id: string | null }>) {
    if (row.facility_id) openCount.set(row.facility_id, (openCount.get(row.facility_id) ?? 0) + 1);
  }

  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5" aria-labelledby="facility-drawings-overview">
      <SectionTitle title="Facility drawings" action={<Link href="/drawings" className="text-sm font-bold text-blue-700 hover:underline">All drawings →</Link>} />
      <p id="facility-drawings-overview" className="mt-1 text-sm text-slate-500">The current layout drawings of each facility you can see. Work Order locations are marked with a star on the drawing inside each Work Order.</p>
      <div className="mt-4 grid gap-5 lg:grid-cols-2">
        {facilities.map((facility) => {
          const own = rows.filter((row) => row.facility_id === facility.id);
          const lead = own.find((row) => previewable(row) && PLAN_HINT.test(`${row.code} ${row.title}`)) ?? own.find(previewable) ?? null;
          const count = openCount.get(facility.id) ?? 0;
          return (
            <article key={facility.id} className="overflow-hidden rounded-xl border border-slate-200">
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-200 bg-slate-50 px-4 py-3">
                <div>
                  <h3 className="font-bold text-slate-900">{facility.name}</h3>
                  <p className="text-xs text-slate-500">{facility.code} · {own.length} drawing{own.length === 1 ? "" : "s"}</p>
                </div>
                <Link href={`/work-orders?facility=${facility.id}`} className="rounded-lg bg-blue-700 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-800">
                  {count} open Work Order{count === 1 ? "" : "s"} →
                </Link>
              </div>
              {lead ? (
                <a href={facilityDrawingSrc(lead.id)} target="_blank" rel="noopener" className="block bg-white">
                  {/* eslint-disable-next-line @next/next/no-img-element -- drawings stream from the authenticated file route */}
                  <img src={facilityDrawingSrc(lead.id, false, hasPinImage(lead))} alt={`${lead.code} ${lead.title}`} loading="lazy" className="h-64 w-full object-contain" />
                  <p className="border-t border-slate-100 px-4 py-2 text-xs text-slate-600"><strong>{lead.code}</strong> — {lead.title} · {lead.revision ?? "No revision"} · click to open</p>
                </a>
              ) : (
                <p className="px-4 py-6 text-sm text-slate-500">PDF drawings only; open them from the list below.</p>
              )}
              <ul className="flex flex-wrap gap-2 border-t border-slate-100 px-4 py-3">
                {own.map((row) => (
                  <li key={row.id}>
                    <a href={facilityDrawingSrc(row.id)} target="_blank" rel="noopener" className="inline-block rounded border border-slate-300 px-2 py-1 text-xs font-semibold text-blue-700 hover:bg-blue-50" title={`${row.title} · ${row.revision ?? "No revision"}`}>
                      {row.code}
                    </a>
                  </li>
                ))}
              </ul>
            </article>
          );
        })}
      </div>
    </section>
  );
}

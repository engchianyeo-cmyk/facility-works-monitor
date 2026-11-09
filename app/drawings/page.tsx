import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { FACILITY_DRAWING_COLUMNS, facilityDrawingSrc, hasPinImage, type FacilityDrawingRow } from "@/lib/facility-drawings";
import { createClient } from "@/lib/supabase/server";

export const revalidate = 0;

/** D-17: staff view and download the layout drawings the Administrator uploaded for each facility. */
export default async function DrawingsPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/drawings");
  const supabase = await createClient();
  const [facilities, drawings, superseded] = await Promise.all([
    supabase.from("sites").select("id,code,name").eq("is_active", true).order("name"),
    supabase.from("facility_drawings").select(FACILITY_DRAWING_COLUMNS).eq("active", true).order("code"),
    // D-44: earlier revisions, kept for reference under each facility.
    supabase.from("facility_drawings").select(FACILITY_DRAWING_COLUMNS).eq("active", false).not("superseded_at", "is", null).order("superseded_at", { ascending: false }),
  ]);
  const earlier = (superseded.error ? [] : superseded.data ?? []) as FacilityDrawingRow[];
  const kind = (row: FacilityDrawingRow) => row.content_type === "application/pdf" ? (hasPinImage(row) ? "PDF · pins ✓" : "PDF") : "Image · pins ✓";
  const rows = (drawings.error ? [] : drawings.data ?? []) as FacilityDrawingRow[];
  const withDrawings = (facilities.data ?? []).filter((facility) => rows.some((row) => row.facility_id === facility.id));
  return <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
    <div>
      <h1 className="text-3xl font-black">Facility drawings</h1>
      <p className="mt-1 text-slate-600">The current layout drawings of each facility, kept as PDF where available. View opens the drawing in a new tab; Download saves the file. Earlier revisions are kept under each facility for reference.</p>
    </div>
    {drawings.error && <p role="alert">Drawings are unavailable in this environment.</p>}
    {!drawings.error && withDrawings.length === 0 && <p>No drawings have been uploaded yet.</p>}
    {withDrawings.map((facility) => <section key={facility.id} className="rounded-xl border bg-white p-5" aria-labelledby={`drawings-${facility.id}`}>
      <h2 id={`drawings-${facility.id}`} className="text-xl font-bold">{facility.name} <span className="text-sm font-normal text-slate-500">· {facility.code}</span></h2>
      <ul className="mt-3 divide-y rounded-lg border">{rows.filter((row) => row.facility_id === facility.id).map((drawing) => <li key={drawing.id} className="flex flex-wrap items-center gap-3 p-3 text-sm">
        <span className="min-w-0 flex-1"><strong>{drawing.code}</strong> — {drawing.title} <span className="text-slate-500">· {drawing.revision ?? "No revision"} · {kind(drawing)} · {(drawing.byte_size / 1024 / 1024).toFixed(1)} MB</span></span>
        <a href={facilityDrawingSrc(drawing.id)} target="_blank" rel="noopener" className="min-h-11 rounded border px-3 py-2 font-semibold text-blue-700">View</a>
        <a href={facilityDrawingSrc(drawing.id, true)} className="min-h-11 rounded border px-3 py-2 font-semibold text-blue-700">Download</a>
      </li>)}</ul>
      {earlier.some((row) => row.facility_id === facility.id) && <details className="mt-3 rounded-lg border bg-slate-50 p-3 text-sm">
        <summary className="cursor-pointer font-semibold">Earlier revisions ({earlier.filter((row) => row.facility_id === facility.id).length}) — superseded, for reference only</summary>
        <ul className="mt-2 divide-y">{earlier.filter((row) => row.facility_id === facility.id).map((drawing) => <li key={drawing.id} className="flex flex-wrap items-center gap-3 py-2 text-slate-600">
          <span className="min-w-0 flex-1"><strong>{drawing.code}</strong> — {drawing.title} · {drawing.revision ?? "No revision"} · superseded {drawing.superseded_at ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeZone: "Asia/Singapore" }).format(new Date(drawing.superseded_at)) : ""}</span>
          <a href={facilityDrawingSrc(drawing.id)} target="_blank" rel="noopener" className="min-h-11 rounded border px-3 py-2 font-semibold text-blue-700">View</a>
          <a href={facilityDrawingSrc(drawing.id, true)} className="min-h-11 rounded border px-3 py-2 font-semibold text-blue-700">Download</a>
        </li>)}</ul>
      </details>}
    </section>)}
  </main>;
}

"use client";

import Image from "next/image";
import { PointerEvent, useCallback, useEffect, useMemo, useState } from "react";
import type { WorkOrderDrawing } from "@/lib/work-order-drawings";

type Point = { x: number; y: number };
type Tool = "marker" | "arrow" | "circle" | "rectangle" | "freehand" | "text";
type Annotation = {
  id: string;
  annotation_type: Tool;
  geometry: { points: Point[] };
  note: string;
  created_at?: string;
  created_by?: string;
  saved?: boolean;
};

const TOOLS: Array<{ value: Tool; label: string }> = [
  { value: "marker", label: "Pin" },
  { value: "arrow", label: "Arrow" },
  { value: "circle", label: "Circle" },
  { value: "rectangle", label: "Rectangle" },
  { value: "freehand", label: "Freehand" },
  { value: "text", label: "Text / Note" },
];

function point(event: PointerEvent<SVGSVGElement>): Point {
  const bounds = event.currentTarget.getBoundingClientRect();
  return {
    x: Math.max(0, Math.min(100, ((event.clientX - bounds.left) / bounds.width) * 100)),
    y: Math.max(0, Math.min(100, ((event.clientY - bounds.top) / bounds.height) * 100)),
  };
}

function annotationShape(annotation: Annotation, selected: boolean) {
  const points = annotation.geometry.points;
  const start = points[0];
  const end = points.at(-1) ?? start;
  if (!start) return null;
  const colour = selected ? "#1d4ed8" : "#dc2626";
  const common = { stroke: colour, strokeWidth: selected ? 0.8 : 0.55, fill: "none", vectorEffect: "non-scaling-stroke" as const };
  if (annotation.annotation_type === "marker") return <g><circle cx={start.x} cy={start.y} r="1.8" fill={colour} stroke="white" strokeWidth="0.45"/><path d={`M ${start.x} ${start.y + 1.5} L ${start.x} ${start.y + 4}`} {...common}/></g>;
  if (annotation.annotation_type === "text") return <g><circle cx={start.x} cy={start.y} r="1.4" fill={colour}/><text x={start.x + 2} y={start.y + 0.8} fill={colour} fontSize="3.2" fontWeight="700">{annotation.note.slice(0, 28)}</text></g>;
  if (annotation.annotation_type === "arrow") return <line x1={start.x} y1={start.y} x2={end.x} y2={end.y} {...common} markerEnd="url(#markup-arrow)"/>;
  if (annotation.annotation_type === "rectangle") return <rect x={Math.min(start.x,end.x)} y={Math.min(start.y,end.y)} width={Math.abs(end.x-start.x)} height={Math.abs(end.y-start.y)} {...common}/>;
  if (annotation.annotation_type === "circle") return <ellipse cx={(start.x+end.x)/2} cy={(start.y+end.y)/2} rx={Math.abs(end.x-start.x)/2} ry={Math.abs(end.y-start.y)/2} {...common}/>;
  return <polyline points={points.map((item)=>`${item.x},${item.y}`).join(" ")} {...common}/>;
}

export default function DrawingMarkupEditor({ workOrderId, drawing, assetMarker, canMutate }: {
  workOrderId: string;
  drawing: WorkOrderDrawing;
  assetMarker?: { x: number; y: number; label: string };
  canMutate: boolean;
}) {
  const [saved, setSaved] = useState<Annotation[]>([]);
  const [drafts, setDrafts] = useState<Annotation[]>([]);
  const [future, setFuture] = useState<Annotation[]>([]);
  const [tool, setTool] = useState<Tool>("marker");
  const [note, setNote] = useState("Roller shutter repair location");
  const [drawingNow, setDrawingNow] = useState<Annotation | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    const response = await fetch(`/api/work-orders/${workOrderId}/release-1`, { cache: "no-store" });
    const body = await response.json();
    if (!response.ok || !body.ok) throw new Error(body.message ?? "Saved markup could not be loaded.");
    const rows = Array.isArray(body.data?.markups) ? body.data.markups : [];
    setSaved(rows.filter((row: Record<string, unknown>) => row.source_reference === drawing.code && row.drawing_revision === drawing.revision).map((row: Annotation) => ({ ...row, saved: true })));
  }, [drawing.code, drawing.revision, workOrderId]);

  useEffect(() => { void load().catch((error) => setMessage(error instanceof Error ? error.message : "Saved markup could not be loaded.")); }, [load]);
  useEffect(() => { setDrafts([]); setFuture([]); setSelectedId(null); }, [drawing.code, drawing.revision]);

  const annotations = useMemo(() => [...saved, ...drafts, ...(drawingNow ? [drawingNow] : [])], [saved, drafts, drawingNow]);

  function begin(event: PointerEvent<SVGSVGElement>) {
    if (!canMutate) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    const start = point(event);
    const annotation: Annotation = { id: crypto.randomUUID(), annotation_type: tool, geometry: { points: [start] }, note: note.trim() || `${tool} annotation` };
    if (tool === "marker" || tool === "text") {
      setDrafts((current) => [...current, annotation]);
      setFuture([]);
      setSelectedId(annotation.id);
      return;
    }
    setDrawingNow(annotation);
  }

  function move(event: PointerEvent<SVGSVGElement>) {
    if (!drawingNow) return;
    const next = point(event);
    setDrawingNow((current) => current ? { ...current, geometry: { points: current.annotation_type === "freehand" ? [...current.geometry.points, next] : [current.geometry.points[0], next] } } : null);
  }

  function finish(event: PointerEvent<SVGSVGElement>) {
    if (!drawingNow) return;
    const end = point(event);
    const completed = { ...drawingNow, geometry: { points: drawingNow.annotation_type === "freehand" ? [...drawingNow.geometry.points, end] : [drawingNow.geometry.points[0], end] } };
    setDrafts((current) => [...current, completed]);
    setFuture([]);
    setSelectedId(completed.id);
    setDrawingNow(null);
  }

  async function save() {
    if (!drafts.length) return;
    setBusy(true); setMessage("");
    try {
      for (const annotation of drafts) {
        const response = await fetch(`/api/work-orders/${workOrderId}/release-1`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ operation: "markup", payload: { source_type: "drawing", source_reference: drawing.code, drawing_revision: drawing.revision, annotation_type: annotation.annotation_type, geometry: annotation.geometry, x_percent: annotation.geometry.points[0].x, y_percent: annotation.geometry.points[0].y, note: annotation.note } }) });
        const body = await response.json();
        if (!response.ok || !body.ok) throw new Error(body.message ?? "Markup could not be saved.");
      }
      setDrafts([]); setFuture([]); setSelectedId(null);
      await load();
      setMessage("Markup saved with drawing revision, author and timestamp.");
    } catch (error) { setMessage(error instanceof Error ? error.message : "Markup could not be saved."); }
    finally { setBusy(false); }
  }

  async function removeSelected() {
    const draft = drafts.find((item) => item.id === selectedId);
    if (draft) { setDrafts((current) => current.filter((item) => item.id !== draft.id)); setSelectedId(null); return; }
    const stored = saved.find((item) => item.id === selectedId);
    if (!stored || !canMutate) return;
    setBusy(true);
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/release-1`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ operation: "delete_markup", payload: { markup_id: stored.id } }) });
      const body = await response.json();
      if (!response.ok || !body.ok) throw new Error(body.message ?? "Markup could not be deleted.");
      setSelectedId(null); await load(); setMessage("Markup deleted; its audit record was retained.");
    } catch (error) { setMessage(error instanceof Error ? error.message : "Markup could not be deleted."); }
    finally { setBusy(false); }
  }

  return <section className="mt-5 border-t border-slate-200 pt-5" aria-labelledby="drawing-markup-heading">
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div><p className="text-xs font-black uppercase text-blue-700">Technician markup</p><h3 id="drawing-markup-heading" className="text-lg font-bold">{drawing.code} · Revision {drawing.revision}</h3></div>
      <span className="text-xs text-slate-500">{saved.length} saved · {drafts.length} unsaved</span>
    </div>
    {canMutate && <div className="mt-3 flex flex-wrap items-end gap-2 rounded-lg border bg-slate-50 p-3" role="toolbar" aria-label="Drawing markup tools">
      <div className="flex flex-wrap gap-1">{TOOLS.map((item)=><button key={item.value} type="button" onClick={()=>setTool(item.value)} aria-pressed={tool===item.value} className={`min-h-10 rounded border px-3 text-sm font-semibold ${tool===item.value?"border-blue-700 bg-blue-700 text-white":"bg-white text-slate-800"}`}>{item.label}</button>)}</div>
      <label className="min-w-52 flex-1 text-xs font-bold">Annotation note<input value={note} onChange={(event)=>setNote(event.target.value)} maxLength={1000} className="mt-1 min-h-10 w-full rounded border bg-white px-3 text-sm"/></label>
      <button type="button" disabled={!drafts.length||busy} onClick={()=>{const last=drafts.at(-1);if(last){setDrafts((current)=>current.slice(0,-1));setFuture((current)=>[last,...current]);}}} className="min-h-10 rounded border bg-white px-3 font-semibold disabled:opacity-40">Undo</button>
      <button type="button" disabled={!future.length||busy} onClick={()=>{const next=future[0];if(next){setFuture((current)=>current.slice(1));setDrafts((current)=>[...current,next]);}}} className="min-h-10 rounded border bg-white px-3 font-semibold disabled:opacity-40">Redo</button>
      <button type="button" disabled={!selectedId||busy} onClick={()=>void removeSelected()} className="min-h-10 rounded border border-red-300 bg-white px-3 font-semibold text-red-700 disabled:opacity-40">Delete</button>
      <button type="button" disabled={!drafts.length||busy} onClick={()=>void save()} className="min-h-10 rounded bg-emerald-700 px-4 font-bold text-white disabled:opacity-40">{busy?"Saving…":"Save markup"}</button>
    </div>}
    <div className="relative mt-3 overflow-hidden rounded-lg border border-slate-300 bg-white" style={{ aspectRatio: `${drawing.width}/${drawing.height}` }}>
      <Image src={drawing.src} alt={drawing.alt} fill sizes="(max-width: 1024px) 100vw, 900px" className="object-contain" priority/>
      <svg className={`absolute inset-0 h-full w-full ${canMutate?"cursor-crosshair":""}`} viewBox="0 0 100 100" preserveAspectRatio="none" aria-label="Saved and draft Work Order annotations" onPointerDown={begin} onPointerMove={move} onPointerUp={finish}>
        <defs><marker id="markup-arrow" markerWidth="5" markerHeight="5" refX="4" refY="2.5" orient="auto"><path d="M0,0 L5,2.5 L0,5 z" fill="#dc2626"/></marker></defs>
        {assetMarker&&<g aria-label={assetMarker.label} data-asset-marker={assetMarker.label} data-drawing-x={assetMarker.x} data-drawing-y={assetMarker.y}><title>{assetMarker.label}</title><circle cx={assetMarker.x} cy={assetMarker.y} r="1.35" fill="#facc15" stroke="#111827" strokeWidth="0.35"/><path d={`M ${assetMarker.x+1} ${assetMarker.y-1} L ${assetMarker.x+2.2} ${assetMarker.y-2.3}`} stroke="#111827" strokeWidth="0.3" vectorEffect="non-scaling-stroke"/><rect x={assetMarker.x+2} y={assetMarker.y-5.1} width="11" height="4" rx="0.7" fill="white" fillOpacity="0.94" stroke="#111827" strokeWidth="0.25"/><text x={assetMarker.x+3} y={assetMarker.y-2.35} fill="#111827" fontSize="2" fontWeight="800">{assetMarker.label.split(/\s/)[0]}</text></g>}
        {annotations.map((annotation)=><g key={annotation.id} onPointerDown={(event)=>{event.stopPropagation();setSelectedId(annotation.id);}} className="cursor-pointer">{annotationShape(annotation,annotation.id===selectedId)}</g>)}
      </svg>
    </div>
    {!canMutate&&<p className="mt-3 rounded-lg bg-slate-50 p-3 text-sm text-slate-600">Markup is read-only for this Work Order state or assignment.</p>}
    {message&&<p className="mt-3 text-sm font-semibold text-blue-800" role="status">{message}</p>}
    {saved.length>0&&<ul className="mt-3 grid gap-2 sm:grid-cols-2">{saved.map((item)=><li key={item.id} className={`rounded border p-3 text-sm ${selectedId===item.id?"border-blue-600 bg-blue-50":"bg-white"}`}><button type="button" className="w-full text-left" onClick={()=>setSelectedId(item.id)}><strong>{item.annotation_type} · {item.note}</strong><span className="mt-1 block text-xs text-slate-500">Revision {drawing.revision} · {item.created_at?new Intl.DateTimeFormat("en-SG",{dateStyle:"medium",timeStyle:"short"}).format(new Date(item.created_at)):"Saved"}</span></button></li>)}</ul>}
  </section>;
}

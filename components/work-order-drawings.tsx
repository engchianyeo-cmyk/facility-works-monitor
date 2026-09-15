"use client";

import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams } from "next/navigation";
import ImageLightbox from "@/components/image-lightbox";
import { WORK_ORDER_DRAWINGS, WorkOrderDrawing } from "@/lib/work-order-drawings";

type FacilityArea = { area_code: string; name: string; level: string | null; drawing_reference: string | null; map_x: number | string | null; map_y: number | string | null };
type LocationContext = { site: string | null; location: string | null; facility_area: FacilityArea | null; asset: { asset_tag: string; name: string } | null };

function calibratedCoordinate(value: number | string | null | undefined) {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
}

function configuredDrawing(context: LocationContext | null) {
  const reference = context?.facility_area?.drawing_reference?.trim().toUpperCase();
  return reference ? WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === reference) ?? null : null;
}

export default function WorkOrderDrawings() {
  const params = useParams<{ id?: string }>();
  const workOrderId = typeof params?.id === "string" ? params.id : null;
  const [selectedDrawing, setSelectedDrawing] = useState<WorkOrderDrawing | null>(null);
  const [locationContext, setLocationContext] = useState<LocationContext | null>(null);
  const [contextState, setContextState] = useState<"idle" | "loading" | "ready" | "unavailable">("idle");
  const openingButtonRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (!workOrderId) return;
    const controller = new AbortController();
    setContextState("loading");
    fetch(`/api/work-orders/${encodeURIComponent(workOrderId)}`, { cache: "no-store", signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error("location context unavailable");
        return response.json() as Promise<{ data?: LocationContext }>;
      })
      .then((payload) => {
        if (!payload.data) throw new Error("location context missing");
        setLocationContext(payload.data);
        setContextState("ready");
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setLocationContext(null);
        setContextState("unavailable");
      });
    return () => controller.abort();
  }, [workOrderId]);

  const locationDrawing = useMemo(() => configuredDrawing(locationContext), [locationContext]);
  const mapX = calibratedCoordinate(locationContext?.facility_area?.map_x);
  const mapY = calibratedCoordinate(locationContext?.facility_area?.map_y);
  const marker = locationDrawing && mapX !== null && mapY !== null && locationContext?.facility_area ? {
    x: mapX,
    y: mapY,
    label: locationContext.asset
      ? `${locationContext.asset.asset_tag} · ${locationContext.facility_area.area_code} ${locationContext.facility_area.name}`
      : `${locationContext.facility_area.area_code} · ${locationContext.facility_area.name}`,
  } : undefined;

  const closeDrawing = useCallback(() => {
    setSelectedDrawing(null);
    window.requestAnimationFrame(() => openingButtonRef.current?.focus());
  }, []);
  const openDrawing = (drawing: WorkOrderDrawing, button: HTMLButtonElement) => {
    openingButtonRef.current = button;
    setSelectedDrawing(drawing);
  };

  return (
    <section aria-labelledby="work-location-heading" className="border-t border-neutral-200 pt-6">
      <h2 id="work-location-heading" className="text-lg font-semibold text-neutral-900">Work Location</h2>
      <p className="mt-1 text-sm text-neutral-500">Use the governed facility location and saved plan marker for this Work Order.</p>

      {contextState === "loading" && <p className="mt-4 text-sm text-neutral-500">Loading work location…</p>}

      {contextState === "ready" && locationContext && (
        <div className="mt-4 rounded-xl border-2 border-blue-300 bg-blue-50 p-4">
          <p className="text-base font-black text-slate-950">{locationContext.facility_area?.name ?? locationContext.location ?? "Location not recorded"}</p>
          <dl className="mt-3 grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2 lg:grid-cols-4">
            <div><dt className="text-slate-500">Building / Block</dt><dd className="font-semibold">{locationContext.site ?? "—"}</dd></div>
            <div><dt className="text-slate-500">Level / Area</dt><dd className="font-semibold">{[locationContext.facility_area?.level, locationContext.facility_area?.area_code].filter(Boolean).join(" · ") || "—"}</dd></div>
            <div><dt className="text-slate-500">Asset</dt><dd className="font-semibold">{locationContext.asset ? `${locationContext.asset.asset_tag} · ${locationContext.asset.name}` : "—"}</dd></div>
            <div><dt className="text-slate-500">Drawing</dt><dd className="font-semibold">{locationContext.facility_area?.drawing_reference ?? "—"}</dd></div>
          </dl>

          {locationDrawing && (
            <div className="mt-4 overflow-hidden rounded-xl border border-blue-200 bg-white">
              <div className="relative aspect-[3/2] w-full overflow-hidden bg-neutral-100">
                <Image src={locationDrawing.src} alt={locationDrawing.alt} fill sizes="(max-width: 768px) 100vw, 720px" className="object-contain" />
              </div>
              <div className="flex flex-wrap items-center justify-between gap-3 p-4">
                <div><p className="text-xs font-bold text-blue-700">{locationDrawing.code}</p><p className="font-semibold">{locationDrawing.title}</p></div>
                <button type="button" onClick={(event) => openDrawing(locationDrawing, event.currentTarget)} className="rounded-lg bg-blue-700 px-4 py-2 text-sm font-bold text-white">View Work Location</button>
              </div>
            </div>
          )}

          {!locationDrawing && <p className="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm font-medium text-amber-900">Work cannot rely on a plan location until an authorised Facility Manager or Administrator links the correct drawing.</p>}
          {locationDrawing && !marker && <p className="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm font-medium text-amber-900">Drawing linked; precise work marker still requires authorised configuration.</p>}
          {marker && <p className="mt-3 text-sm font-semibold text-blue-900">Saved marker ready: {marker.label}.</p>}
        </div>
      )}

      {contextState === "unavailable" && <p className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm font-medium text-amber-900">Work location could not be loaded. Retry before field execution.</p>}

      <details className="mt-5 rounded-xl border border-neutral-200 bg-white p-4">
        <summary className="cursor-pointer font-semibold text-neutral-800">Reference drawing library</summary>
        <p className="mt-2 text-sm text-neutral-500">Reference only. These drawings do not replace the governed Work Location above.</p>
        <ul className="mt-4 grid gap-4 sm:grid-cols-2">
          {WORK_ORDER_DRAWINGS.filter((drawing) => drawing.code !== locationDrawing?.code).map((drawing) => (
            <li key={drawing.code} className="rounded-lg border border-neutral-200 p-3">
              <p className="text-xs font-semibold text-blue-700">{drawing.code}</p>
              <p className="mt-1 text-sm font-medium">{drawing.title}</p>
              <button type="button" onClick={(event) => openDrawing(drawing, event.currentTarget)} className="mt-2 text-sm font-semibold text-blue-700 underline">Open reference drawing</button>
            </li>
          ))}
        </ul>
      </details>

      {selectedDrawing && <ImageLightbox src={selectedDrawing.src} alt={selectedDrawing.alt} code={selectedDrawing.code} title={selectedDrawing.title} crop={{ x: 0, y: 0, width: selectedDrawing.width, height: selectedDrawing.height, sourceWidth: selectedDrawing.width, sourceHeight: selectedDrawing.height }} marker={selectedDrawing.code === locationDrawing?.code ? marker : undefined} open onClose={closeDrawing} />}
    </section>
  );
}

"use client";

import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams } from "next/navigation";
import ImageLightbox from "@/components/image-lightbox";
import {
  WORK_ORDER_DRAWINGS,
  WorkOrderDrawing,
} from "@/lib/work-order-drawings";

type FacilityArea = {
  area_code: string;
  name: string;
  floor_level: string | null;
  drawing_reference: string | null;
  map_x: number | string | null;
  map_y: number | string | null;
};

type LocationContext = {
  site: string | null;
  location: string | null;
  facility_area: FacilityArea | null;
  asset: { asset_tag: string; name: string } | null;
};

function calibratedCoordinate(value: number | string | null | undefined) {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
}

function fallbackDrawing(context: LocationContext | null) {
  if (!context) return null;
  const reference = context.facility_area?.drawing_reference?.trim().toUpperCase();
  if (reference) {
    const exact = WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === reference);
    if (exact) return exact;
  }

  const location = `${context.facility_area?.floor_level ?? ""} ${context.location ?? ""}`.toLowerCase();
  if (/\b(level|floor)\s*2\b|2nd|second|pantry/.test(location)) {
    return WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-002") ?? null;
  }
  if (/roof/.test(location)) {
    return WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-003") ?? null;
  }
  return WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-001") ?? null;
}

export default function WorkOrderDrawings() {
  const params = useParams<{ id?: string }>();
  const workOrderId = typeof params?.id === "string" ? params.id : null;
  const [selectedDrawing, setSelectedDrawing] =
    useState<WorkOrderDrawing | null>(null);
  const [locationContext, setLocationContext] = useState<LocationContext | null>(null);
  const [contextState, setContextState] = useState<"idle" | "loading" | "ready" | "unavailable">("idle");
  const openingButtonRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (!workOrderId) return;
    const controller = new AbortController();
    setContextState("loading");

    fetch(`/api/work-orders/${encodeURIComponent(workOrderId)}`, {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        if (!response.ok) throw new Error("location context unavailable");
        return response.json() as Promise<{ ok?: boolean; data?: LocationContext }>;
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

  const locationDrawing = useMemo(() => fallbackDrawing(locationContext), [locationContext]);
  const mapX = calibratedCoordinate(locationContext?.facility_area?.map_x);
  const mapY = calibratedCoordinate(locationContext?.facility_area?.map_y);
  const marker = mapX !== null && mapY !== null && locationContext?.facility_area
    ? {
        x: mapX,
        y: mapY,
        label: `${locationContext.facility_area.area_code} · ${locationContext.facility_area.name}`,
      }
    : undefined;

  const closeDrawing = useCallback(() => {
    setSelectedDrawing(null);
    window.requestAnimationFrame(() => openingButtonRef.current?.focus());
  }, []);

  const openDrawing = (drawing: WorkOrderDrawing, button: HTMLButtonElement) => {
    openingButtonRef.current = button;
    setSelectedDrawing(drawing);
  };

  return (
    <section
      aria-labelledby="drawings-documents-heading"
      className="border-t border-neutral-200 pt-6"
    >
      <div>
        <h2
          id="drawings-documents-heading"
          className="text-lg font-semibold text-neutral-900"
        >
          Drawings &amp; Documents
        </h2>
        <p className="mt-1 text-sm font-medium text-neutral-700">
          Facility Drawings
        </p>
        <p className="mt-1 text-sm text-neutral-500">
          Facility reference drawings with Work Order location focus where spatial data is available.
        </p>
      </div>

      {contextState === "ready" && locationContext && (
        <div className="mt-4 rounded-xl border border-blue-200 bg-blue-50 p-4">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-xs font-black uppercase tracking-widest text-blue-700">Work Order Location</p>
              <p className="mt-1 text-base font-bold text-slate-950">
                {locationContext.facility_area?.name ?? locationContext.location ?? "Location not recorded"}
              </p>
              <dl className="mt-3 grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2 lg:grid-cols-4">
                <div><dt className="text-slate-500">Location</dt><dd className="font-semibold text-slate-900">{locationContext.location ?? "—"}</dd></div>
                <div><dt className="text-slate-500">Area Code</dt><dd className="font-semibold text-slate-900">{locationContext.facility_area?.area_code ?? "—"}</dd></div>
                <div><dt className="text-slate-500">Floor Level</dt><dd className="font-semibold text-slate-900">{locationContext.facility_area?.floor_level ?? "—"}</dd></div>
                <div><dt className="text-slate-500">Asset / Equipment</dt><dd className="font-semibold text-slate-900">{locationContext.asset?.asset_tag ?? "—"}</dd></div>
              </dl>
            </div>
            {locationDrawing && (
              <button
                type="button"
                onClick={(event) => openDrawing(locationDrawing, event.currentTarget)}
                className="rounded-lg bg-blue-700 px-4 py-2 text-sm font-bold text-white shadow-sm hover:bg-blue-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-700 focus-visible:ring-offset-2"
              >
                View on Layout
              </button>
            )}
          </div>
          {locationContext.facility_area && !marker && (
            <p className="mt-3 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900">
              The correct drawing and facility area are linked. Exact plan-marker coordinates have not yet been calibrated for this area.
            </p>
          )}
          {marker && (
            <p className="mt-3 text-xs font-semibold text-blue-800">
              The layout will highlight {marker.label} at its calibrated plan position.
            </p>
          )}
        </div>
      )}

      {contextState === "unavailable" && (
        <p className="mt-4 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900">
          Work Order spatial context could not be loaded. The shared drawings remain available below.
        </p>
      )}

      <ul className="mt-4 grid gap-4 sm:grid-cols-2">
        {WORK_ORDER_DRAWINGS.map((drawing) => {
          const isLocationDrawing = locationDrawing?.code === drawing.code;
          return (
            <li
              key={drawing.code}
              className={`overflow-hidden rounded-xl border bg-white shadow-sm ${isLocationDrawing ? "border-blue-400 ring-2 ring-blue-100" : "border-neutral-200"}`}
            >
              <div className="relative aspect-[3/2] w-full overflow-hidden bg-neutral-100">
                <Image
                  src={drawing.src}
                  alt={drawing.alt}
                  fill
                  sizes="(max-width: 640px) 100vw, 360px"
                  className="object-contain"
                />
                {isLocationDrawing && (
                  <span className="absolute left-3 top-3 rounded-full bg-blue-700 px-2.5 py-1 text-[11px] font-bold text-white shadow">
                    Work Order location
                  </span>
                )}
              </div>
              <div className="p-4">
                <p className="text-xs font-semibold tracking-widest text-blue-700">
                  {drawing.code}
                </p>
                <h3 className="mt-1 text-sm font-medium text-neutral-900">
                  {drawing.title}
                </h3>
                <button
                  type="button"
                  onClick={(event) => openDrawing(drawing, event.currentTarget)}
                  aria-label={`Open drawing ${drawing.code}: ${drawing.title}`}
                  className="mt-3 rounded-lg border border-blue-200 px-3 py-2 text-sm font-semibold text-blue-700 hover:bg-blue-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-800"
                >
                  {isLocationDrawing ? "View on Layout" : "Open Drawing"}
                </button>
              </div>
            </li>
          );
        })}
      </ul>

      {selectedDrawing && (
        <ImageLightbox
          src={selectedDrawing.src}
          alt={selectedDrawing.alt}
          code={selectedDrawing.code}
          title={selectedDrawing.title}
          crop={{
            x: 0,
            y: 0,
            width: selectedDrawing.width,
            height: selectedDrawing.height,
            sourceWidth: selectedDrawing.width,
            sourceHeight: selectedDrawing.height,
          }}
          marker={selectedDrawing.code === locationDrawing?.code ? marker : undefined}
          open
          onClose={closeDrawing}
        />
      )}
    </section>
  );
}

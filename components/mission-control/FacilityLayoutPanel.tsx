"use client";

import Image from "next/image";
import { useCallback, useRef, useState } from "react";
import ImageLightbox from "@/components/image-lightbox";

export type FacilityLayoutLayer =
  | "systems"
  | "assets"
  | "work_orders"
  | "incidents"
  | "readiness"
  | "utilities"
  | "fire_safety";

export type FacilityLayoutDrawing = {
  id: string;
  label: string;
  alt: string;
  src: string;
  customer?: string;
  site?: string;
  building?: string;
  floorOrZone?: string;
  width: number;
  height: number;
  availableLayers?: FacilityLayoutLayer[];
};

export type FacilityLayoutConfig = {
  contextLabel: string;
  drawings: FacilityLayoutDrawing[];
};

export const sampleFacilityLayoutConfig: FacilityLayoutConfig = {
  contextLabel: "Sample / Development Layout",
  drawings: [
    {
      id: "fw-001",
      label: "Site / 1st Storey / Utility",
      alt: "Sample site plot plan, first-storey plan and utility block layout",
      src: "/work-order-drawings/fw-001-amended-20260728.png",
      site: "Development Site",
      floorOrZone: "Site and first storey",
      width: 1066,
      height: 682,
      availableLayers: ["systems", "utilities", "work_orders"],
    },
    {
      id: "fw-002",
      label: "2nd Storey",
      alt: "Sample second-storey facility plan",
      src: "/work-order-drawings/fw-002-amended-20260728.png",
      site: "Development Site",
      floorOrZone: "Second storey",
      width: 1024,
      height: 742,
      availableLayers: ["systems", "assets", "work_orders"],
    },
    {
      id: "fw-003",
      label: "Roof Plan",
      alt: "Sample facility roof plan",
      src: "/work-order-drawings/fw-003-amended-20260728.png",
      site: "Development Site",
      floorOrZone: "Roof",
      width: 1024,
      height: 742,
      availableLayers: ["systems", "utilities"],
    },
    {
      id: "fw-004",
      label: "Elevations",
      alt: "Sample north, south, east and west facility elevations",
      src: "/work-order-drawings/fw-004-amended-20260728.png",
      site: "Development Site",
      floorOrZone: "Building elevations",
      width: 1024,
      height: 742,
      availableLayers: ["systems", "assets"],
    },
    {
      id: "fw-005",
      label: "3D / 1st Storey / Utility",
      alt: "Sample three-dimensional facility, first-storey and utility layout",
      src: "/work-order-drawings/fw-005-amended-20260728.png",
      site: "Development Site",
      floorOrZone: "Site and first storey",
      width: 1024,
      height: 682,
      availableLayers: ["systems", "assets", "utilities"],
    },
  ],
};

const STATUS_LEGEND = [
  { label: "Healthy / Operational", color: "bg-emerald-500" },
  { label: "Active Work", color: "bg-blue-500" },
  { label: "Attention", color: "bg-amber-500" },
  { label: "Dependency / Waiting", color: "bg-orange-500" },
  { label: "Incident / Critical", color: "bg-red-500" },
  { label: "Approved Concession", color: "bg-purple-500" },
] as const;

const LAYER_LABELS: Record<FacilityLayoutLayer, string> = {
  systems: "Systems",
  assets: "Assets",
  work_orders: "Work Orders",
  incidents: "Incidents",
  readiness: "Readiness",
  utilities: "Utilities",
  fire_safety: "Fire Safety",
};

export default function FacilityLayoutPanel({
  config,
}: {
  config: FacilityLayoutConfig;
}) {
  const [selectedId, setSelectedId] = useState(config.drawings[0]?.id ?? "");
  const [isOpen, setIsOpen] = useState(false);
  const openingButtonRef = useRef<HTMLButtonElement>(null);
  const selected =
    config.drawings.find((drawing) => drawing.id === selectedId) ??
    config.drawings[0];

  const closeLayout = useCallback(() => {
    setIsOpen(false);
    window.requestAnimationFrame(() => openingButtonRef.current?.focus());
  }, []);

  if (!selected) return null;

  return (
    <section
      aria-labelledby="facility-overview-heading"
      className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-black uppercase tracking-[.18em] text-blue-700">
            Spatial view
          </p>
          <h2
            id="facility-overview-heading"
            className="text-xl font-black tracking-tight text-slate-950"
          >
            Facility Overview
          </h2>
          <p className="mt-1 text-sm text-slate-600">
            Spatial view of the facility, systems and operational activity.
          </p>
        </div>
        <span className="rounded-full border border-amber-300 bg-amber-50 px-3 py-1 text-xs font-bold text-amber-900">
          {config.contextLabel}
        </span>
      </div>

      <div className="mt-5 grid gap-5 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <div className="min-w-0">
          <label
            htmlFor="facility-drawing-select"
            className="mb-2 block text-xs font-bold text-slate-700 sm:hidden"
          >
            Layout
          </label>
          <select
            id="facility-drawing-select"
            value={selected.id}
            onChange={(event) => setSelectedId(event.target.value)}
            className="mb-3 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-semibold text-slate-900 sm:hidden"
          >
            {config.drawings.map((drawing) => (
              <option key={drawing.id} value={drawing.id}>
                {drawing.label}
              </option>
            ))}
          </select>

          <div
            className="mb-3 hidden flex-wrap gap-2 sm:flex"
            role="group"
            aria-label="Select facility drawing"
          >
            {config.drawings.map((drawing) => {
              const active = drawing.id === selected.id;
              return (
                <button
                  key={drawing.id}
                  type="button"
                  aria-pressed={active}
                  onClick={() => setSelectedId(drawing.id)}
                  className={`rounded-lg border px-3 py-2 text-xs font-bold transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-700 focus-visible:ring-offset-2 ${
                    active
                      ? "border-slate-950 bg-slate-950 text-white"
                      : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50"
                  }`}
                >
                  {drawing.label}
                </button>
              );
            })}
          </div>

          <button
            ref={openingButtonRef}
            type="button"
            onClick={() => setIsOpen(true)}
            aria-label={`Open facility view: ${selected.label}`}
            className="group relative block h-48 w-full overflow-hidden rounded-xl border border-slate-200 bg-slate-100 text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-700 focus-visible:ring-offset-2 sm:h-auto sm:aspect-[16/9]"
          >
            <Image
              src={selected.src}
              alt={selected.alt}
              fill
              sizes="(max-width: 640px) 100vw, (max-width: 1280px) 85vw, 1050px"
              className="object-contain transition-transform duration-300 group-hover:scale-[1.01]"
            />
            <span className="absolute inset-x-3 bottom-3 flex items-center justify-between gap-3 rounded-lg bg-slate-950/85 px-3 py-2 text-xs font-bold text-white backdrop-blur-sm sm:left-auto sm:w-auto">
              <span className="sm:hidden">Open Facility View</span>
              <span className="hidden sm:inline">Open full facility view</span>
              <span aria-hidden="true">↗</span>
            </span>
          </button>
        </div>

        <aside className="space-y-5 rounded-xl bg-slate-50 p-4">
          <div>
            <h3 className="text-sm font-black text-slate-950">Layout context</h3>
            <dl className="mt-2 space-y-2 text-xs">
              {selected.customer && (
                <div className="flex justify-between gap-3">
                  <dt className="text-slate-500">Customer</dt>
                  <dd className="font-bold text-slate-800">{selected.customer}</dd>
                </div>
              )}
              {selected.site && (
                <div className="flex justify-between gap-3">
                  <dt className="text-slate-500">Site</dt>
                  <dd className="font-bold text-slate-800">{selected.site}</dd>
                </div>
              )}
              {selected.building && (
                <div className="flex justify-between gap-3">
                  <dt className="text-slate-500">Building</dt>
                  <dd className="font-bold text-slate-800">{selected.building}</dd>
                </div>
              )}
              {selected.floorOrZone && (
                <div className="flex justify-between gap-3">
                  <dt className="text-slate-500">Floor / Zone</dt>
                  <dd className="text-right font-bold text-slate-800">
                    {selected.floorOrZone}
                  </dd>
                </div>
              )}
            </dl>
          </div>

          <div>
            <h3 className="text-sm font-black text-slate-950">Overlay status key</h3>
            <ul className="mt-2 grid gap-2 text-xs text-slate-700">
              {STATUS_LEGEND.map((item) => (
                <li key={item.label} className="flex items-center gap-2">
                  <span
                    aria-hidden="true"
                    className={`h-2.5 w-2.5 shrink-0 rounded-full ${item.color}`}
                  />
                  {item.label}
                </li>
              ))}
            </ul>
          </div>

          <div>
            <h3 className="text-sm font-black text-slate-950">Available layers</h3>
            <div className="mt-2 flex flex-wrap gap-1.5">
              {(selected.availableLayers ?? []).map((layer) => (
                <span
                  key={layer}
                  className="rounded-md border border-slate-200 bg-white px-2 py-1 text-[11px] font-bold text-slate-600"
                >
                  {LAYER_LABELS[layer]}
                </span>
              ))}
            </div>
            <p className="mt-2 text-[11px] leading-4 text-slate-500">
              Spatial layers available for this drawing.
            </p>
          </div>
        </aside>
      </div>

      <ImageLightbox
        src={selected.src}
        alt={selected.alt}
        title={selected.label}
        code={config.contextLabel}
        open={isOpen}
        onClose={closeLayout}
      />
    </section>
  );
}

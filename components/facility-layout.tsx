"use client";

import Image from "next/image";
import { useCallback, useRef, useState } from "react";
import ImageLightbox from "@/components/image-lightbox";

const DRAWINGS = [
  {
    label: "FW-001 Site Plan / 1st Storey",
    alt: "FW-001 site plot plan and first storey layout of the one building, to scale",
    src: "/work-order-drawings/FW-001-rev-b.png",
    crop: {
      x: 0,
      y: 0,
      width: 2048,
      height: 1484,
      sourceWidth: 2048,
      sourceHeight: 1484,
    },
  },
  {
    label: "FW-002 2nd Storey",
    alt: "FW-002 second storey plan",
    src: "/work-order-drawings/fw-002-amended-20260728.png",
    crop: {
      x: 0,
      y: 0,
      width: 1024,
      height: 742,
      sourceWidth: 1024,
      sourceHeight: 742,
    },
  },
  {
    label: "FW-003 Roof Plan",
    alt: "FW-003 roof plan",
    src: "/work-order-drawings/fw-003-amended-20260728.png",
    crop: {
      x: 0,
      y: 0,
      width: 1024,
      height: 742,
      sourceWidth: 1024,
      sourceHeight: 742,
    },
  },
  {
    label: "FW-004 Elevations",
    alt: "FW-004 north, south, east and west elevations of the one building, to scale",
    src: "/work-order-drawings/FW-004-rev-b.png",
    crop: {
      x: 0,
      y: 0,
      width: 2048,
      height: 1484,
      sourceWidth: 2048,
      sourceHeight: 1484,
    },
  },
  {
    label: "FW-005 3D / Utility Block",
    alt: "FW-005 three-dimensional perspective of the one building and the utility block layout plan",
    src: "/work-order-drawings/FW-005-rev-b.png",
    crop: {
      x: 0,
      y: 0,
      width: 2048,
      height: 1484,
      sourceWidth: 2048,
      sourceHeight: 1484,
    },
  },
  {
    label: "FW-008 Rendered Site Plan",
    alt: "FW-008 rendered site plan of the one building, car park canopy and site, to scale",
    src: "/work-order-drawings/FW-008-rendered-site-plan.jpg",
    crop: {
      x: 0,
      y: 0,
      width: 2800,
      height: 1980,
      sourceWidth: 2800,
      sourceHeight: 1980,
    },
  },
  {
    label: "FW-007 Solar PV Canopy Access",
    alt: "FW-007 car park solar PV canopy: walkways, guardrails, access stair, robot docks and section",
    src: "/work-order-drawings/FW-007.png",
    crop: {
      x: 0,
      y: 0,
      width: 2048,
      height: 1484,
      sourceWidth: 2048,
      sourceHeight: 1484,
    },
  },
  {
    label: "FW-006 Central Plant Block",
    alt: "FW-006 central plant block layout and roof plan: AHU Room, Chiller Plant Room and cooling towers",
    src: "/work-order-drawings/FW-006.png",
    crop: {
      x: 0,
      y: 0,
      width: 2048,
      height: 1484,
      sourceWidth: 2048,
      sourceHeight: 1484,
    },
  },
] as const;

export default function FacilityLayout() {
  const [isOpen, setIsOpen] = useState(false);
  const [selectedDrawing, setSelectedDrawing] = useState(0);
  const openingButtonRef = useRef<HTMLButtonElement>(null);
  const drawing = DRAWINGS[selectedDrawing];
  const crop = drawing.crop;

  const closeLayout = useCallback(() => {
    setIsOpen(false);
    window.requestAnimationFrame(() => openingButtonRef.current?.focus());
  }, []);

  return (
    <section
      aria-labelledby="facility-layout-heading"
      className="border-t border-slate-200 pt-8"
    >
      <div>
        <h2
          id="facility-layout-heading"
          className="text-2xl font-bold tracking-tight text-slate-900"
        >
          Facility Layout
        </h2>
        <p className="mt-1 text-sm text-slate-500">
          Facility overview and work-order location reference.
        </p>
      </div>

      <div className="mt-4 rounded-xl border border-slate-200 bg-white p-3 shadow-sm sm:p-5">
        <div
          className="mb-4 flex flex-wrap gap-2"
          role="group"
          aria-label="Select facility drawing"
        >
          {DRAWINGS.map((item, index) => {
            const isSelected = selectedDrawing === index;

            return (
              <button
                key={item.label}
                type="button"
                aria-pressed={isSelected}
                onClick={() => setSelectedDrawing(index)}
                className={`rounded-md border px-3 py-1.5 text-xs font-semibold transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-800 focus-visible:ring-offset-2 ${
                  isSelected
                    ? "border-purple-800 bg-purple-800 text-white"
                    : "border-slate-300 bg-white text-slate-700 hover:border-slate-400 hover:bg-slate-50"
                }`}
              >
                {item.label}
              </button>
            );
          })}
        </div>

        <button
          ref={openingButtonRef}
          type="button"
          onClick={() => setIsOpen(true)}
          aria-label={`Enlarge ${drawing.label}`}
          className="group relative mx-auto block w-full max-w-[1536px] cursor-zoom-in overflow-hidden rounded-lg bg-slate-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-800 focus-visible:ring-offset-2"
          style={{ aspectRatio: `${crop.width} / ${crop.height}` }}
        >
          <Image
            src={drawing.src}
            alt={drawing.alt}
            width={crop.sourceWidth}
            height={crop.sourceHeight}
            sizes="(max-width: 1024px) 100vw, 960px"
            className="absolute max-w-none"
            style={{
              width: `${(crop.sourceWidth / crop.width) * 100}%`,
              height: `${(crop.sourceHeight / crop.height) * 100}%`,
              left: `${-(crop.x / crop.width) * 100}%`,
              top: `${-(crop.y / crop.height) * 100}%`,
            }}
          />
          <span className="absolute bottom-3 right-3 rounded-md bg-slate-950/75 px-3 py-1.5 text-xs font-medium text-white">
            Enlarge
          </span>
          <span
            aria-hidden="true"
            data-room-overlay-layer
            className="pointer-events-none absolute inset-0"
          />
        </button>
      </div>

      <ImageLightbox
        src={drawing.src}
        alt={drawing.alt}
        title={drawing.label}
        crop={crop}
        open={isOpen}
        onClose={closeLayout}
      />
    </section>
  );
}

"use client";

import Image from "next/image";
import { useEffect, useState } from "react";

const IMAGE_ALT =
  "Building A facility layout showing the site, floor plans, roof plans and elevations";

export default function FacilityLayout() {
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    if (!isOpen) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setIsOpen(false);
    };
    window.addEventListener("keydown", closeOnEscape);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", closeOnEscape);
    };
  }, [isOpen]);

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

      <div className="mt-4 overflow-hidden rounded-xl border border-slate-200 bg-white p-3 shadow-sm sm:p-5">
        <button
          type="button"
          onClick={() => setIsOpen(true)}
          aria-label="Enlarge facility layout"
          className="group relative mx-auto block aspect-[3/2] w-full max-w-[1536px] cursor-zoom-in overflow-hidden rounded-lg focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-800 focus-visible:ring-offset-2"
        >
          <Image
            src="/facility-floor-plan.png"
            alt={IMAGE_ALT}
            fill
            sizes="(max-width: 1024px) 100vw, 960px"
            className="object-contain"
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

      {isOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Enlarged facility layout"
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/90 p-2 sm:p-6"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setIsOpen(false);
          }}
        >
          <div className="relative h-full w-full">
            <Image
              src="/facility-floor-plan.png"
              alt={IMAGE_ALT}
              fill
              sizes="100vw"
              className="object-contain"
              priority
            />
            <span
              aria-hidden="true"
              data-room-overlay-layer
              className="pointer-events-none absolute inset-0"
            />
          </div>
          <button
            type="button"
            onClick={() => setIsOpen(false)}
            autoFocus
            aria-label="Close enlarged facility layout"
            className="absolute right-3 top-3 rounded-full bg-white px-3 py-2 text-lg font-bold leading-none text-slate-900 shadow-lg hover:bg-slate-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-400 sm:right-6 sm:top-6"
          >
            ×
          </button>
        </div>
      )}
    </section>
  );
}

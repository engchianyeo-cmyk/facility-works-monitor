"use client";

import Image from "next/image";
import { useCallback, useRef, useState } from "react";
import ImageLightbox from "@/components/image-lightbox";

const IMAGE_SRC = "/facility-floor-plan.png";
const IMAGE_ALT =
  "Building A facility layout showing the site, floor plans, roof plans and elevations";

export default function FacilityLayout() {
  const [isOpen, setIsOpen] = useState(false);
  const openingButtonRef = useRef<HTMLButtonElement>(null);

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

      <div className="mt-4 overflow-hidden rounded-xl border border-slate-200 bg-white p-3 shadow-sm sm:p-5">
        <button
          ref={openingButtonRef}
          type="button"
          onClick={() => setIsOpen(true)}
          aria-label="Enlarge facility layout"
          className="group relative mx-auto block aspect-[3/2] w-full max-w-[1536px] cursor-zoom-in overflow-hidden rounded-lg focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-800 focus-visible:ring-offset-2"
        >
          <Image
            src={IMAGE_SRC}
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

      <ImageLightbox
        src={IMAGE_SRC}
        alt={IMAGE_ALT}
        title="Facility Layout"
        open={isOpen}
        onClose={closeLayout}
      />
    </section>
  );
}

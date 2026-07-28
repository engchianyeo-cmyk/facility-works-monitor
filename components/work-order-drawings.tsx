"use client";

import Image from "next/image";
import { useCallback, useRef, useState } from "react";
import ImageLightbox from "@/components/image-lightbox";
import {
  WORK_ORDER_DRAWINGS,
  WorkOrderDrawing,
} from "@/lib/work-order-drawings";

export default function WorkOrderDrawings() {
  const [selectedDrawing, setSelectedDrawing] =
    useState<WorkOrderDrawing | null>(null);
  const openingButtonRef = useRef<HTMLButtonElement | null>(null);

  const closeDrawing = useCallback(() => {
    setSelectedDrawing(null);
    window.requestAnimationFrame(() => openingButtonRef.current?.focus());
  }, []);

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
          Shared facility reference drawings available to every work order.
        </p>
      </div>

      <ul className="mt-4 grid gap-4 sm:grid-cols-2">
        {WORK_ORDER_DRAWINGS.map((drawing) => (
          <li
            key={drawing.code}
            className="overflow-hidden rounded-xl border border-neutral-200 bg-white shadow-sm"
          >
            <div className="relative aspect-[3/2] w-full overflow-hidden bg-neutral-100">
              <Image
                src={drawing.src}
                alt={drawing.alt}
                fill
                sizes="(max-width: 640px) 100vw, 360px"
                className="object-contain"
              />
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
                onClick={(event) => {
                  openingButtonRef.current = event.currentTarget;
                  setSelectedDrawing(drawing);
                }}
                aria-label={`Open drawing ${drawing.code}: ${drawing.title}`}
                className="mt-3 rounded-lg border border-blue-200 px-3 py-2 text-sm font-semibold text-blue-700 hover:bg-blue-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-800"
              >
                Open Drawing
              </button>
            </div>
          </li>
        ))}
      </ul>

      {selectedDrawing && (
        <ImageLightbox
          src={selectedDrawing.src}
          alt={selectedDrawing.alt}
          code={selectedDrawing.code}
          title={selectedDrawing.title}
          open
          onClose={closeDrawing}
        />
      )}
    </section>
  );
}

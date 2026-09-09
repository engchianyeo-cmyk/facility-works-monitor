"use client";

import Image from "next/image";
import { useEffect, useId } from "react";

type ImageLightboxProps = {
  src: string;
  alt: string;
  title: string;
  code?: string;
  crop?: {
    x: number;
    y: number;
    width: number;
    height: number;
    sourceWidth: number;
    sourceHeight: number;
  };
  marker?: {
    x: number;
    y: number;
    label: string;
  };
  open: boolean;
  onClose: () => void;
};

export default function ImageLightbox({
  src,
  alt,
  title,
  code,
  crop,
  marker,
  open,
  onClose,
}: ImageLightboxProps) {
  const titleId = useId();

  useEffect(() => {
    if (!open) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", closeOnEscape);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", closeOnEscape);
    };
  }, [onClose, open]);

  if (!open) return null;

  const accessibleTitle = code ? `${code}: ${title}` : title;
  const markerPosition = crop && marker
    ? {
        left: `${(((marker.x / 100) * crop.sourceWidth - crop.x) / crop.width) * 100}%`,
        top: `${(((marker.y / 100) * crop.sourceHeight - crop.y) / crop.height) * 100}%`,
      }
    : null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex flex-col bg-slate-950/95 p-2 sm:p-5"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        className="flex shrink-0 items-start justify-between gap-4 px-1 pb-2 text-white"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="min-w-0">
          {code && (
            <p className="text-xs font-semibold tracking-widest text-blue-300">
              {code}
            </p>
          )}
          <h2
            id={titleId}
            className="break-words text-sm font-semibold sm:text-base"
          >
            {title}
          </h2>
          {marker && (
            <p className="mt-1 text-xs font-semibold text-amber-200">
              Location focus: {marker.label}
            </p>
          )}
        </div>
        <button
          type="button"
          onClick={onClose}
          autoFocus
          aria-label={`Close ${accessibleTitle}`}
          className="shrink-0 rounded-lg bg-white px-3 py-2 text-sm font-semibold text-slate-900 shadow-lg hover:bg-slate-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-400"
        >
          Close
        </button>
      </div>

      <div
        className="flex min-h-0 flex-1 items-center justify-center overflow-hidden"
        onMouseDown={(event) => event.stopPropagation()}
      >
        {crop ? (
          <div
            className="relative max-h-full max-w-full overflow-hidden"
            style={{
              aspectRatio: `${crop.width} / ${crop.height}`,
              width: `min(100%, calc((100vh - 5rem) * ${crop.width / crop.height}))`,
            }}
          >
            <Image
              src={src}
              alt={alt}
              width={crop.sourceWidth}
              height={crop.sourceHeight}
              sizes="100vw"
              className="absolute max-w-none"
              style={{
                width: `${(crop.sourceWidth / crop.width) * 100}%`,
                height: `${(crop.sourceHeight / crop.height) * 100}%`,
                left: `${-(crop.x / crop.width) * 100}%`,
                top: `${-(crop.y / crop.height) * 100}%`,
              }}
              priority
            />
            {markerPosition && (
              <div
                className="pointer-events-none absolute z-10 -translate-x-1/2 -translate-y-1/2"
                style={markerPosition}
                aria-label={`Highlighted location: ${marker?.label}`}
              >
                <span className="absolute left-1/2 top-1/2 h-10 w-10 -translate-x-1/2 -translate-y-1/2 animate-ping rounded-full border-4 border-red-500 bg-red-400/30" />
                <span className="relative flex h-7 w-7 items-center justify-center rounded-full border-4 border-white bg-red-600 text-xs font-black text-white shadow-xl">
                  !
                </span>
                <span className="absolute left-1/2 top-9 w-max max-w-56 -translate-x-1/2 rounded-md bg-slate-950/90 px-2 py-1 text-center text-xs font-bold text-white shadow-lg">
                  {marker?.label}
                </span>
              </div>
            )}
          </div>
        ) : (
          <div className="relative h-full w-full">
            <Image
              src={src}
              alt={alt}
              fill
              sizes="100vw"
              className="object-contain"
              priority
            />
          </div>
        )}
      </div>
    </div>
  );
}

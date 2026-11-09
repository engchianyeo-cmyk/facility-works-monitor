"use client";

/**
 * D-44 (9 Nov 2026): turn the first page of a PDF drawing into a PNG in the Administrator's browser, so the PDF stays
 * the master copy and Technicians can still pin and mark up Work Orders on it. About 3,500 pixels on the long side
 * keeps room names readable on a phone without making the file too large.
 */
export const PIN_IMAGE_LONG_SIDE = 3500;

export async function pdfFirstPageToPng(file: File, longSide = PIN_IMAGE_LONG_SIDE): Promise<{ blob: Blob; width: number; height: number; pages: number }> {
  // The legacy build carries the polyfills older browsers need (the modern build failed in testing on an older Chromium).
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  pdfjs.GlobalWorkerOptions.workerSrc = new URL("pdfjs-dist/legacy/build/pdf.worker.min.mjs", import.meta.url).toString();
  const task = pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) });
  const pdf = await task.promise;
  try {
    const page = await pdf.getPage(1);
    const base = page.getViewport({ scale: 1 });
    const scale = Math.min(8, longSide / Math.max(base.width, base.height));
    const viewport = page.getViewport({ scale });
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(viewport.width);
    canvas.height = Math.round(viewport.height);
    await page.render({ canvas, viewport, background: "#ffffff" }).promise;
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/png"));
    if (!blob) throw new Error("The PDF page could not be turned into an image.");
    return { blob, width: canvas.width, height: canvas.height, pages: pdf.numPages };
  } finally {
    await task.destroy();
  }
}

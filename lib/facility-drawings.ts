import { WORK_ORDER_DRAWINGS, type WorkOrderDrawing } from "@/lib/work-order-drawings";

/** D-17: a layout drawing uploaded by the Administrator for one facility. */
export type FacilityDrawingRow = {
  id: string;
  facility_id: string;
  code: string;
  title: string;
  revision: string | null;
  original_filename: string;
  content_type: string;
  byte_size: number;
  width: number | null;
  height: number | null;
  uploaded_at: string;
};

export const FACILITY_DRAWING_COLUMNS = "id,facility_id,code,title,revision,original_filename,content_type,byte_size,width,height,uploaded_at";
export const DRAWING_CONTENT_TYPES = ["image/png", "image/jpeg", "image/webp", "application/pdf"] as const;
export const MAX_DRAWING_BYTES = 50 * 1024 * 1024;

export function facilityDrawingSrc(id: string, download = false) {
  return `/api/facility-drawings/${encodeURIComponent(id)}/file${download ? "?download=1" : ""}`;
}

export function isImageDrawing(row: Pick<FacilityDrawingRow, "content_type" | "width" | "height">) {
  return row.content_type !== "application/pdf" && Boolean(row.width) && Boolean(row.height);
}

/** Drawings a Work Order or area pin can be placed on: the facility's own image drawings, or the mock-ups if it has none yet. */
export function markupDrawingsFor(rows: readonly FacilityDrawingRow[]): WorkOrderDrawing[] {
  const own = rows.filter(isImageDrawing).map((row) => ({
    code: row.code,
    title: row.title,
    revision: row.revision ?? "Not stated",
    src: facilityDrawingSrc(row.id),
    alt: `${row.code} ${row.title}`,
    width: Number(row.width),
    height: Number(row.height),
  }));
  return own.length ? own : [...WORK_ORDER_DRAWINGS];
}

/** Uploaded drawings are served through a signed-URL route, so the image optimiser must not fetch them. */
export function unoptimizedDrawing(src: string) {
  return src.startsWith("/api/");
}

export function validDrawingCode(value: unknown): value is string {
  return typeof value === "string" && /^[A-Z0-9][A-Z0-9-]{0,23}$/.test(value.trim().toUpperCase());
}

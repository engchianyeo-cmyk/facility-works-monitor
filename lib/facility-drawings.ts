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
  /** D-44: a PDF's first page as an image, for pins and markup. */
  pin_width?: number | null;
  pin_height?: number | null;
  superseded_at?: string | null;
};

export const FACILITY_DRAWING_COLUMNS = "id,facility_id,code,title,revision,original_filename,content_type,byte_size,width,height,uploaded_at,pin_width,pin_height,superseded_at";
export const DRAWING_CONTENT_TYPES = ["image/png", "image/jpeg", "image/webp", "application/pdf"] as const;
export const MAX_DRAWING_BYTES = 50 * 1024 * 1024;

export function facilityDrawingSrc(id: string, download = false, pin = false) {
  return `/api/facility-drawings/${encodeURIComponent(id)}/file${download ? "?download=1" : pin ? "?pin=1" : ""}`;
}

/** D-44: a PDF drawing that has an image of its first page can take pins too. */
export function hasPinImage(row: Pick<FacilityDrawingRow, "content_type" | "pin_width" | "pin_height">) {
  return row.content_type === "application/pdf" && Boolean(row.pin_width) && Boolean(row.pin_height);
}

export function isImageDrawing(row: Pick<FacilityDrawingRow, "content_type" | "width" | "height">) {
  return row.content_type !== "application/pdf" && Boolean(row.width) && Boolean(row.height);
}

/** Drawings a Work Order or area pin can be placed on: the facility's own image drawings, or the mock-ups if it has none yet. */
/**
 * UAT 18 Nov 2026: the built-in FW-series drawings belong to Facility One (the original UAT facility, code
 * UAT-FAC-001). Another facility with no uploaded drawings shows none, never Facility One's.
 */
export const BUILT_IN_DRAWINGS_FACILITY_CODE = "UAT-FAC-001";
export function usesBuiltInDrawings(facility: { code?: string | null; name?: string | null } | null | undefined): boolean {
  if (!facility) return false;
  return facility.code === BUILT_IN_DRAWINGS_FACILITY_CODE || /^facility one\b/i.test(facility.name ?? "");
}

export function markupDrawingsFor(rows: readonly FacilityDrawingRow[], facility?: { code?: string | null; name?: string | null } | null): WorkOrderDrawing[] {
  const own = rows.filter((row) => isImageDrawing(row) || hasPinImage(row)).map((row) => {
    const pdf = hasPinImage(row);
    return {
      code: row.code,
      title: row.title,
      revision: row.revision ?? "Not stated",
      src: facilityDrawingSrc(row.id, false, pdf),
      alt: `${row.code} ${row.title}`,
      width: Number(pdf ? row.pin_width : row.width),
      height: Number(pdf ? row.pin_height : row.height),
    };
  });
  return own.length ? own : usesBuiltInDrawings(facility) ? [...WORK_ORDER_DRAWINGS] : [];
}

/** Uploaded drawings are served through a signed-URL route, so the image optimiser must not fetch them. */
export function unoptimizedDrawing(src: string) {
  return src.startsWith("/api/");
}

export function validDrawingCode(value: unknown): value is string {
  return typeof value === "string" && /^[A-Z0-9][A-Z0-9-]{0,23}$/.test(value.trim().toUpperCase());
}

import { randomUUID } from "node:crypto";
import { NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { errorResponse, rpcResponse } from "@/lib/work-orders/api";
import { isUuidLike } from "@/lib/work-orders/decision-header";
import { requireAdministrator, safeFilename, text, unavailable } from "@/lib/administration/facility-admin";
import { DRAWING_CONTENT_TYPES, MAX_DRAWING_BYTES, validDrawingCode } from "@/lib/facility-drawings";
import type { RpcResult } from "@/lib/work-orders/types";

/** D-17: upload a layout drawing (image or PDF) for one facility. The file is stored privately and registered in the database. */
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const denied = await requireAdministrator(); if (denied) return denied;
  const { id } = await params;
  if (!isUuidLike(id)) return errorResponse("VALIDATION_ERROR", "Facility not found.", 400);
  const form = await request.formData().catch(() => null);
  const file = form?.get("file");
  const code = text(form?.get("code"), 24)?.toUpperCase() ?? null;
  const title = text(form?.get("title"), 160);
  const revision = typeof form?.get("revision") === "string" ? String(form?.get("revision")).trim().slice(0, 40) : "";
  const width = Number(form?.get("width") ?? 0); const height = Number(form?.get("height") ?? 0);
  if (!(file instanceof File) || !code || !validDrawingCode(code) || !title) {
    return errorResponse("VALIDATION_ERROR", "Choose the file and enter the drawing number and title.", 400);
  }
  // D-47/D-48 (10 Nov 2026): FW-006 to FW-008 join FW-001 to FW-005 as mock-up drawing numbers (the database refuses FW-001 to FW-005).
  if (code === "FW-006" || code === "FW-007" || code === "FW-008") return errorResponse("VALIDATION_ERROR", "FW-001 to FW-008 are the mock-up drawings; choose another drawing number.", 400);
  if (!(DRAWING_CONTENT_TYPES as readonly string[]).includes(file.type)) return errorResponse("VALIDATION_ERROR", "Drawings must be PNG, JPEG, WebP or PDF.", 400);
  if (file.size <= 0 || file.size > MAX_DRAWING_BYTES) return errorResponse("VALIDATION_ERROR", "Drawings must be smaller than 50 MB.", 400);
  const isPdf = file.type === "application/pdf";
  if (!isPdf && !(Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0 && width <= 20000 && height <= 20000)) {
    return errorResponse("VALIDATION_ERROR", "The image size could not be read. Try another file.", 400);
  }
  // D-44 (9 Nov 2026): with a PDF, the browser also sends an image of its first page for pins and markup.
  const pinFile = isPdf ? form?.get("pin_file") : null;
  const pinWidth = Number(form?.get("pin_width") ?? 0); const pinHeight = Number(form?.get("pin_height") ?? 0);
  const withPin = pinFile instanceof File && pinFile.type === "image/png" && pinFile.size > 0 && pinFile.size <= MAX_DRAWING_BYTES
    && Number.isInteger(pinWidth) && Number.isInteger(pinHeight) && pinWidth > 0 && pinHeight > 0 && pinWidth <= 20000 && pinHeight <= 20000;
  const path = `drawings/facility/${id}/${randomUUID()}-${safeFilename(file.name)}`;
  const pinPath = withPin ? `drawings/facility/${id}/${randomUUID()}-pin.png` : null;
  let admin;
  try { admin = createAdminClient(); } catch { return unavailable("The drawing"); }
  const uploaded = await admin.storage.from("field-evidence").upload(path, file, { contentType: file.type, upsert: false });
  if (uploaded.error) return unavailable("The drawing");
  if (pinPath && pinFile instanceof File) {
    const pinUploaded = await admin.storage.from("field-evidence").upload(pinPath, pinFile, { contentType: "image/png", upsert: false });
    if (pinUploaded.error) { await admin.storage.from("field-evidence").remove([path]); return unavailable("The drawing"); }
  }
  const supabase = await createClient();
  const result = await supabase.rpc("admin_register_facility_drawing_revision", {
    p_facility_id: id, p_code: code, p_title: title, p_revision: revision, p_original_filename: file.name.slice(0, 200),
    p_content_type: file.type, p_byte_size: file.size, p_width: isPdf ? null : width, p_height: isPdf ? null : height, p_storage_path: path,
    p_pin_image_path: pinPath, p_pin_width: pinPath ? pinWidth : null, p_pin_height: pinPath ? pinHeight : null,
  });
  const data = result.data as RpcResult | null;
  if (result.error || data?.ok !== true) await admin.storage.from("field-evidence").remove(pinPath ? [path, pinPath] : [path]);
  if (result.error) return unavailable("The drawing");
  return rpcResponse(data, 201);
}

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
  if (!(DRAWING_CONTENT_TYPES as readonly string[]).includes(file.type)) return errorResponse("VALIDATION_ERROR", "Drawings must be PNG, JPEG, WebP or PDF.", 400);
  if (file.size <= 0 || file.size > MAX_DRAWING_BYTES) return errorResponse("VALIDATION_ERROR", "Drawings must be smaller than 50 MB.", 400);
  const isPdf = file.type === "application/pdf";
  if (!isPdf && !(Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0 && width <= 20000 && height <= 20000)) {
    return errorResponse("VALIDATION_ERROR", "The image size could not be read. Try another file.", 400);
  }
  const path = `drawings/facility/${id}/${randomUUID()}-${safeFilename(file.name)}`;
  let admin;
  try { admin = createAdminClient(); } catch { return unavailable("The drawing"); }
  const uploaded = await admin.storage.from("field-evidence").upload(path, file, { contentType: file.type, upsert: false });
  if (uploaded.error) return unavailable("The drawing");
  const supabase = await createClient();
  const result = await supabase.rpc("admin_register_facility_drawing", {
    p_facility_id: id, p_code: code, p_title: title, p_revision: revision, p_original_filename: file.name.slice(0, 200),
    p_content_type: file.type, p_byte_size: file.size, p_width: isPdf ? null : width, p_height: isPdf ? null : height, p_storage_path: path,
  });
  const data = result.data as RpcResult | null;
  if (result.error || data?.ok !== true) await admin.storage.from("field-evidence").remove([path]);
  if (result.error) return unavailable("The drawing");
  return rpcResponse(data, 201);
}

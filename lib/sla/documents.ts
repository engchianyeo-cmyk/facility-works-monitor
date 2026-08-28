import { createHash, randomUUID } from "node:crypto";

export const SLA_DOCUMENT_MAX_BYTES = 10 * 1024 * 1024;
export const SLA_DOCUMENT_TYPES = ["application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "text/plain"] as const;

export function safeDocumentFilename(value: string) {
  const name = value.trim();
  return name.length > 0 && name.length <= 180 && !/[\\/\0\r\n]/.test(name) && !name.startsWith(".");
}

export function validateSlaDocument(file: Pick<File, "name" | "size" | "type">) {
  if (!safeDocumentFilename(file.name)) return "INVALID_FILENAME";
  if (!SLA_DOCUMENT_TYPES.includes(file.type as (typeof SLA_DOCUMENT_TYPES)[number])) return "UNSUPPORTED_DOCUMENT";
  if (file.size < 1) return "EMPTY_DOCUMENT";
  if (file.size > SLA_DOCUMENT_MAX_BYTES) return "DOCUMENT_TOO_LARGE";
  return null;
}

export async function pilotDocumentDescriptor(file: File) {
  const bytes = new Uint8Array(await file.arrayBuffer());
  return {
    original_filename: file.name,
    media_type: file.type,
    byte_size: bytes.byteLength,
    content_sha256: createHash("sha256").update(bytes).digest("hex"),
    storage_key: `pilot-db://${randomUUID()}`,
    extracted_text: file.type === "text/plain" ? new TextDecoder("utf-8", { fatal: false }).decode(bytes) : null,
  };
}

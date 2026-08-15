export const EVIDENCE_CATEGORIES = ["before", "after", "completion", "document", "other"] as const;
export type EvidenceCategory = typeof EVIDENCE_CATEGORIES[number];
export type EvidenceParent = "work_order" | "incident";
export const MAX_EVIDENCE_BYTES = 10 * 1024 * 1024;
export const SIGNED_ACCESS_SECONDS = 300;

export type EvidenceCleanupContext = { evidenceId: string; parentType: EvidenceParent; parentId: string; registrationCode: string };
export async function compensateEvidenceRegistrationFailure(
  removeNewObject: () => Promise<{ error: { message: string } | null }>,
  context: EvidenceCleanupContext,
  reportOrphan: (event: string, details: EvidenceCleanupContext & { cleanupMessage: string }) => void = console.error,
) {
  const { error } = await removeNewObject();
  if (!error) return { orphaned: false as const };
  reportOrphan("evidence_orphaned_storage_object", { ...context, cleanupMessage: error.message });
  return { orphaned: true as const };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TYPES = new Map([
  ["image/jpeg", ["jpg", "jpeg"]], ["image/png", ["png"]],
  ["image/webp", ["webp"]], ["application/pdf", ["pdf"]],
]);

export function cleanFilename(value: string) {
  const leaf = value.replaceAll("\\", "/").split("/").pop() ?? "evidence";
  return leaf.normalize("NFKC").replace(/[^A-Za-z0-9._ -]/g, "_").replace(/\s+/g, " ").slice(0, 120) || "evidence";
}
export function validParent(type: unknown, id: unknown): type is EvidenceParent {
  return (type === "work_order" || type === "incident") && typeof id === "string" && UUID.test(id);
}
export function validCategory(value: unknown): value is EvidenceCategory { return EVIDENCE_CATEGORIES.includes(value as EvidenceCategory); }
export function validateEvidenceFile(file: File, bytes: Uint8Array): string | null {
  if (!file.size || file.size > MAX_EVIDENCE_BYTES) return "File must be between 1 byte and 10 MB.";
  const extensions = TYPES.get(file.type);
  const extension = cleanFilename(file.name).split(".").pop()?.toLowerCase();
  if (!extensions || !extension || !extensions.includes(extension)) return "Use a JPEG, PNG, WebP, or PDF file.";
  const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const png = bytes.slice(0, 8).every((value, index) => value === [137,80,78,71,13,10,26,10][index]);
  const webp = new TextDecoder().decode(bytes.slice(0, 4)) === "RIFF" && new TextDecoder().decode(bytes.slice(8, 12)) === "WEBP";
  const pdf = new TextDecoder().decode(bytes.slice(0, 5)) === "%PDF-";
  if (!({ "image/jpeg": jpeg, "image/png": png, "image/webp": webp, "application/pdf": pdf }[file.type])) return "File content does not match its declared type.";
  return null;
}

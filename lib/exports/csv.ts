export type CsvValue = string | number | boolean | null | undefined;

const FORMULA_PREFIX = /^[\t\r ]*[=+\-@]/;
const INTERNAL_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function exportDisplayValue(value: CsvValue): CsvValue {
  if (typeof value === "string" && INTERNAL_UUID.test(value.trim())) return null;
  return value;
}

export function safeCsvCell(value: CsvValue): string {
  let text = value === null || value === undefined ? "" : String(value);
  if (FORMULA_PREFIX.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

export function createCsv(headers: string[], rows: CsvValue[][]): string {
  const lines = [headers.map(safeCsvCell).join(",")];
  for (const row of rows) lines.push(row.map(safeCsvCell).join(","));
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}

export function singaporeTimestamp(value = new Date()): string {
  const local = new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Singapore",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(value);
  return `${local.replace(" ", "T")}+08:00`;
}

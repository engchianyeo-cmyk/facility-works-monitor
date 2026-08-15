import { describe, expect, test } from "vitest";
import { createCsv, exportDisplayValue, safeCsvCell, singaporeTimestamp } from "@/lib/exports/csv";

describe("controlled CSV output", () => {
  test.each(["=1+1", "+SUM(A1:A2)", "-2+3", "@command", "  =cmd", "\t+cmd"])(
    "neutralizes spreadsheet formula input %s",
    (input) => expect(safeCsvCell(input)).toBe(`"'${input}"`),
  );

  test("quotes commas, quotes and line breaks and emits a UTF-8 BOM", () => {
    expect(createCsv(["name"], [["A, \"quoted\"\nvalue"]])).toBe("\uFEFF\"name\"\r\n\"A, \"\"quoted\"\"\nvalue\"\r\n");
  });

  test("labels extraction time with the pilot timezone", () => {
    expect(singaporeTimestamp(new Date("2026-08-14T00:00:00Z"))).toBe("2026-08-14T08:00:00+08:00");
  });

  test("suppresses an internal UUID accidentally stored in a display field", () => {
    expect(exportDisplayValue("10000000-0000-4000-8000-000000000004")).toBeNull();
    expect(exportDisplayValue("Electrical Team")).toBe("Electrical Team");
  });
});

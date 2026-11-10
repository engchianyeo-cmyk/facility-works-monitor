import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { WORK_ORDER_DRAWINGS } from "@/lib/work-order-drawings";
import { validDrawingReference } from "@/lib/facility-location";
import { markupDrawingsFor } from "@/lib/facility-drawings";

/** D-47 (10 Nov 2026): the Central Plant Block (AHU Room, Chiller Plant Room) on mock-up drawing FW-006. */
function pngSize(path: string) {
  const file = readFileSync(path);
  return { width: file.readUInt32BE(16), height: file.readUInt32BE(20) };
}

const script = readFileSync("scripts/rollout/preview-d47-central-plant-20261110.sql", "utf8");
const uploadRoute = readFileSync("app/api/administration/facilities/[id]/drawings/route.ts", "utf8");

describe("D-47 Central Plant Block drawing", () => {
  const fw006 = WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-006");

  test("FW-006 is one of the mock-up drawings, and its size matches the image", () => {
    expect(fw006).toBeDefined();
    expect(pngSize(`public${fw006!.src}`)).toEqual({ width: fw006!.width, height: fw006!.height });
    expect(validDrawingReference("FW-006")).toBe(true);
    expect(markupDrawingsFor([]).map((drawing) => drawing.code)).toContain("FW-006");
  });

  test("FW-001 Rev B (one building, to scale) and FW-005 Rev B (3D and Utility Block) match their recorded sizes", () => {
    const fw001 = WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-001")!;
    expect(fw001.revision).toBe("B (10 Nov 2026)");
    expect(pngSize(`public${fw001.src}`)).toEqual({ width: fw001.width, height: fw001.height });
    expect(pngSize("public/work-order-drawings/FW-005-rev-b.png")).toEqual({ width: 2048, height: 1484 });
    const fw004 = WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-004")!;
    expect(fw004.revision).toBe("B (10 Nov 2026)");
    expect(pngSize(`public${fw004.src}`)).toEqual({ width: fw004.width, height: fw004.height });
  });

  test("an uploaded facility drawing cannot take the FW-006 or FW-007 number", () => {
    expect(uploadRoute).toContain('code === "FW-006"');
    expect(uploadRoute).toContain('code === "FW-007"');
    expect(uploadRoute).toContain('code === "FW-008"');
  });

  test("the Work Order page shows every mock-up drawing, FW-001 to FW-008, in order", () => {
    expect(markupDrawingsFor([]).map((drawing) => drawing.code)).toEqual(["FW-001", "FW-002", "FW-003", "FW-004", "FW-005", "FW-006", "FW-007", "FW-008"]);
    const fw005 = WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-005")!;
    expect(pngSize(`public${fw005.src}`)).toEqual({ width: fw005.width, height: fw005.height });
    const fw008 = WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-008")!;
    expect(readFileSync(`public${fw008.src}`).subarray(0, 2).toString("hex")).toBe("ffd8");
  });

  test("D-48: FW-007 (solar PV canopy access) is a mock-up drawing and the canopy area is pinned on it", () => {
    const fw007 = WORK_ORDER_DRAWINGS.find((drawing) => drawing.code === "FW-007")!;
    expect(pngSize(`public${fw007.src}`)).toEqual({ width: fw007.width, height: fw007.height });
    expect(validDrawingReference("FW-007")).toBe(true);
    expect(script).toContain('"code":"SPV-01","name":"Solar PV Canopy (Car Park)"');
  });

  test("the Preview script pins both rooms on FW-006 and is a dry run unless asked", () => {
    expect(script).toContain('"code":"AHR-01","name":"AHU Room","x":20.41,"y":35.458');
    expect(script).toContain('"code":"CPR-01","name":"Chiller Plant Room","x":20.41,"y":69.987');
    expect(script).toContain('"code":"SUB-01","name":"Substation","zone":"Utility Block"');
    expect(script).toContain("pin cleared (place again)");
    expect(script).toContain("Dry run only: rolling back.");
    expect(script).toMatch(/\\if :\{\?apply\}/);
  });
});

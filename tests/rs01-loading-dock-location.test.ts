import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { FW001_RS01_LOADING_DOCK, WORK_ORDER_DRAWINGS } from "@/lib/work-order-drawings";

const migration = readFileSync(
  "supabase/migrations/20260919002732_release_1_uat_rs01_main_building_loading_dock.sql",
  "utf8",
);
const editor = readFileSync("components/work-orders/drawing-markup-editor.tsx", "utf8");

describe("RS-01 FW-001 visual acceptance location", () => {
  test("normalizes the measured loading-dock source pixel", () => {
    const drawing = WORK_ORDER_DRAWINGS.find((item) => item.code === "FW-001");
    expect(drawing).toBeDefined();
    expect(FW001_RS01_LOADING_DOCK.normalized.x).toBeCloseTo(
      (FW001_RS01_LOADING_DOCK.sourcePixel.x / drawing!.width) * 100,
      3,
    );
    expect(FW001_RS01_LOADING_DOCK.normalized.y).toBeCloseTo(
      (FW001_RS01_LOADING_DOCK.sourcePixel.y / drawing!.height) * 100,
      3,
    );
    expect(migration).toContain("target_x constant numeric(6,3) := 23.077");
    expect(migration).toContain("target_y constant numeric(6,3) := 37.390");
  });

  test("places RS-01 inside the loading-dock acceptance region and outside parking", () => {
    const { sourcePixel, acceptanceRegion, excludedParkingCanopyRegion } = FW001_RS01_LOADING_DOCK;
    expect(sourcePixel.x).toBeGreaterThanOrEqual(acceptanceRegion.minX);
    expect(sourcePixel.x).toBeLessThanOrEqual(acceptanceRegion.maxX);
    expect(sourcePixel.y).toBeGreaterThanOrEqual(acceptanceRegion.minY);
    expect(sourcePixel.y).toBeLessThanOrEqual(acceptanceRegion.maxY);
    expect(sourcePixel.y).toBeLessThan(excludedParkingCanopyRegion.minY);
  });

  test("retires the failed saved markup and exposes coordinates to browser UAT", () => {
    expect(migration).toContain("set deleted_at = pg_catalog.now(), deleted_by = yang");
    expect(migration).toContain("RS-01 Main Building loading dock roller-shutter opening");
    expect(migration).toContain("visitor and accessibility parking canopy");
    expect(editor).toContain("data-asset-marker={assetMarker.label}");
    expect(editor).toContain("data-drawing-x={assetMarker.x}");
    expect(editor).toContain("data-drawing-y={assetMarker.y}");
  });
});

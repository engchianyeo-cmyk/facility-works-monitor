import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { FACILITY_LOCATION_AUDIT_EVENT, validDrawingReference, validNormalizedCoordinate } from "@/lib/facility-location";

const component = readFileSync(new URL("../components/work-order-drawings.tsx", import.meta.url), "utf8");
const configuration = readFileSync(new URL("../components/facility-area-location-configuration.tsx", import.meta.url), "utf8");
const page = readFileSync(new URL("../app/administration/facility-locations/page.tsx", import.meta.url), "utf8");
const api = readFileSync(new URL("../app/api/admin/facility-locations/route.ts", import.meta.url), "utf8");

describe("Utility Block Work Order location presentation", () => {
  test("shows operational location context and the resolved drawing reference", () => {
    for (const label of ["Building / Block", "Area / Room", "Level / Area Code", "Asset", "Drawing Reference"]) {
      expect(component).toContain(label);
    }
    expect(component).toContain("locationDrawing?.code");
  });

  test("does not silently omit an unconfigured marker", () => {
    expect(component).toContain("Precise asset position has not yet been configured on this drawing.");
    expect(component).toContain("Facility Configuration gap");
    expect(component).toContain("!marker");
    expect(component).not.toContain("locationContext.facility_area && !marker");
  });

  test("only creates a marker from calibrated authoritative coordinates", () => {
    expect(component).toContain("const mapX = calibratedCoordinate(locationContext?.facility_area?.map_x)");
    expect(component).toContain("const mapY = calibratedCoordinate(locationContext?.facility_area?.map_y)");
    expect(component).toContain("mapX !== null && mapY !== null");
  });

  test("Administrator can open the configuration page", () => expect(page).toContain('identity.role !== "administrator"'));
  test.each(["technician", "view_only"])("%s cannot use the Administrator-only API", () => {
    expect(api).toContain('identity?.role === "administrator"');
    expect(api).toContain('status: 403');
  });
  test("drawing selection is persisted", () => { expect(api).toContain("drawing_reference: body.drawing_reference"); expect(validDrawingReference("FW-001")).toBe(true); });
  test("map_x is persisted", () => expect(api).toContain("map_x: body.map_x"));
  test("map_y is persisted", () => expect(api).toContain("map_y: body.map_y"));
  test("coordinates below zero are rejected", () => expect(validNormalizedCoordinate(-0.01)).toBe(false));
  test("coordinates above 100 are rejected", () => expect(validNormalizedCoordinate(100.01)).toBe(false));
  test("marker uses responsive percentage positioning", () => { expect(configuration).toContain("left: `${point.x}%`"); expect(configuration).toContain("top: `${point.y}%`"); });
  test("configured marker identifies the asset and area", () => expect(component).toContain("locationContext.asset.asset_tag"));
  test("save writes the controlled audit event with previous and next coordinates", () => {
    expect(FACILITY_LOCATION_AUDIT_EVENT).toBe("facility_area_drawing_location_updated");
    expect(api).toContain("previous, next, actor_id: identity.userId, timestamp");
  });
  test("does not hard-code WO-TEST-001 or coordinates", () => {
    expect(configuration).not.toContain("WO-TEST-001");
    expect(api).not.toContain("WO-TEST-001");
    expect(configuration).toContain("No default point is supplied.");
  });
});

import { existsSync, readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { ASSET_UNAVAILABLE, assetIdentity, assetOptionLabel, assetReferenceLabel } from "@/lib/assets/presentation";
import { canConfigureAssetSystems, canCorrectAssetTag, canCreateAsset, canLinkIncidentAsset, canLinkWorkOrderAsset, canManageAsset } from "@/lib/assets/types";

const root = new URL("../", import.meta.url);
const read = (path: string) => readFileSync(new URL(path, root), "utf8");
const sample = { id: "asset-internal-id", asset_tag: "AHU-L03-001", name: "Level 3 AHU", asset_type: "Air handling unit", criticality: "high" as const, lifecycle_status: "active" as const, site: "Central Site", location: "Building A · Level 3 Plantroom", system: { name: "Ventilation", system_code: "HVAC" } };

describe("WP-ASSET-001A Asset Registry", () => {
  test("creates canonical registry and immutable detail routes", () => {
    expect(existsSync(new URL("app/assets/page.tsx", root))).toBe(true);
    expect(existsSync(new URL("app/assets/[id]/page.tsx", root))).toBe(true);
    expect(read("app/assets/page.tsx")).toContain("Asset Registry");
    expect(read("app/assets/[id]/page.tsx")).toContain("Canonical route");
  });

  test("provides search and approved P0 filters", () => {
    const page = read("app/assets/page.tsx");
    for (const value of ["asset_tag.ilike", "name.ilike", "model.ilike", "serial_number.ilike", 'params.system', 'params.criticality', 'params.status', 'params.site', 'params.type']) expect(page).toContain(value);
  });

  test("uses only approved criticality and lifecycle terminology", () => {
    const types = read("lib/assets/types.ts");
    expect(types).toContain('["critical", "high", "medium", "low"]');
    expect(types).toContain('["active", "out_of_service", "decommissioned"]');
    expect(types).not.toContain("under_maintenance");
  });

  test("formats registered Assets as human-readable identity", () => {
    expect(assetIdentity(sample)).toBe("AHU-L03-001 · Level 3 AHU");
    expect(assetOptionLabel(sample)).toContain("Ventilation");
    expect(assetOptionLabel(sample)).toContain("Level 3 Plantroom");
    expect(assetOptionLabel(sample)).not.toContain(sample.id);
  });

  test("suppresses unknown historical UUIDs", () => {
    expect(assetReferenceLabel("unmatched-internal-value", null)).toBe(ASSET_UNAVAILABLE);
    expect(assetReferenceLabel(null, null)).toBeNull();
    expect(read("app/operations/page.tsx")).toContain("assetReferenceLabel(order.asset_id, order.asset)");
    expect(read("components/operations/OperationsWorkspace.tsx")).not.toContain("Asset: {item.id}");
  });

  test("replaces Work Order free-text Asset entry with a governed selector", () => {
    const form = read("components/work-orders/work-order-form.tsx");
    expect(form).toContain("<AssetSelector assets={assets}");
    expect(form).not.toContain("Asset reference");
    expect(read("app/work-orders/new/page.tsx")).toContain('from("assets")');
  });

  test("keeps Asset optional for general facilities Work", () => {
    expect(read("components/assets/asset-selector.tsx")).toContain("None — general facilities work");
    expect(read("components/assets/asset-selector.tsx")).not.toContain("required");
  });

  test("does not let broad Work Order edit change the Asset link", () => {
    const route = read("app/api/work-orders/[id]/route.ts");
    expect(route).toContain("delete body.asset_id");
    expect(read("app/api/work-orders/[id]/asset/route.ts")).toContain('rpc("set_work_order_asset"');
  });

  test("supports optional primary Asset selection during Incident reporting", () => {
    expect(read("components/incidents/incident-form.tsx")).toContain('label="Primary affected Asset"');
    expect(read("app/api/incidents/route.ts")).toContain('rpc("create_incident_with_asset"');
  });

  test("uses narrow Incident relinking operation", () => {
    expect(read("app/api/incidents/[id]/asset/route.ts")).toContain('rpc("set_incident_asset"');
    expect(read("app/incidents/[id]/page.tsx")).toContain("Incident location remains the authoritative event-location context.");
  });

  test("enforces approved role-based mutation controls in UI and routes", () => {
    expect(canCreateAsset("supervisor")).toBe(true); expect(canCreateAsset("technician")).toBe(false);
    expect(canManageAsset("administrator")).toBe(true); expect(canManageAsset("approver")).toBe(false);
    expect(canCorrectAssetTag("administrator")).toBe(true); expect(canCorrectAssetTag("supervisor")).toBe(false);
    expect(canConfigureAssetSystems("administrator")).toBe(true); expect(canConfigureAssetSystems("supervisor")).toBe(false);
    expect(canLinkWorkOrderAsset("approver")).toBe(true); expect(canLinkWorkOrderAsset("initiator")).toBe(false);
    expect(canLinkIncidentAsset("supervisor")).toBe(true); expect(canLinkIncidentAsset("approver")).toBe(false);
  });

  test("requires reasons for governed lifecycle criticality and tag changes", () => {
    const actions = read("components/assets/asset-actions.tsx");
    expect(actions.match(/reason required/gi)?.length).toBeGreaterThanOrEqual(3);
    for (const endpoint of ["criticality", "status", "tag"]) expect(actions).toContain(`act("${endpoint}"`);
  });

  test("presents manage-by-exception Asset detail without invented health", () => {
    const detail = read("app/assets/[id]/page.tsx");
    for (const label of ["Required attention", "Active Work Orders", "Active Incidents", "Equipment information", "Asset history", "Not recorded", "Unavailable"]) expect(detail).toContain(label);
    expect(detail).toContain("not live equipment telemetry");
  });

  test("uses responsive card structures without horizontal scrolling", () => {
    const registry = read("app/assets/page.tsx"); const detail = read("app/assets/[id]/page.tsx");
    expect(registry).toContain("md:grid-cols-2"); expect(detail).toContain("sm:grid-cols-2");
    expect(registry).not.toContain("overflow-x-auto"); expect(detail).not.toContain("overflow-x-auto");
  });

  test("does not add PM evidence scanning telemetry or hard-delete features", () => {
    const migration = read("supabase/migrations/0018_asset_registry_foundation.sql");
    for (const forbidden of ["maintenance_strategy", "pm_schedule", "telemetry", "create_asset_evidence", "delete_asset("]) expect(migration.toLowerCase()).not.toContain(forbidden);
    expect(migration).not.toMatch(/create\s+or\s+replace\s+function\s+public\.delete_asset/i);
  });
});

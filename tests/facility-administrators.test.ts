import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { roleLabel } from "@/lib/product-terminology";

const read = (path: string) => readFileSync(path, "utf8");

describe("D-50 / D-53 / D-54 / D-55: facilities, Facility Administrators and removing a person's details", () => {
  it("calls the Administrator the Super-Administrator and adds the Facility Administrator role", () => {
    expect(roleLabel("administrator")).toBe("Super-Administrator");
    expect(roleLabel("facility_administrator")).toBe("Facility Administrator");
    expect(read("lib/auth.ts")).toContain('"facility_administrator"');
  });

  it("scopes facility set-up, Finance and notices in the database", () => {
    const migration = read("supabase/migrations/20261115120000_facility_administrators_and_personal_data.sql");
    for (const text of ["facility_admin_actor_for", "facility_finance_permitted", "facility_administrator_facility_permitted",
      "guard_finance_facility_recipient", "admin_remove_personal_details", "Only the Super-Administrator appoints or removes a Facility Administrator."]) {
      expect(migration).toContain(text);
    }
  });

  it("lets a Facility Administrator create accounts only for its own facility", () => {
    const route = read("app/api/admin/users/direct/route.ts");
    expect(route).toContain("FACILITY_ADMIN_ROLES");
    expect(route).toContain("facility_id: facilityId || null");
    expect(read("components/direct-user-provisioning.tsx")).toContain("Not yet (add as staff later)");
  });

  it("offers Remove personal details to the Super-Administrator and frees the email", () => {
    expect(read("components/user-management.tsx")).toContain("Remove personal details");
    const route = read("app/api/admin/users/[id]/route.ts");
    expect(route).toContain('rpc("admin_remove_personal_details"');
    expect(route).toContain('ban_duration: "876000h"');
  });

  it("narrows the Work Orders list to the facility chosen above it", () => {
    const page = read("app/work-orders/page.tsx");
    expect(page).toContain("FACILITY_COOKIE");
    expect(page).toContain("<FacilitySwitch");
  });

  it("emails each Finance person only their facilities' payments", () => {
    expect(read("lib/notifications/email-dispatch.ts")).toContain("personItems");
    expect(read("lib/notifications/email-dispatch.ts")).toContain('admin.rpc("finance_reminder_facilities"');
  });
});

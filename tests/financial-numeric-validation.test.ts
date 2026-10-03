import { describe, expect, it } from "vitest";
import { invalidFinancialNumber } from "@/lib/work-orders/numeric-validation";

describe("financial request numeric integrity", () => {
  it.each(["NaN", "Infinity", "-Infinity", NaN, Infinity, -Infinity, -1, "", " ", true, {}, []])("rejects invalid financial value %s", (value) => {
    for (const field of ["proposed_amount", "final_contractor_amount", "confirmed_actual_cost", "committed_amount", "paid_amount", "quantity", "unit_rate", "actual_labour_hours"]) {
      expect(invalidFinancialNumber({ [field]: value })).toBe(field);
    }
  });
  it.each([0, "0", 620, "620.50", 1.25])("accepts valid finite values %s", (value) => {
    expect(invalidFinancialNumber({ proposed_amount: value, actual_labour_hours: value })).toBeNull();
  });
  it("leaves omitted optional values and confirmation-only operations to domain validation", () => {
    expect(invalidFinancialNumber({ operation: "confirm", confirmed_actual_cost: null })).toBeNull();
  });
});

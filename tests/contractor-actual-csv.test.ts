import { describe, expect, it } from "vitest";
import { parseContractorActualCsv } from "@/lib/work-orders/contractor-csv";

describe("contractor actual CSV", () => {
  it("parses material rows", () => {
    const csv = [
      "Work Order No.,Rate Code,Actual Quantity,Actual Unit Rate (SGD),Work Date,Remarks",
      "WO-TEST-004,MAT-MODULE,1,210,2026-09-15,Replacement module",
    ].join("\n");
    const result = parseContractorActualCsv(csv);
    expect(result.errors).toEqual([]);
    expect(result.rows).toEqual([expect.objectContaining({ workOrderNumber: "WO-TEST-004", rateCode: "MAT-MODULE", quantity: 1, actualUnitRate: 210 })]);
  });

  it("expands normal and overtime personnel hours", () => {
    const csv = [
      "Work Order No.,Rate Code,Personnel Name,Employee / Worker ID,Work Date,Normal Hours,OT Hours,Normal Hourly Rate (SGD),OT Hourly Rate (SGD),Remarks",
      "WO-TEST-004,LAB-FIRE-ALARM,Lim Wei Ming,UAT-FA-017,2026-09-15,2.5,1,75,115,Testing",
    ].join("\n");
    const result = parseContractorActualCsv(csv);
    expect(result.errors).toEqual([]);
    expect(result.rows).toHaveLength(2);
    expect(result.rows[0]).toEqual(expect.objectContaining({ quantity: 2.5, actualUnitRate: 75, workerName: "Lim Wei Ming" }));
    expect(result.rows[1]).toEqual(expect.objectContaining({ quantity: 1, actualUnitRate: 115, exceptionReason: "Overtime rate submitted by contractor" }));
  });

  it("rejects missing work order and rate code", () => {
    const result = parseContractorActualCsv("Work Order No.,Rate Code,Actual Quantity\n,,1");
    expect(result.errors).toEqual(expect.arrayContaining([expect.stringContaining("Work Order No."), expect.stringContaining("Rate Code")]));
  });
});

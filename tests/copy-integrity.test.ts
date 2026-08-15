import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import {
  incidentStatusLabel,
  operationalLabel,
  priorityLabel,
  roleLabel,
  workOrderStatusLabel,
} from "@/lib/product-terminology";

const sourceRoot = new URL("../", import.meta.url).pathname.replace(/^\/(.:\/)/, "$1");

function userFacingSources(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return userFacingSources(path);
    return /\.tsx?$/.test(entry.name) ? [path] : [];
  });
}

describe("copy and terminology integrity", () => {
  test("user-facing application source contains no known mojibake signatures", () => {
    const signatures = ["\u00c2", "\u00e2\u20ac", "\u00e2\u2020", "\u00c3", "\ufffd"];
    const failures = ["app", "components"].flatMap((directory) =>
      userFacingSources(join(sourceRoot, directory)).flatMap((path) => {
        const source = readFileSync(path, "utf8");
        return signatures.filter((signature) => source.includes(signature)).map((signature) => `${path}: ${JSON.stringify(signature)}`);
      }),
    );
    expect(failures).toEqual([]);
  });

  test("canonical labels preserve operational distinctions", () => {
    expect(workOrderStatusLabel("submitted")).toBe("Awaiting Approval");
    expect(workOrderStatusLabel("completed")).toBe("Completed — Awaiting Review");
    expect(workOrderStatusLabel("closed")).toBe("Closed");
    expect(workOrderStatusLabel("cancelled")).toBe("Cancelled");
    expect(incidentStatusLabel("rescue_in_progress")).toBe("Rescue In Progress");
    expect(operationalLabel("queued")).toBe("Queued");
    expect(operationalLabel("delivered")).toBe("Delivered");
    expect(operationalLabel("unavailable")).toBe("Unavailable");
    expect(priorityLabel("critical")).toBe("Critical");
    expect(roleLabel("technician")).toBe("Technician");
  });

  test("unknown enums receive readable presentation without changing their value", () => {
    const stored = "future_operational_state";
    expect(operationalLabel(stored)).toBe("Future operational state");
    expect(stored).toBe("future_operational_state");
  });
});

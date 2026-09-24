import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const prd = readFileSync("docs/PRD.md", "utf8");
const commercial = readFileSync("docs/COMMERCIAL.md", "utf8");
const tasks = readFileSync("docs/TASKS.md", "utf8");
const workflow = readFileSync("docs/WORKFLOW.md", "utf8");
const ci = readFileSync(".github/workflows/ci.yml", "utf8");

describe("Release-1 governing documentation and independent quality gates", () => {
  test("defines the implemented commercial lifecycle without claiming FMWorks is an accounting ledger", () => {
    expect(prd).toContain("governed contractor qualification/quotation/final-account/payment records");
    expect(prd).toContain("they do not make FMWorks an accounting ledger");
    expect(tasks).toContain("Release-1 commercial control — implemented/remediation");
    expect(commercial).toContain("FMWorks is not an accounting ledger");
  });

  test("documents the S$1,000 boundary and separated completion/payment/closure states", () => {
    expect(commercial).toContain("Below S$1,000 requires at least one authentic quotation");
    expect(commercial).toContain("At or above S$1,000 requires at least three distinct eligible-contractor quotations");
    expect(workflow).toContain("Physical completion requires work-performed notes");
    expect(workflow).toContain("Closure additionally requires recorded reconciled payment or independently approved no payment required");
  });

  test("runs TypeScript, ESLint, Vitest and build as separate CI commands", () => {
    for (const command of ["npm run typecheck", "npm run lint", "npm run test", "npm run build"]) {
      expect(ci).toContain(`run: ${command}`);
    }
  });
});

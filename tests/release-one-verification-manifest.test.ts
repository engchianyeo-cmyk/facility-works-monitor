import { readFileSync, readdirSync } from "node:fs";
import { describe, expect, it } from "vitest";

const manifestPath = "supabase/bootstrap/fresh-install-manifest.txt";
const manifest = readFileSync(manifestPath, "utf8")
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith("#"));

describe("canonical non-Production Release-1 migration manifest", () => {
  it("replays every canonical migration from 0012 through reconciliation", () => {
    const migrations = readdirSync("supabase/migrations")
      .filter((name) => name.endsWith(".sql") && name >= "0012")
      .sort((left, right) => left.localeCompare(right));

    expect(manifest).toEqual([
      "supabase/bootstrap/fmworks_pre_0012_bootstrap.sql",
      ...migrations.map((name) => `supabase/migrations/${name}`),
    ]);
    expect(manifest.at(-1)).toBe(
      "supabase/migrations/20261003033514_configurable_procurement_policy.sql",
    );
  });

  it("is the source consumed by the release verification runner", () => {
    expect(readFileSync("scripts/release-verify.mjs", "utf8")).toContain(
      'const verificationManifest = "supabase/bootstrap/fresh-install-manifest.txt"',
    );
  });
});

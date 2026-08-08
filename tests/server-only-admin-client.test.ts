import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { describe, expect, test } from "vitest";

const root = process.cwd();

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((name) => {
    const entry = path.join(directory, name);
    if (statSync(entry).isDirectory()) return sourceFiles(entry);
    return /\.(ts|tsx)$/.test(name) ? [entry] : [];
  });
}

describe("Supabase service-role boundary", () => {
  test("marks the privileged client factory as server-only", () => {
    const source = readFileSync(
      path.join(root, "lib", "supabase", "admin.ts"),
      "utf8",
    );
    expect(source).toContain('import "server-only";');
    expect(source).toContain("SUPABASE_SERVICE_ROLE_KEY");
    expect(source).not.toContain("NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY");
  });

  test("does not reference the service-role key or admin factory from client components", () => {
    const files = [
      ...sourceFiles(path.join(root, "app")),
      ...sourceFiles(path.join(root, "components")),
      ...sourceFiles(path.join(root, "lib")),
    ];
    const clientViolations = files.filter((file) => {
      const source = readFileSync(file, "utf8");
      const isClient = /^\s*["']use client["'];/m.test(source);
      return (
        isClient &&
        (source.includes("SUPABASE_SERVICE_ROLE_KEY") ||
          source.includes("@/lib/supabase/admin"))
      );
    });
    expect(clientViolations).toEqual([]);
  });
});

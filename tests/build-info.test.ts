import { afterEach, describe, expect, test } from "vitest";
import { getBuildInfo } from "@/lib/build-info";

const commit = process.env.VERCEL_GIT_COMMIT_SHA;
const environment = process.env.VERCEL_ENV;

function restore(name: string, value: string | undefined) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}

afterEach(() => {
  restore("VERCEL_GIT_COMMIT_SHA", commit);
  restore("VERCEL_ENV", environment);
});

describe("build identity", () => {
  test("formats Preview identity with a short commit", () => {
    process.env.VERCEL_GIT_COMMIT_SHA = "1234567890abcdef";
    process.env.VERCEL_ENV = "preview";
    expect(getBuildInfo()).toMatchObject({
      version: "1.1",
      shortCommit: "1234567",
      environmentLabel: "Preview",
    });
  });

  test("labels Production and falls back safely for local builds", () => {
    process.env.VERCEL_ENV = "production";
    expect(getBuildInfo().environmentLabel).toBe("Production");
    delete process.env.VERCEL_ENV;
    delete process.env.VERCEL_GIT_COMMIT_SHA;
    expect(getBuildInfo()).toMatchObject({
      shortCommit: "local",
      environmentLabel: "Local",
    });
  });
});

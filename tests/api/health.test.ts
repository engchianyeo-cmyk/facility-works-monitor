import { afterEach, describe, expect, test } from "vitest";
import { GET } from "@/app/api/health/route";

const commit = process.env.VERCEL_GIT_COMMIT_SHA;
const environment = process.env.VERCEL_ENV;

afterEach(() => {
  process.env.VERCEL_GIT_COMMIT_SHA = commit;
  process.env.VERCEL_ENV = environment;
});

describe("GET /api/health", () => {
  test("exposes non-secret deployment identity", async () => {
    process.env.VERCEL_GIT_COMMIT_SHA = "batch-a-commit";
    process.env.VERCEL_ENV = "preview";
    const response = GET();
    await expect(response.json()).resolves.toMatchObject({
      status: "ok",
      build: {
        version: "1.1",
        commit: "batch-a-commit",
        environment: "preview",
      },
    });
  });
});

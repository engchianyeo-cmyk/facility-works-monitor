import { afterEach, describe, expect, test } from "vitest";
import {
  AppUrlConfigurationError,
  applicationCallbackUrl,
  applicationOrigin,
} from "@/lib/app-url";

const original = {
  appUrl: process.env.NEXT_PUBLIC_APP_URL,
  vercelEnv: process.env.VERCEL_ENV,
  vercelUrl: process.env.VERCEL_URL,
  productionUrl: process.env.VERCEL_PROJECT_PRODUCTION_URL,
};

afterEach(() => {
  process.env.NEXT_PUBLIC_APP_URL = original.appUrl;
  process.env.VERCEL_ENV = original.vercelEnv;
  process.env.VERCEL_URL = original.vercelUrl;
  process.env.VERCEL_PROJECT_PRODUCTION_URL = original.productionUrl;
});

describe("application URL resolution", () => {
  test("uses the configured non-local Preview origin for Auth callbacks", () => {
    process.env.VERCEL_ENV = "preview";
    process.env.NEXT_PUBLIC_APP_URL = "https://preview.fmworks.example";
    process.env.VERCEL_URL = "generated-preview.vercel.app";
    expect(applicationCallbackUrl("http://localhost:3000/api/admin/users")).toBe(
      "https://preview.fmworks.example/auth/callback",
    );
  });

  test("never emits localhost in Preview when Vercel provides its deployment host", () => {
    process.env.VERCEL_ENV = "preview";
    process.env.NEXT_PUBLIC_APP_URL = "http://localhost:3000";
    process.env.VERCEL_URL = "batch-a-preview.vercel.app";
    expect(applicationOrigin("http://localhost:3000/api/admin/users")).toBe(
      "https://batch-a-preview.vercel.app",
    );
  });

  test("fails safely when a deployed environment has only localhost origins", () => {
    process.env.VERCEL_ENV = "production";
    process.env.NEXT_PUBLIC_APP_URL = "http://localhost:3000";
    delete process.env.VERCEL_URL;
    delete process.env.VERCEL_PROJECT_PRODUCTION_URL;
    expect(() => applicationCallbackUrl("http://localhost:3000")).toThrow(
      AppUrlConfigurationError,
    );
  });
});

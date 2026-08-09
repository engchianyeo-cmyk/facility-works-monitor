import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({ createClient: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));

import { GET } from "@/app/auth/callback/route";

beforeEach(() => vi.clearAllMocks());

describe("GET /auth/callback", () => {
  test("handles a missing callback code safely", async () => {
    const response = await GET(new Request("https://preview.example/auth/callback"));
    expect(response.headers.get("location")).toContain("/login?error=");
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("handles an expired or invalid callback without exposing provider details", async () => {
    mocks.createClient.mockResolvedValue({
      auth: {
        exchangeCodeForSession: vi.fn().mockResolvedValue({
          error: { message: "raw token exchange detail" },
        }),
      },
    });
    const response = await GET(
      new Request("https://preview.example/auth/callback?code=expired"),
    );
    const location = response.headers.get("location") ?? "";
    expect(location).toContain("/login?error=");
    expect(location).not.toContain("raw token exchange detail");
  });

  test("continues a valid callback to authenticated completion", async () => {
    mocks.createClient.mockResolvedValue({
      auth: { exchangeCodeForSession: vi.fn().mockResolvedValue({ error: null }) },
    });
    const response = await GET(
      new Request("https://preview.example/auth/callback?code=valid&next=/work-orders"),
    );
    expect(response.headers.get("location")).toBe(
      "https://preview.example/auth/complete?next=%2Fwork-orders",
    );
  });
});

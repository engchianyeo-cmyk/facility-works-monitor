import type { CookieOptions } from "@supabase/ssr";
import { NextRequest } from "next/server";
import { beforeEach, describe, expect, test, vi } from "vitest";

type CookieBatch = Array<{
  name: string;
  value: string;
  options: CookieOptions;
}>;

type ServerClientOptions = {
  cookies: {
    setAll?: (cookies: CookieBatch) => void;
  };
};

const mocks = vi.hoisted(() => ({
  createServerClient: vi.fn(),
  exchangeCodeForSession: vi.fn(),
  from: vi.fn(),
  select: vi.fn(),
  eq: vi.fn(),
  maybeSingle: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: mocks.createServerClient,
}));

import { GET } from "@/app/auth/callback/route";

const authCookies: CookieBatch = [
  {
    name: "sb-preview-auth-token",
    value: "session-cookie-value",
    options: { httpOnly: true, path: "/", sameSite: "lax" },
  },
];

function profile(overrides: Record<string, unknown> = {}) {
  return {
    role: "reviewer",
    is_active: true,
    deleted_at: null,
    password_change_required: false,
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();

  mocks.maybeSingle.mockResolvedValue({ data: profile(), error: null });
  mocks.eq.mockReturnValue({ maybeSingle: mocks.maybeSingle });
  mocks.select.mockReturnValue({ eq: mocks.eq });
  mocks.from.mockReturnValue({ select: mocks.select });

  mocks.createServerClient.mockImplementation(
    (_url: string, _key: string, options: ServerClientOptions) => ({
      auth: {
        exchangeCodeForSession: async (code: string) => {
          options.cookies.setAll?.(authCookies);
          return mocks.exchangeCodeForSession(code);
        },
      },
      from: mocks.from,
    }),
  );

  mocks.exchangeCodeForSession.mockResolvedValue({
    data: { user: { id: "user-1" } },
    error: null,
  });
});

describe("GET /auth/callback", () => {
  test("handles a missing callback code safely", async () => {
    const response = await GET(
      new NextRequest("https://preview.example/auth/callback"),
    );

    expect(response.headers.get("location")).toContain("/login?error=");
    expect(mocks.createServerClient).not.toHaveBeenCalled();
  });

  test("handles a failed code exchange without exposing provider details", async () => {
    mocks.exchangeCodeForSession.mockResolvedValue({
      data: { user: null },
      error: {
        status: 400,
        code: "otp_expired",
        name: "AuthApiError",
        message: "raw token exchange detail",
      },
    });

    const response = await GET(
      new NextRequest("https://preview.example/auth/callback?code=expired"),
    );
    const location = response.headers.get("location") ?? "";

    expect(mocks.exchangeCodeForSession).toHaveBeenCalledWith("expired");
    expect(location).toContain("/login?error=");
    expect(location).not.toContain("raw token exchange detail");
    expect(mocks.from).not.toHaveBeenCalled();
  });

  test("rejects an unavailable profile after a valid exchange", async () => {
    mocks.maybeSingle.mockResolvedValue({ data: null, error: null });

    const response = await GET(
      new NextRequest("https://preview.example/auth/callback?code=valid"),
    );

    expect(mocks.exchangeCodeForSession).toHaveBeenCalledWith("valid");
    expect(mocks.from).toHaveBeenCalledWith("profiles");
    expect(mocks.eq).toHaveBeenCalledWith("id", "user-1");
    expect(response.headers.get("location")).toContain("/login?error=");
    expect(response.headers.get("set-cookie")).toContain(
      "sb-preview-auth-token=session-cookie-value",
    );
  });

  test("redirects a valid callback directly and forwards auth cookies", async () => {
    const response = await GET(
      new NextRequest(
        "https://preview.example/auth/callback?code=valid&next=/work-orders",
      ),
    );

    expect(mocks.exchangeCodeForSession).toHaveBeenCalledWith("valid");
    expect(mocks.from).toHaveBeenCalledWith("profiles");
    expect(mocks.select).toHaveBeenCalledWith(
      "role, is_active, deleted_at, password_change_required",
    );
    expect(mocks.eq).toHaveBeenCalledWith("id", "user-1");
    expect(response.headers.get("location")).toBe(
      "https://preview.example/work-orders",
    );
    expect(response.headers.get("location")).not.toContain("/auth/complete");
    expect(response.headers.get("set-cookie")).toContain(
      "sb-preview-auth-token=session-cookie-value",
    );
  });

  test("routes password recovery to password change with a safe role destination", async () => {
    mocks.maybeSingle.mockResolvedValue({
      data: profile({ role: "technician" }),
      error: null,
    });

    const response = await GET(
      new NextRequest(
        "https://preview.example/auth/callback?code=recovery&next=/account/password",
      ),
    );

    expect(mocks.exchangeCodeForSession).toHaveBeenCalledWith("recovery");
    expect(response.headers.get("location")).toBe(
      "https://preview.example/account/password?next=%2Foperations",
    );
    expect(response.headers.get("set-cookie")).toContain(
      "sb-preview-auth-token=session-cookie-value",
    );
  });

  test("rejects a protocol-relative next target", async () => {
    const response = await GET(
      new NextRequest(
        "https://preview.example/auth/callback?code=valid&next=//evil.example",
      ),
    );

    expect(response.headers.get("location")).toBe("https://preview.example/");
    expect(response.headers.get("location")).not.toContain("evil.example");
  });
});

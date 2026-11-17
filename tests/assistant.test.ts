import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { assistantAiEnabled, assistantModel, DEFAULT_ASSISTANT_MODEL, looksSensitive } from "@/lib/assistant/config";
import { buildSystemPrompt } from "@/lib/assistant/prompt";
import { REMIND_AFTER_MS, shouldRemind } from "@/lib/help/ollie-voice";

describe("D-58 option A: in-app AI assistant", () => {
  it("is off unless switched on and given a key", () => {
    expect(assistantAiEnabled({})).toBe(false);
    expect(assistantAiEnabled({ FMW_ASSISTANT_AI: "on" })).toBe(false);
    expect(assistantAiEnabled({ ANTHROPIC_API_KEY: "k" })).toBe(false);
    expect(assistantAiEnabled({ FMW_ASSISTANT_AI: "off", ANTHROPIC_API_KEY: "k" })).toBe(false);
    expect(assistantAiEnabled({ FMW_ASSISTANT_AI: "On ", ANTHROPIC_API_KEY: "k" })).toBe(true);
    expect(assistantModel({})).toBe(DEFAULT_ASSISTANT_MODEL);
    expect(assistantModel({ FMW_ASSISTANT_MODEL: "other-model" })).toBe("other-model");
  });

  it("refuses passwords, codes and card numbers before they leave FMWorks", () => {
    expect(looksSensitive("my password: Secret12345!")).toBe(true);
    expect(looksSensitive("card 4111 1111 1111 1111")).toBe(true);
    expect(looksSensitive("How do I change my password?")).toBe(false);
    expect(looksSensitive("Work Order FW-2026-0007 is stuck")).toBe(false);
  });

  it("gives the AI the rules, the person's role and page, and the knowledge pack", () => {
    const prompt = buildSystemPrompt({ role: "technician", displayName: "T", path: "/work-orders/abc", workOrder: { reference: "FW-2026-0006", status: "draft", inHouse: true } });
    expect(prompt).toContain("You cannot see or change anything in FMWorks");
    expect(prompt).toContain("Never ask for or accept passwords");
    expect(prompt).toContain("Work Order FW-2026-0006");
    expect(prompt).toContain("in-house work");
    expect(prompt).toContain("Part 4 — The stages of a Work Order");
    expect(prompt).toContain("Location star");
  });

  it("keeps the key on the server and sends no personal data", () => {
    const route = readFileSync("app/api/assistant/route.ts", "utf8");
    expect(route).toContain("getCurrentIdentity()");
    expect(route).toContain("assistantAiEnabled()");
    expect(route).toContain("looksSensitive(question)");
    expect(route).not.toContain("NEXT_PUBLIC");
    expect(route).not.toContain("identity.email");
    expect(route).not.toContain("createAdminClient");
  });

  it("uses the site's own learnings first and the chosen name", () => {
    const prompt = buildSystemPrompt({
      role: "technician", displayName: "T", path: "/work-orders/abc", assistantName: "Max",
      workOrder: { reference: "FW-2026-0009", status: "draft", inHouse: false },
      learnings: [{ work_order_number: "FW-2026-0006", work_order_title: "Battery charger BC-05", confirmed_cause: "sensing lead broken", fix_that_worked: "control board replaced", tip: null, proven: true, repeat_fault: false }],
    });
    expect(prompt).toContain("You are Max");
    expect(prompt).toContain("FW-2026-0006 \"Battery charger BC-05\" (proven fix): cause: sensing lead broken; fix: control board replaced");
    expect(buildSystemPrompt({ role: "approver", displayName: "A", path: "/" })).toContain("You are Ollie");
  });

  it("reminds about sounds a day after they were turned off, once a day", () => {
    const now = 10 * REMIND_AFTER_MS;
    expect(shouldRemind({ sound: true, voice: false, offSince: null, remindedAt: null }, now)).toBe(false);
    expect(shouldRemind({ sound: false, voice: false, offSince: now - REMIND_AFTER_MS / 2, remindedAt: null }, now)).toBe(false);
    expect(shouldRemind({ sound: false, voice: false, offSince: now - REMIND_AFTER_MS, remindedAt: null }, now)).toBe(true);
    expect(shouldRemind({ sound: false, voice: false, offSince: now - 3 * REMIND_AFTER_MS, remindedAt: now - 1000 }, now)).toBe(false);
  });

  it("serves a custom picture safely and lets only the Super-Administrator change it", () => {
    const picture = readFileSync("app/api/assistant/picture/route.ts", "utf8");
    expect(picture).toContain("sandbox");
    expect(picture).toContain("nosniff");
    const settings = readFileSync("app/api/assistant/settings/route.ts", "utf8");
    expect(settings).toContain('identity.role !== "administrator"');
    const migration = readFileSync("supabase/migrations/20261116130000_fault_library_and_assistant_settings.sql", "utf8");
    expect(migration).toContain("has_image boolean generated always");
    expect(migration).toContain("security invoker");
  });
});

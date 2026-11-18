import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { placeNote, placeTerms } from "@/lib/help/places";

describe("Ollie finds places in the facility (UAT 18 Nov 2026)", () => {
  it("turns everyday words into the words the facility lists use", () => {
    expect(placeTerms("Is there a room to store morphine?")).toEqual(["controlled drug", "vault"]);
    expect(placeTerms("Show if there is a lift in the facility")).toEqual(["lift"]);
    expect(placeTerms("where do we keep vaccines")).toEqual(["cold room", "2-8", "chill"]);
    expect(placeTerms("where is the first aid room")).toEqual(["first aid", "defibrillator"]);
    expect(placeTerms("is there a room")).toEqual([]);
    expect(placeTerms("a,b),(name.eq.x")).not.toContain(",");
  });

  it("adds the controlled-drug caution only for controlled-drug questions", () => {
    expect(placeNote("room to store morphine")).toContain("Controlled Drugs Vault");
    expect(placeNote("where is the lift")).toBeNull();
  });

  it("looks up with the person's own access and shows the places in the panel", () => {
    const route = readFileSync("app/api/assistant/places/route.ts", "utf8");
    expect(route).toContain('from "@/lib/supabase/server"');
    expect(route).not.toContain("createAdminClient");
    const panel = readFileSync("components/help/help-panel.tsx", "utf8");
    expect(panel).toContain("/api/assistant/places?q=");
    expect(panel).toContain("Found in your facilities");
  });
});

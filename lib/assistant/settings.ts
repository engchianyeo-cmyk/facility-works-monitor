import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * D-58: the assistant's name and picture chosen by the Super-Administrator (default: Ollie, drawn in code).
 * Pages load only the name and whether a picture exists; the picture itself is served by /api/assistant/picture.
 */
export type AssistantSettings = { name: string; pictureUrl: string | null };
export const DEFAULT_ASSISTANT_SETTINGS: AssistantSettings = { name: "Ollie", pictureUrl: null };

export async function loadAssistantSettings(supabase: SupabaseClient): Promise<AssistantSettings> {
  try {
    const { data, error } = await supabase.from("assistant_settings").select("display_name,has_image,updated_at").maybeSingle();
    if (error || !data) return DEFAULT_ASSISTANT_SETTINGS;
    const row = data as { display_name: string | null; has_image: boolean | null; updated_at: string | null };
    return {
      name: row.display_name?.trim() || "Ollie",
      pictureUrl: row.has_image ? `/api/assistant/picture?v=${encodeURIComponent(row.updated_at ?? "1")}` : null,
    };
  } catch {
    return DEFAULT_ASSISTANT_SETTINGS;
  }
}

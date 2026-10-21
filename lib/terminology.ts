import "server-only";
import { createClient } from "@/lib/supabase/server";
import { applyTerminologyOverrides } from "@/lib/product-terminology";

/** Load the Administrator's terminology overrides for this request and apply them on the server. */
export async function loadTerminology(): Promise<Record<string, string>> {
  try {
    const supabase = await createClient();
    const { data, error } = await supabase.from("terminology_labels").select("code,label");
    const labels = error ? {} : Object.fromEntries((data ?? []).map((row) => [String(row.code), String(row.label)]));
    applyTerminologyOverrides(labels);
    return labels;
  } catch {
    applyTerminologyOverrides({});
    return {};
  }
}

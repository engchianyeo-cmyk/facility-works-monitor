import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { RoundCheck, RoundSettings } from "@/lib/daily-round";

type Supabase = Awaited<ReturnType<typeof createClient>>;

/** The facilities this person is staff of (row security decides what is visible). */
export async function memberFacilities(supabase: Supabase) {
  const { data: sites } = await supabase.from("sites").select("id,name").eq("is_active", true).order("name");
  const list = (sites ?? []) as Array<{ id: string; name: string }>;
  const allowed = await Promise.all(list.map(async (site) => (await supabase.rpc("facility_member", { p_facility_id: site.id })).data === true));
  return list.filter((_, index) => allowed[index]);
}

export async function loadChecklist(supabase: Supabase, facilityId: string, includeInactive = false): Promise<RoundCheck[]> {
  const { data } = await supabase.from("daily_round_checks")
    .select("id,title,equipment,position,active,items:daily_round_items(id,label,reading_unit,reading_min,reading_max,reading_guide,position,active)")
    .eq("facility_id", facilityId).order("position").order("title");
  return ((data ?? []) as Array<{ id: string; title: string; equipment: string | null; position: number; active: boolean; items: Array<{ id: string; label: string; reading_unit: string | null; reading_min: number | string | null; reading_max: number | string | null; reading_guide: string | null; position: number; active: boolean }> }>)
    .filter((c) => includeInactive || c.active)
    .map((c) => ({ id: c.id, title: c.title, equipment: c.equipment, position: c.position, active: c.active,
      items: c.items.filter((i) => includeInactive || i.active).sort((a, b) => a.position - b.position || a.label.localeCompare(b.label))
        .map((i) => ({ id: i.id, label: i.label, unit: i.reading_unit, position: i.position, active: i.active,
          min: i.reading_min == null ? null : Number(i.reading_min), max: i.reading_max == null ? null : Number(i.reading_max), guide: i.reading_guide })) }));
}

export async function loadRoundSettings(supabase: Supabase, facilityId: string): Promise<RoundSettings> {
  const { data } = await supabase.from("facility_settings").select("daily_round_enabled,daily_round_ready,daily_round_due,daily_round_technician_id,daily_round_cover_id").eq("facility_id", facilityId).maybeSingle();
  return { enabled: Boolean(data?.daily_round_enabled), ready: String(data?.daily_round_ready ?? "07:00"), due: String(data?.daily_round_due ?? "10:00"),
    technician_id: (data?.daily_round_technician_id as string | null) ?? null, cover_id: (data?.daily_round_cover_id as string | null) ?? null };
}
